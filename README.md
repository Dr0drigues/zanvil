# ZSH Environment & Productivity Suite

Une configuration Zsh robuste, modulaire et orientée productivité pour développeurs (macOS & Linux).

Ce projet automatise l'installation des outils modernes (`zoxide`, `starship`, `eza`, `nvm`, `sdkman`) et fournit des fonctions avancées pour Git, GitLab et Docker.

---

## Installation Rapide

**1. Cloner le repo** (idéalement dans `~/.zsh_env`) :

```bash
git clone git@github.com:Dr0drigues/zsh_env.git ~/.zsh_env
```

**2. Lancer le script d'installation** :

```bash
cd ~/.zsh_env
./install.sh
```

L'installation est **interactive** et vous permet de choisir les modules à activer.

Pour une installation non-interactive avec tous les modules activés :

```bash
./install.sh --default
```

> Ce script installe les dépendances (via brew/apt/dnf), configure NVM/SDKMAN et modifie votre `.zshrc` automatiquement.

---

## Fonctionnalités Clés

### Navigation Intelligente

- **Auto-Jump (`z`)** : Plus besoin de `cd`. Tapez `z front` pour aller dans `.../front-toto`. Le système "apprend" vos dossiers fréquents (basé sur `zoxide`).

- **Auto-CD** : Tapez juste le chemin d'un dossier (`../utils`) pour y entrer.

- **mkcd** : `mkcd mon_dossier` crée le dossier et rentre dedans immédiatement.

### Gestion de Projets & Git

**Clone Intelligent (`gclone`)** :

```bash
gclone git@github.com:org/projet.git
```

- Clone le projet
- Entre dedans automatiquement
- L'ajoute à l'index de navigation (`z`)

**GitLab Mass Clone** : Des alias comme `gc-frontco-ptf` pour cloner/mettre à jour des groupes entiers de projets (basé sur `scripts/clone-projects.sh`).

### Node.js & NVM

- **Auto-Switch** : En entrant dans un dossier contenant un `.nvmrc`, l'environnement change automatiquement de version Node.

- **Installation Auto** : Si la version requise n'est pas installée, il propose de l'installer.

- **Lazy Loading** : Par défaut, NVM est chargé uniquement au premier appel de `node`/`npm` pour accélérer le démarrage du shell (~200ms gagnées).

```zsh
# Désactiver le lazy loading dans config.zsh
ZSH_ENV_NVM_LAZY=false
```

### Docker & Système

- **`dex`** : Liste les conteneurs actifs et permet d'y entrer via une interface interactive (FZF).

- **`fkill`** : Tuer un processus via une recherche interactive.

- **`trash`** : Remplace `rm` pour envoyer dans la corbeille système au lieu de supprimer définitivement.

### GitLab Utilities

**Trigger Jobs en masse** (`trigger-jobs.sh`) :

```bash
# Par ID de projet
trigger-jobs.sh -P 12345 -j "deploy-staging"

# Par chemin de projet
trigger-jobs.sh -p "group/subgroup/project" -j "deploy"

# Par groupe (tous les projets du groupe)
trigger-jobs.sh -g 789 -j "build"

# Mode forcé (sans confirmation)
trigger-jobs.sh -P 12345 -j "deploy" --force
```

---

## Configuration Modulaire

### Modules disponibles

L'installation vous permet de choisir les modules à activer :

| Module | Description |
|--------|-------------|
| **GitLab** | Scripts et fonctions GitLab (trigger-jobs, clone-projects) |
| **Docker** | Utilitaires Docker (dex, etc.) |
| **NVM** | Auto-switch Node.js via .nvmrc |
| **Nushell** | Intégration Nushell |

### Fichier de configuration

Modifiez `~/.zsh_env/config.zsh` pour activer/désactiver les modules :

```zsh
ZSH_ENV_MODULE_GITLAB=true
ZSH_ENV_MODULE_DOCKER=true
ZSH_ENV_MODULE_NVM=true
ZSH_ENV_MODULE_NUSHELL=false

# NVM lazy loading (true = charge au premier appel node/npm)
ZSH_ENV_NVM_LAZY=true
```

---

## Thèmes Starship

Plusieurs thèmes de prompt sont inclus :

| Thème | Description |
|-------|-------------|
| `minimal` | Prompt minimaliste et rapide |
| `default` | Configuration équilibrée |
| `powerline` | Style powerline avec séparateurs |
| `plain` | Sans icônes (compatible tous terminaux) |

```bash
# Lister les thèmes
zsh-env-theme list

# Appliquer un thème
zsh-env-theme minimal
```

Vous pouvez aussi créer vos propres thèmes dans `~/.zsh_env/themes/`.

---

## Auto-Update

Le système peut vérifier automatiquement les mises à jour.

### Configuration

Dans `~/.zsh_env/config.zsh` :

```zsh
ZSH_ENV_AUTO_UPDATE=true      # Activer/désactiver
ZSH_ENV_UPDATE_FREQUENCY=7    # Tous les X jours (0 = chaque démarrage)
ZSH_ENV_UPDATE_MODE="prompt"  # "prompt" ou "auto"
```

---

## Commandes ZSH-ENV

| Commande | Description |
|----------|-------------|
| `zsh-env-list` | Liste les outils installés avec leurs versions |
| `zsh-env-completions` | Charge les auto-completions |
| `zsh-env-completion-add <nom> <cmd>` | Ajoute une completion personnalisée |
| `zsh-env-completion-remove <nom>` | Supprime une completion personnalisée |
| `zsh-env-status` | Affiche le statut de zsh_env |
| `zsh-env-update` | Force la mise à jour |
| `zsh-env-doctor` | Diagnostic complet de l'installation |
| `zsh-env-theme [nom]` | Gestion des thèmes Starship |
| `zsh-env-help` | Affiche l'aide |

### Completions personnalisées

Ajoutez vos propres completions pour des outils CLI :

```bash
# Ajouter une completion
zsh-env-completion-add bun "bun completions"
zsh-env-completion-add deno "deno completions zsh"

# Supprimer
zsh-env-completion-remove bun

# Charger toutes les completions
zsh-env-completions
```

---

## Aliases Locaux

Pour vos aliases personnels (non versionnés), créez `~/.zsh_env/aliases.local.zsh` :

```bash
cp ~/.zsh_env/aliases.local.zsh.example ~/.zsh_env/aliases.local.zsh
```

Exemple de contenu :

```zsh
# Raccourcis projet
alias myproj="cd ~/Projects/mon-projet && code ."

# Commandes spécifiques machine
alias vpn="sudo openvpn /etc/openvpn/client.conf"
```

---

## Désinstallation

```bash
~/.zsh_env/uninstall.sh
```

Options :
- `--keep-dir` : Conserve le dossier ~/.zsh_env
- `--keep-secrets` : Conserve le fichier ~/.secrets
- `--force` : Pas de confirmation

Le script propose de restaurer un backup de votre `.zshrc` si disponible.

---

## Structure du Projet

```text
~/.zsh_env/
├── install.sh              # Installation interactive
├── uninstall.sh            # Désinstallation
├── rc.zsh                  # Point d'entrée sourcé par .zshrc
├── config.zsh              # Configuration personnelle (ignoré par git)
├── config.zsh.example      # Template de configuration
├── completions.zsh         # Completions personnalisées
├── aliases.zsh             # Alias globaux
├── aliases.local.zsh       # Alias personnels (ignoré par git)
├── variables.zsh           # Variables d'environnement
├── functions.zsh           # Loader de fonctions
├── functions/              # Fonctions chargées dynamiquement
│   ├── auto_update.zsh     # Système d'auto-update
│   ├── zsh_env_commands.zsh # Commandes zsh-env-*
│   ├── nvm_auto.zsh        # Auto-switch NVM
│   ├── gitlab_logic.zsh    # Fonctions GitLab
│   ├── docker_utils.zsh    # Utilitaires Docker
│   └── ...
├── themes/                 # Thèmes Starship
│   ├── minimal.toml
│   ├── default.toml
│   ├── powerline.toml
│   └── plain.toml
└── scripts/                # Scripts autonomes
    ├── clone-projects.sh   # Clone en masse GitLab
    └── trigger-jobs.sh     # Trigger jobs GitLab
```

---

## Astuces

| Commande | Description |
|----------|-------------|
| `ss` | Recharge la configuration Zsh instantanément |
| `please` | Relance la dernière commande avec `sudo` |
| `extract` | Décompresse n'importe quelle archive |
| `gr` | Va à la racine du repo git courant |

---

## Diagnostic

En cas de problème, lancez :

```bash
zsh-env-doctor
```

Cette commande vérifie :
- Les fichiers de configuration
- Les dépendances requises et optionnelles
- Les modules actifs
- Les permissions
- Les variables d'environnement

---

## Secrets

Créez `~/.secrets` pour vos tokens API (fichier ignoré par git) :

```bash
export GITLAB_TOKEN="glpat-xxxx"
export GITHUB_TOKEN="ghp_xxxx"
```
