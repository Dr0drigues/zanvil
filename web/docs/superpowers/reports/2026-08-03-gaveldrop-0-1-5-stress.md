# Rapport — mise à l'épreuve adversariale de gaveldrop v0.1.5

**Pour le dépôt gaveldrop.** Rien n'y a été modifié. Le dépôt était sur `fix/config-errors-read-once`
avec des modifications non committées de 21:54 ; **tous les résultats ci-dessous ont donc été rejoués sur
l'archive publiée de `v0.1.5`**, pour ne pas rapporter contre un travail en cours.

Méthode : fabriquer volontairement des cas pathologiques et regarder si le format les refuse, les
diagnostique, ou les laisse passer.

## Ce qui tient, et qu'il faut dire d'abord

Quatre comportements ont été éprouvés et sont solides :

**Le timeout tue le sujet, et il l'explique.** Ma première crainte était un `got -1` cryptique ; le
verdict complet dit exactement ce qu'il faut, avec le remède et une observation :

```
FAIL subject-that-hangs  0/1  2.0s
    timeout
      expected  the subject exits within 2.0s
      got       still running after 2.0s, so it was killed. Raise `timeout:` on the case if it is
                meant to take this long, otherwise look at what it was waiting for — it wrote
                nothing at all
```

**Le timeout couvre aussi les hooks**, ce qui n'était pas acquis : « A hook that waits for something
that never comes hangs the suite as thoroughly as a subject does ».

**Deux cas revendiquant un nom sont refusés au chargement**, avec les trois raisons (JUnit malformé, clé
du rapport HTML, ligne terminale ambiguë).

**`equals` pointe la ligne qui diverge** : `expected line 3 "charlie"` / `got line 3 "CHARLIE" (the
first 2 lines matched)`.

**`setup.stdin` encaisse 5 Mo** en 110 ms, les 25 000 lignes reçues, et un sujet qui ferme son entrée
après une ligne (`head -1`) ne produit ni blocage ni erreur.

---

## 1. Le timeout tue le sujet, pas sa descendance

Un sujet qui a lancé un processus en arrière-plan laisse celui-ci vivant après avoir été tué :

```yaml
name: orph
timeout: 2
setup: { run: ["sh", "-c", "$GAVELDROP_PROJECT/relprobe & while true; do sleep 1; done"] }
```

```console
avant: 0
apres: 1
 2711     1 sleep 297      ← PPID 1 : reparente a init
```

`adapters.rs:151` fait `child.kill()`, qui envoie SIGKILL au seul processus direct. Le commentaire des
lignes 112-114 montre que la survie d'un petit-enfant est connue — « a grandchild can still hold the
input pipe » — mais elle n'est traitée que pour éviter que le thread d'écriture se bloque, pas pour
nettoyer le processus.

**Pourquoi ça compte au-delà de l'hygiène.** Un sujet qui démarre un service en arrière-plan est banal :
c'est le cas de tout `serve:`-like écrit à la main, de tout script qui lance un worker, de tout test
d'intégration. Sur un runner, l'orphelin tient un port et fait échouer le job suivant pour une raison
qui n'apparaît nulle part. Et la promesse du timeout — « la suite ne se bloque pas » — devient partielle
sans que le rapport le dise.

**Piste :** placer le sujet dans son propre groupe de processus (`process_group(0)` sur Unix) et tuer le
groupe plutôt que le pid. C'est ce que fait `timeout(1)` avec `--kill-after`, et ça vaut aussi pour le
hook `setup.exec`.

## 2. Un nom de cas vide est accepté

```yaml
name: ""
weight: 4
setup: { run: ["true"] }
expect: { exit_code: 0 }
```

```console
ok     4/4
```

La ligne terminale ne nomme rien. Le JUnit produit `<testcase name="">`. Et `--only ''` matche tous les
cas, donc ne peut pas cibler celui-là.

**C'est exactement le raisonnement de #120, appliqué à moitié.** Le message qui refuse deux noms
identiques dit : « A name is what identifies a case in every report this project writes — a JUnit file
with two testcases of the same name is malformed for several dashboards, the HTML report keys each
case's detail by it, and a terminal line naming a failure would not say which file to open. »

Les trois arguments valent tels quels pour le nom vide. Un `<testcase name="">` est malformé pour les
mêmes tableaux de bord ; une ligne `FAIL     0/4` ne dirait pas davantage quel fichier ouvrir.

À noter, et c'est cohérent : **deux** cas au nom vide sont bien refusés (`2 cases are called ""`). C'est
le cas unique qui passe.

**Piste :** refuser un `name` vide ou uniquement composé de blancs, au même endroit et avec le même
message que le doublon.

## 3. Un chemin qui sort de l'isolation par `..` n'est pas détecté

Le même fichier, écrit de deux façons, reçoit deux traitements :

```console
# "/etc/hosts"
expected  a resolvable path
got       path "/etc/hosts" resolves to /etc/hosts, outside the isolated root. Nothing is
          observed out there, so no assertion about it could ever hold

# "$HOME/../../../../etc/hosts"  — le meme fichier
expected  written by the subject
got       not written
```

La validation refuse le chemin absolu et laisse passer le chemin relatif équivalent, avec un message qui
désigne la mauvaise cause : « not written » suggère un défaut du sujet, alors que le chemin n'était pas
observable.

**Ce n'est pas une faille.** L'assertion échoue au lieu de devenir trivialement vraie, donc rien de
dangereux ne passe. C'est un problème de diagnosticabilité, et il touche la troisième propriété du
projet : le message envoie chercher un bug dans le sujet là où il faut corriger le cas.

Le raisonnement est déjà écrit dans `docs/adopting.md`, à propos des variables : « a stray `$TYPO` would
make an `absent` assertion trivially true ». La normalisation manque juste au chemin.

**Piste :** normaliser (`..` compris) avant de comparer à la racine isolée, et réutiliser le message
existant.

## 4. `timeout: 0` vaut « aucune limite »

```yaml
name: tz
timeout: 0
setup: { run: ["sh", "-c", "while true; do sleep 1; done"] }
```

```console
real 8.02          ← tue par un `timeout 8` externe, pas par gaveldrop
```

Un `0` se lit naturellement comme « le plus strict possible », et produit l'inverse : aucune limite du
tout. Le cas n'aurait jamais rendu la main.

**Pourquoi ça mérite un refus plutôt qu'une documentation.** Ce projet refuse déjà ce qui est ambigu, et
le fait bruyamment : `--shard 4/3` est refusé, une suite vide est refusée, un `min_score` supérieur au
total atteignable est refusé depuis la 0.1.2 — tous au motif qu'un run qui « fait silencieusement moins
que demandé » est le pire résultat possible. `timeout: 0` est le même cas de figure : il désarme la
protection en donnant l'impression de la resserrer.

**Piste :** refuser `0` au chargement, avec le choix explicite à faire — retirer la clé pour aucune
limite, ou donner une durée.

---

## Ce que je n'ai pas réussi à casser

Consigné pour éviter qu'on le retente : un `weight` négatif est refusé par le typage (`expected u32`) ;
un chemin absolu hors isolation est refusé avec le bon message ; le `--only` répété fonctionne et refuse
un fragment qui ne matche rien ; les durées par cas et le `slowest —` du résumé sont exacts ; la suite
de zanvil (59 cas) passe sans changement, en 13,8 s.

## Sur la méthode

Deux de mes conclusions ont été fausses en cours de route, et le dire fait partie du rapport :

- j'ai d'abord cru que le timeout ne s'expliquait pas, parce que je lisais la dernière ligne du verdict
  (`exit_code got -1`) et non la première ;
- mon premier test d'orphelin utilisait `sleep 300 --marqueur`, que `sleep` refuse — l'enfant n'avait
  jamais démarré, et j'ai conclu à tort que le nettoyage était complet. Le finding nº 1 n'existe que
  parce que j'ai revérifié que la sonde faisait ce qu'elle prétendait.

C'est la même leçon que la vérification par mutation : un test qui passe sans qu'on ait vu son échec ne
prouve pas ce qu'on croit.
