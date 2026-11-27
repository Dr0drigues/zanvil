# ==============================================================================
# .zanvil.local — variables par projet, chargees au cd (style direnv), avec heritage
# ==============================================================================
# Definitions seulement : le hook chpwd et le chargement initial sont dans hooks.zsh.
#
# En entrant dans un dossier, toute la chaine des .zanvil.local est appliquee, du plus haut
# vers le dossier courant (l'enfant l'emporte sur le parent). Borne : $HOME n'est pas couvert
# (config.zsh et env.d/ servent au global). Trust par sha256 du contenu, fichier par fichier ;
# refuser un parent coupe l'heritage en dessous, et un refus n'est plus redemande de la
# session. Au dechargement, les variables exportees reprennent leur valeur d'avant et les
# fonctions definies par les fichiers sont retirees.

_ZANVIL_LOCAL_TRUST_DIR="${ZANVIL_DIR:-$HOME/.zanvil}/.trusted"
typeset -ga _ZANVIL_LOCAL_FILES      # pile appliquee (racine -> feuille)
typeset -ga _ZANVIL_LOCAL_FUNCS      # fonctions definies par la pile
typeset -ga _ZANVIL_LOCAL_DENIED     # hashes refuses pendant la session
# Variables exportees touchees par la pile : nom -> "-" (absente avant) ou "+<valeur d'avant>".
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
    _ZANVIL_LOCAL_DENIED=("${(@)_ZANVIL_LOCAL_DENIED:#$hash}")
}

# Pile voulue dans reply : les .zanvil.local entre $HOME (exclu) et le dossier courant,
# ordonnes racine -> feuille.
_zanvil_local_stack() {
    reply=()
    local dir="${PWD:A}" home="${HOME:A}"
    while [[ "$dir" != "$home" && "$dir" != / ]]; do
        [[ -f "$dir/.zanvil.local" ]] && reply=("$dir/.zanvil.local" "${reply[@]}")
        dir="${dir:h}"
    done
}

# Contenu autorise dans REPLY, ou code 1 si refuse. Lu une seule fois : ce qui est montre,
# hashe et execute est le meme texte, meme si le fichier change entre-temps (git checkout).
_zanvil_local_approve() {
    local file="$1" content hash response
    _zanvil_local_read "$file"; content=$REPLY
    if ! _zanvil_local_is_trusted "$content"; then
        hash=$(_zanvil_local_hash "$content")
        (( ${_ZANVIL_LOCAL_DENIED[(Ie)$hash]} )) && return 1
        echo ""
        echo -e "${_ui_yellow}[zanvil]${_ui_nc} Fichier .zanvil.local detecte dans ${_ui_bold}${file:h}${_ui_nc}"
        # En entier : autoriser apres n'en avoir vu qu'un extrait laisserait passer la suite.
        print -r -- "$content" | sed 's/^/    /'
        echo ""
        read -q "response?Autoriser ce fichier ? [y/N] "
        echo ""
        if [[ "$response" != "y" ]]; then
            _ZANVIL_LOCAL_DENIED+=("$hash")
            echo -e "${_ui_dim}Ignore. Lancez 'zanvil-trust ${file}' pour autoriser plus tard.${_ui_nc}"
            return 1
        fi
        _zanvil_local_trust "$file" "$content"
    fi
    REPLY=$content
}

# Applique la pile donnee (racine -> feuille) ; un refus coupe l'heritage en dessous.
# Variables locales prefixees : le code evalue ne doit pas pouvoir ecraser celles de la boucle.
_zanvil_local_apply() {
    local -A _zl_before
    local -a _zl_funcs_before=(${(k)functions}) _zl_applied=()
    local _zl_n _zl_file
    for _zl_n in ${(k)parameters[(R)*export*]}; do _zl_before[$_zl_n]=${(P)_zl_n}; done

    for _zl_file in "$@"; do
        _zanvil_local_approve "$_zl_file" || break
        eval "$REPLY"
        _zl_applied+=("$_zl_file")
    done

    _ZANVIL_LOCAL_SAVED=()
    for _zl_n in ${(k)parameters[(R)*export*]}; do
        if (( ! ${+_zl_before[$_zl_n]} )); then
            _ZANVIL_LOCAL_SAVED[$_zl_n]=-
        elif [[ "${_zl_before[$_zl_n]}" != "${(P)_zl_n}" ]]; then
            _ZANVIL_LOCAL_SAVED[$_zl_n]="+${_zl_before[$_zl_n]}"
        fi
    done
    # Variables que la pile a retirees.
    for _zl_n in ${(k)_zl_before}; do
        [[ ${parameters[$_zl_n]} == *export* ]] || _ZANVIL_LOCAL_SAVED[$_zl_n]="+${_zl_before[$_zl_n]}"
    done
    _ZANVIL_LOCAL_FUNCS=(${(k)functions:|_zl_funcs_before})
    _ZANVIL_LOCAL_FILES=("${_zl_applied[@]}")

    (( ${#_zl_applied} )) || return 0
    local msg="${_zl_applied[-1]}"
    (( ${#_zl_applied} > 1 )) && msg+=" (+$(( ${#_zl_applied} - 1 )) herite(s))"
    echo -e "${_ui_green}[zanvil]${_ui_nc} Charge: ${_ui_dim}${msg}${_ui_nc}"
}

# Restaure l'environnement d'avant la pile : une variable modifiee (PATH) reprend sa valeur,
# une variable ajoutee est retiree, une fonction definie est supprimee.
_zanvil_local_unload() {
    (( ${#_ZANVIL_LOCAL_FILES} )) || return 0
    local n
    for n in ${(k)_ZANVIL_LOCAL_SAVED}; do
        if [[ ${_ZANVIL_LOCAL_SAVED[$n]} == - ]]; then
            unset "$n" 2>/dev/null
        else
            export "$n=${_ZANVIL_LOCAL_SAVED[$n]#+}"
        fi
    done
    for n in "${_ZANVIL_LOCAL_FUNCS[@]}"; do unfunction "$n" 2>/dev/null; done
    [[ "$1" == quiet ]] || echo -e "${_ui_dim}[zanvil] Decharge: ${#_ZANVIL_LOCAL_FILES} fichier(s) .zanvil.local${_ui_nc}"
    _ZANVIL_LOCAL_FILES=() _ZANVIL_LOCAL_FUNCS=()
    _ZANVIL_LOCAL_SAVED=()
}

# Hook chpwd : la pile voulue differe de celle appliquee -> decharge puis recharge la chaine.
# Un sous-dossier sans fichier garde donc la pile de son parent ; un dossier voisin au nom
# proche (app-prod a cote de app) n'en herite pas.
_zanvil_local_chpwd() {
    local -a reply
    _zanvil_local_stack
    [[ "${(pj:\0:)reply}" == "${(pj:\0:)_ZANVIL_LOCAL_FILES}" ]] && return 0
    _zanvil_local_unload
    (( ${#reply} )) && _zanvil_local_apply "${reply[@]}"
    return 0
}

# Commande manuelle : autorise un fichier (defaut : celui du dossier courant) et recharge.
zanvil-trust() {
    local file="${1:-$PWD/.zanvil.local}"
    if [[ ! -f "$file" ]]; then
        _ui_msg_fail "Aucun .zanvil.local : $file"
        return 1
    fi
    file=${file:a}
    _zanvil_local_read "$file"
    _zanvil_local_trust "$file" "$REPLY" || return 1
    _ui_msg_ok "Fichier autorise: $file"
    # Pile identique (fichier deja charge puis modifie) : sans ce dechargement, rien ne bougerait.
    _zanvil_local_unload quiet
    _zanvil_local_chpwd
}
