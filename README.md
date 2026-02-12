# ZSH Environment & Productivity Suite

Configuration Zsh modulaire et orientée productivité pour développeurs (macOS & Linux).

**[Documentation complète sur le Wiki](https://github.com/Dr0drigues/zsh_env/wiki)**

## Installation

```bash
git clone git@github.com:Dr0drigues/zsh_env.git ~/.zsh_env
cd ~/.zsh_env && ./install.sh
```

## Fonctionnalités

| Module | Description |
|--------|-------------|
| **Navigation** | Jump intelligent avec `zoxide`, auto-cd |
| **Project Switcher** | Changement de contexte complet (kube, node, tmux) |
| **Kubernetes** | Multi-config avec support Azure/AWS/GCP |
| **SSH Manager** | Gestion simplifiée des connexions SSH |
| **Tmux Manager** | Gestion des sessions tmux |
| **Git Hooks** | Hooks standards (lint, conventional commits) |
| **Security** | Audit des permissions et secrets |
| **Plugins** | Gestionnaire de plugins Zsh intégré |
| **Themes** | Thèmes Starship personnalisables |

## Commandes essentielles

```bash
ss                  # Recharger la config
zsh-env-doctor      # Diagnostic
zsh-env-profile     # Profiler le démarrage
zsh-env-audit       # Audit de sécurité

proj mon-projet     # Charger un projet
kube_select         # Sélectionner configs K8s
ssh_select          # Sélectionner un host SSH
tm                  # Gérer les sessions tmux
hooks_install       # Installer les hooks Git
```

## Documentation

- [Installation](https://github.com/Dr0drigues/zsh_env/wiki/Installation)
- [Configuration](https://github.com/Dr0drigues/zsh_env/wiki/Configuration)
- [Référence des commandes](https://github.com/Dr0drigues/zsh_env/wiki/Commandes)
- [Troubleshooting](https://github.com/Dr0drigues/zsh_env/wiki/Troubleshooting)

## Structure

```
~/.zsh_env/
├── rc.zsh              # Point d'entrée
├── config.zsh          # Configuration personnelle
├── functions/          # Modules fonctionnels
│   ├── ui.zsh          # Système UI (couleurs, formatage)
│   ├── zsh_env_commands.zsh  # Commandes zsh-env-*
│   ├── security_audit.zsh    # Audit de sécurité
│   └── ...             # Autres modules (kube, ssh, tmux, proj...)
├── themes/             # Thèmes Starship
└── scripts/            # Scripts autonomes
```

## Système UI

Toutes les commandes utilisent un style visuel cohérent via `functions/ui.zsh` :

```
╭──────────────────────────────────────────╮
│  ZSH_ENV Doctor                  v1.2.0  │
╰──────────────────────────────────────────╯

Config         rc.zsh ✓  aliases ✓  variables ✓  functions ✓
Requis         git ✓  curl ✓  jq ✓
Recommandés    starship ✓  zoxide ✓  fzf ✓  eza ✓  bat ✓

────────────────────────────────────────────
✓ Tout est OK
```

## Contribuer

Voir [Contributing](https://github.com/Dr0drigues/zsh_env/wiki/Contributing) pour les conventions.

## Désinstallation

```bash
~/.zsh_env/uninstall.sh
```
