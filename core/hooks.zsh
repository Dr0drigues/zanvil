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
# ZANVIL LOCAL (auto-chargement hierarchique, style direnv)
# =======================================================
# Chaque dossier peut contenir un .zanvil.local. En entrant dans un dossier,
# la chaine complete des .zanvil.local est chargee, de la racine projet vers
# le dossier courant (l'enfant override le parent). Borne : $HOME n'est pas
# couvert — utilisez config.zsh / env.d/ pour du global.
# Trust hash-based par fichier + cache de refus par session.
_ZANVIL_LOCAL_TRUST_DIR="${ZANVIL_DIR:-$HOME/.zanvil}/.trusted"
_ZANVIL_LOCAL_FILES=()      # pile des fichiers appliques (racine -> feuille)
_ZANVIL_LOCAL_ADDED=()      # vars exportees ajoutees (unset au dechargement)
_ZANVIL_LOCAL_RESTORE=()    # paires NAME=value des vars modifiees/supprimees
_ZANVIL_LOCAL_FUNCS=()      # fonctions definies par les fichiers
_ZANVIL_LOCAL_DENIED=()     # hashes refuses durant cette session

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

# Construit _ZANVIL_LOCAL_STACK : les .zanvil.local presents entre le dossier
# courant et $HOME (exclu), ordonnes racine -> feuille.
_zanvil_local_stack() {
    _ZANVIL_LOCAL_STACK=()
    local -a rev=()
    local dir="${PWD:A}"
    local home="${HOME:A}"
    while :; do
        [[ "$dir" == "$home" || "$dir" == "/" ]] && break
        [[ -f "$dir/.zanvil.local" ]] && rev+=("$dir/.zanvil.local")
        dir="${dir:h}"
    done
    local i
    for (( i = ${#rev[@]}; i >= 1; i-- )); do
        _ZANVIL_LOCAL_STACK+=("${rev[$i]}")
    done
}

# Source un fichier apres validation du trust. Retourne 1 si refuse.
_zanvil_local_source() {
    local file="$1"

    if ! _zanvil_local_is_trusted "$file"; then
        local hash=$(_zanvil_local_hash "$file")
        # Deja refuse cette session -> pas de re-prompt
        if (( ${_ZANVIL_LOCAL_DENIED[(Ie)$hash]} )); then
            return 1
        fi
        echo ""
        echo -e "${_ui_yellow}[zanvil]${_ui_nc} Fichier .zanvil.local detecte dans ${_ui_bold}$(dirname "$file")${_ui_nc}"
        echo -e "  ${_ui_dim}$(head -3 "$file" | sed 's/^/  /')${_ui_nc}"
        echo ""
        local response
        read -q "response?Autoriser ce fichier ? [y/N] "
        echo ""
        if [[ "$response" != "y" ]]; then
            _ZANVIL_LOCAL_DENIED+=("$hash")
            echo -e "${_ui_dim}Ignore. Lancez 'zanvil-trust [$file]' pour autoriser plus tard.${_ui_nc}"
            return 1
        fi
        _zanvil_local_trust "$file"
    fi

    source "$file"
}

_zanvil_local_unload() {
    (( ${#_ZANVIL_LOCAL_FILES[@]} )) || return 0

    local pair var fn
    # Restaurer les vars modifiees/supprimees par les fichiers
    for pair in "${_ZANVIL_LOCAL_RESTORE[@]}"; do
        export "${pair}" 2>/dev/null
    done
    # Unset les vars ajoutees
    for var in "${_ZANVIL_LOCAL_ADDED[@]}"; do
        unset "${var}" 2>/dev/null
    done
    # Retirer les fonctions definies
    for fn in "${_ZANVIL_LOCAL_FUNCS[@]}"; do
        unfunction "${fn}" 2>/dev/null
    done

    echo -e "${_ui_dim}[zanvil] Decharge: ${#_ZANVIL_LOCAL_FILES[@]} fichier(s) .zanvil.local${_ui_nc}"
    _ZANVIL_LOCAL_FILES=()
    _ZANVIL_LOCAL_ADDED=()
    _ZANVIL_LOCAL_RESTORE=()
    _ZANVIL_LOCAL_FUNCS=()
}

_zanvil_local_chpwd() {
    _zanvil_local_stack
    local -a wanted=("${_ZANVIL_LOCAL_STACK[@]}")

    # Rien a faire si la pile voulue est identique a celle deja appliquee
    if [[ "${(j:\n:)wanted}" == "${(j:\n:)_ZANVIL_LOCAL_FILES}" ]]; then
        return 0
    fi

    _zanvil_local_unload
    (( ${#wanted[@]} )) || return 0

    # Snapshots avant chargement (vars exportees + fonctions)
    local before_env=$(env | LC_ALL=C sort)
    local -a before_funcs=($(print -rl -- ${(ko)functions}))

    # Charger la pile racine -> feuille ; un refus coupe l'heritage en dessous
    local file
    local -a applied=()
    for file in "${wanted[@]}"; do
        if ! _zanvil_local_source "$file"; then
            break
        fi
        applied+=("$file")
    done
    (( ${#applied[@]} )) || return 0

    # Diff vars : ajoutees -> unset au unload ; modifiees/supprimees -> restaurees
    local after_env=$(env | LC_ALL=C sort)
    local -A before_map=()
    local -A after_map=()
    local line
    for line in "${(@f)before_env}"; do
        before_map[${line%%=*}]=${line#*=}
    done
    for line in "${(@f)after_env}"; do
        after_map[${line%%=*}]=${line#*=}
    done

    local key
    for key in "${(k)after_map[@]}"; do
        if [[ -z "${before_map[$key]+x}" ]]; then
            _ZANVIL_LOCAL_ADDED+=("$key")
        elif [[ "${before_map[$key]}" != "${after_map[$key]}" ]]; then
            _ZANVIL_LOCAL_RESTORE+=("${key}=${before_map[$key]}")
        fi
    done
    for key in "${(k)before_map[@]}"; do
        if [[ -z "${after_map[$key]+x}" ]]; then
            _ZANVIL_LOCAL_RESTORE+=("${key}=${before_map[$key]}")
        fi
    done

    # Diff fonctions : celles qui n'existaient pas avant le chargement
    _ZANVIL_LOCAL_FUNCS=($(comm -13 \
        <(print -rl -- ${(ko)before_funcs}) \
        <(print -rl -- ${(ko)functions})))

    _ZANVIL_LOCAL_FILES=("${applied[@]}")

    local leaf="${applied[-1]}"
    local msg="$(dirname "$leaf")/.zanvil.local"
    if (( ${#applied[@]} > 1 )); then
        msg+=" ${_ui_dim}(+$((${#applied[@]} - 1)) herite(s))${_ui_nc}"
    fi
    echo -e "${_ui_green}[zanvil]${_ui_nc} Charge: ${_ui_dim}${msg}${_ui_nc}"
}

# Commande manuelle pour trust un fichier (defaut : repertoire courant)
zanvil-trust() {
    local file="${1:-$PWD/.zanvil.local}"
    if [[ ! -f "$file" ]]; then
        _ui_msg_fail "Aucun .zanvil.local dans le repertoire courant"
        return 1
    fi
    _zanvil_local_trust "$file"
    # Retirer du cache de refus de la session si present
    local hash=$(_zanvil_local_hash "$file")
    _ZANVIL_LOCAL_DENIED=("${_ZANVIL_LOCAL_DENIED[@]:#$hash}")
    _ui_msg_ok "Fichier autorise: $file"
    _zanvil_local_chpwd
}

# Enregistrer le hook chpwd
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _zanvil_local_chpwd

# Charger la pile si on demarre deja dans un dossier couvert
_zanvil_local_chpwd

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
