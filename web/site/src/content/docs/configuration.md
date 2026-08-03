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

## Architecture

La configuration est répartie dans `core/` :

| Fichier | Rôle |
|---------|------|
| `core/ui.zsh` | Système UI — chargé en premier, fournit les `_ui_*` et la palette du thème |
| `core/variables.zsh` | Variables d'environnement |
| `core/aliases.zsh` | Alias globaux |
| `core/loader.zsh` | Découverte et chargement des modules |
| `core/hooks.zsh` | Init des outils (starship, fzf, mise, zoxide, direnv, `.zanvil.local`) |
| `core/completions.zsh` | Complétions des commandes core |
| `core/commands/` | Commandes `zanvil-*` : `commands.zsh`, `admin.zsh`, `theme.zsh`, `setup.zsh`, `check_env_deps.zsh` |
| `core/lifecycle/` | Cycle de vie : `auto_update.zsh`, `migrate.zsh`, `sync.zsh` |

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
# Modules metier
ZANVIL_MODULE_GITLAB=true     # Alias GitLab, clone de groupes, statut PAT
ZANVIL_MODULE_KUBE=true       # Gestion kubeconfig (kube_select, Azure/AWS/GCP)
ZANVIL_MODULE_DOCKER=true     # Utilitaires Docker (dex, dstop)
ZANVIL_MODULE_SECURITY=false  # Audit de securite et scan de secrets
ZANVIL_MODULE_AI=false        # Estimation de tokens LLM et contexte repo
ZANVIL_MODULE_ZPROJECT=false  # Contexte projet par shell, via le CLI Rust
ZANVIL_MODULE_TOOLS=false     # mise hooks, test runner, profiler zsh

# Outils tiers — chacun deploie sa configuration avec <outil>_setup
ZANVIL_MODULE_DELTA=true      # Pager syntaxique pour git diff
ZANVIL_MODULE_LAZYGIT=true    # TUI Git ergonomique (alias lg)
ZANVIL_MODULE_ATUIN=true      # Historique shell enrichi SQLite (fuzzy search)
ZANVIL_MODULE_POSTING=true    # Client HTTP TUI (alias po)

# Integrations
ZANVIL_MODULE_MISE=true       # Gestionnaire de versions (Node, Java, Maven)
ZANVIL_MODULE_NUSHELL=true    # Integration Nushell
```

Un module dont le guard est absent de `config.zsh` reste inactif. Les modules `git`, `ssh`, `utils`,
`project` et `work` n'ont pas de guard : ils sont toujours chargés.

:::note[Migration depuis NVM]
`ZANVIL_MODULE_NVM` est déprécié au profit de `ZANVIL_MODULE_MISE`, qui gère Node mais aussi Java et
Maven. `rc.zsh` reporte automatiquement l'ancienne valeur sur la nouvelle et retire `ZANVIL_NVM_LAZY`,
qui n'a plus d'effet — rien à changer dans un `config.zsh` existant.
:::

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

## Versions de runtimes (mise)

`mise` remplace NVM et couvre Node, Java et Maven. Il est activé par défaut et branché dans
`core/hooks.zsh`, qui appelle `mise activate zsh` au démarrage si le binaire est présent.

```zsh
ZANVIL_MODULE_MISE=true
```

Les hooks du module `tools` (`modules/tools/mise_hooks.zsh`) ajoutent la détection du fichier
`.mise.toml` d'un projet au `cd`.

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
