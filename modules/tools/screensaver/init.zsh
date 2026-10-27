# ==============================================================================
# screensaver — bonsai (cbonsai) aux couleurs du theme zanvil
# Guard: ZANVIL_MODULE_SCREENSAVER=true dans config.zsh
# ==============================================================================

[[ "${ZANVIL_MODULE_SCREENSAVER:-}" != "true" ]] && return 0
command -v cbonsai &>/dev/null || return 0

# Indice 256 couleurs le plus proche d'une couleur RRGGBB (cube 6x6x6 de xterm).
_zsaver_256() {
    local -a lv=(0 95 135 175 215 255)
    local i c best d n idx=16 m=36
    for c in $((16#${1[1,2]})) $((16#${1[3,4]})) $((16#${1[5,6]})); do
        best=0 d=999
        for i in {1..6}; do
            n=$(( c - lv[i] )); (( n < 0 )) && n=$(( -n ))
            (( n < d )) && { d=$n; best=$(( i - 1 )); }
        done
        (( idx += best * m, m /= 6 ))
    done
    print -r -- $idx
}

# zsaver [options cbonsai] : bonsai en mode economiseur (une touche pour quitter), couleurs du theme actif.
zsaver() {
    local cur="" l
    local -A p
    [[ -f "$ZANVIL_DIR/.current_theme" ]] && cur=$(<"$ZANVIL_DIR/.current_theme")
    for l in ${(f)"$(_zanvil_theme_palette_hex "$cur")"}; do p[${l%%=*}]=${l#*=}; done
    # Feuilles sombres, bois sombre, feuilles claires, bois clair
    cbonsai -S -k "$(_zsaver_256 $p[green]),$(_zsaver_256 $p[yellow]),$(_zsaver_256 $p[cyan]),$(_zsaver_256 $p[dim])" "$@"
}

# ZANVIL_SCREENSAVER_IDLE=<secondes> : zsaver apres ce delai sans frappe a l'invite. Un seul a la fois :
# chaque onglet inactif le declencherait sinon.
if [[ -o interactive && "${ZANVIL_SCREENSAVER_IDLE:-}" == <-> ]] && (( ZANVIL_SCREENSAVER_IDLE > 0 )); then
    TMOUT=$ZANVIL_SCREENSAVER_IDLE
    TRAPALRM() {
        pgrep -qx cbonsai && return 0
        zsaver
        zle && zle reset-prompt
    }
fi
