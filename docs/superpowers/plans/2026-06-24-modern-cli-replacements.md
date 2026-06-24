# Modern CLI Replacements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter des remplacements de commandes Unix par des outils modernes (rg, fd, dust, duf, procs, btop, gping, tldr), installés cross-platform et câblés en alias interactifs.

**Architecture:** Trois fichiers touchés, sans interdépendance de runtime : `install.sh` installe les binaires, `core/aliases.zsh` définit les alias gardés par `command -v`, `core/check_env_deps.zsh` les recense dans le doctor. Philosophie hybride : écrasement franc pour les drop-in (`du`/`df`/`ps`/`top`/`ping`), `rg`/`fd` gardés sous leurs noms propres, `tldr` en complément.

**Tech Stack:** zsh (alias + guards `command -v`), bash (install.sh), pas de framework de test — vérifications par sourcing zsh et `bash -n`.

## Global Constraints

- Tous les alias DOIVENT être gardés par `command -v <outil> &>/dev/null &&` — aucun alias inconditionnel.
- `grep`, `find`, `sed` ne sont JAMAIS aliasés ni masqués.
- Suivre les conventions du projet : commentaires en français, pas de couleurs codées en dur.
- Aucune migration `migrations/NNN_*.zsh` : aucun état utilisateur existant n'est invalidé.
- Recharger la config de test avec un `zsh -c 'source ...'` isolé, jamais le shell courant.

---

### Task 1: install.sh — installation des outils modernes

**Files:**
- Modify: `install.sh` — section après `install_tool "trash" …` (~ligne 231) et section « installation manuelle » (~ligne 320, après le bloc Nushell)

**Interfaces:**
- Consumes: la fonction `install_tool "binaire" "brew" "apt" "dnf"` déjà définie (ligne 153), les helpers `log_success` / `_sudo_available`.
- Produces: rien que les tâches suivantes consomment (fichiers indépendants).

- [ ] **Step 1: Écrire le test de syntaxe + présence (doit échouer)**

Créer `/private/tmp/claude-502/-Users-bl209054--zsh-env/518614f2-a551-4e43-9135-dfc256ae2d6e/scratchpad/test_install.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail
F="$HOME/.zsh_env/install.sh"
bash -n "$F" || { echo "FAIL: syntaxe install.sh"; exit 1; }
for line in \
  'install_tool "rg"    "ripgrep"' \
  'install_tool "fd"    "fd"' \
  'install_tool "dust"  "dust"' \
  'install_tool "duf"   "duf"' \
  'install_tool "procs" "procs"' \
  'install_tool "btop"  "btop"' \
  'install_tool "gping" "gping"' \
  'install_tool "tldr"  "tldr"' ; do
  grep -qF "$line" "$F" || { echo "FAIL: ligne absente -> $line"; exit 1; }
done
grep -qF 'ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"' "$F" \
  || { echo "FAIL: symlink fd/fdfind absent"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_install.sh"`
Expected: `FAIL: ligne absente -> install_tool "rg"    "ripgrep"`

- [ ] **Step 3: Ajouter le bloc d'installation des outils**

Dans `install.sh`, juste après la ligne `install_tool "trash"    "trash"     "trash-cli" "trash-cli"` (et son commentaire) :

```sh

# Remplacements de commandes modernes (alias dans core/aliases.zsh)
install_tool "rg"    "ripgrep" "ripgrep" "ripgrep"  # grep moderne (nom propre, pas d'alias)
install_tool "fd"    "fd"      "fd-find" "fd-find"   # find moderne (nom propre, pas d'alias)
install_tool "dust"  "dust"    ""        ""          # du arborescent (brew only)
install_tool "duf"   "duf"     "duf"     "duf"       # df colore
install_tool "procs" "procs"   ""        "procs"     # ps moderne
install_tool "btop"  "btop"    "btop"    "btop"      # top / moniteur TUI
install_tool "gping" "gping"   ""        ""          # ping graphique (brew only)
install_tool "tldr"  "tldr"    "tldr"    "tldr"      # exemples concrets (complement man)
```

- [ ] **Step 4: Ajouter le symlink fd/fdfind dans la section manuelle**

Dans `install.sh`, après le bloc d'installation manuelle de Nushell (juste avant `# --- Configuration Automatique du .zshrc ---`) :

```sh

# fd : sur Debian/Ubuntu le binaire installe par 'fd-find' s'appelle 'fdfind'
if ! command -v fd &> /dev/null && command -v fdfind &> /dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    log_success "Symlink fd -> fdfind cree dans ~/.local/bin"
fi
```

- [ ] **Step 5: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_install.sh"`
Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
git add install.sh
git commit -m "feat(install): installer rg/fd/dust/duf/procs/btop/gping/tldr"
```

---

### Task 2: core/aliases.zsh — section MODERN CLI REPLACEMENTS

**Files:**
- Modify: `core/aliases.zsh` — après le bloc `if command -v bat … alias cat='bat'` (ligne 111), avant la section « Sécurité suppression »

**Interfaces:**
- Consumes: rien (les alias sont autonomes).
- Produces: les alias `du`, `df`, `top`, `ping`, `ps` — actifs uniquement si l'outil correspondant est présent.

- [ ] **Step 1: Écrire le test de comportement (doit échouer)**

Créer `$SCRATCHPAD/test_aliases.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail
F="$HOME/.zsh_env/core/aliases.zsh"

# 1. Avec stubs présents -> les alias doivent être définis
stub=$(mktemp -d)
for b in dust duf btop gping procs; do
  printf '#!/bin/sh\necho %s\n' "$b" > "$stub/$b"; chmod +x "$stub/$b"
done
out=$(PATH="$stub:$PATH" zsh -c "source '$F' 2>/dev/null; \
  alias du; alias df; alias top; alias ping; alias ps")
for pair in "du='dust'" "df='duf'" "top='btop'" "ping='gping'" "ps='procs'"; do
  echo "$out" | grep -qF "$pair" || { echo "FAIL: alias attendu absent -> $pair"; exit 1; }
done

# 2. grep/find/sed ne doivent JAMAIS être aliasés
forbidden=$(PATH="$stub:$PATH" zsh -c "source '$F' 2>/dev/null; \
  alias grep 2>/dev/null; alias find 2>/dev/null; alias sed 2>/dev/null")
[[ -z "$forbidden" ]] || { echo "FAIL: grep/find/sed ne doivent pas etre alias -> $forbidden"; exit 1; }

# 3. Sans le binaire, l'alias ne doit pas exister
noalias=$(PATH="/usr/bin:/bin" zsh -c "source '$F' 2>/dev/null; alias du 2>/dev/null")
echo "$noalias" | grep -qF "du='dust'" && { echo "FAIL: du alias sans dust installe"; exit 1; }

echo "PASS"
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_aliases.sh"`
Expected: `FAIL: alias attendu absent -> du='dust'`

- [ ] **Step 3: Ajouter la section MODERN CLI REPLACEMENTS**

Dans `core/aliases.zsh`, juste après le bloc `bat` (après la ligne 113 `fi` qui ferme `if command -v bat`) :

```zsh

# =======================================================
# MODERN CLI REPLACEMENTS
# =======================================================
# Remplacements drop-in en usage interactif. Chaque alias est garde par
# 'command -v' : si l'outil est absent, l'alias ne s'active pas.
# Echappatoire pour les usages avances : 'command du', '\ps', etc.
# grep/find/sed NE sont PAS aliases : rg et fd s'utilisent sous leurs vrais noms.

command -v dust  &>/dev/null && alias du='dust'
command -v duf   &>/dev/null && alias df='duf'
command -v btop  &>/dev/null && alias top='btop'
command -v gping &>/dev/null && alias ping='gping'
# Attention: 'procs aux' n'est pas equivalent a 'ps aux'. Usage interactif simple.
command -v procs &>/dev/null && alias ps='procs'
```

Note : vérifier la ligne exacte de fermeture du bloc `bat`. À l'écriture, le fichier contient ligne 111 `alias cat='bat'` puis `fi`. Insérer la section après ce `fi`.

- [ ] **Step 4: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_aliases.sh"`
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add core/aliases.zsh
git commit -m "feat(aliases): remplacements modernes du/df/top/ping/ps (hybride)"
```

---

### Task 3: core/check_env_deps.zsh — recensement dans le doctor

**Files:**
- Modify: `core/check_env_deps.zsh:19` (tableau `dependencies`) et bloc des cas par-OS (lignes 28-34)

**Interfaces:**
- Consumes: les fonctions `_ui_*` (header, ok, fail) et `check_env_health` existantes.
- Produces: rien.

- [ ] **Step 1: Écrire le test (doit échouer)**

Créer `$SCRATCHPAD/test_doctor.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$HOME/.zsh_env"
out=$(zsh -c "source '$DIR/core/ui.zsh' 2>/dev/null; \
  source '$DIR/core/check_env_deps.zsh'; check_env_health" 2>&1)
for tool in rg fd dust duf procs btop gping tldr; do
  echo "$out" | grep -qw "$tool" || { echo "FAIL: $tool absent du doctor"; exit 1; }
done
echo "PASS"
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_doctor.sh"`
Expected: `FAIL: rg absent du doctor`

- [ ] **Step 3: Étendre le tableau dependencies**

Dans `core/check_env_deps.zsh`, remplacer la ligne 19 :

```zsh
    local dependencies=(git curl jq fzf eza starship zoxide python3 node)
```

par :

```zsh
    local dependencies=(git curl jq fzf eza starship zoxide python3 node \
                        rg fd dust duf procs btop gping tldr)
```

- [ ] **Step 4: Gérer le cas fd/fdfind sur Linux**

Dans `core/check_env_deps.zsh`, juste après le bloc `if [[ "$dep" == "bat" && "$(uname)" == "Linux" ]]` (lignes 32-34) :

```zsh
        if [[ "$dep" == "fd" && "$(uname)" == "Linux" ]]; then
            if command -v fdfind &> /dev/null; then cmd_to_check="fdfind"; fi
        fi
```

- [ ] **Step 5: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_doctor.sh"`
Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
git add core/check_env_deps.zsh
git commit -m "feat(doctor): recenser les outils modernes dans check_env_health"
```

---

## Notes d'exécution

- `$SCRATCHPAD` = `/private/tmp/claude-502/-Users-bl209054--zsh-env/518614f2-a551-4e43-9135-dfc256ae2d6e/scratchpad`
- Sur la machine de dev actuelle, seuls `rg`/`fd` sont installés (pas `dust`/`duf`/`procs`/`btop`/`gping`/`tldr`) → le test du doctor (Task 3) affichera ces outils en `fail`, ce qui est attendu et n'invalide pas le test (il vérifie leur *présence dans la liste*, pas leur installation). Le test des alias (Task 2) utilise des stubs, donc indépendant de l'installation réelle.
- Les tests des Tasks 2 et 3 sourcent les fichiers dans un `zsh -c` isolé, jamais le shell courant.
