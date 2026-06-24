<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/logo-mark-light.svg">
    <img src="assets/branding/logo-mark.svg" alt="zanvil" width="128" height="128">
  </picture>
</p>

<h1 align="center">zanvil</h1>
<p align="center"><em>craft your shell</em></p>

<p align="center">
Configuration Zsh modulaire et orientee productivite pour developpeurs (macOS &amp; Linux).<br>
Architecture hybride <strong>Rust CLI + modules zsh</strong> pour des performances optimales.
</p>

<p align="center"><strong><a href="https://dr0drigues.github.io/zsh_env/">Site de documentation</a></strong> · <a href="https://github.com/Dr0drigues/zsh_env/wiki">Wiki</a></p>

## Installation

```bash
git clone git@github.com:Dr0drigues/zsh_env.git ~/.zsh_env
cd ~/.zsh_env && ./install.sh
```

Le script installe les dependances, configure `.zshrc`, et build le CLI Rust si `cargo` est disponible.

## Fonctionnalites

| Module | Description |
|--------|-------------|
| **Navigation** | Jump intelligent avec `zoxide`, auto-cd |
| **Project Switcher** | Changement de contexte complet (kube, node, tmux) |
| **Kubernetes** | Multi-config Azure/AWS/GCP, aliases, `kube_switch`, `k` (k9s) |
| **GitLab** | Clone groupes, PAT status, browse, pipelines |
| **SSH Manager** | Gestion simplifiee des connexions SSH |
| **Tmux Manager** | Gestion des sessions tmux |
| **Git Bulk** | Operations git en masse avec dry-run |
| **Security** | Audit des permissions et secrets |
| **Themes** | Themes unifies Starship + palette shell (true color) |
| **CLI Rust** | Binaire natif optionnel pour doctor, audit, context, modules |
| **env.d/** | Variables d'env dynamiques avec support sops |
| **.zsh-env.local** | Auto-chargement par projet (style direnv) |

## Commandes essentielles

```bash
ss                         # Recharger la config
zsh-env-help               # Liste toutes les commandes
zsh-env-doctor             # Diagnostic systeme
zsh-env-audit              # Audit de securite
zsh-env-modules list       # Lister/activer/desactiver les modules
zsh-env-theme list         # Gestion des themes (prompt + palette)
zsh-env-backup             # Sauvegarde des configs

kube_switch blg-dev        # Switch de cluster (avec aliases)
kube_ns                    # Switch de namespace
k blg-dev                  # k9s sur un cluster
kube_status                # Contexte + namespace + pods

zsh-env-gitlab-status      # Statut du PAT GitLab
zsh-env-gitlab-browse -m   # Ouvrir les MRs dans le navigateur
gpr                        # Raccourci creation MR

proj mon-projet            # Charger un projet
zsh-env-switch env         # Switcher d'environnement
ssh_select                 # Selectionner un host SSH
tm                         # Gerer les sessions tmux
hooks_install              # Installer les hooks Git
```

## Architecture

```
~/.zsh_env/
├── rc.zsh              # Point d'entree
├── config.zsh          # Configuration modules (gitignored)
├── core/               # Systeme central
│   ├── ui.zsh          # Systeme UI + palette loader
│   ├── loader.zsh      # Module loader automatique
│   ├── commands.zsh    # zsh-env-list, doctor, status, help
│   ├── admin.zsh       # modules, backup, restore, switch
│   ├── theme.zsh       # Themes Starship + Ghostty
│   └── hooks.zsh       # Init outils + .zsh-env.local
├── modules/            # Features modulaires
│   ├── git/            # bulk, hooks, change-author
│   ├── gitlab/         # clone, pipelines, PAT, browse
│   ├── kube/           # config, switch, ns, k9s, aliases
│   ├── docker/         # dex, dstop
│   ├── ssh/            # select, add, remove, test
│   ├── tmux/           # sessions (lazy loaded)
│   ├── ai/             # context, tokens (lazy loaded)
│   └── ...
├── themes/             # Flat .toml ou directory (prompt.toml + palette.zsh)
├── env.d/              # Variables dynamiques (*.zsh, *.sops.zsh)
├── cli/                # CLI Rust companion (optionnel)
└── scripts/            # Scripts autonomes
```

## CLI Rust (optionnel)

Le binaire `zsh-env-cli` (684 Ko) accelere les commandes lourdes. Les fonctions zsh delegent automatiquement au CLI quand il est disponible.

```bash
zsh-env-cli doctor          # Diagnostic natif
zsh-env-cli audit           # Scan securite
zsh-env-cli theme list      # Gestion themes
zsh-env-cli context         # Contexte kube (pour Starship)
zsh-env-cli modules list    # Gestion modules
```

Build manuel : `cd cli && cargo build --release && cp target/release/zsh-env-cli ~/.local/bin/`

## Systeme de themes

Les themes unifies controlent a la fois le prompt Starship et les couleurs des commandes zsh-env-* :

```
themes/
├── tokyo-night-pro/     # Directory theme
│   ├── prompt.toml      # Config Starship
│   └── palette.zsh      # Couleurs true color pour _ui_*
├── minimal.toml         # Flat theme (couleurs par defaut)
└── ...
```

```bash
zsh-env-theme list              # Voir les themes disponibles
zsh-env-theme tokyo-night-pro   # Appliquer (prompt + palette)
```

## Contribuer

Voir [Contributing](https://github.com/Dr0drigues/zsh_env/wiki/Contributing) pour les conventions.

## Desinstallation

```bash
~/.zsh_env/uninstall.sh
```
