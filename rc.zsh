# Init prompt (Starship)
# Vérification stricte avant le eval
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
else
    # Fallback minimaliste si starship absent
    # Affiche: [user@host dir]$ 
    PROMPT='%n@%m %1~ %# '
fi

# OPTIONAL: Activate AUTO_CD if wanted
# Uncomment the following line to enable AUTO_CD
setopt AUTO_CD

# Init Environment
if [ -z "$ZSH_ENV_DIR" ]; then
    echo "WARNING: ZSH_ENV_DIR is not set. Assuming default location."
    export ZSH_ENV_DIR="$HOME/.zsh_env" # Valeur par défaut de sécurité
fi

# Load Configuration (modules actifs/inactifs)
# Valeurs par defaut (tout actif)
ZSH_ENV_MODULE_GITLAB=${ZSH_ENV_MODULE_GITLAB:-true}
ZSH_ENV_MODULE_DOCKER=${ZSH_ENV_MODULE_DOCKER:-true}
ZSH_ENV_MODULE_NVM=${ZSH_ENV_MODULE_NVM:-true}
ZSH_ENV_MODULE_NUSHELL=${ZSH_ENV_MODULE_NUSHELL:-true}

# Auto-update (valeurs par defaut)
ZSH_ENV_AUTO_UPDATE=${ZSH_ENV_AUTO_UPDATE:-true}
ZSH_ENV_UPDATE_FREQUENCY=${ZSH_ENV_UPDATE_FREQUENCY:-7}
ZSH_ENV_UPDATE_MODE=${ZSH_ENV_UPDATE_MODE:-prompt}

# Charger config personnalisee si presente
if [ -f "$ZSH_ENV_DIR/config.zsh" ]; then
    source "$ZSH_ENV_DIR/config.zsh"
fi

# Load Secrets (Ignored by git)
if [ -f "$HOME/.secrets" ]; then
    source "$HOME/.secrets"
fi

# Load variables (Critique : Doit être chargé en premier)
if [ -f "$ZSH_ENV_DIR/variables.zsh" ]; then
    source "$ZSH_ENV_DIR/variables.zsh"
else
    echo "ERROR: variables.zsh not found in $ZSH_ENV_DIR"
fi

export PATH="$SCRIPTS_DIR:$PATH"

# Load functions
if [ -f "$ZSH_ENV_DIR/functions.zsh" ]; then
    source "$ZSH_ENV_DIR/functions.zsh"
fi

# Load aliases
if [ -f "$ZSH_ENV_DIR/aliases.zsh" ]; then
    source "$ZSH_ENV_DIR/aliases.zsh"
fi

# =======================================================
# NVM INIT (Cross-Platform)
# =======================================================

if [ "$ZSH_ENV_MODULE_NVM" = "true" ]; then
    export NVM_DIR="$HOME/.nvm"

    # Liste priorisée des chemins d'initialisation possibles
    nvm_candidates=(
        "$NVM_DIR/nvm.sh"                          # Linux / Install Manuelle
        "/opt/homebrew/opt/nvm/nvm.sh"             # MacOS Apple Silicon (Brew)
        "/usr/local/opt/nvm/nvm.sh"                # MacOS Intel (Brew)
        "/usr/share/nvm/init-nvm.sh"               # Arch Linux (AUR)
    )

    for nvm_path in $nvm_candidates; do
        if [ -s "$nvm_path" ]; then
            source "$nvm_path"

            # Chargement de l'autocomplétion si disponible (même dossier, sous-dossier etc)
            # On tente de déduire le chemin de bash_completion par rapport à nvm.sh
            local nvm_root=$(dirname "$nvm_path")
            local completion_path="$nvm_root/etc/bash_completion.d/nvm"

            # Fallback pour install manuelle
            if [ ! -f "$completion_path" ]; then
                completion_path="$NVM_DIR/bash_completion"
            fi

            [ -s "$completion_path" ] && source "$completion_path"

            break
        fi
    done

    # Hook automatique (Uniquement si NVM est chargé)
    if command -v nvm &> /dev/null; then
        autoload -U add-zsh-hook
        add-zsh-hook chpwd load-nvmrc
        load-nvmrc # Exécution au démarrage
    fi
fi

# SDKMAN (Optimisé et Silencieux)
# On vérifie d'abord que le dossier existe avant de tester le fichier
export SDKMAN_DIR="$HOME/.sdkman"
if [ -d "$SDKMAN_DIR" ] && [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi

# PATH Final (Déduplication)
# Empêche d'avoir le PATH qui grandit à l'infini si on reload le .zshrc
typeset -U PATH