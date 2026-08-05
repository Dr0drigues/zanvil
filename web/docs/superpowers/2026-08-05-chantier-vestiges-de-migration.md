# Chantier — les vestiges du renommage `zsh_env` → `zanvil`

**À prendre en compte, pas encore fait.** Ce document est le cadrage, écrit pendant le chantier 3 du
spec zsh/Rust parce que c'est là que le problème est apparu deux fois de suite.

## Ce qui a déclenché ce cadrage

Deux pannes du même type, à trois jours d'écart :

**Le 3 août, le binaire.** `~/.local/bin/` portait `zsh-env-cli` v3.0.0 et pas `zanvil`. Quatre mois
sans que rien ne le signale, précisément parce que le repli fonctionnait. Corrigé : `install.sh` retire
l'ancien binaire, `doctor` porte une section `Binaire` qui compte son absence comme une erreur, et un cas
gaveldrop tient la position.

**Le 5 août, les variables d'environnement.** En cherchant pourquoi un cas rendait un verdict différent
sur ma machine et sur un runner, j'ai trouvé que mon `env.d/work.zsh` exporte encore
`ZSH_ENV_WORK_NEXUS_URL`. Le code lit `ZANVIL_WORK_NEXUS_URL` depuis la v4.0.0.

Le même mécanisme, la même durée, la même absence de signal.

## L'inventaire, mesuré

Sept variables `ZSH_ENV_*` sont encore exportées sur ce poste, depuis deux fichiers de `env.d/`. Ce qui
décide de la gravité n'est pas leur nombre mais si le code attend leur équivalent :

| Ancien nom exporté | Le code lit-il l'équivalent `ZANVIL_*` ? | Conséquence |
|---|---|---|
| `ZSH_ENV_WORK_ES_URL` | **oui** — `elasticsearch.zsh:11` | L'URL Elasticsearch réglée est ignorée : le défaut en dur s'applique |
| `ZSH_ENV_WORK_NEXUS_URL` | **oui** — `work_context.zsh:10` | La détection du contexte Work est inerte |
| `ZSH_ENV_WORK_TIMEOUT` | **oui** — `work_context.zsh:13` | Le timeout réglé est ignoré, le défaut de 2 s s'applique |
| `ZSH_ENV_WORK_CACHE_TTL` | **oui** — `work_context.zsh` | Le TTL du cache réglé est ignoré |
| `ZSH_ENV_DOCKER_ADDRESS_POOL` | non | Vestige sans effet, ou réglage abandonné |
| `ZSH_ENV_WORK_PKI_URL` | non | Idem |
| `ZSH_ENV_ENTERPRISE_CA_ISSUERS` | non | Idem |

**Quatre réglages sur sept sont donc silencieusement inertes.** Aucun message, aucune trace : la valeur
par défaut s'applique et rien ne dit qu'un choix a été écrasé.

## La cause : la migration ne couvre pas `env.d/`

`core/lifecycle/migrate_zanvil.zsh` réécrit deux fichiers :

```zsh
sed -e 's/ZSH_ENV_DIR/ZANVIL_DIR/g' -e 's#\.zsh_env#.zanvil#g' "$zshrc"   # .zshrc
sed 's/ZSH_ENV_/ZANVIL_/g' "$cfg"                                          # config.zsh
```

`grep -c 'env.d' core/lifecycle/migrate_zanvil.zsh` rend **0**. Or `env.d/*.zsh` est l'endroit que
`CLAUDE.md` et `examples/env.d/` désignent pour les variables d'environnement — donc le lieu le plus
probable où trouver des `ZSH_ENV_*`, et le seul que la migration ignore. `secrets/` non plus n'est pas
couvert (`grep -c 'secrets'` rend 0), ce qui reste à vérifier.

Les fichiers de `env.d/` sont gitignorés : **le dépôt n'est pas fautif, la migration l'est.**

## Les trois volets

### 1. Étendre la migration à `env.d/` et vérifier `secrets/`

Le même `sed` que pour `config.zsh`, avec la même prudence — sauvegarde horodatée, fichier temporaire
plutôt que `sed -i` dont la syntaxe du suffixe diffère entre BSD et GNU. Le code existant est le modèle,
il n'y a rien à inventer.

Point d'attention : la migration ne s'exécute qu'une fois, quand `~/.zsh_env` existe encore. Un poste
déjà migré ne la rejouera pas, donc étendre la migration ne répare **pas** les postes déjà passés. D'où
le volet 2, qui est le seul à les atteindre.

### 2. Faire dire à `doctor` qu'un réglage est mort

C'est le volet qui compte, et le raisonnement est déjà écrit dans le spec zsh/Rust à propos du binaire :
**un repli silencieux masque une panne, un repli est acceptable s'il est visible.**

Ce que `doctor` peut voir sans rien deviner : une variable `ZSH_ENV_<X>` exportée alors que le code lit
`ZANVIL_<X>`. Le test est mécanique — la liste des noms lus est dans le code — et le message peut nommer
le fichier de `env.d/` qui l'exporte.

Un cas gaveldrop tient la position : `env: { ZSH_ENV_WORK_ES_URL: "…" }` doit faire apparaître
l'avertissement. C'est testable sans réseau et le verdict est le même partout, contrairement à ce que
j'ai essayé pour les sondes réseau du démarrage.

### 3. Corriger la documentation qui renvoie à des noms disparus

`web/docs/ROADMAP.md:5` dit « Version actuelle : voir `core/ui.zsh` (`ZSH_ENV_VERSION`) ». Cette variable
n'existe plus : `grep -c 'ZSH_ENV_VERSION' core/ui.zsh` rend 0.

Le reste des occurrences est légitime et ne doit pas être touché : `migrate_zanvil.zsh` porte les anciens
noms parce que c'est son métier, la ligne 69 du ROADMAP les cite comme historique livré, et les plans
sous `superpowers/plans/` sont des archives datées.

Le garde-fou `tests/bin/stale-binary-references` fait déjà ce travail pour l'ancien nom du binaire, en
restreignant son scan aux invocations et en excluant `install.sh`. Le même patron s'applique ici : scanner
les **lectures** de variables, pas les mentions.

## Ce que ce chantier n'est pas

**Ce n'est pas un renommage de plus.** Le renommage est fait et livré ; ce chantier traite ce que le
renommage a laissé derrière lui sur les postes, et l'absence de mécanisme pour le voir.

**Ce n'est pas un audit de sécurité.** Aucune de ces variables ne porte de secret. Le préjudice est
qu'un réglage explicite est ignoré sans le dire — sur `WORK_ES_URL`, cela signifie interroger l'instance
par défaut au lieu de celle qu'on a choisie.

## Lien avec l'autre chantier ouvert

Trois des quatre réglages perdus appartiennent au module `work`, dont l'extraction vers un dépôt privé
est cadrée dans [le document voisin](2026-08-05-cadrage-depot-prive-work.md). Si cette extraction se
fait, elle emporte une partie du problème avec elle — mais pas le mécanisme de détection, qui vaut pour
toutes les variables du projet.
