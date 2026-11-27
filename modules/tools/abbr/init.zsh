# ==============================================================================
# zsh-abbr — abreviations a la fish (la commande complete s'affiche avant de partir)
# Guard: ZANVIL_MODULE_ABBR=true dans config.zsh
# Le plugin vient de ZANVIL_PLUGINS (olets/zsh-abbr). Ce module ajoute zanvil-abbr, qui
# reprend les alias existants en abreviations.
# ==============================================================================

[[ "${ZANVIL_MODULE_ABBR:-}" != "true" ]] && return 0

# Usage : zanvil-abbr import [--apply]
# Seuls les alias de plusieurs mots deviennent des abreviations (gco='git checkout') : un
# remplacement de commande (cat=bat, cd=z, ls=eza) s'afficherait a chaque espace pour rien.
# Sans --apply, liste ce qui serait ajoute.
zanvil-abbr() {
    case "$1" in
        import) ;;
        -h|--help|help|"") echo "Usage: zanvil-abbr import [--apply]"; [[ -n "$1" ]]; return ;;
        *) _ui_msg_fail "Action inconnue : $1"; return 1 ;;
    esac
    local apply=false name value n=0
    [[ "$2" == --apply ]] && apply=true
    if $apply && ! (( $+functions[abbr] )); then
        _ui_msg_fail "zsh-abbr n'est pas charge (ajoutez olets/zsh-abbr a ZANVIL_PLUGINS)"
        return 1
    fi
    for name value in "${(@kv)aliases}"; do
        [[ "$value" == *" "* ]] || continue
        if $apply; then
            abbr add --quieter -- "$name=$value" 2>/dev/null && (( n++ ))
        else
            printf "  %-14s %s\n" "$name" "$value"; (( n++ ))
        fi
    done
    if $apply; then
        _ui_msg_ok "$n abreviation(s) ajoutee(s) (deja presentes ignorees)"
    else
        _ui_msg_info "$n alias de plusieurs mots ; zanvil-abbr import --apply pour les ajouter"
    fi
}
