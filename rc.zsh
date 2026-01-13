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

# SDKMAN (Optimisé et Silencieux)
# On vérifie d'abord que le dossier existe avant de tester le fichier
export SDKMAN_DIR="$HOME/.sdkman"
if [ -d "$SDKMAN_DIR" ] && [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi

# PATH Final (Déduplication)
# Empêche d'avoir le PATH qui grandit à l'infini si on reload le .zshrc
typeset -U PATH