<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="web/assets/branding/logo-mark-light.svg">
    <img src="web/assets/branding/logo-mark.svg" alt="zanvil" width="128" height="128">
  </picture>
</p>

<h1 align="center">zanvil</h1>
<p align="center"><em>craft your shell</em></p>

<p align="center">
Configuration Zsh modulaire et orientee productivite pour developpeurs (macOS &amp; Linux).<br>
Architecture hybride <strong>Rust CLI + modules zsh</strong> pour des performances optimales.
</p>

<p align="center"><strong><a href="https://dr0drigues.github.io/zanvil/">Site de documentation</a></strong> · <a href="https://github.com/Dr0drigues/zanvil/wiki">Wiki</a></p>

## Installation

```bash
git clone git@github.com:Dr0drigues/zanvil.git ~/.zanvil
cd ~/.zanvil && ./install.sh
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
| **.zanvil.local** | Auto-chargement par projet (style direnv) |

## Commandes essentielles

```bash
ss                         # Recharger la config
zanvil-help               # Liste toutes les commandes
zanvil-doctor             # Diagnostic systeme
zanvil-audit              # Audit de securite
zanvil-modules list       # Lister/activer/desactiver les modules
zanvil-theme list         # Gestion des themes (prompt + palette)
zanvil-backup             # Sauvegarde des configs

kube_switch blg-dev        # Switch de cluster (avec aliases)
kube_ns                    # Switch de namespace
k blg-dev                  # k9s sur un cluster
kube_status                # Contexte + namespace + pods

zanvil-gitlab-status      # Statut du PAT GitLab
zanvil-gitlab-browse -m   # Ouvrir les MRs dans le navigateur
gpr                        # Raccourci creation MR

proj mon-projet            # Charger un projet
zanvil-switch env         # Switcher d'environnement
ssh_select                 # Selectionner un host SSH
tm                         # Gerer les sessions tmux
hooks_install              # Installer les hooks Git
```

## Architecture

```
~/.zanvil/
├── rc.zsh              # Point d'entree
├── config.zsh          # Configuration modules (gitignored)
├── core/               # Systeme central
│   ├── ui.zsh          # Systeme UI + palette loader
│   ├── loader.zsh      # Module loader automatique
│   ├── commands.zsh    # zanvil-list, doctor, status, help
│   ├── admin.zsh       # modules, backup, restore, switch
│   ├── theme.zsh       # Themes Starship + Ghostty
│   └── hooks.zsh       # Init outils + .zanvil.local
├── modules/            # Features modulaires
│   ├── git/            # bulk, hooks, change-author
│   ├── gitlab/         # clone, pipelines, PAT, browse
│   ├── docker/         # dex, dstop
│   ├── ssh/            # select, add, remove, test
│   ├── tmux/           # sessions (lazy loaded)
│   ├── ai/             # context, tokens (lazy loaded)
│   └── ...             # kube, project, security, utils, tools (guard: ZANVIL_MODULE_*)
├── config/             # Configs outils versionnees (atuin, delta, ghostty, k9s, lazygit)
├── secrets/            # Fichiers sensibles (gitignored)
│   ├── secrets/kube/   # Kubeconfigs + .context_aliases
│   └── secrets/work/   # Certificats et settings dechiffres
├── examples/           # Templates de config (config.zsh, aliases.local.zsh)
├── themes/             # Flat .toml ou directory (prompt.toml + palette.zsh)
├── env.d/              # Variables dynamiques (*.zsh, *.sops.zsh)
├── cli/                # CLI Rust companion (optionnel)
└── scripts/            # Scripts autonomes
```

## CLI Rust (optionnel)

Le binaire `zanvil` (684 Ko) accelere les commandes lourdes. Les fonctions zsh delegent automatiquement au CLI quand il est disponible.

```bash
zanvil doctor          # Diagnostic natif
zanvil audit           # Scan securite
zanvil theme list      # Gestion themes
zanvil context         # Contexte kube (pour Starship)
zanvil modules list    # Gestion modules
```

Build manuel : `cd cli && cargo build --release && cp target/release/zanvil ~/.local/bin/`

## Systeme de themes

Les themes unifies controlent a la fois le prompt Starship et les couleurs des commandes zanvil-* :

```
themes/
├── tokyo-night-pro/     # Directory theme
│   ├── prompt.toml      # Config Starship
│   └── palette.zsh      # Couleurs true color pour _ui_*
├── minimal.toml         # Flat theme (couleurs par defaut)
└── ...
```

```bash
zanvil-theme list              # Voir les themes disponibles
zanvil-theme tokyo-night-pro   # Appliquer (prompt + palette)
```

## Contribuer

Voir [Contributing](https://github.com/Dr0drigues/zanvil/wiki/Contributing) pour les conventions.

## Desinstallation

```bash
~/.zanvil/uninstall.sh
```
