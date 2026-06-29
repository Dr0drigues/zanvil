# ==============================================================================
# zanvil - Point d'entree principal
# ==============================================================================
# Source par .zshrc via $ZANVIL_DIR
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

# --- Migration one-shot zsh_env -> zanvil (avant tout chargement) ---
if [[ -z "$ZANVIL_DIR" && -d "$HOME/.zsh_env" && ! -d "$HOME/.zanvil" ]]; then
    source "${${(%):-%x}:A:h}/core/lifecycle/migrate_zanvil.zsh"
fi

# --- Verification ZANVIL_DIR ---
if [[ -z "$ZANVIL_DIR" ]]; then
    echo "WARNING: ZANVIL_DIR is not set. Assuming default location."
    export ZANVIL_DIR="$HOME/.zanvil"
fi

# --- 1. Configuration ---
# Valeurs par defaut des modules
ZANVIL_MODULE_GITLAB=${ZANVIL_MODULE_GITLAB:-true}
ZANVIL_MODULE_DOCKER=${ZANVIL_MODULE_DOCKER:-true}
ZANVIL_MODULE_MISE=${ZANVIL_MODULE_MISE:-true}
ZANVIL_MODULE_NUSHELL=${ZANVIL_MODULE_NUSHELL:-true}
ZANVIL_MODULE_KUBE=${ZANVIL_MODULE_KUBE:-false}
ZANVIL_MODULE_SECURITY=${ZANVIL_MODULE_SECURITY:-true}
ZANVIL_MODULE_AI=${ZANVIL_MODULE_AI:-true}
ZANVIL_MODULE_ZPROJECT=${ZANVIL_MODULE_ZPROJECT:-true}

# Auto-update
ZANVIL_AUTO_UPDATE=${ZANVIL_AUTO_UPDATE:-true}
ZANVIL_UPDATE_FREQUENCY=${ZANVIL_UPDATE_FREQUENCY:-7}
ZANVIL_UPDATE_MODE=${ZANVIL_UPDATE_MODE:-prompt}

# Charger config personnalisee si presente
[[ -f "$ZANVIL_DIR/config.zsh" ]] && source "$ZANVIL_DIR/config.zsh"

# Backward compat: NVM -> mise (pour les anciens config.zsh)
if [[ -n "$ZANVIL_MODULE_NVM" && -z "$ZANVIL_MODULE_MISE" ]]; then
    ZANVIL_MODULE_MISE="$ZANVIL_MODULE_NVM"
    unset ZANVIL_MODULE_NVM ZANVIL_NVM_LAZY
fi

# --- 2. Secrets ---
[[ -f "$HOME/.secrets" ]] && source "$HOME/.secrets"

# --- 3. Variables ---
if [[ -f "$ZANVIL_DIR/core/variables.zsh" ]]; then
    source "$ZANVIL_DIR/core/variables.zsh"
else
    echo "ERROR: core/variables.zsh not found in $ZANVIL_DIR"
fi

export PATH="$SCRIPTS_DIR:$PATH"

# --- 3b. Variables dynamiques (env.d/) ---
# Charge tous les fichiers .zsh dans env.d/ (variables d'env thematiques)
# Les fichiers .sops.zsh sont dechiffres automatiquement si sops/age sont disponibles
if [[ -d "$ZANVIL_DIR/env.d" ]]; then
    for _env_file in "$ZANVIL_DIR/env.d"/*.zsh(N); do
        local _base="${_env_file:t}"
        # Fichiers sops : dechiffrer a la volee
        if [[ "$_base" == *.sops.zsh ]]; then
            if command -v sops &>/dev/null; then
                eval "$(sops -d "$_env_file" 2>/dev/null)"
            fi
        else
            source "$_env_file"
        fi
    done
    unset _env_file _base
fi

# --- 4. Completions ---
autoload -Uz compinit
# Cache des completions (surchargeable via ZANVIL_ZCOMPDUMP_CACHE_HOURS)
_zanvil_zcompdump_hours="${ZANVIL_ZCOMPDUMP_CACHE_HOURS:-24}"
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+${_zanvil_zcompdump_hours}) ]]; then
    compinit -u
else
    compinit -u -C
fi
unset _zanvil_zcompdump_hours

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

# --- 5. Module Loader ---
source "$ZANVIL_DIR/core/loader.zsh"

# --- 6. Aliases ---
source "$ZANVIL_DIR/core/aliases.zsh"
[[ -f "$ZANVIL_DIR/aliases.local.zsh" ]] && source "$ZANVIL_DIR/aliases.local.zsh"

# --- 7. Plugins ---
[[ -f "$ZANVIL_DIR/plugins.zsh" ]] && source "$ZANVIL_DIR/plugins.zsh"

# --- 8. Hooks (outils externes) ---
source "$ZANVIL_DIR/core/hooks.zsh"

# --- Options ZSH ---
setopt AUTO_CD

# --- PATH Final (Deduplication) ---
typeset -U PATH
