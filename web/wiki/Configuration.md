# Configuration

La configuration se fait via `~/.zanvil/config.zsh`.

## Fichier de configuration

```bash
# Creer depuis le template
cp ~/.zanvil/examples/config.zsh.example ~/.zanvil/config.zsh
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
| `core/commands/commands.zsh` | Commandes zanvil-* |
| `core/commands/admin.zsh` | Administration |
| `core/commands/theme.zsh` | Gestion des themes |
| `core/commands/setup.zsh` | Setup initial |
| `core/lifecycle/` | Mise a jour, migration, sync |

## Modules

Les modules sont maintenant geres via `zanvil-modules` :

```bash
# Lister les modules
zanvil-modules list

# Activer un module
zanvil-modules enable gitlab

# Desactiver un module
zanvil-modules disable docker
```

Chaque module est dans `modules/<name>/` avec un `init.zsh` et optionnellement un `completions.zsh`.

Configuration manuelle dans `config.zsh` :

```zsh
# Activer/desactiver les modules
ZANVIL_MODULE_GITLAB=true    # Scripts GitLab
ZANVIL_MODULE_DOCKER=true    # Utilitaires Docker
ZANVIL_MODULE_MISE=true      # Versions Node, Java, Maven (remplace NVM)
ZANVIL_MODULE_NUSHELL=false  # Integration Nushell
ZANVIL_MODULE_KUBE=true      # Gestion Kubernetes
```

## Variables dynamiques (env.d/)

Le dossier `env.d/` permet de definir des variables d'environnement par fichier. Chaque fichier `*.zsh` est charge automatiquement au demarrage.

```bash
# Creer une variable
echo 'export MY_VAR=value' > ~/.zanvil/env.d/my-project.zsh
```

### Chiffrement sops

Les fichiers `env.d/*.sops.zsh` sont dechiffres par sops au chargement :

```bash
# Creer un fichier chiffre
sops ~/.zanvil/env.d/secrets.sops.zsh

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

## Versions de runtimes (mise)

`mise` remplace NVM et SDKMAN : il gere Node, Java et Maven, et lit `.nvmrc`, `.sdkmanrc` et
`.tool-versions`. `ZANVIL_MODULE_NVM` et `ZANVIL_NVM_LAZY` sont deprecies : `rc.zsh` reporte
`ZANVIL_MODULE_NVM` sur `ZANVIL_MODULE_MISE`.

```zsh
ZANVIL_MODULE_MISE=true
```

## Auto-update

```zsh
ZANVIL_UPDATE_MODE="auto"    # "auto" (defaut), "prompt" ou "off"
ZANVIL_UPDATE_FREQUENCY=1    # Verifier tous les X jours
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
# Dossier de travail
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
| `env.d/*.zsh` | Variables dynamiques | Non (sauf chiffrees) |
| `profiles/` | Profils d'environnement | Non |
| `~/.secrets` | Tokens et secrets | Non |
| `~/.gitlab_secrets` | Config GitLab | Non |
| `~/.kube/.context_aliases` | Alias de contextes Kube | Non |
