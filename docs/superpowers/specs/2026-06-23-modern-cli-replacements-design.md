# Design : remplacements de commandes modernes

**Date** : 2026-06-23
**Statut** : Validé (en attente d'implémentation)

## Objectif

Étendre les remplacements de commandes Unix natives par des outils modernes,
dans la continuité des alias existants `ls`→`eza`, `cat`→`bat`, `rm`→`trash`.
Garantir que les nouveaux outils sont installés par `install.sh` de façon
cross-platform (brew / apt / dnf).

## Philosophie : hybride par outil

Décidée avec l'utilisateur :

- **Écrasement franc** pour les remplacements drop-in en usage interactif
  (`du`, `df`, `ps`, `top`, `ping`).
- **Préservation du natif** pour les commandes à syntaxe POSIX divergente
  (`grep`, `find`, `sed`) : `rg` et `fd` restent sous leurs propres noms,
  déjà courts, sans aliaser ni masquer les commandes natives.
- **Complément** pour `tldr` : `man` reste `man`, `tldr` s'invoque directement.

Tous les alias sont gardés par `command -v <outil> &>/dev/null` : si l'outil est
absent sur la plateforme, l'alias ne s'active pas (aucune casse). Les alias zsh
ne s'appliquent qu'en interactif, jamais dans les scripts.

## Périmètre des outils

| binaire | brew    | apt        | dnf        | alias / usage         | note |
|---------|---------|------------|------------|-----------------------|------|
| `rg`    | ripgrep | ripgrep    | ripgrep    | nom propre (pas d'alias) | paquet `ripgrep`, binaire `rg` |
| `fd`    | fd      | fd-find    | fd-find    | nom propre (pas d'alias) | binaire Debian = `fdfind` → symlink |
| `dust`  | dust    | *(vide)*   | *(vide)*   | `alias du='dust'`     | brew only (apt/dnf via cargo, skip + warn) |
| `duf`   | duf     | duf        | duf        | `alias df='duf'`      | |
| `procs` | procs   | *(vide)*   | procs      | `alias ps='procs'`    | ⚠️ `procs aux` ≠ `ps aux` |
| `btop`  | btop    | btop       | btop       | `alias top='btop'`    | TUI interactif |
| `gping` | gping   | *(vide)*   | *(vide)*   | `alias ping='gping'`  | brew only |
| `tldr`  | tldr    | tldr       | tldr       | pas d'alias (complément de `man`) | |

Les champs vides (`""`) sont déjà gérés par `install_tool` (ligne ~175 :
log un warn et `return`). L'outil ne sera pas installé sur ces plateformes et
son alias ne s'activera pas.

## Modifications par fichier

### 1. `install.sh`

**Section « Modern replacements »** (après la ligne `install_tool "trash" …`,
~ligne 231) :

```sh
# Remplacements de commandes modernes (alias dans core/aliases.zsh)
install_tool "rg"    "ripgrep" "ripgrep" "ripgrep"  # grep moderne (nom propre)
install_tool "fd"    "fd"      "fd-find" "fd-find"   # find moderne (nom propre)
install_tool "dust"  "dust"    ""        ""          # du arborescent (brew only)
install_tool "duf"   "duf"     "duf"     "duf"       # df coloré
install_tool "procs" "procs"   ""        "procs"     # ps moderne
install_tool "btop"  "btop"    "btop"    "btop"      # top / moniteur TUI
install_tool "gping" "gping"   ""        ""          # ping graphique (brew only)
install_tool "tldr"  "tldr"    "tldr"    "tldr"      # exemples concrets (complément man)
```

**Cas `fd` / Debian** dans la section « installation manuelle »
(~ligne 320, après le bloc Nushell) : créer un symlink si seul `fdfind` existe.

```sh
# fd : sur Debian/Ubuntu le binaire s'appelle 'fdfind'
if ! command -v fd &> /dev/null && command -v fdfind &> /dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    log_success "Symlink fd -> fdfind créé dans ~/.local/bin"
fi
```

### 2. `core/aliases.zsh`

Nouvelle section après le bloc `if command -v bat` (~ligne avec `alias cat='bat'`),
avant la section sécurité suppression :

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

### 3. `core/check_env_deps.zsh`

Étendre le tableau `dependencies` (ligne 19) avec les nouveaux binaires et gérer
le cas `fd`/`fdfind` sur Linux, à l'image du cas `batcat` existant (lignes 32-34) :

```zsh
local dependencies=(git curl jq fzf eza starship zoxide python3 node \
                    rg fd dust duf procs btop gping tldr)
```

```zsh
if [[ "$dep" == "fd" && "$(uname)" == "Linux" ]]; then
    if command -v fdfind &> /dev/null; then cmd_to_check="fdfind"; fi
fi
```

## Migration

**Aucune migration nécessaire.** On n'invalide aucun état utilisateur existant
(pas de renommage de config, pas de déplacement de fichier). Les nouveaux alias
s'activent au reload (`ss`), les outils au prochain `install.sh`.

## Hors périmètre

- `sed`→`sd` : `sd` est installé seulement si l'utilisateur le souhaite plus tard ;
  non inclus dans ce lot (syntaxe trop divergente, pas demandé).
- Le bug préexistant `bat`/`batcat` sur Debian (alias `cat='bat'` qui échoue si le
  binaire est `batcat`) n'est pas traité ici — hors périmètre.
- `diff`→`delta` : `delta` lit un diff unifié, ce n'est pas un remplaçant direct
  de `diff` ; non aliasé.
