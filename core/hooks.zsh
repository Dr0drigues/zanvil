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
if [[ "$ZANVIL_MODULE_MISE" = "true" ]]; then
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
# ZANVIL LOCAL (auto-chargement par projet, style direnv)
# =======================================================
# Detecte .zanvil.local dans le repertoire courant au cd
# Trust hash-based : demande confirmation la premiere fois ou si modifie
_ZANVIL_LOCAL_TRUST_DIR="${ZANVIL_DIR:-$HOME/.zanvil}/.trusted"
_ZANVIL_LOCAL_LOADED=""
_ZANVIL_LOCAL_VARS=()

_zanvil_local_hash() {
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

_zanvil_local_is_trusted() {
    local file="$1"
    local hash=$(_zanvil_local_hash "$file")
    local trust_file="$_ZANVIL_LOCAL_TRUST_DIR/${hash}"
    [[ -f "$trust_file" ]]
}

_zanvil_local_trust() {
    local file="$1"
    local hash=$(_zanvil_local_hash "$file")
    mkdir -p "$_ZANVIL_LOCAL_TRUST_DIR"
    echo "$file" > "$_ZANVIL_LOCAL_TRUST_DIR/${hash}"
}

_zanvil_local_load() {
    local file="$1"

    if ! _zanvil_local_is_trusted "$file"; then
        echo ""
        echo -e "${_ui_yellow}[zanvil]${_ui_nc} Fichier .zanvil.local detecte dans ${_ui_bold}$(dirname "$file")${_ui_nc}"
        echo -e "  ${_ui_dim}$(head -3 "$file" | sed 's/^/  /')${_ui_nc}"
        echo ""
        local response
        read -q "response?Autoriser ce fichier ? [y/N] "
        echo ""
        if [[ "$response" != "y" ]]; then
            echo -e "${_ui_dim}Ignore. Lancez 'zanvil-trust' pour autoriser plus tard.${_ui_nc}"
            return 1
        fi
        _zanvil_local_trust "$file"
    fi

    # Capturer les variables avant/apres pour le unload
    local before_vars=$(env | sort)
    source "$file"
    local after_vars=$(env | sort)

    # Stocker les nouvelles variables pour cleanup
    _ZANVIL_LOCAL_VARS=($(comm -13 <(echo "$before_vars") <(echo "$after_vars") | cut -d= -f1))
    _ZANVIL_LOCAL_LOADED="$file"

    echo -e "${_ui_green}[zanvil]${_ui_nc} Charge: ${_ui_dim}$(dirname "$file")/.zanvil.local${_ui_nc}"
}

_zanvil_local_unload() {
    if [[ -n "$_ZANVIL_LOCAL_LOADED" ]]; then
        # Unset les variables ajoutees par le fichier
        for var in "${_ZANVIL_LOCAL_VARS[@]}"; do
            unset "$var" 2>/dev/null
        done
        echo -e "${_ui_dim}[zanvil] Decharge: $(dirname "$_ZANVIL_LOCAL_LOADED")/.zanvil.local${_ui_nc}"
        _ZANVIL_LOCAL_LOADED=""
        _ZANVIL_LOCAL_VARS=()
    fi
}

_zanvil_local_chpwd() {
    local local_file="$PWD/.zanvil.local"

    # Si on a un fichier charge et on est sorti du dossier
    if [[ -n "$_ZANVIL_LOCAL_LOADED" ]]; then
        local loaded_dir="$(dirname "$_ZANVIL_LOCAL_LOADED")"
        if [[ "$PWD" != "$loaded_dir"* ]]; then
            _zanvil_local_unload
        fi
    fi

    # Si un .zanvil.local existe dans le nouveau dossier
    if [[ -f "$local_file" && "$local_file" != "$_ZANVIL_LOCAL_LOADED" ]]; then
        _zanvil_local_load "$local_file"
    fi
}

# Commande manuelle pour trust le fichier courant
zanvil-trust() {
    local file="${1:-$PWD/.zanvil.local}"
    if [[ ! -f "$file" ]]; then
        _ui_msg_fail "Aucun .zanvil.local dans le repertoire courant"
        return 1
    fi
    _zanvil_local_trust "$file"
    _ui_msg_ok "Fichier autorise: $file"
    _zanvil_local_load "$file"
}

# Enregistrer le hook chpwd
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _zanvil_local_chpwd

# Charger si on est deja dans un dossier avec .zanvil.local
[[ -f "$PWD/.zanvil.local" ]] && _zanvil_local_load "$PWD/.zanvil.local"

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
if [[ "${ZANVIL_MODULE_ATUIN:-}" == "true" ]] && command -v atuin &>/dev/null; then
    eval "$(atuin init zsh --disable-up-arrow)"
fi

# =======================================================
# BANNIERE DE DEMARRAGE (zanvil)
# =======================================================
# Ligne compacte a chaque shell interactif. Opt-out : ZANVIL_STARTUP_BANNER=false
if [[ -o interactive && "${ZANVIL_STARTUP_BANNER:-true}" != "false" ]]; then
    _zanvil_banner_compact
fi
