# Identité visuelle zanvil Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduire l'identité visuelle « zanvil » (logo enclume, ligne compacte, tagline « craft your shell ») dans la bannière, l'install et l'auto-update, sans renommer la tuyauterie.

**Architecture:** Un fichier d'art statique unique (`assets/zanvil-logo.txt`) rendu par `cat` à la fois côté zsh (`core/ui.zsh`, colorisé) et côté bash (`install.sh`). Trois fonctions zsh (`_zanvil_logo` splash, `_zanvil_banner_compact` ligne compacte, `_zsh_env_banner` reload existant modifié). Un hook de démarrage opt-out et un appel post-update.

**Tech Stack:** zsh (fonctions UI + hooks), bash (install.sh), pas de framework de test — vérifications par sourcing zsh isolé et `bash -n`.

## Global Constraints

- Nom affiché : `zanvil`. Tagline : `craft your shell`. Verbatim, partout.
- Aucun rename : commandes `zsh-env-*`, dossier `~/.zsh_env`, variables `ZSH_ENV_*`, binaire `zsh-env-cli`, repo → INCHANGÉS. Seul l'affichage devient zanvil.
- Le nouveau toggle garde le préfixe existant : `ZSH_ENV_STARTUP_BANNER` (défaut `true`).
- Toujours utiliser les fonctions/variables `_ui_*` pour les couleurs en zsh ; jamais de `\033[...]` en dur dans les nouveaux blocs zsh. (`install.sh` utilise ses propres `${CYAN}`/`${BOLD}`/`${NC}` déjà définis.)
- Commentaires en français sans accents dans le code shell.
- Aucune migration `migrations/NNN_*.zsh`.
- Tests : sourcing dans un `zsh -c` isolé, jamais le shell courant.
- `$SCRATCHPAD` = `/private/tmp/claude-502/-Users-bl209054--zsh-env/518614f2-a551-4e43-9135-dfc256ae2d6e/scratchpad`

Art de référence (logo splash 3A, à placer dans `assets/zanvil-logo.txt`) :

```
      ▟████████████████▆▄
      ████████████████████
      ▝▀▀▀▀▀▜██████▛▀▀▀▀▀▘
              ██████
            ▟██████████▙
            ▀▀▀▀▀▀▀▀▀▀▀▀

        zanvil · craft your shell
```

Ligne compacte de référence :

```
  ░▒▓█ zanvil █▓▒░  ⚒  craft your shell
```

---

### Task 1: Asset logo + fonctions d'affichage zanvil dans core/ui.zsh

**Files:**
- Create: `assets/zanvil-logo.txt`
- Modify: `core/ui.zsh` (ajout `_zanvil_logo` et `_zanvil_banner_compact` ; modification de `_zsh_env_banner` ~ligne 331-348)
- Test: `$SCRATCHPAD/test_ui.sh`

**Interfaces:**
- Consumes: variables `_ui_cyan`, `_ui_bold`, `_ui_dim`, `_ui_nc`, `_ui_check`, `_ui_green` (déjà définies dans `core/ui.zsh`), `$ZSH_ENV_VERSION`, `$ZSH_ENV_DIR`.
- Produces :
  - `_zanvil_logo()` — imprime le contenu de `assets/zanvil-logo.txt` (colorisé) + une ligne version. Aucun argument.
  - `_zanvil_banner_compact()` — imprime UNIQUEMENT la ligne compacte zanvil (1 ligne, sans infos). Aucun argument.
  - `_zsh_env_banner()` — imprime la ligne compacte (via `_zanvil_banner_compact`) + la ligne d'infos existante (branche · hash · plugins · reloaded). Aucun argument. (nom conservé, appelé par l'alias `ss`.)

- [ ] **Step 1: Créer le fichier d'art**

Créer `assets/zanvil-logo.txt` avec EXACTEMENT ce contenu (8 lignes, dont une vide avant la tagline) :

```
      ▟████████████████▆▄
      ████████████████████
      ▝▀▀▀▀▀▜██████▛▀▀▀▀▀▘
              ██████
            ▟██████████▙
            ▀▀▀▀▀▀▀▀▀▀▀▀

        zanvil · craft your shell
```

- [ ] **Step 2: Écrire le test (doit échouer)**

Créer `$SCRATCHPAD/test_ui.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$HOME/.zsh_env"

# Asset présent + contient l'enclume et la tagline
[[ -f "$DIR/assets/zanvil-logo.txt" ]] || { echo "FAIL: assets/zanvil-logo.txt absent"; exit 1; }
grep -q "craft your shell" "$DIR/assets/zanvil-logo.txt" || { echo "FAIL: tagline absente du logo"; exit 1; }
grep -q "▟" "$DIR/assets/zanvil-logo.txt" || { echo "FAIL: enclume (blocs) absente du logo"; exit 1; }

src="export ZSH_ENV_DIR='$DIR'; source '$DIR/core/ui.zsh' 2>/dev/null;"

# _zanvil_logo : contient zanvil + tagline + version
logo=$(zsh -c "$src ZSH_ENV_VERSION=v9.9.9; _zanvil_logo")
echo "$logo" | grep -q "zanvil"          || { echo "FAIL: _zanvil_logo sans 'zanvil'"; exit 1; }
echo "$logo" | grep -q "craft your shell"|| { echo "FAIL: _zanvil_logo sans tagline"; exit 1; }
echo "$logo" | grep -q "v9.9.9"          || { echo "FAIL: _zanvil_logo sans version"; exit 1; }

# _zanvil_banner_compact : 'zanvil' + tagline, SANS ligne d'infos (pas de 'reloaded')
cpt=$(zsh -c "$src _zanvil_banner_compact")
echo "$cpt" | grep -q "zanvil"           || { echo "FAIL: compact sans 'zanvil'"; exit 1; }
echo "$cpt" | grep -q "craft your shell" || { echo "FAIL: compact sans tagline"; exit 1; }
echo "$cpt" | grep -q "reloaded"         && { echo "FAIL: compact ne doit pas avoir d'infos"; exit 1; }

# _zsh_env_banner : ligne compacte + ligne d'infos (plugins + reloaded), plus de 'zsh-env'
ban=$(zsh -c "$src ZSH_ENV_PLUGINS=(); _zsh_env_banner")
echo "$ban" | grep -q "zanvil"   || { echo "FAIL: banner sans 'zanvil'"; exit 1; }
echo "$ban" | grep -q "reloaded" || { echo "FAIL: banner sans ligne d'infos"; exit 1; }
echo "$ban" | grep -q "zsh-env █"&& { echo "FAIL: banner contient encore 'zsh-env'"; exit 1; }

echo "PASS"
```

- [ ] **Step 3: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_ui.sh"`
Expected: `FAIL: _zanvil_logo sans 'zanvil'` (ou échec antérieur si l'asset n'a pas encore été commit) — l'important est un FAIL avant implémentation des fonctions.

- [ ] **Step 4: Ajouter `_zanvil_logo` et `_zanvil_banner_compact`, modifier `_zsh_env_banner`**

Dans `core/ui.zsh`, remplacer le bloc actuel de `_zsh_env_banner` (lignes ~329-348) par :

```zsh
# Ligne compacte zanvil (1 ligne, sans infos)
# Usage: _zanvil_banner_compact
_zanvil_banner_compact() {
    echo -e "  ${_ui_dim}░▒▓${_ui_nc}${_ui_bold}${_ui_cyan}█ zanvil █${_ui_nc}${_ui_dim}▓▒░${_ui_nc}  ${_ui_bold}⚒${_ui_nc}  ${_ui_dim}craft your shell${_ui_nc}"
}

# Splash complet (logo enclume + tagline + version) — install / update
# Usage: _zanvil_logo
_zanvil_logo() {
    local logo_file="${ZSH_ENV_DIR}/assets/zanvil-logo.txt"
    echo ""
    if [[ -f "$logo_file" ]]; then
        # Enclume + wordmark en cyan/bold, lus depuis l'asset partage
        echo -e "${_ui_bold}${_ui_cyan}$(cat "$logo_file")${_ui_nc}"
    else
        _zanvil_banner_compact
    fi
    echo -e "  ${_ui_dim}${ZSH_ENV_VERSION}${_ui_nc}"
    echo ""
}

# Affiche un banner compact au reload (ligne compacte + infos)
# Usage: _zsh_env_banner
_zsh_env_banner() {
    local branch hash plugin_count info_line

    branch=$(git -C "$ZSH_ENV_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    hash=$(git -C "$ZSH_ENV_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
    plugin_count=${#ZSH_ENV_PLUGINS[@]}

    info_line="${branch} ${_ui_dim}·${_ui_nc} ${hash} ${_ui_dim}·${_ui_nc} ${plugin_count} plugins ${_ui_dim}·${_ui_nc} ${_ui_green}${_ui_check} reloaded${_ui_nc}"

    echo ""
    _zanvil_banner_compact
    echo -e "  ${info_line}"
    echo ""
}
```

- [ ] **Step 5: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_ui.sh"`
Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
git add assets/zanvil-logo.txt core/ui.zsh
git commit -m "feat(ui): identité visuelle zanvil (logo enclume, ligne compacte, tagline)"
```

---

### Task 2: Bannière de démarrage opt-out dans core/hooks.zsh

**Files:**
- Modify: `core/hooks.zsh` (ajout en fin de fichier)
- Test: `$SCRATCHPAD/test_startup.sh`

**Interfaces:**
- Consumes: `_zanvil_banner_compact()` (Task 1), variable d'env `ZSH_ENV_STARTUP_BANNER`.
- Produces: comportement de démarrage — la ligne compacte s'affiche au chargement interactif sauf si `ZSH_ENV_STARTUP_BANNER=false`.

- [ ] **Step 1: Écrire le test (doit échouer)**

Créer `$SCRATCHPAD/test_startup.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$HOME/.zsh_env"

# On source ui.zsh (pour la fonction) puis hooks.zsh, en simulant un shell interactif.
# Le garde [[ -o interactive ]] : on force l'option interactive via 'set -o interactive'.
base="export ZSH_ENV_DIR='$DIR'; source '$DIR/core/ui.zsh' 2>/dev/null;"

# Defaut (toggle non defini) -> banniere affichee
out_default=$(zsh -ic "$base set -o interactive; source '$DIR/core/hooks.zsh' 2>/dev/null" 2>/dev/null || true)
echo "$out_default" | grep -q "zanvil" || { echo "FAIL: pas de banniere par defaut au demarrage"; exit 1; }

# Toggle a false -> rien
out_off=$(ZSH_ENV_STARTUP_BANNER=false zsh -ic "$base set -o interactive; source '$DIR/core/hooks.zsh' 2>/dev/null" 2>/dev/null || true)
echo "$out_off" | grep -q "craft your shell" && { echo "FAIL: banniere affichee malgre opt-out"; exit 1; }

echo "PASS"
```

> Note d'implémentation : `core/hooks.zsh` initialise des outils (starship, mise…) qui peuvent émettre du bruit ; le test filtre sur la présence/absence de `zanvil`/`craft your shell` uniquement. Le `|| true` évite qu'une erreur d'init non liée fasse échouer le test.

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_startup.sh"`
Expected: `FAIL: pas de banniere par defaut au demarrage`

- [ ] **Step 3: Ajouter le hook de démarrage**

Ajouter à la TOUTE FIN de `core/hooks.zsh` :

```zsh
# =======================================================
# BANNIERE DE DEMARRAGE (zanvil)
# =======================================================
# Ligne compacte a chaque shell interactif. Opt-out : ZSH_ENV_STARTUP_BANNER=false
if [[ -o interactive && "${ZSH_ENV_STARTUP_BANNER:-true}" != "false" ]]; then
    _zanvil_banner_compact
fi
```

- [ ] **Step 4: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_startup.sh"`
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add core/hooks.zsh
git commit -m "feat(ui): bannière compacte au démarrage (opt-out ZSH_ENV_STARTUP_BANNER)"
```

---

### Task 3: Splash à l'install (install.sh) + documentation du toggle (config.zsh)

**Files:**
- Modify: `install.sh` (avant le message `=== Installation Terminee ===`)
- Modify: `config.zsh` (documentation du toggle)
- Test: `$SCRATCHPAD/test_install_splash.sh`

**Interfaces:**
- Consumes: `assets/zanvil-logo.txt` (Task 1), variables `${BOLD}`/`${CYAN}`/`${NC}` déjà définies dans `install.sh`, `$TARGET_DIR`.
- Produces: affichage du splash en fin d'install.

- [ ] **Step 1: Écrire le test (doit échouer)**

Créer `$SCRATCHPAD/test_install_splash.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$HOME/.zsh_env"
bash -n "$DIR/install.sh" || { echo "FAIL: syntaxe install.sh"; exit 1; }
grep -qF 'assets/zanvil-logo.txt' "$DIR/install.sh" || { echo "FAIL: install.sh n'affiche pas le logo"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_install_splash.sh"`
Expected: `FAIL: install.sh n'affiche pas le logo`

- [ ] **Step 3: Afficher le splash en fin d'install**

Dans `install.sh`, juste AVANT la ligne `echo -e "\n${BOLD}=== Installation Terminee ===${NC}"` (fin du fichier), insérer :

```sh
# Splash zanvil (logo enclume partage avec core/ui.zsh)
if [[ -f "$TARGET_DIR/assets/zanvil-logo.txt" ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}"
    cat "$TARGET_DIR/assets/zanvil-logo.txt"
    echo -e "${NC}"
fi
```

- [ ] **Step 4: Documenter le toggle dans config.zsh**

Dans `config.zsh`, ajouter (à un endroit cohérent avec les autres options, ex. près des autres variables `ZSH_ENV_*`) :

```zsh
# Banniere zanvil au demarrage de chaque shell interactif (defaut: true)
# Mettre a false pour un demarrage silencieux.
# ZSH_ENV_STARTUP_BANNER=false
```

- [ ] **Step 5: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_install_splash.sh"`
Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
git add install.sh config.zsh
git commit -m "feat(install): splash zanvil en fin d'install + doc toggle ZSH_ENV_STARTUP_BANNER"
```

---

### Task 4: Splash après une mise à jour réussie (core/auto_update.zsh)

**Files:**
- Modify: `core/auto_update.zsh` (après l'affichage du message de succès d'update, ~ligne 88)
- Test: `$SCRATCHPAD/test_autoupdate.sh`

**Interfaces:**
- Consumes: `_zanvil_logo()` (Task 1).
- Produces: appel de `_zanvil_logo` après une mise à jour appliquée avec succès.

- [ ] **Step 1: Repérer le point d'insertion**

Lire `core/auto_update.zsh` autour des lignes 70-95 (le bloc qui affiche `$old_version → $new_version` et conclut une mise à jour appliquée). Identifier la fin du bloc de succès (après l'affichage des nouveautés, avant la fermeture du `if`/fonction).

- [ ] **Step 2: Écrire le test (doit échouer)**

Créer `$SCRATCHPAD/test_autoupdate.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$HOME/.zsh_env"
# Verifie que _zanvil_logo est bien appele dans le chemin de succes d'update.
grep -q "_zanvil_logo" "$DIR/core/auto_update.zsh" || { echo "FAIL: _zanvil_logo non appele dans auto_update"; exit 1; }
# Sanity : le fichier reste sourcable sans erreur de syntaxe
zsh -n "$DIR/core/auto_update.zsh" || { echo "FAIL: syntaxe auto_update.zsh"; exit 1; }
echo "PASS"
```

- [ ] **Step 3: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_autoupdate.sh"`
Expected: `FAIL: _zanvil_logo non appele dans auto_update`

- [ ] **Step 4: Appeler `_zanvil_logo` après succès d'update**

Dans `core/auto_update.zsh`, à la fin du bloc qui confirme une mise à jour appliquée (juste après l'`echo ""` de la ligne ~88, dans la branche succès), ajouter :

```zsh
        # Splash zanvil apres une mise a jour reussie
        _zanvil_logo
```

(Respecter l'indentation du bloc englobant. `_zanvil_logo` est défini dans `core/ui.zsh`, chargé avant les modules — donc disponible au moment de l'exécution de l'auto-update.)

- [ ] **Step 5: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_autoupdate.sh"`
Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
git add core/auto_update.zsh
git commit -m "feat(update): splash zanvil après une mise à jour réussie"
```

---

## Notes d'exécution

- Sur la machine de dev, les fonctions s'affichent en couleurs réelles ; les tests filtrent sur le texte (`zanvil`, `craft your shell`, `reloaded`) indépendamment des couleurs.
- La branche d'implémentation DOIT être nommée `feature/*` ou `feat/*` pour déclencher le bump **minor** (v3.9.0) via `auto-release.yml` au merge. Une branche `chore/*`/`fix/*` ne déclencherait pas de release minor.
- Le secret `RELEASE_TOKEN` est en place → la release se publiera automatiquement au merge de la PR `feature/*`.
