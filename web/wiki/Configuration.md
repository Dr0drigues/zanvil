# Configuration

La configuration se fait via `~/.zanvil/config.zsh`.

## Fichier de configuration

```bash
# Creer depuis le template
cp ~/.zanvil/config.zsh.example ~/.zanvil/config.zsh
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
| `core/commands.zsh` | Commandes zanvil-* |
| `core/admin.zsh` | Administration |
| `core/theme.zsh` | Gestion des themes |
| `core/setup.zsh` | Setup initial |

## Modules

Les modules sont maintenant geres via `zanvil-modules` :

```bash
# Lister les modules
zanvil-modules list

# Activer un module
zanvil-modules enable gitlab

# Desactiver un module
zanvil-modules disable nvm
```

Chaque module est dans `modules/<name>/` avec un `init.zsh` et optionnellement un `completions.zsh`.

Configuration manuelle dans `config.zsh` :

```zsh
# Activer/desactiver les modules
ZANVIL_MODULE_GITLAB=true    # Scripts GitLab
ZANVIL_MODULE_DOCKER=true    # Utilitaires Docker
ZANVIL_MODULE_NVM=true       # Auto-switch Node
ZANVIL_MODULE_NUSHELL=false  # Integration Nushell
ZANVIL_MODULE_KUBE=true      # Gestion Kubernetes
```

## Variables dynamiques (env.d/)

Le dossier `env.d/` permet de definir des variables d'environnement par fichier. Chaque fichier `.env` est charge automatiquement au demarrage.

```bash
# Creer une variable
echo 'MY_VAR=value' > ~/.zanvil/env.d/my-project.env
```

### Chiffrement sops

Les fichiers `env.d/` supportent le chiffrement sops :

```bash
# Creer un fichier chiffre
sops ~/.zanvil/env.d/secrets.env

# Le dechiffrement est automatique au chargement
```

## Chargement local (.zanvil.local)

Le fichier `.zanvil.local` dans un repertoire est auto-charge lorsque vous y entrez (similaire a direnv). Un mecanisme de confiance base sur un hash empeche l'execution de fichiers non approuves.

```bash
# Creer un fichier local
echo 'export NODE_ENV=development' > /path/to/project/.zanvil.local

# La premiere fois, zanvil demandera d'approuver le fichier
# Apres approbation, il sera charge automatiquement
```

Voir [[Security]] pour les details du mecanisme de confiance.

## Profils d'environnement

Les profils permettent de basculer entre differents jeux de configuration :

```bash
# Changer de profil
zanvil-switch work
zanvil-switch personal

# Reinitialiser la configuration
zanvil-config-reset
```

Les profils sont stockes dans `~/.zanvil/profiles/`.

## Themes

```zsh
# Definir le theme (via commande)
zanvil-theme minimal
```

Le theme actif est enregistre dans `~/.zanvil/.current_theme`.

Voir [[Themes]] pour la liste des themes et le systeme de theming unifie.

## NVM (Node Version Manager)

```zsh
# Lazy loading (recommande) - charge NVM au premier appel node/npm
ZANVIL_NVM_LAZY=true

# Chargement immediat (ajoute ~200ms au demarrage)
ZANVIL_NVM_LAZY=false
```

## Auto-update

```zsh
ZANVIL_AUTO_UPDATE=true      # Activer
ZANVIL_UPDATE_FREQUENCY=7    # Verifier tous les X jours
ZANVIL_UPDATE_MODE="prompt"  # "prompt" ou "auto"
```

## Plugins

```zsh
# Organisation par defaut
ZANVIL_PLUGINS_ORG=zsh-users

# Plugins a installer
ZANVIL_PLUGINS=(
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
SCRIPTS_DIR="$ZANVIL_DIR/scripts"
```

## Secrets

Creez `~/.secrets` pour vos tokens (ignore par git) :

```zsh
export GITLAB_TOKEN="glpat-xxxx"
export GITHUB_TOKEN="ghp_xxxx"
export AWS_PROFILE="default"
```

## Aliases locaux

Creez `~/.zanvil/aliases.local.zsh` pour vos alias personnels :

```zsh
alias myproj="cd ~/Projects/mon-projet && code ."
alias vpn="sudo openvpn /etc/openvpn/client.conf"
```

## Sauvegarde et restauration

```bash
# Sauvegarder la config
zanvil-backup

# Restaurer
zanvil-restore
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
