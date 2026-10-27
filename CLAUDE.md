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
│   ├── commands/       # Commandes zanvil-* (admin, commands, theme, setup, check_env_deps, dotfiles)
│   └── lifecycle/      # Migration, sync, auto-update (auto_update, migrate, sync) ; auto-update en arriere-plan (ff-only de main) + rechargement des shells ouverts au precmd
├── modules/            # Features modulaires (init.zsh + completions.zsh par module)
│   ├── git/            # git_bulk, git_hooks, git_change_author, git_root
│   ├── gitlab/         # gitlab_logic, pipeline_bulk (guard: ZANVIL_MODULE_GITLAB)
│   ├── kube/           # kube_config, kube_switch, kube_ns, k (guard: ZANVIL_MODULE_KUBE)
│   ├── docker/         # docker_utils (guard: ZANVIL_MODULE_DOCKER)
│   ├── ssh/            # ssh_manager
│   ├── tmux/           # tmux_manager (lazy loaded)
│   ├── ai/             # ai_context, ai_tokens (lazy loaded)
│   ├── project/        # project open <lien-MR> (worktree + Orca + IDEA), project clean (guard: ZANVIL_MODULE_PROJECT)
│   ├── security/       # security_audit
│   ├── utils/          # utils, extract, fkill, net_utils (lazy)
│   ├── tools/          # mise_hooks, test_runner, zsh_profile ; sous-module screensaver (zsaver, cbonsai)
│   └── boulanger/      # boulanger_context
├── brew/               # base.Brewfile : dependances de zanvil (common/profil vivent dans le depot dotfiles)
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
- `colors.sh` (0xAARRGGBB, sh/zsh) genere par `_zanvil_theme_colors` depuis `_ui_blue/_ui_white/_ui_dim` + `_theme_bg` de la palette (sous-shell, valeurs de repli) ; recharge sketchybar/borders s'ils tournent, ne les demarre jamais ; un `<config sketchybar>/recolor` executable remplace `sketchybar --reload` (recolore sans reconstruire la barre)
- `_zanvil_theme_wallpaper` (macOS) : pose `~/.config/zanvil/wallpapers/<theme>.{jpg,jpeg,png,heic}` via NSWorkspace (JXA, sans autorisation) s'il existe
- `zanvil-ghostty auto` : ecrit `theme = light:<chemin>,dark:<chemin>` (ZANVIL_GHOSTTY_LIGHT/DARK, defauts tokyo-light-storm/tokyo-night-storm) ; Ghostty suit l'apparence sans rechargement. `zanvil-theme auto` (ZANVIL_THEME_LIGHT/DARK) tourne au demarrage du shell ; le direct passe par un declencheur externe (SketchyBar sur AppleInterfaceThemeChangedNotification)
- Fichiers generes dans `~/.config/zanvil/theme/` (jamais dans les configs versionnees ni le depot dotfiles) : `starship.toml` (`STARSHIP_CONFIG` exporte par `core/hooks.zsh`), `ghostty` (inclus par `config-file = ?~/.config/zanvil/theme/ghostty`), k9s via `K9S_SKIN`. Un CLI Rust compile avant ce changement doit etre reconstruit
- Outils suivant le theme (`core/commands/theme_tools.zsh`, un `_zanvil_theme_tool_<outil>` par outil installe) : bat, delta, fzf, eza, lazygit, btop, atuin, posting, lazydocker, tmux (+ k9s). Exports (`_zanvil_theme_exports`, `BAT_THEME_*`) seulement si le fichier genere existe ; jamais par-dessus un reglage ou theme de l'utilisateur ; selecteur ajoute seulement s'il n'y en a aucun (`_zanvil_theme_adopt`, avertissement unique) ; config en lien symbolique jamais ecrite. nvim : rien (Neovim >= 0.11 suit DEC 2031). Themes bat vendus sous Apache-2.0 (`config/bat/themes/NOTICE`)

### Dotfiles (core/commands/dotfiles.zsh)

`zanvil-dotfiles status|pull|install|cleanup|link|adopt|apply|migrate`. Brewfiles en couches (`brew/base.Brewfile` + `common` + profil du depot dotfiles), liens Stow toujours `--no-folding`. Apres un `install` reussi sur macOS, lance `macos.sh` a la racine du depot s'il existe (`sh`, idempotent ; un echec avertit sans faire echouer l'install). `cleanup` liste puis exige une confirmation explicite ; `link` bloque sur conflit ; `adopt` refuse les secrets. `migrate` (core/commands/dotfiles_migrate.zsh) applique le depot sur une machine deja configuree : ecrit seulement les cles absentes ou vides de `config.zsh`, `--adopt` des casks deja installes (refus et echecs retires du Brewfile donne a `brew bundle`), resolution des conflits d/l/p avec sauvegarde dans `~/.zanvil-backup/`, liens Stow de tout sauf les fichiers passes (`--ignore` par chemin), commit local sans push, simulation de `cleanup` sans jamais desinstaller ; proposee une fois apres une mise a jour reussie (`.dotfiles_migrate_suggested`, gitignore). Variables : `ZANVIL_PROFILE` (pro|perso), `ZANVIL_DOTFILES_REPO`, `ZANVIL_DOTFILES_DIR` (defaut `~/.dotfiles`). `install.sh` ecrit les trois dans `config.zsh` (`--profile`, `--dotfiles`, sinon question ou valeur deja presente dans `config.zsh`).

### Auto-update (core/lifecycle/auto_update.zsh)

`ZANVIL_UPDATE_MODE` auto (defaut) | prompt | off, `ZANVIL_UPDATE_FREQUENCY` (jours, defaut 1). En auto, le demarrage ne lit que `.last_update_check` (ni git ni fork) ; si due, `_zanvil_update_background` tourne en `&!` (verrou `.update.lock` a jeton proprietaire, repris apres 1 h par rename atomique, sortie `.update.log` ; fetch sans invite : GIT_TERMINAL_PROMPT=0, ssh BatchMode, http.lowSpeed*) : fetch puis `_zanvil_update_apply` (commun avec `zanvil-update`), qui n'applique qu'un `merge --ff-only` sur `main` sans modification suivie ; sinon, comme pour une fusion impossible ou 3 fetch en echec de suite (`.update_fetch_failures`), une notification par situation et par HEAD (`.update_blocked`) ; binaire CLI remplace par cp+mv. Sans TTY : reconstruction du CLI si deja installe, jamais de migration (notification). `_zanvil_update_precmd` compare a chaque invite `_ZANVIL_LOADED_REV` a la revision lue dans `.git` (HEAD, ref ou packed-refs, sans fork) et recharge via `sched +0 ss` (niveau global : sourcer depuis une fonction rendrait les typeset locaux) ; attend la fin d'un verrou frais ; `ZANVIL_UPDATE_RELOAD=false` coupe.

### Project (modules/project/project.zsh)

`project` sans argument appelle `work_explore` (module work ; message sinon). `project open <lien-de-MR>` clone au besoin le depot sous `$WORK_DIR/<chemin GitLab>` (hote GitLab pris du lien) et cree un worktree de la branche de la MR dans `$WORK_DIR/<sous-groupe>/.worktrees/<repo>/<branche>` ; le depot principal n'est jamais touche, le `.zanvil.local` du depot est copie. Ouvre ensuite Orca et IntelliJ IDEA ; les erreurs passent par une notification (`_project_notify`). `project clean` retire les worktrees des MR terminees sans travail non pousse ; `init.zsh` le lance en arriere-plan une fois par 24 h. `scripts/raycast/project-open.sh` (Hyper+O dans Raycast) lit le presse-papiers et rebranche `PATH` et `~/.gitlab_secrets` avant d'appeler `project open`.

### Explorateur de projets (modules/work/explore.zsh, cli/src/cmd/explore/)

`work_explore` lance `zanvil explore --out <tmp>` (TUI a deux volets, CLI Rust requis) puis `cd` vers le depot choisi ; l'index GitLab `${XDG_CACHE_HOME:-~/.cache}/zanvil/projects.json` est rafraichi en arriere-plan (`zanvil explore --refresh`) s'il est absent ou a plus de 24 h, un seul a la fois (verrou `refresh.lock`, perime apres 1 h) ; un index vide n'ecrase pas le cache. Acces effectif = max des listes `min_access_level=30/40/50` ; variables lues sur les groupes `<bu>/<app_segment>/<app>` des projets ou l'on est Maintainer. Reglages dans `~/.config/zanvil/projects.toml` (fichier des dotfiles, jamais dans ce depot public ; modele : `examples/projects.toml.example`).

### Kube aliases

`~/.kube/.context_aliases` mappe des noms courts vers les contextes complets :
```
blg-dev=aks-blg-caasplatform-dev-common-001
```
Utilise par : `kube_switch`, `k` (sofka ou k9s selon `ZANVIL_KUBE_TUI`, `kube_tui` pour changer), `zanvil context` (prompt Starship)

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
