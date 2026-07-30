# Suite de tests gaveldrop — assertions là où il n'y en a aucune

## Problème

zanvil n'a pas de tests. Il a un `.shellspec` sans aucun spec — reliquat de la suite supprimée en
mars 2026 — et quatre étapes de `.github/workflows/tests.yml` écrites en shell dans du YAML, dont
trois ne peuvent pas échouer :

- **`Verify zsh loads without errors`** construit à la main l'isolation entière (`mktemp -d`,
  `export HOME`, `mkdir -p .config .kube work`, copie de `config.zsh.example`), source `rc.zsh` avec
  `2>&1`, puis `echo`. **Il n'y a aucune assertion.** Un module qui casse au chargement ne rougit pas.
  Pire : `examples/config.zsh.example:46` déclare `ZANVIL_PLUGINS=(zsh-autosuggestions
  Aloxaf/fzf-tab)` et `plugins.zsh:136` fait `git clone` — cette étape **atteint le réseau** à chaque
  exécution, silencieusement.
- **`Test CLI commands`** lance cinq commandes, trois terminées par `|| true`. Rien n'est asserté sur
  aucune sortie ; `doctor` peut paniquer sans que le job échoue.
- **`Test binary-absent fallback warnings`** est la seule qui teste quelque chose : elle ampute
  `PATH`, source les quatre `modules/tools/*/init.zsh` et cherche `brew install …`. Mais elle ne
  couvre que **la moitié absente** — la branche où le binaire est présent n'est jamais exercée, parce
  que cela supposerait d'installer posting, delta, lazygit et atuin sur le runner.

À quoi s'ajoute un trou indépendant : `scripts/tests/k9s-log-fmt.test.sh` et ses 53 assertions ne
sont référencés **nulle part** dans `.github/` — ils ne tournent jamais en CI.

Et rien de tout cela ne s'exécute sur une machine de développement sans refaire les `export` à la
main.

Le gain visé n'est donc pas un nombre de lignes. C'est **des assertions là où il n'y en a aucune**,
la moitié de chaque module aujourd'hui intestable, et une suite exécutable localement.

## Solution

[gaveldrop](https://github.com/Dr0drigues/gaveldrop) — un moteur de test où **un cas est un fichier
YAML**. Il prépare un environnement isolé (`HOME` redirigé dans un répertoire temporaire), invoque le
sujet, observe, rend un verdict. zanvil ne change rien pour devenir testable : l'adoption consiste à
ajouter des fichiers, pas à en modifier.

zanvil est le **premier consommateur réel de l'adaptateur shell** de gaveldrop. Trouver un défaut
dans gaveldrop fait partie du résultat attendu, et le rapport final est la sortie la plus précieuse
de ce chantier.

### Ce que gaveldrop apporte ici

| Mécanisme | Ce qu'il débloque dans zanvil |
|---|---|
| Isolation de `HOME` | les `*_setup` écrivent dans `$HOME/.config/…` : observable sans machinerie |
| `fake:` (exécutable placé en tête de `PATH`) | la branche « binaire présent » **sans installer l'outil** |
| `calls:` | prouver qu'une dépendance a été appelée — ou ne l'a **pas** été |
| `setup.env` | activer un module guardé par `ZANVIL_MODULE_*` sans toucher au module |
| `setup.exec` | construire l'état dont le sujet a besoin, avant lui |

### Les trois murs, mesurés

Chacun a été vérifié sur une probe hors dépôt, pas supposé :

1. **Un cas ne peut pas déclarer qu'un outil est absent, et déclarer un outil *présent* interdit
   l'autre branche.** `PATH` dans l'isolation est le répertoire des symlinks de fakes suivi de celui
   hérité, donc `command -v posting` trouve l'outil réel quand la machine l'a. Le faker rend un outil
   *présent* ; rien ne le rend manquant.

   Le mur est plus haut que cela. `fake.bins` vit dans `gaveldrop.yaml` et **rien au niveau d'un cas
   ne peut le corriger** : le bloc `fake:` d'un cas n'accepte que `render` et `rules`. Le symlink est
   donc posé sur `PATH` pour *tous* les cas, y compris ceux sans bloc `fake:` — vérifié sur probe avec
   un outil qui n'existe sur aucune machine :

   ```
   FAIL does-a-declared-bin-exist-without-a-fake-block  0/1
       expect.stdout.contains[0]
         expected  contains "MISSING"
         got       SHADOWED
   ```

   Conséquence directe : déclarer `posting` — indispensable au cas « binaire présent » — rend le cas
   « binaire absent » **impossible à faire passer, y compris sur un runner nu**. Les deux branches
   d'un module sont mutuellement exclusives dans une même configuration, et les deux exemples que le
   briefing donne côte à côte sont donc incompatibles entre eux.

   Arbitrage retenu : gaveldrop prend la branche présente — celle qu'aucun mécanisme actuel n'atteint
   — et la branche absente reste couverte par l'étape CI existante, qui ampute `PATH` et fonctionne.
   Aucun cas `allow_fail` n'est écrit : un cas qui ne peut structurellement pas passer n'est pas une
   tolérance, c'est un cas faux.
2. **`setup` ne connaît que `env`, `exec` et `run` — il n'y a pas de `stdin:`.** Un filtre
   `stdin → stdout` comme `scripts/k9s-log-fmt.sh` n'est donc pas invocable directement.
3. **Aucune normalisation ANSI côté assertion.** Le formatteur entoure *chaque champ* de codes
   (`^[[2m08:00:00.123^[[0m ^[[1;32mINFO ^[[0m…`), donc un `contains:` sur une ligne rendue casse sur
   les escapes intercalés. `expect.invariants` ne comble pas ce manque : les invariants portent sur
   des *events* JSONL, pas sur du texte.

Les murs 2 et 3 imposent, pour la migration k9s du lot 2, un exécutable de plomberie côté zanvil —
pour que les cas restent des faits plutôt que d'embarquer un `sed`.

## Architecture

```
zanvil/
├── gaveldrop.yaml                        # cases, fake.bins, gate
├── tests/
│   ├── cases/
│   │   ├── boot/rc-loads-without-an-error.yaml
│   │   ├── cli/*.yaml                    # lot 1 — 5 cas
│   │   ├── modules/*.yaml                # lot 1 — 8 cas
│   │   └── k9s/*.yaml                    # lot 2
│   ├── hooks/prepare-zanvil-dir.sh       # lot 1
│   ├── bin/k9s-fmt-plain                 # lot 2
│   └── fixtures/k9s/*.jsonl              # lot 2
└── .shellspec                            # supprimé
```

`.shellspec` disparaît : il configure un outil qu'aucun fichier n'utilise, et la convention du projet
est de ne pas écrire de specs shellspec.

### `tests/hooks/prepare-zanvil-dir.sh` — la pierre angulaire

Un hook `setup.exec` unique construit un `ZANVIL_DIR` **à l'intérieur de l'isolation**, et tous les
cas déclarent `ZANVIL_DIR: "$HOME/zanvil"`. Il copie sélectivement `core/ modules/ config/ scripts/
examples/` plus `rc.zsh plugins.zsh completions.zsh`, puis écrit deux fichiers d'état :

- un `config.zsh` **hermétique**, avec `ZANVIL_PLUGINS=()` — aucun `git clone`, donc aucun réseau ;
- un `.current_theme` fixé, pour que les couleurs ne dépendent pas du poste.

Quatre raisons, toutes mesurées :

| Raison | Conséquence si `ZANVIL_DIR` pointait sur le dépôt |
|---|---|
| `.current_theme` et `config.zsh` sont gitignored | `theme current` et `modules list` rendent un verdict dépendant de la machine |
| `delta_setup` écrit dans `$ZANVIL_DIR/config/lazygit/config.yml` (`modules/tools/delta/init.zsh:31-38`) | un cas modifierait un fichier versionné |
| `rc.zsh` écrit `.last_update_check` et `.work_context_cache` dans `$ZANVIL_DIR` | les tests laisseraient des traces dans le dépôt |
| le dépôt pèse 1,9 Go (`cli/target`) | une copie intégrale est exclue — d'où la copie sélective |

`source:` reste relatif au dépôt, parce qu'un fichier sourcé **est** le sujet : le code testé vient
du dépôt, seul l'état est isolé.

## Le lot 1 — dix cas

### Chargement

`rc-loads-without-an-error`, poids 9. Le chargement complet, avec assertion : `ZANVIL_VERSION`
affiché, `stderr` exempt de `command not found`, `no such file or directory` et `parse error`.

Il exige un bloc `fake:` couvrant les outils appelés au démarrage, sinon gaveldrop refuse l'appel
imprévu. La probe l'a montré sur un cas concret : `modules/tools/posting/completions.zsh:4` exécute
`posting --completion-script-zsh` **à chaque démarrage de shell**. Le cas documente donc, au passage,
les dépendances réelles du démarrage.

### CLI (5 cas, poids 5 à 7)

`theme list`, `theme current`, `modules list`, `doctor`, `--help`. Chacun asserte **le code de sortie
et une chose sur la sortie** — n'importe quelle assertion est un progrès sur `|| true`. Si l'une de
ces commandes échoue légitimement, c'est un bug de zanvil à corriger, pas un cas à affaiblir.

Le briefing proposait un contournement par symlink (`ln -s "$GAVELDROP_PROJECT" "$HOME/.zanvil"`)
parce que `cli/src/config.rs:8-15` retombe sur `~/.zanvil`. **Il est inutile** : `setup.env` alimente
l'adaptateur process, donc `ZANVIL_DIR` passé en clair suffit. Vérifié sur probe
(`cli-theme-list-needs-no-symlink`, `ok 1/1`).

### Modules tools (4 cas, poids 5)

Un cas par module — `<tool>-<action>-when-the-binary-is-there` pour posting, delta, lazygit et
atuin — et un seul, à cause du mur nº 1 : déclarer l'outil dans `fake.bins` pour atteindre cette
branche rend l'autre inatteignable.

C'est l'argument de tout l'exercice : la branche « binaire présent » est aujourd'hui inaccessible en
CI, parce qu'elle supposerait d'installer quatre outils sur le runner. Déjà démontré sur probe pour
posting — `5/5`, avec assertion sur le fichier déployé (`$HOME/.config/posting/config.yaml`), sur
l'absence du message d'avertissement, et sur `calls: { posting: 1 }`.

La branche absente n'est pas perdue : elle reste couverte par l'étape CI qui ampute `PATH`, et qui
devient de ce fait une pièce nécessaire plutôt qu'un héritage.

### Pas de bloc `gate:`

Le total des poids du lot 1 vaut **56** — 9 pour le chargement, 27 pour les cinq cas CLI, 20 pour les
quatre branches présentes. Aucun des trois seuils que gaveldrop propose n'apporte quoi que ce soit à
une suite qui ne tolère aucun échec :

- `min_score` est comparé au score **absolu**, pas à un pourcentage (`report.rs:88`). Un
  `min_score: 80` — la valeur de l'exemple dans `docs/ci.md` — ferait échouer le gate en permanence sur
  une suite dont le maximum est 56. Et une valeur correcte devrait être bumpée à chaque cas ajouté.
- `fail_above_weight` ne se déclenche que sur un cas `!passed && !allow_fail` (`report.rs:109`), or un
  tel cas rend déjà `is_success()` faux. Redondant avec le code de sortie.
- `max_tolerated` n'observe que les cas `allow_fail`, et le lot 1 n'en compte aucun.

`gaveldrop.yaml` se limite donc à `cases:` et `fake.bins:`. Un `gate:` absent n'impose rien, et c'est
exact : ici, `failed == 0` est la seule question. Le bloc redeviendra utile le jour où un `allow_fail`
sera légitime — c'est-à-dire quand le mur nº 1 tombera.

## CI

Un job `cases` dans `tests.yml` : checkout, installation de zsh sur Linux (l'image `ubuntu-24.04` ne
l'embarque pas), `cargo install --git https://github.com/Dr0drigues/gaveldrop --rev
6d896b83b3bbe772700b75c5ecd1e1f94ed6fb2c --locked` pour **les deux** binaires, cache cargo, build du
CLI zanvil, puis `gaveldrop --annotate
--report-junit junit.xml` et l'upload du rapport en `if: always()`.

Deux points non évidents :

- **Il faut installer `gaveldrop-cli` *et* `gaveldrop-fake`.** Sans le second, toute exécution meurt
  sur `the fake binary was not found beside this executable`. `docs/ci.md:18` ne mentionne qu'un seul
  `cargo install`, pour une version publiée qui n'existe pas encore.
- **Le SHA est pinné.** gaveldrop est en 0.1.0 sans aucun tag ; suivre `main` ferait rougir la CI de
  zanvil pour un changement qui n'est pas dans zanvil. Le bump du SHA est un geste explicite.

### Ce que le job remplace, et ce qu'il ne remplace pas

| Étape actuelle | Sort |
|---|---|
| `Verify zsh loads without errors` | **remplacée** par `rc-loads-without-an-error`, qui asserte et n'atteint pas le réseau |
| `Test CLI commands` | **remplacée** par les cinq cas CLI |
| `Test binary-absent fallback warnings` | **gardée** — voir ci-dessous |
| `Verify core files exist`, `Verify modules structure` | **gardées** : gaveldrop saurait l'exprimer, mais ce serait un `ls` en moins bien |
| `scripts/tests/k9s-log-fmt.test.sh` | **ajoutée** en CI, où elle ne tournait pas, jusqu'à la fin du lot 2 |

L'étape `Test binary-absent fallback warnings` est gardée à contre-courant du briefing, et ce n'est
pas de la prudence : c'est le mur nº 1. Puisque `fake.bins` shadowe un outil pour toute la suite, la
branche absente est **inexprimable** en gaveldrop dès lors que la branche présente est testée. Cette
étape est donc le seul endroit où cette moitié du code est vérifiée. En amputant `PATH`, elle est
déterministe sur un runner ; la supprimer perdrait la couverture sans rien apporter. Elle partira
quand gaveldrop saura déclarer un outil absent, ou déclarer ses bins par cas.

## Le lot 2 — migration de `k9s-log-fmt.test.sh`

Les 53 assertions deviennent des cas, un scénario par fichier. Trois pièces :

- **`tests/bin/k9s-fmt-plain`** — reçoit un nom de fixture et les options du formatteur, alimente
  `scripts/k9s-log-fmt.sh` sur son entrée standard, retire les codes ANSI. Il existe uniquement à
  cause des murs 2 et 3 ; c'est de la plomberie que gaveldrop devrait rendre inutile, et le rapport le
  dira.
- **`tests/fixtures/k9s/*.jsonl`** — une fixture par scénario d'entrée (niveaux textuels et
  numériques, les quatre champs de stack trace, logger dotté et sans point, tabulations et retours
  chariot, JSON malformé, texte brut, absence de chaque champ). Plusieurs cas peuvent partager une
  fixture. `config/k9s/fixtures/logs-sample.jsonl` reste où il est : il sert à rejouer le rendu à la
  main, ce qui est documenté.
- **Les cas du viewer** gagnent au change : le test bash fabrique un faux `fzf`, que
  `fake: { bins: [fzf] }` fournit nativement.

`scripts/tests/k9s-log-fmt.test.sh` est supprimé à la fin du lot 2, et son étape CI avec lui.

## Hors périmètre

- Les modules non cités par le briefing (kube, git, docker, gitlab, ssh) : un second chantier, une
  fois la mécanique éprouvée.
- Le rendu couleur du formatteur : ni le test bash ni les cas migrés ne l'assertent — le wrapper
  retire les ANSI. Les mettre dans les attendus (`"\x1b[2m…"`) est possible mais illisible, ce qui
  contredit la première propriété de gaveldrop.
- Toute modification de `~/work/misc/gaveldrop`. Ce qui manque est décrit, pas corrigé ici.

## Vérification

- `gaveldrop` à la racine du dépôt, et `gaveldrop --watch` pendant l'écriture des cas.
- `gaveldrop --only <fragment>` pour un cas seul.
- La CI comme une étape unique, avec annotations sur la ligne de l'assertion qui casse.
- Critère de réussite qui n'est pas un nombre de lignes : **tout cas remplaçant un `|| true` doit
  pouvoir échouer**. Un cas incapable d'échouer est pire que le `|| true` qu'il remplace, parce qu'il
  ressemble à de la couverture.

## Rapport à gaveldrop

Livrable du lot 1, adressé au dépôt gaveldrop sans le modifier. Déjà acquis :

1. Le contournement par symlink du briefing est inutile — `setup.env` alimente l'adaptateur process.
   Si le briefing l'a recommandé, c'est que `setup.env` est moins connu qu'il ne le mérite.
2. L'installation depuis les sources demande **deux** `cargo install` ; `docs/ci.md` n'en documente
   qu'un, et l'échec est immédiat mais tardif.
3. Pas de `stdin:` dans `setup` : un filtre `stdin → stdout` — une forme très courante en shell —
   n'est pas invocable sans un wrapper.
4. Pas de normalisation ANSI avant assertion : tout sujet qui colore sa sortie force le même wrapper.
5. **Le plus important.** `fake.bins` est global et aucun cas ne peut s'en soustraire — le bloc `fake:`
   d'un cas n'accepte que `render` et `rules`. Déclarer un outil pour tester la branche « présent »
   rend donc la branche « absent » inatteignable, sur **toute** machine. Les deux exemples que le
   briefing donne côte à côte (`posting-warns-when-its-binary-is-missing` et
   `posting-deploys-its-config-when-the-binary-is-there`) ne peuvent pas coexister dans une même
   configuration. `allow_fail: true` ne sauve pas le premier : il ne masque pas une non-déterminisme,
   il masque un cas qui ne peut jamais passer.

   Deux formes de correctif possibles, à choisir chez gaveldrop : des `bins` déclarables par cas, ou
   la capacité de déclarer un outil absent — cette dernière rendant les deux cas déterministes d'un
   coup.
6. Corollaire du précédent : `unexpected calls` est jugé par cas alors que `bins` est global, donc un
   cas qui charge tout un shell doit prévoir une règle pour chaque outil déclaré ailleurs dans la
   suite, même s'il ne le concerne pas.
7. Le mur nº 1 reste le seul qui rende des cas carrément inexprimables, et donc le plus coûteux.
8. `min_score` se compare au score **absolu** alors que son nom, et l'exemple `min_score: 80` de
   `docs/ci.md` en regard d'un `score 1/1` dans `docs/adopting.md`, invitent à y lire un pourcentage.
   Un projet qui reprend l'exemple obtient un gate qui échoue toujours, sans que le message —
   « the weighted score is 56 of 56, below the 80 this project requires » — désigne la confusion.
9. `min_score` et `fail_above_weight` sont tous deux redondants avec le code de sortie pour un projet
   qui ne tolère aucun échec, puisque `is_success()` teste déjà `failed == 0`. Des trois seuils, seul
   `max_tolerated` observe quelque chose qu'aucun autre mécanisme ne voit — un `allow_fail` qui casse —
   et le point nº 5 le rend inutilisable ici, faute d'un `allow_fail` légitime à surveiller.
