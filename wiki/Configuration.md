# Configuration

La configuration se fait via `~/.zsh_env/config.zsh`.

## Fichier de configuration

```bash
# Creer depuis le template
cp ~/.zsh_env/config.zsh.example ~/.zsh_env/config.zsh
```

## Architecture v2

En v2, la configuration est repartie dans `core/` :

| Fichier | Role |
|---------|------|
| `core/variables.zsh` | Variables d'environnement |
| `core/aliases.zsh` | Alias globaux |
| `core/hooks.zsh` | Hooks shell (chpwd, precmd, etc.) |
| `core/loader.zsh` | Chargement des modules |
| `core/ui.zsh` | Systeme UI |
| `core/commands.zsh` | Commandes zsh-env-* |
| `core/admin.zsh` | Administration |
| `core/theme.zsh` | Gestion des themes |
| `core/setup.zsh` | Setup initial |

## Modules

Les modules sont maintenant geres via `zsh-env-modules` :

```bash
# Lister les modules
zsh-env-modules list

# Activer un module
zsh-env-modules enable gitlab

# Desactiver un module
zsh-env-modules disable nvm
```

Chaque module est dans `modules/<name>/` avec un `init.zsh` et optionnellement un `completions.zsh`.

Configuration manuelle dans `config.zsh` :

```zsh
# Activer/desactiver les modules
ZSH_ENV_MODULE_GITLAB=true    # Scripts GitLab
ZSH_ENV_MODULE_DOCKER=true    # Utilitaires Docker
ZSH_ENV_MODULE_NVM=true       # Auto-switch Node
ZSH_ENV_MODULE_NUSHELL=false  # Integration Nushell
ZSH_ENV_MODULE_KUBE=true      # Gestion Kubernetes
```

## Variables dynamiques (env.d/)

Le dossier `env.d/` permet de definir des variables d'environnement par fichier. Chaque fichier `.env` est charge automatiquement au demarrage.

```bash
# Creer une variable
echo 'MY_VAR=value' > ~/.zsh_env/env.d/my-project.env
```

### Chiffrement sops

Les fichiers `env.d/` supportent le chiffrement sops :

```bash
# Creer un fichier chiffre
sops ~/.zsh_env/env.d/secrets.env

# Le dechiffrement est automatique au chargement
```

## Chargement local (.zsh-env.local)

Le fichier `.zsh-env.local` dans un repertoire est auto-charge lorsque vous y entrez (similaire a direnv). Un mecanisme de confiance base sur un hash empeche l'execution de fichiers non approuves.

```bash
# Creer un fichier local
echo 'export NODE_ENV=development' > /path/to/project/.zsh-env.local

# La premiere fois, zsh-env demandera d'approuver le fichier
# Apres approbation, il sera charge automatiquement
```

Voir [[Security]] pour les details du mecanisme de confiance.

## Profils d'environnement

Les profils permettent de basculer entre differents jeux de configuration :

```bash
# Changer de profil
zsh-env-switch work
zsh-env-switch personal

# Reinitialiser la configuration
zsh-env-config-reset
```

Les profils sont stockes dans `~/.zsh_env/profiles/`.

## Themes

```zsh
# Definir le theme (via commande)
zsh-env-theme minimal
```

Le theme actif est enregistre dans `~/.zsh_env/.current_theme`.

Voir [[Themes]] pour la liste des themes et le systeme de theming unifie.

## NVM (Node Version Manager)

```zsh
# Lazy loading (recommande) - charge NVM au premier appel node/npm
ZSH_ENV_NVM_LAZY=true

# Chargement immediat (ajoute ~200ms au demarrage)
ZSH_ENV_NVM_LAZY=false
```

## Auto-update

```zsh
ZSH_ENV_AUTO_UPDATE=true      # Activer
ZSH_ENV_UPDATE_FREQUENCY=7    # Verifier tous les X jours
ZSH_ENV_UPDATE_MODE="prompt"  # "prompt" ou "auto"
```

## Plugins

```zsh
# Organisation par defaut
ZSH_ENV_PLUGINS_ORG=zsh-users

# Plugins a installer
ZSH_ENV_PLUGINS=(
    zsh-autosuggestions
    zsh-syntax-highlighting
    Aloxaf/fzf-tab
)
```

Voir [[Plugins]] pour plus de details.

## Variables d'environnement

```zsh
# Dossier de travail (utilise par proj --scan)
WORK_DIR="$HOME/work"

# Dossier des scripts
SCRIPTS_DIR="$ZSH_ENV_DIR/scripts"
```

## Secrets

Creez `~/.secrets` pour vos tokens (ignore par git) :

```zsh
export GITLAB_TOKEN="glpat-xxxx"
export GITHUB_TOKEN="ghp_xxxx"
export AWS_PROFILE="default"
```

## Aliases locaux

Creez `~/.zsh_env/aliases.local.zsh` pour vos alias personnels :

```zsh
alias myproj="cd ~/Projects/mon-projet && code ."
alias vpn="sudo openvpn /etc/openvpn/client.conf"
```

## Sauvegarde et restauration

```bash
# Sauvegarder la config
zsh-env-backup

# Restaurer
zsh-env-restore
```

## Structure des fichiers

| Fichier | Description | Versionne |
|---------|-------------|-----------|
| `config.zsh` | Configuration personnelle | Non |
| `aliases.local.zsh` | Aliases personnels | Non |
| `.current_theme` | Theme actif | Non |
| `env.d/*.env` | Variables dynamiques | Non (sauf chiffrees) |
| `profiles/` | Profils d'environnement | Non |
| `~/.secrets` | Tokens et secrets | Non |
| `~/.gitlab_secrets` | Config GitLab | Non |
| `~/.kube/.context_aliases` | Alias de contextes Kube | Non |
