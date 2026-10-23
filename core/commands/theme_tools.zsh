# ==============================================================================
# core/commands/theme_tools.zsh — Generateurs de theme par outil
# ==============================================================================
# Regle : « pointeur fixe, contenu echange ». Chaque outil pointe une fois vers un emplacement
# fixe ; zanvil-theme ne reecrit que le contenu (jamais une config versionnee).
# Un generateur = _zanvil_theme_tool_<outil> <theme>, appele si <outil> est installe.
# ==============================================================================

# Appelle chaque generateur dont l'outil est dans le PATH ; un outil absent est ignore.
_zanvil_theme_tools() {
    local f tool
    for f in ${(ok)functions[(I)_zanvil_theme_tool_*]}; do
        tool="${f#_zanvil_theme_tool_}"
        (( $+commands[$tool] )) && "$f" "$1"
    done
    return 0
}

# Affiche une ligne cle=RRGGBB par couleur de la palette du theme (repli : tokyo-light).
# Sous-shell : les _ui_* de la session ne bougent pas (meme technique que _zanvil_theme_colors).
_zanvil_theme_palette_hex() {
    local palette="$ZANVIL_DIR/config/themes/$1/palette.zsh"
    local -A fb=( bg e1e2e7 fg 383e5d dim 969cb4 blue 2e7de9 red f52a65 green 587539 yellow 8c6c3e magenta 9854f1 cyan 007197 )
    local out k v w
    out=$(
        unset _ui_white _ui_dim _ui_blue _ui_red _ui_green _ui_yellow _ui_magenta _ui_cyan _theme_bg
        [[ -f "$palette" ]] && source "$palette"
        print -r -- "bg=${_theme_bg#\#}" "fg=$(_zanvil_theme_hex "$_ui_white")" "dim=$(_zanvil_theme_hex "$_ui_dim")" \
            "blue=$(_zanvil_theme_hex "$_ui_blue")" "red=$(_zanvil_theme_hex "$_ui_red")" \
            "green=$(_zanvil_theme_hex "$_ui_green")" "yellow=$(_zanvil_theme_hex "$_ui_yellow")" \
            "magenta=$(_zanvil_theme_hex "$_ui_magenta")" "cyan=$(_zanvil_theme_hex "$_ui_cyan")"
    )
    for k in bg fg dim blue red green yellow magenta cyan; do
        v=""; for w in ${=out}; do [[ "$w" == "$k="* ]] && v="${w#*=}"; done
        [[ "$v" =~ '^[0-9a-fA-F]{6}$' ]] || v="${fb[$k]}"
        print -r -- "$k=$v"
    done
}

# k9s : skin du theme copie en skins/zanvil.yaml (K9S_SKIN=zanvil, constant, exporte par ui.zsh).
_zanvil_theme_tool_k9s() {
    [[ "${ZANVIL_K9S_AUTO_THEME:-true}" == "false" ]] && return 0
    local src="$ZANVIL_DIR/config/themes/$1/k9s-skin.yaml" dir="$(_k9s_config_dir)/skins"
    mkdir -p "$dir" || return 0
    if [[ -f "$src" ]]; then
        cp "$src" "$dir/zanvil.yaml"
        return 0
    fi
    # Theme sans skin : repli genere depuis la palette
    local -A p
    p=( ${(s:=:)${(f)"$(_zanvil_theme_palette_hex "$1")"}} )
    local k; for k in ${(k)p}; do p[$k]="'#${p[$k]}'"; done
    cat > "$dir/zanvil.yaml" <<YAML
# Genere par zanvil-theme depuis la palette de '$1'
k9s:
  body: {fgColor: $p[fg], bgColor: $p[bg], logoColor: $p[blue]}
  prompt: {fgColor: $p[fg], bgColor: $p[bg], suggestColor: $p[cyan]}
  info: {fgColor: $p[blue], bgColor: $p[bg]}
  dialog: {fgColor: $p[fg], bgColor: $p[bg], buttonFgColor: $p[bg], buttonBgColor: $p[blue], buttonFocusFgColor: $p[bg], buttonFocusBgColor: $p[green], labelFgColor: $p[yellow], fieldFgColor: $p[fg]}
  frame:
    border: {fgColor: $p[dim], focusColor: $p[blue]}
    menu: {fgColor: $p[fg], keyColor: $p[cyan], numKeyColor: $p[red]}
    crumbs: {fgColor: $p[bg], bgColor: $p[dim], activeColor: $p[blue]}
    status: {newColor: $p[blue], modifyColor: $p[yellow], addColor: $p[green], errorColor: $p[red], highlightColor: $p[cyan], killColor: $p[dim], completedColor: $p[dim]}
    title: {fgColor: $p[fg], bgColor: $p[bg], highlightColor: $p[cyan], counterColor: $p[blue], filterColor: $p[green]}
  views:
    table:
      fgColor: $p[fg]
      bgColor: $p[bg]
      cursorFgColor: $p[bg]
      cursorBgColor: $p[blue]
      header: {fgColor: $p[yellow], bgColor: $p[bg], sorterColor: $p[cyan]}
YAML
}
