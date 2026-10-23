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
        cp "$src" "$dir/zanvil.yaml" && export K9S_SKIN=zanvil
        return 0
    fi
    # Theme sans skin : repli genere depuis la palette
    local -A p
    local l; for l in ${(f)"$(_zanvil_theme_palette_hex "$1")"}; do p[${l%%=*}]=${l#*=}; done
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
    export K9S_SKIN=zanvil
}

# Affiche light|dark : _theme_mode de la palette, sinon deduit de la luminance de _theme_bg.
_zanvil_theme_mode() {
    local m bg r g b
    m=$(
        unset _theme_mode _theme_bg
        [[ -f "$ZANVIL_DIR/config/themes/$1/palette.zsh" ]] && source "$ZANVIL_DIR/config/themes/$1/palette.zsh"
        print -r -- "${_theme_mode:-}|${_theme_bg#\#}"
    )
    [[ "${m%%|*}" == (light|dark) ]] && { print -r -- "${m%%|*}"; return 0; }
    bg="${m#*|}"; [[ "$bg" =~ '^[0-9a-fA-F]{6}$' ]] || bg=e1e2e7
    r=$((16#${bg[1,2]})); g=$((16#${bg[3,4]})); b=$((16#${bg[5,6]}))
    (( (299*r + 587*g + 114*b) / 1000 > 128 )) && print light || print dark
}

# bat : paire native clair/sombre (BAT_THEME_LIGHT/DARK exportes par ui.zsh). Les .tmTheme vendus
# sont copies seulement s'ils different, et le cache n'est reconstruit que dans ce cas.
_zanvil_theme_tool_bat() {
    local dir f changed=0
    local -a copied
    dir="$(bat --config-dir 2>/dev/null)"
    [[ -n "$dir" ]] || return 0
    mkdir -p "$dir/themes" || return 0
    for f in "$ZANVIL_DIR"/config/bat/themes/*.tmTheme(N); do
        cmp -s "$f" "$dir/themes/${f:t}" && continue
        cp "$f" "$dir/themes/${f:t}" && changed=1 && copied+=( "$dir/themes/${f:t}" )
    done
    if (( changed )) && ! bat cache --build >/dev/null 2>&1; then
        # Echec : on retire les copies pour retenter au prochain passage, sans export
        rm -f "${copied[@]}"
        _ui_msg_warn "bat cache --build a echoue : themes bat non actives (nouvel essai au prochain zanvil-theme)"
        return 0
    fi
    export BAT_THEME_LIGHT=tokyonight_day BAT_THEME_DARK=tokyonight_night
    return 0
}

# delta : fichier a inclure depuis la config du VCS ([include] path = ~/.config/zanvil/theme/delta.gitconfig).
_zanvil_theme_tool_delta() {
    local dir="$(_zanvil_theme_dir)" st=tokyonight_night k c o i ch bc
    [[ "$(_zanvil_theme_mode "$1")" == light ]] && st=tokyonight_day
    local -A p
    local l; for l in ${(f)"$(_zanvil_theme_palette_hex "$1")"}; do p[${l%%=*}]=${l#*=}; done
    # 20 % de la couleur sur le fond pour les lignes ajoutees/supprimees
    for k in red green; do
        o=""
        for i in 1 3 5; do
            ch=$((16#${p[$k][i,i+1]})); bc=$((16#${p[bg][i,i+1]}))
            o+=$(printf '%02x' $(( (ch*2 + bc*8) / 10 )))
        done
        p[${k}bg]=$o
    done
    mkdir -p "$dir" || return 0
    cat > "$dir/delta.gitconfig" <<CFG
# Genere par zanvil-theme depuis la palette de '$1'
[delta]
    syntax-theme = $st
    minus-style = syntax "#$p[redbg]"
    minus-emph-style = syntax "#$p[red]" bold
    plus-style = syntax "#$p[greenbg]"
    plus-emph-style = syntax "#$p[green]" bold
    line-numbers-minus-style = "#$p[red]"
    line-numbers-plus-style = "#$p[green]"
    line-numbers-zero-style = "#$p[dim]"
    file-style = "#$p[blue]" bold
    hunk-header-style = "#$p[cyan]"
CFG
}

# Melange 20 % de $1 sur $2 (RRGGBB) : fond de ligne selectionnee.
_zanvil_theme_blend() {
    local o="" i
    for i in 1 3 5; do o+=$(printf '%02x' $(( ($((16#${1[i,i+1]}))*2 + $((16#${2[i,i+1]}))*8) / 10 ))); done
    print -r -- "$o"
}

# Charge la palette dans le tableau associatif $p de l'appelant.
_zanvil_theme_load_p() {
    local l; for l in ${(f)"$(_zanvil_theme_palette_hex "$1")"}; do p[${l%%=*}]=${l#*=}; done
}

# fzf : FZF_DEFAULT_OPTS_FILE (constant) ; fzf le combine avec FZF_DEFAULT_OPTS, qui reste prioritaire.
_zanvil_theme_tool_fzf() {
    local dir="$(_zanvil_theme_dir)"
    local -A p; _zanvil_theme_load_p "$1"
    mkdir -p "$dir" || return 0
    print -r -- "--color=fg:#$p[fg],bg:-1,hl:#$p[blue],fg+:#$p[fg],bg+:#$(_zanvil_theme_blend $p[blue] $p[bg]),hl+:#$p[cyan],info:#$p[yellow],prompt:#$p[blue],pointer:#$p[magenta],marker:#$p[green],spinner:#$p[magenta],header:#$p[dim],border:#$p[dim]" > "$dir/fzf"
    _zanvil_theme_exports
}

# eza : theme.yml dans EZA_CONFIG_DIR (constant ; eza >= 0.20).
_zanvil_theme_tool_eza() {
    local dir="$(_zanvil_theme_dir)/eza"
    if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/eza/theme.yml" ]]; then
        # Theme eza de l'utilisateur : on ne le masque pas (avertissement une seule fois)
        if [[ ! -f "$dir/.user-theme-notice" ]]; then
            mkdir -p "$dir" && : > "$dir/.user-theme-notice"
            _ui_msg_warn "theme eza utilisateur conserve (${XDG_CONFIG_HOME:-$HOME/.config}/eza/theme.yml) : zanvil n'ecrit pas de theme eza"
        fi
        return 0
    fi
    local -A p; _zanvil_theme_load_p "$1"
    local k; for k in ${(k)p}; do p[$k]="{foreground: \"#${p[$k]}\"}"; done
    mkdir -p "$dir" || return 0
    cat > "$dir/theme.yml" <<YAML
# Genere par zanvil-theme depuis la palette de '$1'
colourful: true
filekinds:
  normal: $p[fg]
  directory: $p[blue]
  symlink: $p[cyan]
  pipe: $p[yellow]
  block_device: $p[yellow]
  char_device: $p[yellow]
  socket: $p[red]
  special: $p[magenta]
  executable: $p[green]
  mount_point: $p[blue]
perms:
  user_read: $p[yellow]
  user_write: $p[red]
  user_execute_file: $p[green]
  user_execute_other: $p[green]
  group_read: $p[yellow]
  group_write: $p[red]
  group_execute: $p[green]
  other_read: $p[yellow]
  other_write: $p[red]
  other_execute: $p[green]
size:
  major: $p[green]
  minor: $p[cyan]
  number_byte: $p[green]
  number_kilo: $p[green]
  number_mega: $p[green]
  number_giga: $p[green]
  number_huge: $p[green]
  unit_byte: $p[dim]
  unit_kilo: $p[dim]
  unit_mega: $p[dim]
  unit_giga: $p[dim]
  unit_huge: $p[dim]
users:
  user_you: $p[yellow]
  user_root: $p[red]
  user_other: $p[magenta]
  group_yours: $p[yellow]
  group_other: $p[dim]
  group_root: $p[red]
links:
  normal: $p[cyan]
  multi_link_file: $p[red]
git:
  new: $p[green]
  modified: $p[yellow]
  deleted: $p[red]
  renamed: $p[cyan]
  typechange: $p[magenta]
  ignored: $p[dim]
  conflicted: $p[red]
date: $p[blue]
punctuation: $p[dim]
YAML
    _zanvil_theme_exports
}

# lazygit : gui.theme ; LG_CONFIG_FILE (constant) liste la config de l'utilisateur puis ce fichier.
_zanvil_theme_tool_lazygit() {
    local dir="$(_zanvil_theme_dir)"
    local -A p; _zanvil_theme_load_p "$1"
    local sel="$(_zanvil_theme_blend $p[blue] $p[bg])"
    mkdir -p "$dir" || return 0
    cat > "$dir/lazygit.yml" <<YAML
# Genere par zanvil-theme depuis la palette de '$1'
gui:
  theme:
    activeBorderColor: ['#$p[blue]', bold]
    inactiveBorderColor: ['#$p[dim]']
    searchingActiveBorderColor: ['#$p[yellow]', bold]
    optionsTextColor: ['#$p[blue]']
    selectedLineBgColor: ['#$sel']
    inactiveViewSelectedLineBgColor: ['#$sel']
    cherryPickedCommitFgColor: ['#$p[blue]']
    cherryPickedCommitBgColor: ['#$sel']
    markedBaseCommitFgColor: ['#$p[yellow]']
    unstagedChangesColor: ['#$p[red]']
    defaultFgColor: ['#$p[fg]']
YAML
    _zanvil_theme_exports
}
