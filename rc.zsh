# ==============================================================================
# ZSH_ENV - Point d'entree principal
# ==============================================================================
# Source par .zshrc via $ZSH_ENV_DIR
# Ordre de chargement:
#   1. Configuration (modules, options)
#   2. Secrets
#   3. Variables
#   4. Completions
#   5. Functions
#   6. Aliases
#   7. Plugins
#   8. Hooks (outils externes: starship, mise, zoxide, direnv)
# ==============================================================================

# --- Verification ZSH_ENV_DIR ---
if [[ -z "$ZSH_ENV_DIR" ]]; then
    echo "WARNING: ZSH_ENV_DIR is not set. Assuming default location."
    export ZSH_ENV_DIR="$HOME/.zsh_env"
fi

# --- 1. Configuration ---
# Valeurs par defaut des modules
ZSH_ENV_MODULE_GITLAB=${ZSH_ENV_MODULE_GITLAB:-true}
ZSH_ENV_MODULE_DOCKER=${ZSH_ENV_MODULE_DOCKER:-true}
ZSH_ENV_MODULE_MISE=${ZSH_ENV_MODULE_MISE:-true}
ZSH_ENV_MODULE_NUSHELL=${ZSH_ENV_MODULE_NUSHELL:-true}

# Auto-update
ZSH_ENV_AUTO_UPDATE=${ZSH_ENV_AUTO_UPDATE:-true}
ZSH_ENV_UPDATE_FREQUENCY=${ZSH_ENV_UPDATE_FREQUENCY:-7}
ZSH_ENV_UPDATE_MODE=${ZSH_ENV_UPDATE_MODE:-prompt}

# Charger config personnalisee si presente
[[ -f "$ZSH_ENV_DIR/config.zsh" ]] && source "$ZSH_ENV_DIR/config.zsh"

# Backward compat: NVM -> mise (pour les anciens config.zsh)
if [[ -n "$ZSH_ENV_MODULE_NVM" && -z "$ZSH_ENV_MODULE_MISE" ]]; then
    ZSH_ENV_MODULE_MISE="$ZSH_ENV_MODULE_NVM"
    unset ZSH_ENV_MODULE_NVM ZSH_ENV_NVM_LAZY
fi

# --- 2. Secrets ---
[[ -f "$HOME/.secrets" ]] && source "$HOME/.secrets"

# --- 3. Variables ---
if [[ -f "$ZSH_ENV_DIR/variables.zsh" ]]; then
    source "$ZSH_ENV_DIR/variables.zsh"
else
    echo "ERROR: variables.zsh not found in $ZSH_ENV_DIR"
fi

export PATH="$SCRIPTS_DIR:$PATH"

# --- 4. Completions ---
autoload -Uz compinit
# Cache quotidien pour performance
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

# Menu interactif : navigation avec les fleches, highlight de la selection
zmodload zsh/complist
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Case-insensitive + partial-word matching (ex: "doc" complete "Documents")
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Groupes avec headers
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{cyan}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{yellow}Aucun resultat pour: %d%f'

# Navigation dans le menu avec vim-style en plus des fleches
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char

# --- 5. Functions ---
[[ -f "$ZSH_ENV_DIR/functions.zsh" ]] && source "$ZSH_ENV_DIR/functions.zsh"

# --- 6. Aliases ---
[[ -f "$ZSH_ENV_DIR/aliases.zsh" ]] && source "$ZSH_ENV_DIR/aliases.zsh"
[[ -f "$ZSH_ENV_DIR/aliases.local.zsh" ]] && source "$ZSH_ENV_DIR/aliases.local.zsh"

# --- 7. Plugins ---
[[ -f "$ZSH_ENV_DIR/plugins.zsh" ]] && source "$ZSH_ENV_DIR/plugins.zsh"

# --- 8. Hooks (outils externes) ---
[[ -f "$ZSH_ENV_DIR/hooks.zsh" ]] && source "$ZSH_ENV_DIR/hooks.zsh"

# --- Options ZSH ---
setopt AUTO_CD

# --- PATH Final (Deduplication) ---
typeset -U PATH
