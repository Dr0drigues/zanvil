---
title: Configuration
description: Configurer zanvil (zanvil) via config.zsh et les modules
---

La configuration se fait via `~/.zanvil/config.zsh`.

## Fichier de configuration

```bash
# Créer depuis le template
cp ~/.zanvil/examples/config.zsh.example ~/.zanvil/config.zsh
```

## Architecture v2

En v2, la configuration est répartie dans `core/` :

| Fichier | Rôle |
|---------|------|
| `core/variables.zsh` | Variables d'environnement |
| `core/aliases.zsh` | Alias globaux |
| `core/hooks.zsh` | Hooks shell (chpwd, precmd, etc.) |
| `core/loader.zsh` | Chargement des modules |
| `core/ui.zsh` | Système UI |
| `core/commands.zsh` | Commandes zanvil-* |
| `core/admin.zsh` | Administration |
| `core/theme.zsh` | Gestion des thèmes |
| `core/setup.zsh` | Setup initial |

## Modules

Les modules sont maintenant gérés via `zanvil-modules` :

```bash
# Lister les modules
zanvil-modules list

# Activer un module
zanvil-modules enable gitlab

# Désactiver un module
zanvil-modules disable nvm
```

Chaque module est dans `modules/<name>/` avec un `init.zsh` et optionnellement un `completions.zsh`.

Configuration manuelle dans `config.zsh` :

```zsh
# Activer/désactiver les modules
ZANVIL_MODULE_GITLAB=true    # Scripts GitLab
ZANVIL_MODULE_DOCKER=true    # Utilitaires Docker
ZANVIL_MODULE_NVM=true       # Auto-switch Node
ZANVIL_MODULE_NUSHELL=false  # Intégration Nushell
ZANVIL_MODULE_KUBE=true      # Gestion Kubernetes
```

## Variables dynamiques (env.d/)

Le dossier `env.d/` permet de définir des variables d'environnement par fichier. Chaque fichier `.env` est chargé automatiquement au démarrage.

```bash
# Créer une variable
echo 'MY_VAR=value' > ~/.zanvil/env.d/my-project.env
```

### Chiffrement sops

Les fichiers `env.d/` supportent le chiffrement sops :

```bash
# Créer un fichier chiffré
sops ~/.zanvil/env.d/secrets.env

# Le déchiffrement est automatique au chargement
```

## Chargement local (.zanvil.local)

Le fichier `.zanvil.local` dans un répertoire est auto-chargé lorsque vous y entrez (similaire à direnv). Un mécanisme de confiance basé sur un hash empêche l'exécution de fichiers non approuvés.

```bash
# Créer un fichier local
echo 'export NODE_ENV=development' > /path/to/project/.zanvil.local

# La première fois, zanvil demandera d'approuver le fichier
# Après approbation, il sera chargé automatiquement
```

## Profils d'environnement

Les profils permettent de basculer entre différents jeux de configuration :

```bash
# Changer de profil
zanvil-switch work
zanvil-switch personal

# Réinitialiser la configuration
zanvil-config-reset
```

Les profils sont stockés dans `~/.zanvil/profiles/`.

## Thèmes

```zsh
# Définir le thème (via commande)
zanvil-theme minimal
```

Le thème actif est enregistré dans `~/.zanvil/.current_theme`.

## NVM (Node Version Manager)

```zsh
# Lazy loading (recommandé) — charge NVM au premier appel node/npm
ZANVIL_NVM_LAZY=true

# Chargement immédiat (ajoute ~200ms au démarrage)
ZANVIL_NVM_LAZY=false
```

## Auto-update

```zsh
ZANVIL_AUTO_UPDATE=true      # Activer
ZANVIL_UPDATE_FREQUENCY=7    # Vérifier tous les X jours
ZANVIL_UPDATE_MODE="prompt"  # "prompt" ou "auto"
```

## Plugins

```zsh
# Organisation par défaut
ZANVIL_PLUGINS_ORG=zsh-users

# Plugins à installer
ZANVIL_PLUGINS=(
    zsh-autosuggestions
    zsh-syntax-highlighting
    Aloxaf/fzf-tab
)
```

## Variables d'environnement

```zsh
# Dossier de travail (utilisé par proj --scan)
WORK_DIR="$HOME/work"

# Dossier des scripts
SCRIPTS_DIR="$ZANVIL_DIR/scripts"
```

## Secrets

Créez `~/.secrets` pour vos tokens (ignoré par git) :

```zsh
export GITLAB_TOKEN="glpat-xxxx"
export GITHUB_TOKEN="ghp_xxxx"
export AWS_PROFILE="default"
```

## Aliases locaux

Créez `~/.zanvil/aliases.local.zsh` pour vos alias personnels :

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

| Fichier | Description | Versionné |
|---------|-------------|-----------|
| `config.zsh` | Configuration personnelle | Non |
| `aliases.local.zsh` | Aliases personnels | Non |
| `.current_theme` | Thème actif | Non |
| `env.d/*.env` | Variables dynamiques | Non (sauf chiffrées) |
| `profiles/` | Profils d'environnement | Non |
| `~/.secrets` | Tokens et secrets | Non |
| `~/.gitlab_secrets` | Config GitLab | Non |
| `~/.kube/.context_aliases` | Alias de contextes Kube | Non |
