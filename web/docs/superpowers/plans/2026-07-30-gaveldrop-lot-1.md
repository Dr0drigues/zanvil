# Suite de tests gaveldrop — lot 1 : plan d'implémentation

> **Exécuté et clos le 3 août 2026.** Deux écarts par rapport à ce qui est écrit plus bas, tous deux
> dus à l'arrivée de `setup.hide` dans gaveldrop pendant l'exécution :
>
> - **Quatorze cas livrés, pas dix.** Les quatre cas « binaire absent », que ce plan déclarait
>   inexprimables, le sont devenus. Ils vivent dans `tests/cases-hidden/` avec leur propre
>   `gaveldrop.hidden.yaml`, parce qu'un outil ne peut pas être à la fois faké et caché.
> - **La tâche 5 ne conserve plus `Test binary-absent fallback warnings`** et n'installe plus gaveldrop
>   depuis un SHA pinné : l'action officielle en `install-only` la remplace, et les quatre nouveaux cas
>   remplacent l'étape.
>
> Le spec est à jour ; ce plan reste tel qu'il a été écrit, pour que la trace des décisions et de leur
> révision soit lisible.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** doter zanvil de dix cas gaveldrop qui assertent réellement quelque chose, là où
`.github/workflows/tests.yml` compte aujourd'hui trois étapes incapables d'échouer.

**Architecture:** un cas est un fichier YAML sous `tests/cases/`. Un hook unique
(`tests/hooks/prepare-zanvil-dir.sh`) construit un `ZANVIL_DIR` **dans l'isolation** — le dépôt reste
en lecture seule et aucun verdict ne dépend d'un fichier gitignored. Les quatre outils de
`modules/tools/` sont rendus *présents* par le faker de gaveldrop, ce qui atteint pour la première
fois la moitié du code qu'aucune CI ne pouvait exercer.

**Tech Stack:** gaveldrop 0.1.0 (Rust, non publié — installé par `--git --rev`), zsh, le CLI Rust
`zanvil` déjà présent dans `cli/`.

## Global Constraints

- **Aucune modification de `~/work/misc/gaveldrop`.** Ce qui manque est décrit dans le rapport de la
  tâche 6, jamais corrigé sur place.
- **Aucune modification du code de zanvil pour le rendre testable.** Si un cas révèle un défaut, il
  est rapporté, pas contourné en affaiblissant le cas.
- **SHA gaveldrop pinné :** `6d896b83b3bbe772700b75c5ecd1e1f94ed6fb2c`. Toute commande d'installation
  le cite ; le bump est un geste explicite.
- **Deux binaires à installer**, `gaveldrop-cli` *et* `gaveldrop-fake`. Sans le second, toute
  exécution meurt sur `the fake binary was not found beside this executable`.
- **`fake.bins` est global.** Un outil déclaré est shadowé pour *tous* les cas. Conséquence tenue dans
  tout le plan : aucun cas « binaire absent » n'est écrit, et tout cas qui charge le shell complet doit
  prévoir une règle pour chacun des quatre outils déclarés.
- **Aucun `allow_fail`.** Un cas qui ne peut structurellement pas passer est un cas faux.
- **Un cas ne contient aucune logique** — pas de `sh -c "… | sed"`. Ce qui calcule va dans un hook.
- **Poids :** 9 pour le chargement, 5 à 7 pour le CLI, 5 pour les modules. Total attendu : 56.
- **Chaque cas doit prouver qu'il peut échouer** avant d'être commité : on l'écrit avec un attendu
  faux, on constate le `FAIL`, puis on corrige. C'est le rouge-vert de ce plan.
- Les documents sous `web/docs/superpowers/` sont gitignored : les commits les ajoutent avec
  `git add -f`.

---

### Task 1: Infrastructure et premier cas

**Files:**
- Create: `gaveldrop.yaml`
- Create: `tests/cases/cli/cli-lists-its-commands.yaml`
- Delete: `.shellspec`

**Interfaces:**
- Consumes: rien.
- Produces: `gaveldrop.yaml` avec le motif `cases: tests/cases/**/*.yaml` et
  `fake.bins: [posting, delta, lazygit, atuin]`, sur lesquels toutes les tâches suivantes reposent.
  Le binaire du CLI zanvil compilé en `cli/target/release/zanvil`, référencé par les cas CLI.

- [ ] **Step 1: Installer les deux binaires gaveldrop**

```bash
cargo install --git https://github.com/Dr0drigues/gaveldrop \
  --rev 6d896b83b3bbe772700b75c5ecd1e1f94ed6fb2c --locked gaveldrop-cli
cargo install --git https://github.com/Dr0drigues/gaveldrop \
  --rev 6d896b83b3bbe772700b75c5ecd1e1f94ed6fb2c --locked gaveldrop-fake
gaveldrop --version   # attendu : gaveldrop 0.1.0
command -v gaveldrop-fake   # doit répondre un chemin
```

- [ ] **Step 2: Compiler le CLI zanvil, dont les cas CLI ont besoin**

```bash
cd cli && cargo build --release && cd ..
ls -l cli/target/release/zanvil
```

- [ ] **Step 3: Vérifier que gaveldrop refuse une suite vide**

```bash
cd ~/.zanvil && gaveldrop
```

Attendu : un échec nommant l'absence de configuration —
`gaveldrop: no usable configuration at gaveldrop.yaml`. C'est le point de départ rouge.

- [ ] **Step 4: Créer la configuration**

```yaml
# gaveldrop.yaml
cases: tests/cases/**/*.yaml

# Les quatre outils de modules/tools/. Déclarés ici, ils sont shadowés pour TOUS les cas :
# c'est ce qui rend la branche « binaire présent » testable, et la branche « binaire absent »
# inexprimable. Voir le spec, mur nº 1.
fake:
  bins: [posting, delta, lazygit, atuin]
```

- [ ] **Step 5: Relancer, et constater le second message rouge**

```bash
gaveldrop
```

Attendu : `gaveldrop: the "cases" pattern "tests/cases/**/*.yaml" matched no file under .` — une suite
vide est refusée bruyamment, ce qui est exactement ce qu'on veut.

- [ ] **Step 6: Écrire le premier cas avec un attendu délibérément faux**

```yaml
# tests/cases/cli/cli-lists-its-commands.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Dr0drigues/gaveldrop/main/docs/case.schema.json
name: cli-lists-its-commands
weight: 5
setup:
  run: ["$GAVELDROP_PROJECT/cli/target/release/zanvil", "--help"]
expect:
  exit_code: 0
  stdout:
    contains: ["une-sous-commande-qui-nexiste-pas"]
```

- [ ] **Step 7: Lancer, et vérifier que le cas échoue**

```bash
gaveldrop --only cli-lists-its-commands
```

Attendu : `FAIL cli-lists-its-commands 0/5`, avec `expect.stdout.contains[0]` et la sortie réelle de
`--help` en regard. Ce rouge prouve que le cas observe vraiment stdout.

- [ ] **Step 8: Corriger l'attendu**

Remplacer le bloc `contains:` par les trois sous-commandes que `--help` liste réellement :

```yaml
  stdout:
    contains: ["theme", "doctor", "audit"]
```

- [ ] **Step 9: Vérifier le vert**

```bash
gaveldrop --only cli-lists-its-commands
```

Attendu : `ok cli-lists-its-commands 5/5`.

- [ ] **Step 10: Supprimer le `.shellspec`**

```bash
git rm .shellspec
```

Il configure shellspec, qu'aucun fichier du dépôt n'utilise depuis la suppression de la suite en
mars 2026, et la convention du projet est de ne pas écrire de specs shellspec.

- [ ] **Step 11: Commit**

```bash
git add gaveldrop.yaml tests/cases/cli/cli-lists-its-commands.yaml
git commit -m "test(gaveldrop): configuration et premier cas — le CLI liste ses commandes

Retire aussi le .shellspec, qui configurait un outil qu'aucun fichier
n'utilise depuis la suppression de la suite en mars 2026."
```

---

### Task 2: Le hook de préparation et les quatre cas CLI qui en dépendent

**Files:**
- Create: `tests/hooks/prepare-zanvil-dir.sh`
- Create: `tests/cases/cli/cli-theme-list-names-the-committed-themes.yaml`
- Create: `tests/cases/cli/cli-theme-current-reads-the-state-file.yaml`
- Create: `tests/cases/cli/cli-modules-list-reflects-config-zsh.yaml`
- Create: `tests/cases/cli/cli-doctor-runs-on-an-isolated-home.yaml`

**Interfaces:**
- Consumes: `gaveldrop.yaml` (tâche 1), `cli/target/release/zanvil` (tâche 1).
- Produces: `tests/hooks/prepare-zanvil-dir.sh`, invoqué par `setup.exec` dans les tâches 3 et 4. Il
  garantit, pour tout cas qui le déclare : `$HOME/zanvil` contenant `core/ modules/ config/ scripts/
  examples/` plus `rc.zsh plugins.zsh completions.zsh`, un `config.zsh` avec `ZANVIL_PLUGINS=()` et
  six lignes `ZANVIL_MODULE_*` (`KUBE=true`, `DOCKER=false`, `POSTING=true`, `DELTA=true`,
  `LAZYGIT=true`, `ATUIN=true`), un `.current_theme` valant `minimal`, et `$HOME/.config`,
  `$HOME/.kube`, `$HOME/work` créés.

- [ ] **Step 1: Écrire le hook**

```sh
#!/bin/sh
# Construit un ZANVIL_DIR à l'intérieur de l'isolation.
#
# Pourquoi : .current_theme et config.zsh sont gitignored (un verdict qui les lit depuis le dépôt
# dépend de la machine), delta_setup écrit dans $ZANVIL_DIR/config/lazygit/config.yml, et rc.zsh y
# écrit .last_update_check et .work_context_cache. Le dépôt reste donc en lecture seule.
#
# La copie est sélective parce que le dépôt pèse 1,9 Go — entièrement cli/target.
set -eu

cat >/dev/null   # drain de la charge setup envoyée sur stdin

SRC="$GAVELDROP_PROJECT"
DST="$HOME/zanvil"

mkdir -p "$DST"
for d in core modules config scripts examples; do
    cp -R "$SRC/$d" "$DST/"
done
for f in rc.zsh plugins.zsh completions.zsh; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DST/"
done

# Aucun plugin : plugins.zsh ferait un git clone, donc le réseau, donc un verdict qui en dépend.
{
    printf 'ZANVIL_PLUGINS=()\n'
    printf 'ZANVIL_MODULE_KUBE=true\n'
    printf 'ZANVIL_MODULE_DOCKER=false\n'
    printf 'ZANVIL_MODULE_POSTING=true\n'
    printf 'ZANVIL_MODULE_DELTA=true\n'
    printf 'ZANVIL_MODULE_LAZYGIT=true\n'
    printf 'ZANVIL_MODULE_ATUIN=true\n'
} >"$DST/config.zsh"

printf 'minimal\n' >"$DST/.current_theme"

mkdir -p "$HOME/.config" "$HOME/.kube" "$HOME/work"
```

```bash
chmod +x tests/hooks/prepare-zanvil-dir.sh
```

`ZANVIL_MODULE_DOCKER=false` est délibéré : le cas `modules list` a besoin d'un module inactif pour
que l'assertion sur `inactif` prouve quelque chose.

- [ ] **Step 2: Écrire les quatre cas, chacun avec un attendu faux**

```yaml
# tests/cases/cli/cli-theme-list-names-the-committed-themes.yaml
name: cli-theme-list-names-the-committed-themes
weight: 5
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  env:
    ZANVIL_DIR: "$HOME/zanvil"
  run: ["$GAVELDROP_PROJECT/cli/target/release/zanvil", "theme", "list"]
expect:
  exit_code: 0
  stdout:
    contains: ["theme-qui-nexiste-pas"]
```

```yaml
# tests/cases/cli/cli-theme-current-reads-the-state-file.yaml
name: cli-theme-current-reads-the-state-file
weight: 5
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  env:
    ZANVIL_DIR: "$HOME/zanvil"
  run: ["$GAVELDROP_PROJECT/cli/target/release/zanvil", "theme", "current"]
expect:
  exit_code: 0
  stdout:
    contains: ["theme-qui-nexiste-pas"]
```

```yaml
# tests/cases/cli/cli-modules-list-reflects-config-zsh.yaml
name: cli-modules-list-reflects-config-zsh
weight: 5
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  env:
    ZANVIL_DIR: "$HOME/zanvil"
  run: ["$GAVELDROP_PROJECT/cli/target/release/zanvil", "modules", "list"]
expect:
  exit_code: 0
  stdout:
    contains: ["MODULE-QUI-NEXISTE-PAS"]
```

```yaml
# tests/cases/cli/cli-doctor-runs-on-an-isolated-home.yaml
name: cli-doctor-runs-on-an-isolated-home
weight: 7
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  env:
    ZANVIL_DIR: "$HOME/zanvil"
  run: ["$GAVELDROP_PROJECT/cli/target/release/zanvil", "doctor"]
expect:
  exit_code: 0
  stdout:
    contains: ["Doctor-qui-nexiste-pas"]
```

- [ ] **Step 3: Lancer les quatre, et lire les sorties réelles**

```bash
gaveldrop --only cli-
```

Attendu : quatre `FAIL`, et pour chacun la sortie réelle affichée sous `got`. C'est cette sortie qui
sert à calibrer l'étape suivante — on n'écrit pas un attendu de mémoire.

- [ ] **Step 4: Remplacer chaque attendu faux par le vrai**

`cli-theme-list-names-the-committed-themes` — trois thèmes versionnés sous `config/themes/`, donc
présents dans la copie isolée :

```yaml
  stdout:
    contains: ["minimal", "tokyo-night-pro", "forge"]
```

`cli-theme-current-reads-the-state-file` — le hook a écrit `minimal` dans `.current_theme`, et c'est
là tout l'intérêt du cas : la commande lit bien l'état isolé et non celui du poste :

```yaml
  stdout:
    contains: ["minimal"]
```

`cli-modules-list-reflects-config-zsh` — les lignes viennent des `.module.toml` (`config.rs:51`,
`scan_module_metas`) et le statut d'une correspondance exacte avec une ligne de `config.zsh`
(`modules.rs:46-48`), donc `KUBE=true` donne `actif` et `DOCKER=false` donne `inactif` :

```yaml
  stdout:
    contains: ["MODULE", "STATUT", "KUBE", "DOCKER", "actif", "inactif"]
```

`cli-doctor-runs-on-an-isolated-home` — l'en-tête porte la version, et `doctor` ne sort jamais non nul
(aucun `process::exit` dans `cli/src/cmd/doctor.rs`, les erreurs sont comptées puis affichées) :

```yaml
  stdout:
    contains: ["Zanvil Doctor v", "Config"]
```

- [ ] **Step 5: Vérifier le vert des cinq cas CLI**

```bash
gaveldrop --only cli-
```

Attendu : `5 cases · 5 passed · 0 failed`, score `27/27`.

- [ ] **Step 6: Noter les défauts de zanvil observés, sans les corriger**

Deux observations à reporter telles quelles dans le rapport de la tâche 6, sans toucher au code :
`doctor` sort `0` même quand il compte des erreurs, et `modules list` sur un `config.zsh` illisible
écrit sur stderr puis sort `0` (`modules.rs:23-29`). Aucun des deux n'est assertable par le code de
sortie — c'est une limite de zanvil, pas de gaveldrop.

- [ ] **Step 7: Commit**

```bash
git add tests/hooks/prepare-zanvil-dir.sh tests/cases/cli/
git commit -m "test(gaveldrop): cinq cas CLI, sur un ZANVIL_DIR construit dans l'isolation

Remplace les cinq commandes de l'etape « Test CLI commands », dont trois
terminees par || true. Chaque cas asserte le code de sortie et une chose de
la sortie.

Le hook construit un ZANVIL_DIR dans l'isolation : .current_theme et
config.zsh sont gitignored, donc un cas qui les lirait depuis le depot
rendrait un verdict dependant de la machine."
```

---

### Task 3: Les quatre cas « binaire présent » des modules tools

**Files:**
- Create: `tests/cases/modules/posting-deploys-its-config-when-the-binary-is-there.yaml`
- Create: `tests/cases/modules/atuin-deploys-its-config-when-the-binary-is-there.yaml`
- Create: `tests/cases/modules/delta-wires-itself-into-gitconfig-when-the-binary-is-there.yaml`
- Create: `tests/cases/modules/lazygit-points-at-the-committed-config-when-the-binary-is-there.yaml`

**Interfaces:**
- Consumes: `tests/hooks/prepare-zanvil-dir.sh` (tâche 2), `fake.bins` de `gaveldrop.yaml` (tâche 1).
- Produces: rien que les tâches suivantes consomment.

C'est le cœur de l'exercice : ces quatre branches sont aujourd'hui inaccessibles en CI, parce qu'elles
supposeraient d'installer posting, delta, lazygit et atuin sur le runner. Le faker les rend présents
sans rien installer.

- [ ] **Step 1: Écrire le cas posting, avec un attendu de fichier faux**

```yaml
# tests/cases/modules/posting-deploys-its-config-when-the-binary-is-there.yaml
name: posting-deploys-its-config-when-the-binary-is-there
weight: 5
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  shell: zsh
  source:
    - "core/ui.zsh"
    - "modules/tools/posting/init.zsh"
  call: ["posting_setup"]
  env:
    ZANVIL_MODULE_POSTING: "true"
    ZANVIL_DIR: "$HOME/zanvil"
fake:
  rules:
    - match: { bin: posting, args_contain: "--version" }
      stdout: "posting 1.0.0"
    - match: {}
      exit: 127
      stderr: "the case did not foresee this call"
expect:
  exit_code: 0
  files:
    "$HOME/.config/posting/config.yaml":
      contains: ["une-cle-qui-nexiste-pas"]
  stdout:
    absent: ["brew install posting"]
  calls:
    posting: 1
```

`core/ui.zsh` vient en premier parce que `posting_setup` appelle `_ui_header` et `_ui_msg_ok` :
l'ordre de `source:` porte le sens. La règle `match: {}` finale est obligatoire — sans elle, gaveldrop
refuse le cas au chargement.

- [ ] **Step 2: Lancer et vérifier l'échec sur le contenu du fichier**

```bash
gaveldrop --only posting-deploys
```

Attendu : `FAIL`, sur `expect.files` — le fichier **a** été déployé, mais ne contient pas la clé
inventée. Ce rouge prouve que l'assertion lit vraiment le fichier.

- [ ] **Step 3: Corriger l'attendu avec le contenu réel de `config/posting/config.yaml`**

```yaml
    "$HOME/.config/posting/config.yaml":
      contains: ["theme: galaxy", "use_host_environment: false"]
```

- [ ] **Step 4: Vérifier le vert**

```bash
gaveldrop --only posting-deploys
```

Attendu : `ok posting-deploys-its-config-when-the-binary-is-there 5/5`.

- [ ] **Step 5: Écrire le cas atuin**

`atuin_setup` copie la config puis appelle `atuin --version` **et** `atuin info`, dont il extrait la
ligne `database` — deux appels, donc `calls: { atuin: 2 }`.

```yaml
# tests/cases/modules/atuin-deploys-its-config-when-the-binary-is-there.yaml
name: atuin-deploys-its-config-when-the-binary-is-there
weight: 5
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  shell: zsh
  source:
    - "core/ui.zsh"
    - "modules/tools/atuin/init.zsh"
  call: ["atuin_setup"]
  env:
    ZANVIL_MODULE_ATUIN: "true"
    ZANVIL_DIR: "$HOME/zanvil"
fake:
  rules:
    - match: { bin: atuin, args_contain: "--version" }
      stdout: "atuin 18.0.0"
    - match: { bin: atuin, args_contain: "info" }
      stdout: "database path: /tmp/atuin/history.db"
    - match: {}
      exit: 127
      stderr: "the case did not foresee this call"
expect:
  exit_code: 0
  files:
    "$HOME/.config/atuin/config.toml":
      contains: ["auto_sync = false"]
  stdout:
    contains: ["/tmp/atuin/history.db"]
    absent: ["brew install atuin"]
  calls:
    atuin: 2
```

L'assertion sur `/tmp/atuin/history.db` est la plus intéressante du cas : elle prouve que la sortie du
faux `atuin info` a bien traversé le `grep -i 'database' | head -1 | cut -d: -f2- | xargs` du module.

- [ ] **Step 6: Écrire le cas delta**

`delta_setup` copie `config/delta/gitconfig` vers `$HOME/.gitconfig.d/delta`, ajoute un `[include]`
dans `$HOME/.gitconfig`, puis examine `$ZANVIL_DIR/config/lazygit/config.yml` — qui contient déjà
`pager: delta`, donc il n'y touche pas et le dit.

```yaml
# tests/cases/modules/delta-wires-itself-into-gitconfig-when-the-binary-is-there.yaml
name: delta-wires-itself-into-gitconfig-when-the-binary-is-there
weight: 5
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  shell: zsh
  source:
    - "core/ui.zsh"
    - "modules/tools/delta/init.zsh"
  call: ["delta_setup"]
  env:
    ZANVIL_MODULE_DELTA: "true"
    ZANVIL_DIR: "$HOME/zanvil"
fake:
  rules:
    - match: { bin: delta, args_contain: "--version" }
      stdout: "delta 0.18.2"
    - match: {}
      exit: 127
      stderr: "the case did not foresee this call"
expect:
  exit_code: 0
  files:
    "$HOME/.gitconfig.d/delta":
      contains: ["pager = delta"]
    "$HOME/.gitconfig":
      contains: ["gitconfig.d/delta"]
  stdout:
    contains: ["lazygit pager déjà configuré"]
    absent: ["brew install git-delta"]
  calls:
    delta: 1
```

L'assertion `lazygit pager déjà configuré` vaut double : elle vérifie le message, et elle prouve que la
branche qui **réécrit** `config/lazygit/config.yml` n'a pas été prise — c'est-à-dire qu'aucun fichier
versionné n'a été modifié par le test.

- [ ] **Step 7: Écrire le cas lazygit**

Particularité : `lazygit_setup` n'écrit aucun fichier. Il affiche la version, le chemin de
configuration, et l'état de `config-local.yml`. Le code testé est donc l'exportation faite au
chargement (`LG_CONFIG_FILE`) plus le rendu.

```yaml
# tests/cases/modules/lazygit-points-at-the-committed-config-when-the-binary-is-there.yaml
name: lazygit-points-at-the-committed-config-when-the-binary-is-there
weight: 5
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  shell: zsh
  source:
    - "core/ui.zsh"
    - "modules/tools/lazygit/init.zsh"
  call: ["lazygit_setup"]
  env:
    ZANVIL_MODULE_LAZYGIT: "true"
    ZANVIL_DIR: "$HOME/zanvil"
fake:
  rules:
    - match: { bin: lazygit, args_contain: "--version" }
      stdout: "commit=abc123, version=0.50.0"
    - match: {}
      exit: 127
      stderr: "the case did not foresee this call"
expect:
  exit_code: 0
  stdout:
    contains: ["zanvil/config/lazygit/config.yml", "config-local.yml"]
    absent: ["brew install lazygit"]
  calls:
    lazygit: 1
```

L'attendu `zanvil/config/lazygit/config.yml` est un **suffixe** du chemin : le préfixe est le répertoire
temporaire de l'isolation, qui change à chaque exécution. Asserter le suffixe prouve que
`LG_CONFIG_FILE` pointe vers la configuration versionnée, sans dépendre du chemin temporaire.

- [ ] **Step 8: Lancer les quatre cas modules**

```bash
gaveldrop --only modules/
```

Attendu : `4 cases · 4 passed · 0 failed`, score `20/20`. Si un cas échoue sur `unexpected calls`,
c'est qu'un appel n'avait pas été prévu : ajouter la règle correspondante plutôt que d'élargir le
`match: {}`.

- [ ] **Step 9: Vérifier que le dépôt est intact**

```bash
git status --porcelain
```

Attendu : seuls les fichiers de cas nouvellement créés. Aucune modification de
`config/lazygit/config.yml` — c'est la garantie que le hook, et non le dépôt, a servi de `ZANVIL_DIR`.

- [ ] **Step 10: Commit**

```bash
git add tests/cases/modules/
git commit -m "test(gaveldrop): la branche « binaire present » des quatre modules tools

Cette moitie du code n'a jamais ete exercee : la tester supposerait
d'installer posting, delta, lazygit et atuin sur le runner. Le faker les rend
presents sans rien installer.

Le cas delta asserte « lazygit pager deja configure », ce qui prouve du meme
coup que la branche reecrivant config/lazygit/config.yml n'a pas ete prise."
```

---

### Task 4: Le cas de chargement complet

**Files:**
- Create: `tests/cases/boot/rc-loads-without-an-error.yaml`

**Interfaces:**
- Consumes: `tests/hooks/prepare-zanvil-dir.sh` (tâche 2) — en particulier les six lignes
  `ZANVIL_MODULE_*` du `config.zsh` qu'il écrit, sans lesquelles les modules ne se chargeraient pas et
  le cas ne prouverait presque rien. `fake.bins` de la tâche 1.
- Produces: rien.

C'est le cas de poids 9, celui qui remplace `Verify zsh loads without errors` — une étape qui construit
l'isolation à la main, source `rc.zsh`, et **n'asserte rien**.

- [ ] **Step 1: Écrire le cas, sans bloc `fake:`, pour découvrir les appels réels**

```yaml
# tests/cases/boot/rc-loads-without-an-error.yaml
name: rc-loads-without-an-error
weight: 9
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  shell: zsh
  source: ["rc.zsh"]
  call: ["eval", "printf 'version=%s\\n' \"$ZANVIL_VERSION\""]
  env:
    ZANVIL_DIR: "$HOME/zanvil"
expect:
  exit_code: 0
  stdout:
    contains: ["version=v"]
```

`call: ["eval", "…"]` parce que les arguments de `call:` sont inertes : gaveldrop les passe
single-quotés, donc `$ZANVIL_VERSION` n'est pas développé sans un `eval` explicite. C'est le seul
endroit du lot où cette forme est nécessaire.

- [ ] **Step 2: Lancer, et lire la liste des appels imprévus**

```bash
gaveldrop --only rc-loads
```

Attendu : `FAIL` sur `unexpected calls`, listant les outils déclarés dans `fake.bins` que le chargement
invoque. Les quatre modules `completions.zsh` en appellent chacun un, plus `atuin init` dans
`core/hooks.zsh:192` :

| Appel | Origine |
|---|---|
| `posting --completion-script-zsh` | `modules/tools/posting/completions.zsh:4` |
| `delta --generate-completion zsh` | `modules/tools/delta/completions.zsh:5` |
| `lazygit completion zsh` | `modules/tools/lazygit/completions.zsh:5` |
| `atuin gen-completions --shell zsh` | `modules/tools/atuin/completions.zsh:5` |
| `atuin init zsh --disable-up-arrow` | `core/hooks.zsh:192` |

Le rapport mentionne aussi, sous `also written, not asserted`, les fichiers que le chargement crée :
`.zcompdump`, les migrations de mise, `zanvil/.last_update_check` et `zanvil/.work_context_cache`. Ce
ne sont pas des échecs — mais les deux derniers confirment pourquoi `ZANVIL_DIR` ne peut pas pointer
sur le dépôt.

- [ ] **Step 3: Ajouter le bloc `fake:` et resserrer les assertions**

```yaml
fake:
  rules:
    - match: { bin: posting, args_contain: "--completion-script-zsh" }
      stdout: ""
    - match: { bin: delta, args_contain: "--generate-completion" }
      stdout: ""
    - match: { bin: lazygit, args_contain: "completion" }
      stdout: ""
    - match: { bin: atuin, args_contain: "gen-completions" }
      stdout: ""
    - match: { bin: atuin, args_contain: "init" }
      stdout: ""
    - match: {}
      exit: 127
      stderr: "the case did not foresee this call"
expect:
  exit_code: 0
  stdout:
    contains: ["version=v"]
  stderr:
    absent:
      - "command not found"
      - "parse error"
      - "no such file or directory"
```

Chaque règle répond par une sortie vide, ce qui est correct : ces sorties sont passées à `eval`, et
`eval` de rien ne fait rien. Le bloc `stderr.absent` est le cœur du cas — c'est l'assertion qui
n'existait nulle part, et qui fait rougir un module cassé au chargement.

- [ ] **Step 4: Vérifier le vert**

```bash
gaveldrop --only rc-loads
```

Attendu : `ok rc-loads-without-an-error 9/9`.

- [ ] **Step 5: Prouver que le cas peut échouer sur ce qui compte**

```bash
printf '\nechoo "une faute de frappe volontaire"\n' >> modules/utils/init.zsh
gaveldrop --only rc-loads
```

Attendu : `FAIL`, sur `expect.stderr.absent` — `command not found: echoo`. C'est précisément le défaut
que l'étape CI actuelle laisse passer sans broncher. Puis restaurer :

```bash
git checkout modules/utils/init.zsh
gaveldrop --only rc-loads   # de nouveau ok 9/9
```

- [ ] **Step 6: Lancer la suite entière**

```bash
gaveldrop
```

Attendu : `10 cases · 10 passed · 0 failed · 0 tolerated · score 56/56`.

- [ ] **Step 7: Commit**

```bash
git add tests/cases/boot/rc-loads-without-an-error.yaml
git commit -m "test(gaveldrop): le chargement complet, avec une assertion

Remplace « Verify zsh loads without errors », qui construisait l'isolation a
la main puis n'assertait rien : un module cassant au chargement ne faisait pas
rougir le job.

Le cas asserte ZANVIL_VERSION et l'absence de command not found sur stderr.
Il documente au passage les cinq appels d'outils du demarrage, dont
posting --completion-script-zsh a chaque ouverture de shell."
```

---

### Task 5: Le job CI

**Files:**
- Modify: `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: `gaveldrop.yaml` et les dix cas des tâches 1 à 4.
- Produces: un job `cases` sur ubuntu-latest et macos-latest.

- [ ] **Step 1: Retirer les deux étapes remplacées**

Dans le job `smoke-test`, supprimer `Verify zsh loads without errors` (lignes 25-40) et, dans le job
`rust-cli`, `Test CLI commands` (lignes 114-133). La première est remplacée par
`rc-loads-without-an-error`, la seconde par les cinq cas CLI.

- [ ] **Step 2: Conserver explicitement les trois autres étapes**

`Verify core files exist` et `Verify modules structure` restent : gaveldrop saurait les exprimer, mais
ce serait un `ls` en moins bien. `Test binary-absent fallback warnings` reste parce que la branche
« binaire absent » est **inexprimable** en gaveldrop dès que `fake.bins` déclare l'outil — cette étape
est la seule couverture de cette moitié du code. Ajouter ce commentaire au-dessus d'elle :

```yaml
      # Conservee volontairement : gaveldrop ne peut pas exprimer ce cas. fake.bins est global,
      # donc declarer posting/delta/lazygit/atuin pour tester leur branche « present » rend leur
      # branche « absent » inatteignable sur toute machine. Voir
      # web/docs/superpowers/specs/2026-07-30-gaveldrop-test-suite-design.md, mur nº 1.
      - name: Test binary-absent fallback warnings
```

- [ ] **Step 3: Ajouter l'exécution du test k9s, qui ne tournait nulle part**

Dans le job `smoke-test`, après `Verify modules structure` :

```yaml
      - name: Test k9s log formatter
        run: |
          export ZANVIL_DIR="$PWD"
          bash scripts/tests/k9s-log-fmt.test.sh
```

Ses 53 assertions n'étaient référencées dans aucun fichier de `.github/`. L'étape partira quand le
lot 2 les aura migrées.

- [ ] **Step 4: Ajouter le job `cases`**

```yaml
  cases:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install zsh (Linux)
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y zsh jq

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Cache cargo
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            ~/.cargo/bin
            cli/target
          key: ${{ runner.os }}-gaveldrop-6d896b8-${{ hashFiles('cli/Cargo.lock') }}

      # gaveldrop n'est pas publie et n'a aucun tag : le SHA est pinne pour que la CI de zanvil ne
      # rougisse pas au prochain commit d'un autre depot. Le bump est un geste explicite.
      # Les DEUX binaires sont necessaires : sans gaveldrop-fake, toute execution meurt sur
      # « the fake binary was not found beside this executable ».
      - name: Install gaveldrop
        run: |
          cargo install --git https://github.com/Dr0drigues/gaveldrop \
            --rev 6d896b83b3bbe772700b75c5ecd1e1f94ed6fb2c --locked gaveldrop-cli
          cargo install --git https://github.com/Dr0drigues/gaveldrop \
            --rev 6d896b83b3bbe772700b75c5ecd1e1f94ed6fb2c --locked gaveldrop-fake

      - name: Build the zanvil CLI
        run: cd cli && cargo build --release

      - name: Run the cases
        run: gaveldrop --annotate --report-junit junit.xml

      - name: Keep the report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: cases-${{ matrix.os }}
          path: junit.xml
```

`--annotate` place l'échec sur la ligne de l'assertion qui casse, pas dans un log. `if: always()` sur
l'upload, parce que le rapport est le plus utile quand l'étape précédente a échoué.

- [ ] **Step 5: Valider le YAML du workflow**

`pyyaml` n'est pas installé sur cette machine — `python3 -c "import yaml"` échoue. Utiliser `yq`,
qui est présent, et qui vérifie du même coup que les étapes sont bien rattachées à leur job :

```bash
yq '.jobs | to_entries | .[] | .key + ": " + ([.value.steps[].name] | join(" | "))' \
  .github/workflows/tests.yml
```

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/tests.yml
git commit -m "ci(gaveldrop): job cases, et retrait des deux etapes sans assertion

Retire « Verify zsh loads without errors » et « Test CLI commands », que dix
cas gaveldrop remplacent en assertant vraiment quelque chose.

Ajoute l'execution de scripts/tests/k9s-log-fmt.test.sh : ses 53 assertions
n'etaient referencees nulle part dans .github/.

gaveldrop est installe depuis un SHA pinne, et les deux binaires le sont :
gaveldrop-fake est indispensable au faker."
```

- [ ] **Step 7: Pousser et vérifier la CI**

```bash
git push -u origin feature/gaveldrop-test-suite
gh pr create --fill
gh pr checks --watch --fail-fast
```

Attendu : tous les jobs verts, dont `cases` sur les deux systèmes. Un échec sur macos-latest
uniquement signalerait une dépendance au poste que le hook n'a pas neutralisée.

---

### Task 6: Le rapport à gaveldrop

**Files:**
- Create: `web/docs/superpowers/reports/2026-07-30-gaveldrop-shell-adapter.md`

**Interfaces:**
- Consumes: tout ce que les tâches 1 à 5 ont révélé.
- Produces: le livrable que le briefing désigne comme le plus précieux du chantier.

- [ ] **Step 1: Rédiger le rapport, une section par point**

Reprendre les neuf points de la section « Rapport à gaveldrop » du spec, et pour chacun donner : le
fichier et la fonction concernés, ce qui a été tenté, pourquoi le contournement était mauvais. Les
neuf sont déjà établis et vérifiés ; les trois qui comptent le plus :

1. **`fake.bins` global rend une branche inexprimable** — les deux exemples du briefing ne peuvent pas
   coexister. Reproduction : un bin déclaré dans `gaveldrop.yaml` est shadowé même pour un cas sans
   bloc `fake:` (`does-a-declared-bin-exist-without-a-fake-block`, `got SHADOWED`). Deux correctifs
   possibles : des `bins` par cas, ou la capacité de déclarer un outil absent.
2. **`min_score` se compare au score absolu** alors que son nom et l'exemple `min_score: 80` de
   `docs/ci.md` invitent à lire un pourcentage (`report.rs:88`).
3. **Ni `stdin:` ni normalisation ANSI** — les deux murs qui imposeront un wrapper au lot 2.

Ajouter ce que l'implémentation a réellement coûté : le hook de préparation est-il resté raisonnable,
combien de cas ont demandé un aller-retour de calibrage, et le contournement par symlink du briefing
s'est-il avéré inutile dans tous les cas CLI ou seulement certains.

- [ ] **Step 2: Vérifier qu'aucun fichier de gaveldrop n'a été touché**

```bash
git -C ~/work/misc/gaveldrop status --porcelain
```

Attendu : vide. Le rapport décrit, il ne corrige pas.

- [ ] **Step 3: Commit**

```bash
mkdir -p web/docs/superpowers/reports
git add -f web/docs/superpowers/reports/2026-07-30-gaveldrop-shell-adapter.md
git commit -m "docs(gaveldrop): rapport du premier consommateur de l'adaptateur shell

Neuf points, dont un bloquant : fake.bins est global et aucun cas ne peut
s'en soustraire, ce qui rend les deux exemples du briefing mutuellement
incompatibles."
```

---

## Auto-review de ce plan

**Couverture du spec.** Les sections du spec et la tâche qui les implémente :
`gaveldrop.yaml`, retrait de `.shellspec` → tâche 1. Hook de préparation → tâche 2. Cinq cas CLI →
tâches 1 et 2. Quatre cas modules → tâche 3. Cas de chargement → tâche 4. Absence de `gate:` →
tâche 1, étape 4. Job CI, étapes conservées et étape k9s ajoutée → tâche 5. Rapport → tâche 6. Lot 2 →
hors de ce plan, par construction.

**Cohérence des noms.** Le hook est `tests/hooks/prepare-zanvil-dir.sh` dans les six tâches ; les cas
qui le déclarent écrivent tous `exec: ./tests/hooks/prepare-zanvil-dir.sh` et
`ZANVIL_DIR: "$HOME/zanvil"`. Les noms de cas des commits correspondent aux noms de fichiers. Les
poids annoncés (9 + 27 + 20) donnent bien le `56/56` attendu à la tâche 4, étape 6.

**Un écart assumé avec le spec.** Le spec écrit que « tous les cas déclarent
`ZANVIL_DIR: "$HOME/zanvil"` ». `cli-lists-its-commands` ne le fait pas : `--help` ne lit aucun état,
donc le hook serait une copie de répertoire pour rien. L'écart est délibéré et local à ce cas.
