# Installation

## Prerequis

- macOS ou Linux (Debian/Ubuntu/Fedora)
- `git` et `curl`
- Acces sudo (pour l'installation des dependances)
- Rust toolchain (pour le CLI optionnel)

## Installation rapide

```bash
# Cloner le repo
git clone git@github.com:Dr0drigues/zsh_env.git ~/.zsh_env

# Lancer l'installation
cd ~/.zsh_env
./install.sh
```

## Options d'installation

### Mode interactif (defaut)

```bash
./install.sh
```

L'installation vous guide et permet de choisir :
- Les modules a activer
- Le theme Starship
- Les options NVM

### Mode automatique

```bash
./install.sh --default
```

Installe tout avec les parametres par defaut.

## Ce que fait le script

1. **Detecte le systeme** (macOS/Debian/Fedora)
2. **Installe Homebrew** (macOS uniquement, si absent)
3. **Installe les dependances** :
   - Outils de base : `git`, `curl`, `zsh`, `jq`, `tmux`
   - Outils modernes : `eza`, `starship`, `zoxide`, `fzf`, `bat`
   - Chiffrement : `sops`, `age`
   - Kubernetes : `kubectl`, `helm`, `kubelogin`, `azure-cli`
4. **Installe NVM et SDKMAN**
5. **Configure `.zshrc`** pour sourcer `rc.zsh`
6. **Cree `config.zsh`** avec vos preferences
7. **Initialise `env.d/`** pour les variables dynamiques

## CLI Rust (zsh-env-cli)

Le CLI Rust est optionnel mais recommande pour des performances optimales :

```bash
cd ~/.zsh_env/zsh-env-cli
cargo build --release

# Le binaire est installe dans le PATH automatiquement
# Ou copier manuellement :
cp target/release/zsh-env-cli ~/.local/bin/
```

Le CLI fournit les commandes : `theme`, `doctor`, `audit`, `context`, `modules`.

```bash
# Verifier l'installation du CLI
zsh-env-cli --version
```

## Configuration de env.d/

Le dossier `env.d/` permet de charger des variables d'environnement dynamiques :

```bash
# Creer le dossier (fait automatiquement par install.sh)
mkdir -p ~/.zsh_env/env.d

# Ajouter des variables
echo 'export MY_VAR=value' > ~/.zsh_env/env.d/custom.env

# Pour les secrets, utiliser sops
sops ~/.zsh_env/env.d/secrets.env
```

## Post-installation

Apres l'installation :

```bash
# Recharger le shell
source ~/.zshrc

# Verifier l'installation
zsh-env-doctor

# Lister les modules disponibles
zsh-env-modules list

# Appliquer un theme
zsh-env-theme list
zsh-env-theme minimal
```

## Mise a jour

```bash
cd ~/.zsh_env
git pull
ss  # Recharger
```

Pour mettre a jour le CLI Rust :

```bash
cd ~/.zsh_env/zsh-env-cli
cargo build --release
```

Ou activez l'auto-update dans `config.zsh` :

```zsh
ZSH_ENV_AUTO_UPDATE=true
ZSH_ENV_UPDATE_FREQUENCY=7  # jours
```

## Desinstallation

```bash
~/.zsh_env/uninstall.sh
```

Options :
- `--keep-dir` : Conserver le dossier
- `--keep-secrets` : Conserver `~/.secrets`
- `--force` : Sans confirmation
