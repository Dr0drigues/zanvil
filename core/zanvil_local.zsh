# ==============================================================================
# .zanvil.local — variables par projet, chargees au cd (style direnv)
# ==============================================================================
# Definitions seulement : le hook chpwd et le chargement initial sont dans hooks.zsh.
# Trust par sha256 du contenu : confirmation la premiere fois et a chaque modification.

_ZANVIL_LOCAL_TRUST_DIR="${ZANVIL_DIR:-$HOME/.zanvil}/.trusted"
_ZANVIL_LOCAL_LOADED=""
# Variables exportees touchees par le fichier : nom -> "-" (absente avant) ou "+<valeur d'avant>".
typeset -gA _ZANVIL_LOCAL_SAVED

# Contenu exact du fichier dans REPLY (le x garde les sauts de ligne finaux, donc le meme
# sha256 que le fichier : les autorisations deja donnees restent valides).
_zanvil_local_read() {
    REPLY="$(command cat -- "$1" 2>/dev/null; print x)"
    REPLY=${REPLY%x}
}

# Usage : _zanvil_local_hash <contenu>
_zanvil_local_hash() {
    print -rn -- "$1" | shasum -a 256 2>/dev/null | awk '{print $1}'
}

_zanvil_local_is_trusted() {
    local hash=$(_zanvil_local_hash "$1")
    [[ -n "$hash" && -f "$_ZANVIL_LOCAL_TRUST_DIR/$hash" ]]
}

# Usage : _zanvil_local_trust <fichier> <contenu>
_zanvil_local_trust() {
    local hash=$(_zanvil_local_hash "$2")
    [[ -n "$hash" ]] || return 1
    mkdir -p "$_ZANVIL_LOCAL_TRUST_DIR"
    print -r -- "$1" > "$_ZANVIL_LOCAL_TRUST_DIR/$hash"
}

_zanvil_local_load() {
    local _zl_file="$1" _zl_content
    # Lu une seule fois : ce qui est montre, hashe et execute est le meme texte, meme si le
    # fichier change entre-temps (git checkout).
    _zanvil_local_read "$_zl_file"; _zl_content=$REPLY

    if ! _zanvil_local_is_trusted "$_zl_content"; then
        echo ""
        echo -e "${_ui_yellow}[zanvil]${_ui_nc} Fichier .zanvil.local detecte dans ${_ui_bold}${_zl_file:h}${_ui_nc}"
        # En entier : autoriser apres n'en avoir vu qu'un extrait laisserait passer la suite.
        print -r -- "$_zl_content" | sed 's/^/    /'
        echo ""
        local response
        read -q "response?Autoriser ce fichier ? [y/N] "
        echo ""
        if [[ "$response" != "y" ]]; then
            echo -e "${_ui_dim}Ignore. Lancez 'zanvil-trust' pour autoriser plus tard.${_ui_nc}"
            return 1
        fi
        _zanvil_local_trust "$_zl_file" "$_zl_content"
    fi

    # Un seul fichier actif : decharger le precedent (dossier parent) avant d'en charger un autre.
    _zanvil_local_unload quiet

    local -A _zl_before
    local _zl_n
    for _zl_n in ${(k)parameters[(R)*export*]}; do _zl_before[$_zl_n]=${(P)_zl_n}; done
    eval "$_zl_content"
    _ZANVIL_LOCAL_SAVED=()
    for _zl_n in ${(k)parameters[(R)*export*]}; do
        if (( ! ${+_zl_before[$_zl_n]} )); then
            _ZANVIL_LOCAL_SAVED[$_zl_n]=-
        elif [[ "${_zl_before[$_zl_n]}" != "${(P)_zl_n}" ]]; then
            _ZANVIL_LOCAL_SAVED[$_zl_n]="+${_zl_before[$_zl_n]}"
        fi
    done
    # Variables que le fichier a retirees.
    for _zl_n in ${(k)_zl_before}; do
        [[ ${parameters[$_zl_n]} == *export* ]] || _ZANVIL_LOCAL_SAVED[$_zl_n]="+${_zl_before[$_zl_n]}"
    done
    _ZANVIL_LOCAL_LOADED="$_zl_file"

    echo -e "${_ui_green}[zanvil]${_ui_nc} Charge: ${_ui_dim}${_zl_file}${_ui_nc}"
}

# Restaure l'environnement d'avant le chargement : une variable modifiee (PATH) reprend sa
# valeur, une variable ajoutee est retiree.
_zanvil_local_unload() {
    [[ -n "$_ZANVIL_LOCAL_LOADED" ]] || return 0
    local n
    for n in ${(k)_ZANVIL_LOCAL_SAVED}; do
        if [[ ${_ZANVIL_LOCAL_SAVED[$n]} == - ]]; then
            unset "$n" 2>/dev/null
        else
            export "$n=${_ZANVIL_LOCAL_SAVED[$n]#+}"
        fi
    done
    [[ "$1" == quiet ]] || echo -e "${_ui_dim}[zanvil] Decharge: ${_ZANVIL_LOCAL_LOADED}${_ui_nc}"
    _ZANVIL_LOCAL_LOADED=""
    _ZANVIL_LOCAL_SAVED=()
}

_zanvil_local_chpwd() {
    local local_file="$PWD/.zanvil.local"

    # Sorti du dossier charge : egalite ou sous-dossier, pas un simple prefixe
    # (~/work/app-prod n'est pas dans ~/work/app).
    if [[ -n "$_ZANVIL_LOCAL_LOADED" ]]; then
        local loaded_dir="${_ZANVIL_LOCAL_LOADED:h}"
        if [[ "$PWD" != "$loaded_dir" && "$PWD" != "$loaded_dir"/* ]]; then
            _zanvil_local_unload
        fi
    fi

    if [[ -f "$local_file" && "$local_file" != "$_ZANVIL_LOCAL_LOADED" ]]; then
        _zanvil_local_load "$local_file"
    fi
}

# Commande manuelle pour autoriser le fichier courant
zanvil-trust() {
    local file="${1:-$PWD/.zanvil.local}"
    if [[ ! -f "$file" ]]; then
        _ui_msg_fail "Aucun .zanvil.local dans le repertoire courant"
        return 1
    fi
    file=${file:a}
    _zanvil_local_read "$file"
    _zanvil_local_trust "$file" "$REPLY" || return 1
    _ui_msg_ok "Fichier autorise: $file"
    # Un fichier deja charge serait sinon saute par le test « deja actif ».
    [[ "$file" == "$_ZANVIL_LOCAL_LOADED" ]] && _zanvil_local_unload quiet
    _zanvil_local_load "$file"
}
