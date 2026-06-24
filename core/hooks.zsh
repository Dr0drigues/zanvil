# ==============================================================================
# Hooks & Initialisations d'outils externes
# ==============================================================================
# Ce fichier centralise les initialisations d'outils qui utilisent des hooks zsh
# (eval "$(tool init zsh)", hooks chpwd, etc.)
# ==============================================================================

# =======================================================
# FZF (Keybindings & Completion)
# =======================================================
# Ctrl+R : recherche historique | Ctrl+T : fichiers | Alt+C : cd
if command -v fzf &> /dev/null; then
    # Chemins possibles pour les scripts fzf
    _fzf_paths=(
        "/opt/homebrew/opt/fzf/shell"    # MacOS Apple Silicon (Brew)
        "/usr/local/opt/fzf/shell"       # MacOS Intel (Brew)
        "/usr/share/fzf"                 # Linux (apt/dnf)
        "$HOME/.fzf"                     # Installation manuelle
    )

    for _fzf_path in "${_fzf_paths[@]}"; do
        if [[ -d "$_fzf_path" ]]; then
            [[ -f "$_fzf_path/key-bindings.zsh" ]] && source "$_fzf_path/key-bindings.zsh"
            [[ -f "$_fzf_path/completion.zsh" ]] && source "$_fzf_path/completion.zsh"
            break
        fi
    done
    unset _fzf_paths _fzf_path
fi

# =======================================================
# STARSHIP (Prompt)
# =======================================================
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
else
    # Fallback minimaliste si starship absent
    PROMPT='%n@%m %1~ %# '
fi

# =======================================================
# MISE (Gestionnaire de versions: Node, Java, Maven, etc.)
# =======================================================
if [[ "$ZSH_ENV_MODULE_MISE" = "true" ]]; then
    if command -v mise &> /dev/null; then
        eval "$(mise activate zsh)"
    fi
fi

# =======================================================
# ZOXIDE (Navigation rapide)
# =======================================================
# Zoxide utilise un hook chpwd pour enregistrer les repertoires.
if command -v zoxide &> /dev/null; then
    export _ZO_DOCTOR=0  # Desactive l'avertissement (direnv charge apres)
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

# =======================================================
# DIRENV (Charge/decharge les .envrc automatiquement)
# =======================================================
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi

# =======================================================
# ZSH-ENV LOCAL (auto-chargement par projet, style direnv)
# =======================================================
# Detecte .zsh-env.local dans le repertoire courant au cd
# Trust hash-based : demande confirmation la premiere fois ou si modifie
_ZSH_ENV_LOCAL_TRUST_DIR="${ZSH_ENV_DIR:-$HOME/.zsh_env}/.trusted"
_ZSH_ENV_LOCAL_LOADED=""
_ZSH_ENV_LOCAL_VARS=()

_zsh_env_local_hash() {
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

_zsh_env_local_is_trusted() {
    local file="$1"
    local hash=$(_zsh_env_local_hash "$file")
    local trust_file="$_ZSH_ENV_LOCAL_TRUST_DIR/${hash}"
    [[ -f "$trust_file" ]]
}

_zsh_env_local_trust() {
    local file="$1"
    local hash=$(_zsh_env_local_hash "$file")
    mkdir -p "$_ZSH_ENV_LOCAL_TRUST_DIR"
    echo "$file" > "$_ZSH_ENV_LOCAL_TRUST_DIR/${hash}"
}

_zsh_env_local_load() {
    local file="$1"

    if ! _zsh_env_local_is_trusted "$file"; then
        echo ""
        echo -e "${_ui_yellow}[zsh-env]${_ui_nc} Fichier .zsh-env.local detecte dans ${_ui_bold}$(dirname "$file")${_ui_nc}"
        echo -e "  ${_ui_dim}$(head -3 "$file" | sed 's/^/  /')${_ui_nc}"
        echo ""
        local response
        read -q "response?Autoriser ce fichier ? [y/N] "
        echo ""
        if [[ "$response" != "y" ]]; then
            echo -e "${_ui_dim}Ignore. Lancez 'zsh-env-trust' pour autoriser plus tard.${_ui_nc}"
            return 1
        fi
        _zsh_env_local_trust "$file"
    fi

    # Capturer les variables avant/apres pour le unload
    local before_vars=$(env | sort)
    source "$file"
    local after_vars=$(env | sort)

    # Stocker les nouvelles variables pour cleanup
    _ZSH_ENV_LOCAL_VARS=($(comm -13 <(echo "$before_vars") <(echo "$after_vars") | cut -d= -f1))
    _ZSH_ENV_LOCAL_LOADED="$file"

    echo -e "${_ui_green}[zsh-env]${_ui_nc} Charge: ${_ui_dim}$(dirname "$file")/.zsh-env.local${_ui_nc}"
}

_zsh_env_local_unload() {
    if [[ -n "$_ZSH_ENV_LOCAL_LOADED" ]]; then
        # Unset les variables ajoutees par le fichier
        for var in "${_ZSH_ENV_LOCAL_VARS[@]}"; do
            unset "$var" 2>/dev/null
        done
        echo -e "${_ui_dim}[zsh-env] Decharge: $(dirname "$_ZSH_ENV_LOCAL_LOADED")/.zsh-env.local${_ui_nc}"
        _ZSH_ENV_LOCAL_LOADED=""
        _ZSH_ENV_LOCAL_VARS=()
    fi
}

_zsh_env_local_chpwd() {
    local local_file="$PWD/.zsh-env.local"

    # Si on a un fichier charge et on est sorti du dossier
    if [[ -n "$_ZSH_ENV_LOCAL_LOADED" ]]; then
        local loaded_dir="$(dirname "$_ZSH_ENV_LOCAL_LOADED")"
        if [[ "$PWD" != "$loaded_dir"* ]]; then
            _zsh_env_local_unload
        fi
    fi

    # Si un .zsh-env.local existe dans le nouveau dossier
    if [[ -f "$local_file" && "$local_file" != "$_ZSH_ENV_LOCAL_LOADED" ]]; then
        _zsh_env_local_load "$local_file"
    fi
}

# Commande manuelle pour trust le fichier courant
zsh-env-trust() {
    local file="${1:-$PWD/.zsh-env.local}"
    if [[ ! -f "$file" ]]; then
        _ui_msg_fail "Aucun .zsh-env.local dans le repertoire courant"
        return 1
    fi
    _zsh_env_local_trust "$file"
    _ui_msg_ok "Fichier autorise: $file"
    _zsh_env_local_load "$file"
}

# Enregistrer le hook chpwd
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _zsh_env_local_chpwd

# Charger si on est deja dans un dossier avec .zsh-env.local
[[ -f "$PWD/.zsh-env.local" ]] && _zsh_env_local_load "$PWD/.zsh-env.local"

# =======================================================
# KEYBINDINGS
# =======================================================
# Fleches haut/bas : recherche historique par prefixe
# Tape "git" puis fleche haut -> affiche les commandes commencant par "git"
autoload -U history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end

bindkey '^[[A' history-beginning-search-backward-end  # Fleche haut
bindkey '^[[B' history-beginning-search-forward-end   # Fleche bas
bindkey '^[OA' history-beginning-search-backward-end  # Fleche haut (mode application)
bindkey '^[OB' history-beginning-search-forward-end   # Fleche bas (mode application)

# =======================================================
# ATUIN (Historique enrichi — remplace Ctrl+R de fzf)
# =======================================================
# Chargé en dernier pour que Ctrl+R override celui de fzf.
# --disable-up-arrow : les flèches ↑↓ restent en recherche par préfixe.
if [[ "${ZSH_ENV_MODULE_ATUIN:-}" == "true" ]] && command -v atuin &>/dev/null; then
    eval "$(atuin init zsh --disable-up-arrow)"
fi

# =======================================================
# BANNIERE DE DEMARRAGE (zanvil)
# =======================================================
# Ligne compacte a chaque shell interactif. Opt-out : ZSH_ENV_STARTUP_BANNER=false
if [[ -o interactive && "${ZSH_ENV_STARTUP_BANNER:-true}" != "false" ]]; then
    _zanvil_banner_compact
fi
