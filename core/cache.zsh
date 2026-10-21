# ==============================================================================
# Cache des scripts generes (init, completions)
# ==============================================================================
# Lancer un binaire coute 50 a 800 ms sous un EDR (SentinelOne) : on garde sa
# sortie dans un fichier, regenere seulement quand le binaire change.
# ==============================================================================

# Usage : _zanvil_cached <nom> <commande> [args...] && source "$REPLY"
# Le source reste chez l'appelant : depuis une fonction, les typeset du script
# deviendraient locaux.
_zanvil_cached() {
    local name="$1" bin="${commands[$2]}"
    shift
    [[ -z "$bin" ]] && return 1
    REPLY="${XDG_CACHE_HOME:-$HOME/.cache}/zanvil/$name.zsh"
    # Le chemin resolu change a chaque upgrade brew (Cellar/<version>)
    local stamp="# ${bin:A}" first=
    [[ -s "$REPLY" ]] && read -r first < "$REPLY"
    [[ "$first" == "$stamp" && ! "$bin" -nt "$REPLY" ]] && return 0

    [[ -d "${REPLY:h}" ]] || mkdir -p "${REPLY:h}"
    if { print -r -- "$stamp"; "$@" 2>/dev/null } >| "$REPLY.$$"; then
        mv -f "$REPLY.$$" "$REPLY"
    else
        rm -f "$REPLY.$$"
        return 1
    fi
}
