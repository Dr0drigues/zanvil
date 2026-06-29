---
title: Installation
description: Installer zanvil (zanvil) sur macOS et Linux
---

## Prérequis

- macOS ou Linux (Debian/Ubuntu/Fedora)
- `git` et `curl`
- Accès sudo (pour l'installation des dépendances)
- Rust toolchain (pour le CLI optionnel)

## Installation rapide

```bash
# Cloner le repo
git clone git@github.com:Dr0drigues/zanvil.git ~/.zanvil

# Lancer l'installation
cd ~/.zanvil
./install.sh
```

## Options d'installation

### Mode interactif (défaut)

```bash
./install.sh
```

L'installation vous guide et permet de choisir :
- Les modules à activer
- Le thème Starship
- Les options NVM

### Mode automatique

```bash
./install.sh --default
```

Installe tout avec les paramètres par défaut.

## Ce que fait le script

1. **Détecte le système** (macOS/Debian/Fedora)
2. **Installe Homebrew** (macOS uniquement, si absent)
3. **Installe les dépendances** :
   - Outils de base : `git`, `curl`, `zsh`, `jq`, `tmux`
   - Outils modernes : `eza`, `starship`, `zoxide`, `fzf`, `bat`
   - Chiffrement : `sops`, `age`
   - Kubernetes : `kubectl`, `helm`, `kubelogin`, `azure-cli`
4. **Installe NVM et SDKMAN**
5. **Configure `.zshrc`** pour sourcer `rc.zsh`
6. **Crée `config.zsh`** avec vos préférences
7. **Initialise `env.d/`** pour les variables dynamiques

## CLI Rust (zanvil)

Le CLI Rust est optionnel mais recommandé pour des performances optimales :

```bash
cd ~/.zanvil/cli
cargo build --release

# Le binaire est installé dans le PATH automatiquement
# Ou copier manuellement :
cp target/release/zanvil ~/.local/bin/
```

Le CLI fournit les commandes : `theme`, `doctor`, `audit`, `context`, `modules`.

```bash
# Vérifier l'installation du CLI
zanvil --version
```

## Configuration de env.d/

Le dossier `env.d/` permet de charger des variables d'environnement dynamiques :

```bash
# Créer le dossier (fait automatiquement par install.sh)
mkdir -p ~/.zanvil/env.d

# Ajouter des variables
echo 'export MY_VAR=value' > ~/.zanvil/env.d/custom.env

# Pour les secrets, utiliser sops
sops ~/.zanvil/env.d/secrets.env
```

## Post-installation

Après l'installation :

```bash
# Recharger le shell
source ~/.zshrc

# Vérifier l'installation
zanvil-doctor

# Lister les modules disponibles
zanvil-modules list

# Appliquer un thème
zanvil-theme list
zanvil-theme minimal
```

## Mise à jour

```bash
cd ~/.zanvil
git pull
ss  # Recharger
```

Pour mettre à jour le CLI Rust :

```bash
cd ~/.zanvil/cli
cargo build --release
```

Ou activez l'auto-update dans `config.zsh` :

```zsh
ZANVIL_AUTO_UPDATE=true
ZANVIL_UPDATE_FREQUENCY=7  # jours
```

## Désinstallation

```bash
~/.zanvil/uninstall.sh
```

Options :
- `--keep-dir` : Conserver le dossier
- `--keep-secrets` : Conserver `~/.secrets`
- `--force` : Sans confirmation
