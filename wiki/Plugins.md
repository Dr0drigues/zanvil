# Gestionnaire de Plugins

Gestionnaire de plugins Zsh léger sans dépendance externe.

## Commandes

| Commande | Description |
|----------|-------------|
| `zsh-plugin-list` | Liste les plugins installés |
| `zsh-plugin-install <repo>` | Installe un plugin |
| `zsh-plugin-remove <nom>` | Supprime un plugin |
| `zsh-plugin-update` | Met à jour tous les plugins |

## Configuration

Dans `~/.zsh_env/config.zsh` :

```zsh
# Organisation par défaut (optionnel)
ZSH_ENV_PLUGINS_ORG=zsh-users

# Plugins à installer
ZSH_ENV_PLUGINS=(
    zsh-autosuggestions        # -> zsh-users/zsh-autosuggestions
    zsh-syntax-highlighting    # -> zsh-users/zsh-syntax-highlighting
    Aloxaf/fzf-tab             # org explicite
    https://github.com/custom/plugin.git  # URL complète
)
```

## Formats supportés

```zsh
ZSH_ENV_PLUGINS=(
    nom-plugin                              # Utilise l'org par défaut
    owner/repo                              # GitHub owner/repo
    https://github.com/owner/repo.git       # URL complète
    https://gitlab.com/owner/repo.git       # GitLab, etc.
)
```

## Installation

Les plugins sont automatiquement installés au premier chargement du shell.

Installation manuelle :

```bash
zsh-plugin-install zsh-users/zsh-autosuggestions
```

## Mise à jour

```bash
# Met à jour tous les plugins
zsh-plugin-update
```

## Suppression

```bash
zsh-plugin-remove zsh-autosuggestions
```

## Plugins recommandés

| Plugin | Description |
|--------|-------------|
| `zsh-users/zsh-autosuggestions` | Suggestions basées sur l'historique |
| `zsh-users/zsh-syntax-highlighting` | Coloration syntaxique en temps réel |
| `zsh-users/zsh-completions` | Complétions additionnelles |
| `Aloxaf/fzf-tab` | Complétions interactives avec fzf |
| `hlissner/zsh-autopair` | Auto-fermeture des parenthèses/quotes |
| `agkozak/zsh-z` | Alternative à zoxide en pur zsh |

## Emplacement

Les plugins sont installés dans `~/.zsh_env/plugins/` (ignoré par git).
