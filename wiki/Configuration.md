# Configuration

La configuration se fait via `~/.zsh_env/config.zsh`.

## Fichier de configuration

```bash
# Créer depuis le template
cp ~/.zsh_env/config.zsh.example ~/.zsh_env/config.zsh
```

## Modules

```zsh
# Activer/désactiver les modules
ZSH_ENV_MODULE_GITLAB=true    # Scripts GitLab
ZSH_ENV_MODULE_DOCKER=true    # Utilitaires Docker
ZSH_ENV_MODULE_NVM=true       # Auto-switch Node
ZSH_ENV_MODULE_NUSHELL=false  # Intégration Nushell
ZSH_ENV_MODULE_KUBE=true      # Gestion Kubernetes
```

## NVM (Node Version Manager)

```zsh
# Lazy loading (recommandé) - charge NVM au premier appel node/npm
ZSH_ENV_NVM_LAZY=true

# Chargement immédiat (ajoute ~200ms au démarrage)
ZSH_ENV_NVM_LAZY=false
```

## Auto-update

```zsh
ZSH_ENV_AUTO_UPDATE=true      # Activer
ZSH_ENV_UPDATE_FREQUENCY=7    # Vérifier tous les X jours
ZSH_ENV_UPDATE_MODE="prompt"  # "prompt" ou "auto"
```

## Plugins

```zsh
# Organisation par défaut
ZSH_ENV_PLUGINS_ORG=zsh-users

# Plugins à installer
ZSH_ENV_PLUGINS=(
    zsh-autosuggestions
    zsh-syntax-highlighting
    Aloxaf/fzf-tab
)
```

Voir [[Plugins]] pour plus de détails.

## Thèmes Starship

```zsh
# Définir le thème (dans config.zsh ou via commande)
STARSHIP_THEME="minimal"
```

Voir [[Themes]] pour la liste des thèmes.

## Variables d'environnement

```zsh
# Dossier de travail (utilisé par proj --scan)
WORK_DIR="$HOME/work"

# Dossier des scripts
SCRIPTS_DIR="$ZSH_ENV_DIR/scripts"
```

## Secrets

Créez `~/.secrets` pour vos tokens (ignoré par git) :

```zsh
export GITLAB_TOKEN="glpat-xxxx"
export GITHUB_TOKEN="ghp_xxxx"
export AWS_PROFILE="default"
```

## Aliases locaux

Créez `~/.zsh_env/aliases.local.zsh` pour vos alias personnels :

```zsh
alias myproj="cd ~/Projects/mon-projet && code ."
alias vpn="sudo openvpn /etc/openvpn/client.conf"
```

## Structure des fichiers

| Fichier | Description | Versionné |
|---------|-------------|-----------|
| `config.zsh` | Configuration personnelle | Non |
| `aliases.local.zsh` | Aliases personnels | Non |
| `~/.secrets` | Tokens et secrets | Non |
| `~/.gitlab_secrets` | Config GitLab | Non |
