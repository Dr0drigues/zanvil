# Demandes d'évolution gaveldrop — les échanges, depuis zanvil

**Pour un agent travaillant dans `~/work/misc/gaveldrop`.** Rien n'a été modifié là-bas ; tout ce qui
suit est décrit, jamais corrigé sur place.

> **Répondu par la `v0.1.14` — sept demandes sur neuf livrées.** Vérifié contre l'archive publiée, par
> comportement. Réponse détaillée dans `~/work/misc/gaveldrop/docs/superpowers/maj-zanvil-0-1-14.md`.
>
> | # | État | Constaté ici |
> |---|---|---|
> | 1. `shell.md` muet sur les échanges | livré | Les deux formes documentées, avec `weight`, `expect: {}` et la persistance de la racine isolée. |
> | 2. `timeout:` par échange | livré | **8,3 s → 2,0 s.** « the case exits within 2.0s, exchanges included », l'échange tué est nommé, les non tentés le disent chacun sous son chemin. |
> | 3. `calls` cumulatifs par échange | livré | La sonde qui donnait `2` au second échange donne `1`. Le global additionne toujours. |
> | 4. Chemin d'un `calls` violé | livré | `steps[1] "le deuxieme se trompe".calls.outil`. |
> | 5. « The body was empty » | livré | « there is no response document to walk … a process and a shell function answer text on standard output ». |
> | 6. `time` sur les nœuds JUnit | **refusé** | Sur la condition que j'avais posée : la durée n'est pas mesurée par échange, donc la condition s'applique. Et le motif qui la justifiait est parti avec la nº 2. |
> | 7. Règle d'agrégation non documentée | livré | Table dans `shell.md` et dans le schéma, sur `exit_code` et sur `steps`. |
> | 8. `args_include` | livré | Vérifié en sonde : `theme` servi, `themes` refusé. La même sonde en `args_contain` laisse passer les deux — c'était bien le trou. |
> | 9. Association sur une ligne | livré, **corrigé** | `line_includes`, adopté dans `cli-modules-list-reflects-config-zsh`. |
>
> **Sur la nº 9, ma proposition était fausse et ils l'ont corrigée.** Je demandais des fragments cherchés
> comme sous-chaînes ; écrite ainsi, l'assertion **passe** sur la table inversée, puisque « inactif »
> contient « actif ». Les valeurs sont donc comparées comme des **mots** — d'où `include` plutôt que
> `contain`, la même distinction que pour `args_include`. Mes deux trous d'injection étaient le même trou.
>
> **Les demandes 10 et 11 sont livrées par la `v0.1.15`, et adoptées ici.**
>
> | # | Constaté |
> |---|---|
> | 10. `not_written` | Adopté sur six cas. Le message dit *comment* le chemin a été touché — « created, 7 bytes » — ce qui envoie au bon endroit, un fichier créé, modifié ou supprimé demandant trois enquêtes différentes. |
> | 11. `fake.bins` par cas | `--verbose` montre `faked … zanvil` pour le seul cas concerné, et les huit cas de `tests/cases/sync/` atteignent toujours le vrai binaire. |
>
> **La nº 11 rend son assertion au cas de délégation.** Avec `bins: [zanvil]` déclaré dans le cas et
> `args_include: ["theme"]` dans la règle, la mutation `theme` → `themes` rougit désormais **dans les deux
> configurations** — avec le binaire installé comme sans. Elle ne mordait avant que là où le binaire
> existe, ce qui laissait la CI aveugle à une panne que ce projet a déjà vécue.
>
> Deux remarques sur leur mise en œuvre, parce qu'elles nous concernent :
>
> - `bins` est **additif** et `setup.hide` gagne toujours. C'est le bon sens : un cas qui désombrerait un
>   outil en silence ferait moins que ce que la suite demande.
> - `not_written` **ne dit rien de l'existence**. Un fichier jamais créé n'est pas écrit, et un fichier déjà
>   là et laissé tranquille non plus. Nos six usages veulent la première lecture ; pour prouver qu'un
>   fichier *survit*, il faudra le créer dans le hook d'abord.
>
> Et un défaut qu'ils ont trouvé en câblant la nº 14, dans la liste où j'avais trouvé le nº 4 :
> `files::check` était **la huitième vérification à composer sa propre racine**, donc un `files:` cassé dans
> un échange était rapporté `expect.files[…]`. « Il était dans la même liste et aucun de nous deux n'a
> regardé au-delà de ce que vous aviez énuméré. » — c'est juste, et ça vaut d'être retenu : énumérer sept
> cas sur huit se lit comme une liste exhaustive.

## Ce qui a produit ces demandes

zanvil est passé de la 0.1.5 à la 0.1.12 d'un coup, sans document de mise à jour dans le canal. **Les 59
cas passent inchangés** : 223/223, en 11,2 s contre 13,8 s — sept versions d'écart, zéro adaptation. La
deuxième propriété du format tient, et c'est ce qui a permis de travailler sur le reste.

Les quatre findings du rapport 0.1.5 sont corrigés et vérifiés par comportement, pas d'après le
changelog : le groupe de processus est bien tué (l'enfant tourne pendant le run, zéro après), le nom vide
est refusé avec les trois arguments demandés, le `..` est résolu avant la comparaison, et `timeout: 0`
est refusé avec « disarms the guard rather than tightening it ».

Les demandes ci-dessous portent toutes sur les **échanges** (0.1.11/0.1.12), parce que c'est le code le
plus récent et que zanvil en est le premier consommateur shell. Elles sont classées par ce qu'elles
coûtent, pas par difficulté.

Le rapport complet, avec les reproductions et ce qui tient :
`~/.zanvil/web/docs/superpowers/reports/2026-08-05-gaveldrop-0-1-12-echanges.md`.

---

## 1. Bloquant : `docs/shell.md` ne mentionne pas les échanges

C'est la seule demande qui a coûté du travail immédiat. Pour écrire mon premier cas à échanges, j'ai dû
lire `crates/gaveldrop/src/adapters/process.rs` — le geste exact que la troisième propriété du projet
cherche à rendre inutile.

Le support existe et il est **double**, ce que rien n'annonce côté doc :

```yaml
steps:
  - name: "l ecriture pose l etat"
    request: { run: ["sh", "-c", "echo ecrit > note.txt"] }   # commande propre a l echange
    expect: { exit_code: 0 }
  - name: "la relecture retrouve le meme etat"
    request: { run: ["sh", "-c", "cat note.txt"] }
    expect: { stdout: { contains: ["ecrit"] } }
```

et un échange **sans** `request`, qui réinvoque le `setup.run` — la répétition d'invocation de la #142,
vérifiée sur `process.rs:504-512`.

**Demandé :** une section « Exchanges » dans `docs/shell.md`, avec les deux formes et une phrase sur ce
qui est partagé entre échanges. Deux points valent d'y figurer parce qu'ils m'ont coûté un aller-retour
chacun : **`weight` est requis**, et **`expect:` au niveau du cas l'est aussi** — même quand chaque
échange porte le sien, il faut écrire `expect: {}`.

Un troisième mérite une phrase, parce qu'il décide de la faisabilité d'un scénario : **l'état de la
racine isolée persiste entre les échanges**. C'est ce qui rend testable un export suivi d'une relecture,
et c'est exactement l'usage pour lequel zanvil va s'en servir.

**Écarté :** générer cette section depuis `case.schema.json`. Le schéma dit ce qu'une clé accepte ;
`shell.md` doit dire ce qu'un `run` répété *signifie* pour un processus, ce qu'aucune description de
champ ne porte.

## 2. Majeur : le `timeout:` borne chaque échange, pas le cas

Reproduction, contre l'archive publiée de la 0.1.12 :

```yaml
name: quatre-echanges-bloques
weight: 1
timeout: 2
setup: { run: ["sh", "-c", "true"] }
steps:
  - { name: "premier bloque",   request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
  - { name: "deuxieme bloque",  request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
  - { name: "troisieme bloque", request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
  - { name: "quatrieme bloque", request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
expect: {}
```

```console
FAIL quatre-echanges-bloques  0/1  8.3s
    timeout
      expected  the subject exits within 2.0s
      got       still running after 2.0s, so it was killed. […] it wrote nothing at all
```

Le cas annonce 2 s et tient **8,3 s**. Le verdict imprime « exits within 2.0s » à trois caractères du
`8.3s` qu'il vient de mesurer. Un cas à vingt échanges avec `timeout: 30` peut tenir dix minutes en
annonçant trente secondes.

Le comptage est aussi partiel. Dans `gathered()` :

```rust
let timed_out_after_ms = steps.iter().filter_map(|seen| seen.timed_out_after_ms).next();
```

Quatre échanges ont été tués ; le rapport en mentionne un.

**Pourquoi ça mérite mieux qu'une ligne de doc.** C'est le motif du finding `timeout: 0` que la 0.1.6 a
corrigé en refusant la valeur — une protection qui paraît resserrée et qui se relâche. Ici elle se dilue
par le nombre d'échanges, et le facteur n'apparaît nulle part : `grep -i timeout docs/*.md` ne renvoie
rien sur les échanges, et le schéma dit « how many seconds **this case's subject** may run before it is
killed », au singulier.

**Demandé :** trancher entre les deux lectures, et que le rapport dise laquelle.

- Si `timeout:` borne le **cas**, chaque échange consomme le budget restant, et le verdict reste exact.
- S'il borne l'**échange**, le dire dans le schéma, écrire « each exchange exits within 2.0s » dans le
  verdict, et compter les dépassements au lieu d'en garder un.

Ma préférence va au premier : c'est la lecture que le mot « case » induit, et c'est celle qui préserve la
promesse « la suite ne se bloque pas » indépendamment du nombre d'échanges.

**Écarté :** une clé `timeout_per_step:` séparée. Deux limites à tenir dans la tête pour un format dont
la valeur est qu'un cas se lit d'un coup — et le jour où elles se contredisent, il faut documenter
laquelle gagne.

## 3. Majeur : `expect.calls` dans un échange compte depuis le début du cas

| Échange | Appels réels | Ce qu'il voit |
|---|---|---|
| `steps[0]` | 1 | **1** ✓ |
| `steps[1]` | 1 | **2** ✗ |
| global | 2 | 2 ✓ |

Vérifié par élimination : `calls: { outil: 1 }` au premier échange passe, la même assertion au second
échoue, `{ outil: 2 }` au second passe. Le journal n'est pas segmenté par échange.

**La conséquence est celle que `writing-cases.md` promet d'éviter.** Cette page défend les assertions qui
ne cassent pas « the day the subject gains one log line ». Ici, insérer un échange en amont fausse le
`calls` de tous les suivants, et écrire celui du troisième échange demande de compter les appels des
deux premiers.

Pour zanvil ça mord tout de suite : les cas du viewer k9s assertent `calls: { fzf: 1 }`, et leur forme
naturelle en échanges — ouvrir, puis rafraîchir par `Ctrl-R` — verrait 2 au second.

**Le remède est déjà écrit, dans la même boucle.** `process.rs:92-94` segmente les effets fichiers
ainsi :

```rust
let before = crate::iso::snapshot::Snapshot::take(iso.root());
let mut seen = one_run(case, iso, &argv)?;
seen.files = before.changes_since(iso.root());
```

**Demandé :** le même avant/après appliqué au journal d'appels, pour que `calls` ait par échange la
granularité que les fichiers ont déjà. Le global doit continuer à voir le cumul — il est juste
aujourd'hui.

**Un détail qui explique pourquoi ça n'a pas été vu.** Le commentaire de `gathered()` dit « the last exit
and **the last call journal**, because that is what "the run" ended as ». Comme le journal est cumulatif,
« le dernier » vaut « tous » : le résultat global est correct, mais pour une raison différente de celle
que le commentaire énonce. Le code et son commentaire décrivent deux mécanismes qui coïncident au niveau
global et divergent par échange. Ça vaut d'être corrigé aussi, sinon la prochaine lecture repart sur la
même hypothèse — c'est celle sur laquelle je suis parti, et elle m'a fait annoncer un défaut au mauvais
endroit avant que la sonde me corrige.

**Écarté :** demander aux cas d'écrire des compteurs cumulés. Ça marche et c'est exactement ce que la
page sur l'écriture des suites déconseille : une assertion dont la valeur dépend de tout ce qui précède
casse à la première insertion.

## 4. Mécanique : un `calls` violé dans un échange est rapporté comme s'il était global

```console
FAIL un-appel-par-echange  0/3
    expect.calls.outil          ← l assertion violee est celle de steps[1]
      expected  1
      got       2
```

On cherche donc un défaut dans le bloc `expect:` du cas, qui est correct. À comparer avec ce que le même
verdict produit pour `stdout` :

```console
    steps[1] "le deuxieme se trompe".stdout.contains[0]
```

`verdict.rs:230` est **la seule des sept vérifications de `check()` à ne pas recevoir le préfixe `at`** :

```rust
if let Some(expected) = &expect.calls {
    diffs.extend(calls::check(expected, &observations.calls));   // ← pas de `at`
}
```

Ses voisines le prennent toutes — `stdout` via `&format!("{at}.stdout")`, `stderr`, `events`,
`event_counts`, `invariants`, `status`. Et `verdict/calls.rs:21` écrit le chemin en dur :
`path: format!("expect.calls.{bin}")`.

**Demandé :** ajouter le paramètre `at` à `calls::check` et composer le chemin comme les six autres.
Indépendant du nº 3 : cette correction ne rend pas les comptes justes, elle dit seulement où regarder.

## 5. Mineur : « The body was empty » pour un sujet qui n'a pas de body

Un `capture:` sur un sujet process est correctement refusé, et pour la bonne raison — le commentaire de
`process.rs` la formule mieux que je ne le ferais : « a process answers text, and deciding that its
output is a JSON document to walk by path would invent a meaning for the format rather than implement
one ». Mais le message emprunte le vocabulaire du web :

```console
steps[0] "il capture un identifiant".capture.ident
  expected  a value at id
  got       the path yielded no value, so `$ident` stays literal in every later request.
            The body was empty
```

Le sujet avait écrit `{"id":7}` sur sa sortie standard. Le lecteur cherche donc pourquoi son sujet n'a
rien produit, alors qu'il a produit exactement ce qui était attendu, et que le vrai motif est qu'un
processus n'a pas de body du tout.

**Demandé :** pour l'adaptateur process, dire ce que le commentaire du code dit déjà. La phrase existe,
elle est juste restée dans la source.

## 6. Mineur : les nœuds JUnit d'échange n'ont pas de durée

```xml
<testcase name="the run as a whole" classname="gaveldrop.timeout-par-echange" time="4.645"/>
<testcase name="un et demi"         classname="gaveldrop.timeout-par-echange"/>
<testcase name="encore un et demi"  classname="gaveldrop.timeout-par-echange"/>
```

`writing-cases.md` pose que les durées « are reported everywhere and asserted nowhere », et la 0.1.12 a
ajouté la durée par cas. Les échanges n'en ont pas, ce qui laisse les 4,645 s indécomposables — c'est
précisément l'information qui aurait rendu le nº 2 visible sans qu'il faille le chercher.

**Demandé :** l'attribut `time` sur les nœuds d'échange, si la durée est déjà mesurée par échange. Si
elle ne l'est pas, ça ne vaut pas de l'ajouter pour ce seul motif — traitez le nº 2 et celui-ci tombe.

## 7. Documentation seule : `expect.exit_code` sélectionne, ses voisines agrègent

Ce cas passe :

```yaml
steps:
  - { name: "celui du milieu echoue vraiment", request: { run: ["sh", "-c", "echo boum >&2; exit 42"] },
      expect: { stderr: { contains: ["boum"] } } }
  - { name: "le dernier reussit", request: { run: ["sh", "-c", "echo fini"] },
      expect: { stdout: { contains: ["fini"] } } }
expect:
  exit_code: 0        # ← vrai, et un echange est sorti en 42
```

**Je ne demande pas de le changer.** `gathered()` l'assume — « that is what "the run" ended as » — la
définition se défend, et un échange qui échoue exprès au milieu d'un scénario est un usage légitime.

Ce qui manque, c'est de le dire côté utilisateur : `expect.stdout` concatène tous les échanges,
`expect.exit_code` en sélectionne un. Deux clés voisines dans le même bloc, deux règles d'agrégation
opposées, aucune des deux écrite dans le schéma. Un cas qui n'observe pas ses échanges un par un croira
avoir vérifié que rien n'a échoué.

**Demandé :** une phrase dans la description de `exit_code` et une dans celle de `steps`.

---

# Deux demandes nées d'une campagne d'injection

Douze défauts volontaires ont été injectés dans zanvil sur un worktree isolé, classés en mineurs,
majeurs et complexes, pour mesurer ce que la suite attrape. Rapport complet :
`~/.zanvil/web/docs/superpowers/reports/2026-08-05-injection-de-defauts-classes.md`.

Résultat : **les quatre défauts majeurs sont tous attrapés**, avec des portées cohérentes — `pad()`
neutralisé fait rougir 17 cas, un troncage de logger 2, un raccourci disparu 1. Deux trous existaient,
tous deux comblés côté zanvil. Mais les deux ont demandé une contorsion, et c'est là que portent ces
demandes.

## 8. `args_contain` ne distingue pas un nom de sous-commande de son préfixe

Le défaut injecté : renommer `zanvil theme` en `zanvil themes` dans une fonction zsh qui délègue. C'est
la panne réelle de zanvil, rejouée — un binaire renommé a laissé trois commandes en mode dégradé pendant
quatre mois.

Le cas écrit pour l'attraper :

```yaml
fake:
  rules:
    - match: { bin: zanvil, args_contain: "theme" }
      stdout: "Available themes:"
    - match: {}
      exit: 127
```

**Il passe aussi sous la mutation.** `args_contain` est documenté comme « substring searched for in the
arguments joined by spaces », et « themes » contient « theme » : la règle nommée sert le mauvais appel,
donc le catch-all ne voit rien et `unexpected calls` reste vide.

La parade existe — inclure l'argument suivant :

```yaml
    - match: { bin: zanvil, args_contain: "theme list" }
```

« themes list » ne contient plus « theme list », et le cas mord. Mais la règle est désormais couplée à la
forme complète de l'appel : le jour où la fonction insère un drapeau entre les deux, elle cesse de
matcher pour une raison qui n'a rien à voir avec ce qu'elle vérifie.

**Demandé :** un critère qui compare un argument comme **mot** plutôt que comme sous-chaîne — soit un
`args:` qui prend la liste exacte, soit la sémantique « l'un des arguments égale cette valeur ». Le cas
d'usage n'est pas exotique : vérifier qu'une délégation appelle la bonne sous-commande est le premier
usage d'un `fake` sur son propre binaire, et distinguer un nom de son préfixe est exactement ce qu'un
renommage exige.

**Écarté :** une expression régulière dans `args_contain`. Ça résoudrait ce cas et ouvrirait la porte à
des règles illisibles en revue, ce qui coûterait la première propriété du format. Un critère nommé qui
dit ce qu'il fait vaut mieux qu'un langage dans une chaîne.

## 9. Rien n'exprime « ces deux fragments sur la même ligne »

Le défaut injecté : inverser `if enabled` en `if !enabled` dans le CLI, ce qui échange tous les statuts
d'une table `MODULE / STATUT / DESCRIPTION`.

Le cas assertait `contains: ["KUBE", "DOCKER", "actif", "inactif"]`. Les quatre mots restent présents
après l'inversion, l'assertion reste vraie, et **la sortie est entièrement fausse**. `contains` dit qu'un
fragment existe, jamais que deux fragments sont associés.

La seule parade disponible est de figer la ligne avec son espacement :

```yaml
      - "KUBE         actif"
```

Elle mord, et c'est ce qui est en place aujourd'hui. Le coût est écrit dans le cas : treize espaces
figés, donc passer `{:<12}` à `{:<14}` — une décision de présentation — fera rougir un test de
comportement. C'est précisément ce que `writing-cases.md` déconseille : « a case that breaks for that
reason gets deleted rather than maintained ».

**Demandé :** un moyen d'asserter une association sans figer la mise en forme. La forme la plus proche de
l'existant serait une entrée de `TextExpectation` qui prend plusieurs fragments à trouver dans une même
ligne — quelque chose comme `line_contains: [["KUBE", "actif"]]`, dont l'échec dirait quelle ligne a été
trouvée et ce qui y manquait.

**Écarté :** `equals` sur la sortie entière. C'est possible aujourd'hui et c'est pire : treize lignes
figées au lieu d'une, et un cas qui rougit dès qu'un module s'ajoute — alors que l'ajout d'un module est
exactement ce que cette commande doit savoir faire.

---

# Deux demandes nées de la migration de `sync`

Le chantier 2 du spec zsh/Rust a été mené jusqu'au bout avec gaveldrop comme filet : huit cas
caractérisent la fonction zsh, le Rust a été complété jusqu'à les satisfaire, puis la délégation a été
branchée. **Les huit passent inchangés dans les deux configurations** — le Rust quand le binaire est
installé, le repli zsh quand il ne l'est pas. C'est exactement la non-régression que le format promet, et
elle a tenu.

Deux choses ont manqué en route.

## 10. Rien ne permet d'asserter qu'un fichier n'a **pas** été écrit

Un import qui refuse un fichier illisible ne doit rien laisser derrière lui — en particulier pas la
sauvegarde `config.zsh.pre-import`, dont la présence signifierait qu'il avait déjà commencé à travailler.

Le cas ne peut pas le dire. Les quatre champs de `expect.files` portent tous sur un contenu :

```console
case ...sync-import-refuses-a-missing-file.yaml is invalid:
  expect.files.zanvil/config.zsh.pre-import: unknown field `absent_file`,
  expected one of `contains`, `absent`, `equals`, `ignore_ansi`
```

Le message est bon — il liste les champs valides — mais il n'y en a aucun pour l'absence. Écrire
`contains: []` ne dit rien, et `equals: ""` teste un fichier vide, ce qui est un autre fait.

**Demandé :** un moyen de déclarer qu'un chemin ne doit pas exister à la fin du cas. L'information est
déjà côté moteur, puisque `unmentioned files` sait lister ce qui a été écrit sans être asserté ; il
manque de pouvoir la retourner en exigence.

**Écarté :** un `expect.files` où la clé seule, sans valeur, vaudrait « absent ». Une clé qui change de
sens selon qu'elle a un corps ou non se lit mal en revue, et le format tire sa valeur de l'inverse.

## 11. `fake.bins` est global, donc falsifier son propre binaire interdit de l'utiliser ailleurs

Le pattern de délégation est central dans zanvil : douze sous-commandes, invoquées depuis le zsh, dont
`zanvil project` 47 fois. Une fonction fait `command -v zanvil` puis appelle le binaire **par son nom**.

Pour vérifier *avec quels arguments* elle l'appelle, il faut un faux — donc `fake.bins: [zanvil]`. Mais
`bins` est global à `gaveldrop.yaml`, et le faux prend la tête du `PATH` : les huit cas de
`tests/cases/sync/` se sont alors mis à parler à un faux muet et à échouer en bloc, alors qu'ils ont
besoin du vrai pour prouver que la délégation rend le même résultat que le repli.

Les trois portes de sortie sont fermées, et chacune pour une bonne raison :

- **`setup.env` refuse `PATH`** — « isolation defines it, and a case that could point it elsewhere would
  undo the isolation it is running in ». Le refus est juste, et le message le dit bien.
- **`setup.hide`** retire des répertoires entiers et ne pose pas de symlink pour l'outil hidé : il donne
  « aucun zanvil », pas « le vrai zanvil ».
- **`fake` par cas** n'accepte que `rules` et `render`, pas `bins`.

Le résultat est qu'on doit choisir, pour toute la suite, entre observer les appels à son propre binaire
et s'en servir. J'ai choisi de m'en servir, et le cas de délégation a perdu son assertion la plus forte —
le nom exact de la sous-commande, vérifiable partout. Il ne détecte plus un renommage que là où le
binaire est installé.

**Demandé :** de quoi lever le choix. Deux formes possibles, par ordre de préférence :

1. **`bins` déclarable par cas**, en complément du global — la symétrie de `setup.hide`, qui permet déjà
   à un cas de se soustraire à une falsification globale. Ici il s'agirait de s'y ajouter.
2. **Un `setup.expose`** qui ajoute un répertoire du projet devant le `PATH` de l'isolation sans le
   remplacer. Plus général, mais il entame la propriété que le refus de `env.PATH` protège, donc la
   première forme me paraît plus sûre.

**Écarté :** qu'un hook dépose lui-même un script `zanvil` journalisant ses arguments dans un répertoire
du `PATH`. C'est faisable — le `PATH` de l'isolation contient `$HOME/.local/bin` — et c'est
précisément le contournement qu'il ne faut pas : ce serait réécrire `fake` et son journal à la main, dans
un hook, sans le verdict `unexpected calls` qui en fait la valeur.

---

## Ce qui tient, et qu'il ne faut pas retoucher

Éprouvé et solide, consigné pour que personne n'y touche en corrigeant le reste :

- l'état de la racine isolée **persiste** entre les échanges ;
- **tous** les échanges tournent, même après un échec, et **toutes** les assertions sont rapportées —
  le global d'abord, puis les échanges dans l'ordre ;
- le verdict situe l'assertion par index **et** par nom : `steps[1] "le deuxieme se trompe".stdout.contains[0]` ;
- un échange **sans nom** donne `<testcase name="step 1">` dans le JUnit, pas le `name=""` que le nom de
  cas vide produisait — le raisonnement de la #130 est bien appliqué aux échanges, je m'attendais à le
  trouver à moitié et il ne l'est pas ;
- les effets **fichiers** sont correctement segmentés par échange ;
- le **catch-all reste obligatoire**, et le message le justifie ;
- `steps: []` est accepté et se comporte comme un cas sans échanges ;
- un échange déclaré mais non effectué est rapporté avec le compte des deux côtés, et l'inverse est
  traité comme « the same class of surprise as an unexpected call ».

## Une remarque sur le canal

La 0.1.6 à la 0.1.12 sont arrivées sans document dans `docs/superpowers/`. Ce n'est pas un reproche — le
changelog et les docs suffisaient — mais deux choses m'ont coûté du temps et une aurait tenu en une
ligne : que **les quatre findings de zanvil étaient traités** (je l'ai vérifié en le testant), et que
`@v1` avait déjà emmené la CI de zanvil en 0.1.12 sans qu'aucun commit de zanvil ne le dise. Le tag
mobile fait ce qu'on lui demande ; c'est juste qu'un consommateur ne sait pas quand il change de version.
