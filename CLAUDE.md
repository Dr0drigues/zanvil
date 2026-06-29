# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Description

Suite de configuration Zsh modulaire et orientee productivite pour macOS et Linux. Architecture hybride Rust CLI + modules zsh. Automatise l'installation d'outils modernes (zoxide, starship, eza, mise, nushell) et fournit des fonctions avancees pour Git, GitLab, Docker et Kubernetes.

## Installation

```bash
git clone git@github.com:Dr0drigues/zanvil.git ~/.zanvil
cd ~/.zanvil
./install.sh
```

Le script `install.sh` installe les dependances via brew/apt/dnf, configure `.zshrc`, et build le CLI Rust si cargo est disponible.

## Architecture

```
~/.zanvil/
├── rc.zsh              # Point d'entree principal (source par .zshrc)
├── config.zsh          # Configuration modules (gitignored)
├── completions.zsh     # Completions custom utilisateur
├── core/               # Systeme central
│   ├── ui.zsh          # Systeme UI (_ui_* variables + fonctions) + palette loader
│   ├── loader.zsh      # Module loader (decouverte auto modules/)
│   ├── variables.zsh   # Variables d'environnement
│   ├── aliases.zsh     # Alias globaux
│   ├── hooks.zsh       # Init outils (starship, fzf, mise, zoxide, direnv, .zanvil.local)
│   ├── completions.zsh # Completions des commandes core
│   ├── commands/       # Commandes zanvil-* (admin, commands, theme, setup, check_env_deps)
│   └── lifecycle/      # Migration, sync, auto-update (auto_update, migrate, sync)
├── modules/            # Features modulaires (init.zsh + completions.zsh par module)
│   ├── git/            # git_bulk, git_hooks, git_change_author, git_root
│   ├── gitlab/         # gitlab_logic, pipeline_bulk (guard: ZANVIL_MODULE_GITLAB)
│   ├── kube/           # kube_config, kube_switch, kube_ns, k (guard: ZANVIL_MODULE_KUBE)
│   ├── docker/         # docker_utils (guard: ZANVIL_MODULE_DOCKER)
│   ├── ssh/            # ssh_manager
│   ├── tmux/           # tmux_manager (lazy loaded)
│   ├── ai/             # ai_context, ai_tokens (lazy loaded)
│   ├── project/        # project_switcher
│   ├── security/       # security_audit
│   ├── utils/          # utils, extract, fkill, net_utils (lazy)
│   ├── tools/          # mise_hooks, test_runner, zsh_profile
│   └── boulanger/      # boulanger_context
├── config/             # Configs outils versionnees (atuin, delta, ghostty, k9s, lazygit, posting)
│   └── themes/         # Themes Starship (flat .toml ou directory avec palette.zsh)
│       ├── tokyo-night-pro/
│       │   ├── prompt.toml
│       │   └── palette.zsh
│       └── minimal.toml
├── secrets/            # .enc versionnés, plaintext déchiffré gitignored
│   ├── secrets/kube/   # Kubeconfigs + .context_aliases
│   └── secrets/work/   # Certificats et settings dechiffres
├── examples/           # Templates de config utilisateur
│   ├── config.zsh.example
│   └── env.d/          # Exemples de variables d'env dynamiques
├── env.d/              # Variables d'env dynamiques (*.zsh, *.sops.zsh)
├── cli/                # CLI Rust companion (optionnel)
│   ├── Cargo.toml
│   └── src/
├── web/                # Assets web regroupes
│   ├── site/           # Site de doc Astro Starlight (GitHub Pages, theme forge)
│   │   └── src/content/docs/
│   ├── wiki/           # Pages wiki GitHub (deploye via wiki.yml)
│   ├── docs/           # Documentation interne (specs, roadmap, superpowers)
│   └── assets/         # Assets statiques (branding, logo)
├── scripts/            # Scripts autonomes (clone-projects, trigger-jobs)
└── install.sh          # Bootstrapper cross-platform
```

Le site (`web/site/`) est un projet Astro Starlight déployé sur GitHub Pages via `.github/workflows/pages.yml`. Contenu Markdown sous `web/site/src/content/docs/`.

### Flux de chargement

1. `.zshrc` source `rc.zsh` via `$ZANVIL_DIR`
2. `rc.zsh` charge : config.zsh, secrets, `core/variables.zsh`, `env.d/*.zsh`
3. compinit (completions zsh)
4. `core/loader.zsh` : charge `core/ui.zsh` en premier, puis core/*.zsh, puis modules/*/init.zsh + completions.zsh
5. `core/aliases.zsh`
6. plugins.zsh
7. `core/hooks.zsh` (starship, fzf, mise, zoxide, direnv, .zanvil.local)

### Module Loader (core/loader.zsh)

- Decouvre automatiquement les modules dans `modules/*/init.zsh`
- Module guards : `ZANVIL_MODULE_<NAME>` (derive du nom du dossier, uppercased)
- Lazy loading : modules avec fichier `.lazy` (liste les fonctions publiques a stub)
- Completions par module : `modules/*/completions.zsh`

### CLI Rust (cli/)

Binary optionnel `zanvil` qui accelere les commandes lourdes. Les fonctions zsh delegent au CLI quand disponible, fallback au zsh sinon.

Commandes implementees : `theme list|apply|current`, `doctor`, `audit`, `context`, `modules list|enable|disable`

Pattern de delegation :
```zsh
zanvil-function() {
    if command -v zanvil &>/dev/null; then
        zanvil subcommand "$@"; return $?
    fi
    # ... fallback zsh ...
}
```

### Systeme de themes unifie

Un theme controle a la fois le prompt Starship ET les couleurs des commandes zanvil-*.

- **Flat .toml** : theme Starship uniquement (couleurs UI par defaut)
- **Directory** : `prompt.toml` + `palette.zsh` (override des `_ui_*` variables en true color)
- Etat stocke dans `.current_theme`, lu par `core/ui.zsh` au startup

### Kube aliases

`~/.kube/.context_aliases` mappe des noms courts vers les contextes complets :
```
blg-dev=aks-blg-caasplatform-dev-common-001
```
Utilise par : `kube_switch`, `k` (k9s), `zanvil context` (prompt Starship)

### .zanvil.local (direnv-like)

Fichier `.zanvil.local` a la racine d'un projet, auto-source au `cd`.
Trust hash-based (sha256). Auto-unload en sortant du dossier.

## Systeme UI (`core/ui.zsh`)

Toutes les commandes `zanvil-*` utilisent un style visuel coherent via les fonctions UI :

**Variables disponibles :**
- Couleurs : `$_ui_green`, `$_ui_red`, `$_ui_yellow`, `$_ui_blue`, `$_ui_cyan`
- Styles : `$_ui_bold`, `$_ui_dim`, `$_ui_nc` (reset)
- Symboles : `$_ui_check`, `$_ui_cross`, `$_ui_circle`
- Version : `$ZANVIL_VERSION`

**Fonctions de formatage :**
- `_ui_header "Titre"` - Header boxed avec version
- `_ui_section "Label" contenu` - Section avec label aligne (14 chars)
- `_ui_separator [largeur]` - Ligne de separation
- `_ui_summary $issues $warnings` - Resume final

**Indicateurs inline :**
- `_ui_ok "nom" ["version"]` / `_ui_fail "nom" ["detail"]` / `_ui_warn "nom"` / `_ui_skip "nom"`

**Messages :**
- `_ui_msg_ok` / `_ui_msg_fail` / `_ui_msg_warn` / `_ui_msg_info`
- `_ui_tag_ok` / `_ui_tag_fail` / `_ui_tag_warn`

## Conventions

### General
- Les alias et fonctions verifient la presence des outils avant utilisation (`command -v`)
- Les secrets doivent aller dans `~/.secrets`, `~/.gitlab_secrets` ou `env.d/*.sops.zsh`
- Module guards dans config.zsh (ex: `ZANVIL_MODULE_GITLAB=true`)
- Recharger la config : `ss` ou `source ~/.zshrc`

### Developpement UI
- **Toujours utiliser les fonctions `_ui_*`** pour les couleurs et le formatage
- **Ne jamais coder les couleurs en dur** (`\033[...`) dans les nouveaux fichiers
- Les commandes `zanvil-*` doivent avoir un header avec `_ui_header "Titre"`
- Les palettes de themes overrident les `_ui_*` via `config/themes/<name>/palette.zsh`

### Modules
- Chaque module a `init.zsh` (fonctions) + `completions.zsh` (compdef)
- Fichier `.lazy` pour le lazy loading (liste les fonctions publiques)
- Les guards de module restent dans les fichiers source (defense-in-depth)

### CLI Rust
- Code dans `cli/src/cmd/<command>.rs`
- Utilise `clap` derive pour le parsing, `colored` pour les couleurs
- Decouvre `$ZANVIL_DIR` depuis l'env, fallback `~/.zanvil`
- Les commandes zsh gardent le fallback complet si le binaire est absent
