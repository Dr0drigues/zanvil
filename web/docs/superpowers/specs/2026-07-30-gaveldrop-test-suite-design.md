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

### Les quatre murs, mesurés — tous levés depuis

Chacun a été vérifié sur une probe hors dépôt, pas supposé :

1. ~~**Un cas ne peut pas déclarer qu'un outil est absent, et déclarer un outil présent interdit
   l'autre branche.**~~ **Entièrement levé le 3 août 2026, en deux temps, tous deux issus de ce
   travail.**

   `setup.hide` (v0.1.0) a rendu une absence prouvable. Vérifié dans les deux sens sur un poste où
   `posting` est installé : sans la clé le cas échoue (`got (empty)`), avec elle il passe (`3/3`).

   Puis, en réponse au rapport, `hide` a cessé de refuser un outil que `fake.bins` déclare (v0.1.1) :
   le cas gagne, aucun lien symbolique n'est posé pour cet outil-là, les autres restent intacts. La
   déclaration vaut pour la suite, la clé vaut pour un cas, et le plus spécifique décide. **Les deux
   branches d'un module tiennent donc dans une seule configuration** — `gaveldrop.hidden.yaml` et
   `tests/cases-hidden/` ont existé une demi-journée et n'existent plus.

   Ce que ce mur laisse comme trace : la version minimale de gaveldrop est **v0.1.1**. Sous v0.1.0 les
   quatre cas `*-warns-when-its-binary-is-missing` sont refusés au chargement, avec `case hides
   `posting` and the project fakes it`. C'est pourquoi le job CI épingle cette version.

   Note sur `hide`, toujours valable : cacher un outil retire **tout le répertoire** qui le contient.
   `hide: [posting]` fait disparaître `/opt/homebrew/bin`, donc aussi delta, lazygit et atuin. Sans
   effet ici — la branche absente n'appelle rien d'autre, et `zsh`, `cp`, `jq`, `git` vivent dans
   `/bin` et `/usr/bin`.

   Pour mémoire, l'état antérieur, qui explique les décisions prises avant cette date : `PATH` dans
   l'isolation étant les symlinks de fakes suivis du `PATH` hérité, `command -v posting` trouvait
   l'outil réel quand la machine l'avait. Le faker rendait un outil *présent* ; rien ne le rendait
   manquant. Et un bin déclaré était shadowé pour *tous* les cas de la configuration, y compris ceux
   sans bloc `fake:` — ce que `setup.hide` corrige désormais cas par cas :

   ```
   FAIL does-a-declared-bin-exist-without-a-fake-block  0/1
       expect.stdout.contains[0]
         expected  contains "MISSING"
         got       SHADOWED
   ```

   Aucun cas `allow_fail` n'est écrit : il n'y a rien à tolérer.
2. ~~**`setup` ne connaît que `env`, `exec` et `run` — il n'y a pas de `stdin:`.**~~ **Levé en v0.1.2 par
   `setup.stdin`**, écrit dans le cas via un bloc `|` de YAML. Un filtre `stdin → stdout` s'invoque
   désormais directement.
3. ~~**Aucune normalisation ANSI côté assertion.**~~ **Levé en v0.1.2 par `ignore_ansi: true`**, à
   déclarer sur l'assertion — éteint par défaut, pour qu'`absent: ["\e["]` reste une assertion possible
   sur un outil qui ne doit pas colorer hors terminal.
4. ~~**Aucune égalité exacte.**~~ **Levé en v0.1.2 par `equals`.** C'était le plus coûteux : un comptage
   asserté en `contains` passait sur un mauvais résultat, `contains: ["2"]` étant satisfait par une
   sortie `12`.

Les murs 2, 3 et 4 ont imposé un exécutable de plomberie pendant une heure — `tests/bin/k9s-fmt-plain`,
écrit pour le lot 2a et retiré le jour même. Aucun mur ne subsiste : la version minimale de gaveldrop est
**v0.1.2**, et c'est tout ce qu'il en reste.

## Architecture

```
zanvil/
├── gaveldrop.yaml                        # cases + fake.bins
├── tests/
│   ├── cases/
│   │   ├── boot/rc-loads-without-an-error.yaml
│   │   ├── cli/*.yaml                    # lot 1 — 5 cas
│   │   ├── modules/*.yaml                # lot 1 — 8 cas, les deux branches
│   │   └── k9s/*.yaml                    # lot 2 — 24 cas de rendu
│   └── hooks/prepare-zanvil-dir.sh       # lot 1
└── .shellspec                            # supprimé
```

Une seule configuration, et une seule invocation : `fake.bins` déclare les quatre outils pour la suite,
et les quatre cas qui testent la branche absente s'y soustraient un par un avec `setup.hide`. Le plus
spécifique décide.

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

## Le lot 1 — quatorze cas

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

### Modules tools — les deux branches (8 cas)

**La branche « binaire présent »**, 4 cas de poids 5 sous `tests/cases/modules/`. C'est l'argument de
tout l'exercice : elle est inaccessible à la CI actuelle, qui supposerait d'installer quatre outils sur
le runner. Chacun asserte le fichier déployé, l'absence du message d'avertissement et le nombre
d'appels — deux pour atuin, qui invoque `--version` puis `info`.

**La branche « binaire absent »**, 4 cas de poids 3 dans le même répertoire, chacun déclarant
`hide: [<outil>]`. C'est ce que la CI vérifiait en amputant `PATH` à la main, désormais exprimé par le
format et avec un verdict identique partout. Aucun hook : cette branche ne lit ni ne déploie rien.

### Pas de bloc `gate:`

Le total des poids vaut **68** — 9 pour le chargement, 27 pour les cinq cas CLI, 20 pour les quatre
branches présentes, 12 pour les quatre branches absentes. Aucun des trois seuils que gaveldrop propose
n'apporte quoi que ce soit à une suite qui ne tolère aucun échec :

- `min_score` est comparé au score **absolu**, pas à un pourcentage (`report.rs:88`). Un
  `min_score: 80` — la valeur de l'exemple dans `docs/ci.md` — ferait échouer le gate en permanence sur
  une suite dont le maximum est 68. Et une valeur correcte devrait être bumpée à chaque cas ajouté.
- `fail_above_weight` ne se déclenche que sur un cas `!passed && !allow_fail` (`report.rs:109`), or un
  tel cas rend déjà `is_success()` faux. Redondant avec le code de sortie.
- `max_tolerated` n'observe que les cas `allow_fail`, et le lot 1 n'en compte aucun.

`gaveldrop.yaml` se limite donc à `cases:` et `fake.bins:`. Un `gate:` absent n'impose rien, et c'est
exact : ici, `failed == 0` est la seule question. Le bloc redeviendra utile le jour où un `allow_fail`
sera légitime — c'est-à-dire quand le mur nº 1 tombera.

## CI

Un job `cases` dans `tests.yml` : checkout, installation de zsh sur Linux (l'image `ubuntu-24.04` ne
l'embarque pas), build du CLI zanvil, installation de gaveldrop depuis les **binaires précompilés de la
release**, puis une exécution et l'upload du rapport en `if: always()`.

```yaml
- run: |
    curl -fsSL -O "$base/$archive" -O "$base/$archive.sha256"
    sha256sum -c "$archive.sha256"      # shasum -a 256 -c sur macOS
    tar xzf "$archive" && mv …/gaveldrop …/gaveldrop-fake "$HOME/.local/bin/"
- run: gaveldrop --annotate --report-junit junit.xml
```

Quatre points non évidents :

- **La version est un minimum, pas une préférence.** `v0.1.1` est la première où `setup.hide` accepte un
  outil que `fake.bins` déclare ; sous `v0.1.0`, les quatre cas `*-warns-when-its-binary-is-missing`
  sont refusés au chargement. Vérifié en comparant les deux binaires sur le même cas.
- **La release plutôt que `cargo install`.** Aucune compilation — deux minutes par job — donc rien à
  cacher, et donc pas de `--force` : cacher `~/.cargo/bin` fait échouer le second run sur
  `error: binary gaveldrop already exists in destination`, exit 101, ce qui est arrivé. Un tag dit aussi
  ce qu'on installe, là où un SHA ne le dit pas.
- **La somme est vérifiée avant extraction**, avec `sha256sum` sur Linux et `shasum -a 256` sur macOS.
  Une archive altérée ne doit pas s'exécuter.
- **Les deux binaires sortent de la même archive, côte à côte** — ce que gaveldrop exige, puisqu'il
  cherche `gaveldrop-fake` à côté de lui. Par `cargo install`, il faut **deux** crates, `cargo`
  n'installant pas les binaires des dépendances.
- **L'installation ne fournit pas les outils dont les cas ont besoin.** L'étape `zsh` sur Linux n'est pas
  optionnelle — c'est ce qui a fait échouer la CI de gaveldrop elle-même la première fois.

L'action officielle ferait tout cela en une ligne, avec `install-only: 'true'` qui correspond exactement
au cas où plusieurs invocations seraient nécessaires. Elle est inutilisable aujourd'hui : `Dr0drigues/gaveldrop/action@v0.1.0`
ne résout pas, l'action ayant été ajoutée au dépôt **après** le tag — `git tag --contains` sur son commit
ne renvoie rien, et GitHub échoue au démarrage du job sur `Can't find 'action.yml'`. À rebasculer dessus
dès qu'un tag la contient.

### Ce que le job remplace

| Étape actuelle | Sort |
|---|---|
| `Verify zsh loads without errors` | **remplacée** par `rc-loads-without-an-error`, qui asserte et n'atteint pas le réseau |
| `Test CLI commands` | **remplacée** par les cinq cas CLI |
| `Test binary-absent fallback warnings` | **remplacée** par les quatre cas `*-warns-when-its-binary-is-missing` |
| `Verify core files exist`, `Verify modules structure` | **gardées** : gaveldrop saurait l'exprimer, mais ce serait un `ls` en moins bien |
| `scripts/tests/k9s-log-fmt.test.sh`, `zsh-special-vars.test.sh` | **ajoutées** en CI, où elles ne tournaient pas |

La ligne `Test binary-absent fallback warnings` a changé deux fois. Elle était d'abord **gardée** parce
que la branche absente était inexprimable ; `setup.hide` l'exprime désormais, avec un verdict identique
sur un poste équipé et sur un runner nu — ce que l'amputation de `PATH` ne garantissait que par
accident, en dépendant de ce que le runner n'avait pas installé.

## Le lot 2 — migration de `k9s-log-fmt.test.sh`

Livré en deux passes, la seconde ayant effacé une partie de la première.

**Lot 2a**, sous les murs 2 à 4 : douze cas de rendu, un wrapper `tests/bin/k9s-fmt-plain` pour fournir
l'entrée et retirer les codes ANSI, et des assertions en `contains` faute de mieux.

**Lot 2b**, après `v0.1.2` : le wrapper disparaît, les douze cas passent à `stdin` + `ignore_ansi` +
`equals`, et vingt-quatre autres les rejoignent — dont les comptages, devenus des égalités sur la sortie
entière. « Quatre lignes » devient « ces quatre lignes-là », ce que le test bash ne vérifiait pas.

Deux écarts avec le plan d'origine, tous deux justifiés par une mesure :

- **Pas de fixtures découpées.** Le spec en prévoyait une trentaine ; `setup.stdin` porte l'entrée dans
  le cas, qui se lit d'un bloc. `config/k9s/fixtures/logs-sample.jsonl` reste où il est, pour les deux
  assertions du contrat `--pairs` et pour rejouer le rendu à la main.
- **Les attendus multi-lignes portent `|2`.** Sans l'indicateur d'indentation explicite, YAML mange
  l'indentation de tête et `equals` échoue sur `— the same but for whitespace`.

**Ce qui reste en bash**, vingt assertions : celles qui exigent de découper la sortie avant de comparer
(`cut -f2-` pour le JSON source, `awk -F'\t' NF` pour le nombre de champs — une égalité sur la ligne
entière contiendrait une tabulation littérale au milieu d'un JSON), le contrat `--pairs` sur la fixture
de dix lignes, et les trois sections du viewer qui pilotent un faux `fzf`.

**Vérification par mutation**, parce que ces cas dérivent d'une sortie réelle et passeraient donc par
construction : neutraliser `pad()` dans le formatteur fait rougir 17 cas, remplacer `⤷` en fait rougir 2.
Le garde-fou à la génération est complémentaire — le fragment que le test bash assertait est vérifié dans
la sortie capturée, sans quoi le cas n'est pas écrit.

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
5. **Le plus important, et à moitié résolu depuis.** `fake.bins` est global et aucun cas ne peut s'en
   soustraire — le bloc `fake:` d'un cas n'accepte que `render` et `rules`. `setup.hide` a levé
   l'impossibilité de prouver une absence, mais **pas** celle de tester les deux branches d'un même
   module dans une seule configuration : gaveldrop refuse qu'un cas cache un outil que le projet fake,
   et il a raison de le refuser. La conséquence pratique reste entière — zanvil porte deux
   configurations et la CI lance `gaveldrop` deux fois.

   Le correctif qui refermerait complètement le sujet est celui qui n'a pas été retenu : des `bins`
   déclarables par cas. Il ferait tenir les deux exemples que le briefing donne côte à côte dans un
   seul `gaveldrop.yaml`.
6. Corollaire du précédent : `unexpected calls` est jugé par cas alors que `bins` est global, donc un
   cas qui charge tout un shell doit prévoir une règle pour chaque outil déclaré ailleurs dans la
   suite, même s'il ne le concerne pas — `rc-loads-without-an-error` en porte cinq pour cette raison.
7. `setup.hide` retire **tout le répertoire** contenant l'outil. Sur macOS avec Homebrew,
   `hide: [posting]` fait disparaître `/opt/homebrew/bin` et donc les trois autres outils. Sans
   conséquence ici, mais un cas ayant besoin d'un outil voisin échouerait pour une raison qui n'est
   pas la sienne. La documentation le dit ; la surprise reste possible.
8. **Le `got` d'une assertion `stdout` n'affiche que la première ligne.** Quand la sortie commence par
   un code ANSI suivi d'un saut de ligne — ce que produit `_ui_header` — le rapport affiche un `got`
   vide et laisse croire que le sujet n'a rien écrit. Cela m'a coûté un cas-sonde et une fausse piste
   sur `lazygit_setup`, avant de comprendre que la sortie était bien là. `--verbose` n'aide pas ici :
   ce qui manque, c'est quelques lignes de contexte dans le `got`.
9. `min_score` se compare au score **absolu** alors que son nom, et l'exemple `min_score: 80` de
   `docs/ci.md` en regard d'un `score 1/1` dans `docs/adopting.md`, invitent à y lire un pourcentage.
   Un projet qui reprend l'exemple obtient un gate qui échoue toujours, sans que le message —
   « the weighted score is 68 of 68, below the 80 this project requires » — désigne la confusion.
10. `min_score` et `fail_above_weight` sont tous deux redondants avec le code de sortie pour un projet
    qui ne tolère aucun échec, puisque `is_success()` teste déjà `failed == 0`. Des trois seuils, seul
    `max_tolerated` observe quelque chose qu'aucun autre mécanisme ne voit — un `allow_fail` qui casse —
    et la suite n'en compte aucun.
