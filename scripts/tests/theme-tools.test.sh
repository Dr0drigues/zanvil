#!/usr/bin/env bash
# Verifie les generateurs de theme par outil (core/commands/theme_tools.zsh) : k9s a nom fixe,
# palette. Faux k9s, HOME et XDG_CONFIG_HOME temporaires.
# Usage : scripts/tests/theme-tools.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"

TEST_TMPDIR=$(mktemp -d) || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
echo 0 > "$TEST_TMPDIR/pass"
echo 0 > "$TEST_TMPDIR/fail"

assert_equals() {
    local label="$1" needle="$2" out
    out=$(cat)
    if [[ "$out" == "$needle" ]]; then
        printf '  ok   %s\n' "$label"
        echo $(($(cat "$TEST_TMPDIR/pass") + 1)) > "$TEST_TMPDIR/pass"
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        echo $(($(cat "$TEST_TMPDIR/fail") + 1)) > "$TEST_TMPDIR/fail"
    fi
}

Z="$ROOT"
H="$TEST_TMPDIR/home"
X="$TEST_TMPDIR/xdg"
BIN="$TEST_TMPDIR/bin"
NOBIN="$TEST_TMPDIR/nobin"
mkdir -p "$BIN" "$NOBIN"
printf '#!/bin/sh\nexit 0\n' > "$BIN/k9s"
printf '#!/bin/sh\nexit 0\n' > "$BIN/delta"
# Faux bat : --config-dir -> $XDG_CONFIG_HOME/bat ; toute autre commande est journalisee
cat > "$BIN/bat" <<'FAKE'
#!/bin/sh
[ "$1" = "--config-dir" ] && { echo "$XDG_CONFIG_HOME/bat"; exit 0; }
echo "$*" >> "$BATLOG"
[ -n "$BATFAIL" ] && [ "$1 $2" = "cache --build" ] && exit 1
exit 0
FAKE
# Faux tmux : has-session reussit si TMUXRUN ; les autres commandes sont journalisees
cat > "$BIN/tmux" <<'FAKE'
#!/bin/sh
[ "$1" = has-session ] && { [ -n "$TMUXRUN" ]; exit $?; }
echo "$*" >> "$TMUXLOG"
FAKE
chmod +x "$BIN/k9s" "$BIN/delta" "$BIN/bat" "$BIN/tmux"
export TMUXLOG="$TEST_TMPDIR/tmux.log"
export BATLOG="$TEST_TMPDIR/bat.log"

# Garde : les vrais k9s, bat et delta ne doivent pas etre atteignables depuis le PATH minimal du test
for tool in fzf eza lazygit btop atuin posting lazydocker; do printf '#!/bin/sh\nexit 0\n' > "$BIN/$tool"; chmod +x "$BIN/$tool"; done
for tool in k9s bat delta fzf eza lazygit btop atuin posting lazydocker tmux; do
    if PATH="$NOBIN:/usr/bin:/bin" command -v $tool >/dev/null; then
        echo "$tool reel accessible depuis le PATH de test" >&2; exit 2
    fi
done

# Les sorties de zt sont des pipes : on simule un terminal (voir _zanvil_theme_visible)
export ZANVIL_THEME_TTY=1

# zt <commande> [setup] [PATH] : HOME et XDG neufs ; PATH = faux bin (defaut) ou NOBIN
zt() {
    rm -rf "$H" "$X"; mkdir -p "$H/.config" "$X"
    eval "${2:-}"
    env -u K9S_SKIN -u FZF_DEFAULT_OPTS_FILE -u EZA_CONFIG_DIR -u LG_CONFIG_FILE HOME="$H" XDG_CONFIG_HOME="$X" ZANVIL_DIR="$Z" PATH="${3:-$BIN}:/usr/bin:/bin" zsh -f -c "
        source '$Z/core/ui.zsh'
        source '$Z/core/commands/theme.zsh'
        SK=\"\$(_k9s_config_dir)/skins/zanvil.yaml\"
        $1
    " 2>&1
}

echo "k9s : skin a nom fixe"
for t in tokyo-night-pro tokyo-light-pro; do
    zt "_zanvil_theme_tools $t; cmp -s \"\$SK\" '$Z/config/themes/$t/k9s-skin.yaml' && echo egal" \
        | assert_equals "zanvil.yaml egal au skin de $t" "egal"
done
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-light-pro; echo "${K9S_SKIN:-vide}"; ls "$(dirname "$SK")"' \
    | assert_equals "K9S_SKIN reste zanvil, un seul fichier skin" "$(printf 'zanvil\nzanvil.yaml')"
zt '_zanvil_theme_tools minimal; grep -c "^k9s:" "$SK"; grep -c "#1a1b26" "$SK"; grep -c "#e1e2e7" "$SK" | sed "s/^[1-9].*/ok/"' \
    | assert_equals "theme sans skin : repli genere (palette de repli)" "$(printf '1\n0\nok')"
zt '_zanvil_theme_tools forge; grep -c "^k9s:" "$SK"' \
    | assert_equals "theme plat a palette : repli genere" "1"
zt '_zanvil_theme_tools minimal; grep -c "logoColor: .#2e7de9." "$SK"' \
    | assert_equals "repli k9s : couleurs de la palette (pas decalees)" "1"
zt '_zanvil_theme_tools tokyo-night-pro; ls "$(dirname "$SK")" 2>/dev/null | wc -l | tr -d " "' "" "$NOBIN" \
    | assert_equals "k9s absent : aucun fichier" "0"
zt 'ZANVIL_K9S_AUTO_THEME=false _zanvil_theme_tools tokyo-night-pro; ls "$(dirname "$SK")" 2>/dev/null | wc -l | tr -d " "' \
    | assert_equals "ZANVIL_K9S_AUTO_THEME=false : aucun fichier" "0"
zt 'unset K9S_SKIN; _zanvil_theme_tool_k9s tokyo-night-pro; echo "${K9S_SKIN:-vide}"' \
    | assert_equals "le generateur exporte K9S_SKIN=zanvil (skin du theme)" "zanvil"
zt 'unset K9S_SKIN; _zanvil_theme_tool_k9s minimal; echo "${K9S_SKIN:-vide}"' \
    | assert_equals "le generateur exporte K9S_SKIN=zanvil (skin de repli)" "zanvil"
zt 'echo "${K9S_SKIN:-vide}"' "" "$NOBIN" | assert_equals "K9S_SKIN non exporte sans k9s" "vide"
zt 'ZANVIL_K9S_AUTO_THEME=false; unset K9S_SKIN; source "$ZANVIL_DIR/core/ui.zsh"; echo "${K9S_SKIN:-vide}"' \
    | assert_equals "K9S_SKIN non exporte avec l'opt-out" "vide"

echo "_zanvil_theme_palette_hex"
zt '_zanvil_theme_palette_hex tokyo-night-pro | grep -E "^(bg|blue)="' \
    | assert_equals "bg et blue de tokyo-night-pro" "$(printf 'bg=1a1b26\nblue=7aa2f7')"
zt '_zanvil_theme_palette_hex minimal | wc -l | tr -d " "; _zanvil_theme_palette_hex minimal | grep "^bg="' \
    | assert_equals "theme plat : 9 cles, repli" "$(printf '9\nbg=e1e2e7')"

echo "bat : paire native"
zt 'rm -f "$BATLOG"; _zanvil_theme_tools tokyo-night-pro; ls "$XDG_CONFIG_HOME/bat/themes"; cat "$BATLOG"' \
    | assert_equals "premier passage : themes copies, cache --build une fois" "$(printf 'tokyonight_day.tmTheme\ntokyonight_night.tmTheme\ncache --build')"
zt 'rm -f "$BATLOG"; _zanvil_theme_tools tokyo-night-pro; rm "$BATLOG"; _zanvil_theme_tools tokyo-night-pro; cat "$BATLOG" 2>/dev/null; echo fin' \
    | assert_equals "second passage identique : aucun cache --build" "fin"
zt 'rm -f "$BATLOG"; _zanvil_theme_tools tokyo-night-pro; echo x >> "$XDG_CONFIG_HOME/bat/themes/tokyonight_day.tmTheme"; rm "$BATLOG"; _zanvil_theme_tools tokyo-night-pro; cat "$BATLOG"; cmp "$XDG_CONFIG_HOME/bat/themes/tokyonight_day.tmTheme" "$ZANVIL_DIR/config/bat/themes/tokyonight_day.tmTheme" && echo egal' \
    | assert_equals "fichier modifie : recopie et cache --build" "$(printf 'cache --build\negal')"
zt '_zanvil_theme_tools tokyo-night-pro; ls "$XDG_CONFIG_HOME/bat" 2>/dev/null | wc -l | tr -d " "' "" "$NOBIN" \
    | assert_equals "bat absent : rien" "0"
MK='mkdir -p "$X/bat/themes"; touch "$X/bat/themes/tokyonight_day.tmTheme" "$X/bat/themes/tokyonight_night.tmTheme"'
zt 'echo "$BAT_THEME_LIGHT $BAT_THEME_DARK ${BAT_THEME:-vide}"' "$MK" \
    | assert_equals "themes installes : exports constants au demarrage, pas de BAT_THEME" "tokyonight_day tokyonight_night vide"
zt 'echo "${BAT_THEME_LIGHT:-vide}"' \
    | assert_equals "themes absents : pas d'export au demarrage" "vide"
zt 'echo "$BAT_THEME_LIGHT"' 'mkdir -p "$TEST_TMPDIR/bcd/themes"; touch "$TEST_TMPDIR/bcd/themes/tokyonight_day.tmTheme" "$TEST_TMPDIR/bcd/themes/tokyonight_night.tmTheme"; export BAT_CONFIG_DIR="$TEST_TMPDIR/bcd"' \
    | assert_equals "BAT_CONFIG_DIR respecte" "tokyonight_day"
unset BAT_CONFIG_DIR
zt '_zanvil_theme_tools tokyo-night-pro; echo "$BAT_THEME_LIGHT $BAT_THEME_DARK"' \
    | assert_equals "le generateur exporte dans le shell courant" "tokyonight_day tokyonight_night"
BATFAIL=1 zt 'unset BAT_THEME_LIGHT; _zanvil_theme_tools tokyo-night-pro >"$XDG_CONFIG_HOME/o.txt" 2>&1; grep -c "cache --build a echoue" "$XDG_CONFIG_HOME/o.txt"; echo "${BAT_THEME_LIGHT:-vide}"; ls "$XDG_CONFIG_HOME/bat/themes" | wc -l | tr -d " "' \
    | assert_equals "cache --build echoue : avertissement, pas d'export, copies retirees" "$(printf '1\nvide\n0')"
zt 'echo "${BAT_THEME_LIGHT:-vide}"' "$MK" "$NOBIN" | assert_equals "pas d'export sans bat" "vide"

echo "delta"
for t in tokyo-night-pro:tokyonight_night tokyo-light-pro:tokyonight_day forge:tokyonight_night plain:tokyonight_day minimal:tokyonight_day; do
    zt "_zanvil_theme_tools ${t%%:*}; grep syntax-theme \"\$XDG_CONFIG_HOME/zanvil/theme/delta.gitconfig\"" \
        | assert_equals "syntax-theme de ${t%%:*}" "    syntax-theme = ${t##*:}"
done
zt '_zanvil_theme_tools tokyo-night-pro; grep -E "^    (minus|plus)-style" "$XDG_CONFIG_HOME/zanvil/theme/delta.gitconfig"' \
    | assert_equals "fonds de diff derives de la palette" "$(printf '    minus-style = syntax "#462d3a"\n    plus-style = syntax "#343e33"')"
zt '_zanvil_theme_tools tokyo-night-pro' "" "$NOBIN" >/dev/null
zt '_zanvil_theme_tools tokyo-night-pro; ls "$XDG_CONFIG_HOME/zanvil/theme" 2>/dev/null | grep -c delta' "" "$NOBIN" \
    | assert_equals "delta absent : rien" "0"
zt '_zanvil_theme_mode tokyo-light-pro; _zanvil_theme_mode forge; _zanvil_theme_mode minimal' \
    | assert_equals "_theme_mode et repli par luminance" "$(printf 'light\ndark\nlight')"

echo "fzf, eza, lazygit"
TD='$XDG_CONFIG_HOME/zanvil/theme'
# YAML : parse si PyYAML est utilisable, sinon controle de structure (cles de tete + pas de ligne vide de valeur)
YOK="$TEST_TMPDIR/yamlok"
cat > "$YOK" <<'SH'
#!/bin/bash
if python3 -c 'import yaml' 2>/dev/null; then python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$1" && echo ok
else grep -q '^[a-z]*:' "$1" && ! grep -qvE '^#|^ *[A-Za-z_]+:( .+)?$' "$1" && echo ok; fi
SH
chmod +x "$YOK"
FZFRE='^--color=fg:#[0-9a-f]{6},bg:-1(,[a-z+]+:#[0-9a-f]{6}){11}$'
for t in tokyo-night-pro minimal; do
    zt "_zanvil_theme_tools $t; [[ \"\$(<$TD/fzf)\" =~ '$FZFRE' ]] && echo ok" | assert_equals "fzf ($t) : --color bien forme" ok
    zt "_zanvil_theme_tools $t; [[ \"\$(<$TD/eza/theme.yml)\" == *'directory: {foreground: \"#'* ]] && $YOK $TD/eza/theme.yml" | assert_equals "eza ($t) : theme.yml valide" ok
    zt "_zanvil_theme_tools $t; $YOK $TD/lazygit.yml; grep -c \"^    [a-zA-Z]*Color: \['#[0-9a-f]\{6\}'\" $TD/lazygit.yml | sed 's/^[1-9][0-9]*\$/couleurs/'" \
        | assert_equals "lazygit ($t) : yaml valide, couleurs hex" "$(printf 'ok\ncouleurs')"
done
zt "_zanvil_theme_tools tokyo-night-pro; grep -o 'fg:#[0-9a-f]*,bg:-1,hl:#[0-9a-f]*' $TD/fzf; grep 'directory:' $TD/eza/theme.yml; grep activeBorderColor $TD/lazygit.yml | head -1" \
    | assert_equals "tokyo-night-pro : couleurs de la palette" "$(printf 'fg:#a9b1d6,bg:-1,hl:#7aa2f7\n  directory: {foreground: "#7aa2f7"}\n    activeBorderColor: ['"'#7aa2f7'"', bold]')"
zt "_zanvil_theme_tools minimal; grep -o 'hl:#[0-9a-f]*' $TD/fzf" | assert_equals "repli fzf : bleu de repli" "hl:#2e7de9"
zt "_zanvil_theme_tools tokyo-night-pro; ls $TD 2>/dev/null" "" "$NOBIN" | assert_equals "outils absents : aucun fichier" ""
zt '_zanvil_theme_tools tokyo-night-pro; echo "${FZF_DEFAULT_OPTS_FILE##*/}|${EZA_CONFIG_DIR##*/}|${LG_CONFIG_FILE##*/}|${FZF_DEFAULT_OPTS:-vide}"' \
    | assert_equals "exports : fzf, eza, lazygit ; FZF_DEFAULT_OPTS intact" "fzf|eza|lazygit.yml|vide"
zt 'echo "${FZF_DEFAULT_OPTS_FILE:-vide}|${EZA_CONFIG_DIR:-vide}|${LG_CONFIG_FILE:-vide}"' \
    | assert_equals "fichiers absents : aucun export au demarrage" "vide|vide|vide"
zt '_zanvil_theme_tools tokyo-night-pro; unset FZF_DEFAULT_OPTS_FILE EZA_CONFIG_DIR LG_CONFIG_FILE; source "$ZANVIL_DIR/core/ui.zsh"; echo "${FZF_DEFAULT_OPTS_FILE##*/}|${EZA_CONFIG_DIR##*/}|${LG_CONFIG_FILE##*/}"' \
    | assert_equals "fichiers presents : exports constants au demarrage" "fzf|eza|lazygit.yml"
zt '_zanvil_theme_tools tokyo-night-pro; unset FZF_DEFAULT_OPTS_FILE EZA_CONFIG_DIR LG_CONFIG_FILE; source "$ZANVIL_DIR/core/ui.zsh"; echo "${FZF_DEFAULT_OPTS_FILE:-vide}|${EZA_CONFIG_DIR:-vide}|${LG_CONFIG_FILE:-vide}"' "" "$NOBIN" \
    | assert_equals "outils absents : pas d'export meme avec fichiers" "vide|vide|vide"
zt '_zanvil_theme_tools tokyo-night-pro; echo "${LG_CONFIG_FILE//$XDG_CONFIG_HOME/X}"' 'mkdir -p "$X/lazygit"; touch "$X/lazygit/config.yml"' \
    | assert_equals "lazygit : config utilisateur XDG d'abord" "X/lazygit/config.yml,X/zanvil/theme/lazygit.yml"
UE='mkdir -p "$X/eza"; echo "x: 1" > "$X/eza/theme.yml"'
zt '_zanvil_theme_tools tokyo-night-pro; echo "${EZA_CONFIG_DIR:-vide}"; ls "$XDG_CONFIG_HOME/zanvil/theme/eza" | grep -c theme.yml' "$UE" \
    | grep -v 'theme eza utilisateur' | assert_equals "theme eza utilisateur : pas d'export, pas de fichier eza zanvil" "$(printf 'vide\n0')"
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro' "$UE" \
    | grep -c 'theme eza utilisateur' | assert_equals "theme eza utilisateur : avertissement une seule fois" 1
zt '_zanvil_theme_tools tokyo-night-pro; echo "${EZA_CONFIG_DIR:-vide}"' "$UE" | tail -1 | assert_equals "demarrage avec theme eza utilisateur : pas d'export" vide
zt 'export FZF_DEFAULT_OPTS_FILE=/mon/fzf LG_CONFIG_FILE=/mon/lg.yml; _zanvil_theme_tools tokyo-night-pro; echo "$FZF_DEFAULT_OPTS_FILE|$LG_CONFIG_FILE"' \
    | assert_equals "FZF_DEFAULT_OPTS_FILE et LG_CONFIG_FILE de l'utilisateur conserves" "/mon/fzf|/mon/lg.yml"
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools minimal; echo "${FZF_DEFAULT_OPTS_FILE##*/}|${LG_CONFIG_FILE##*/}"' \
    | assert_equals "valeurs deja a zanvil : reexportees" "fzf|lazygit.yml"
echo "btop, atuin, posting, lazydocker, tmux"
D="$H/.local/share"
for t in tokyo-night-pro minimal; do
    zt "_zanvil_theme_tools $t; grep -c '^theme\[[a-z_]*\]=\"#[0-9a-f]\{6\}\"\$' \$XDG_CONFIG_HOME/btop/themes/zanvil.theme" \
        | assert_equals "btop ($t) : 37 cles hex" "37"
    zt "_zanvil_theme_tools $t; grep -c '^[A-Za-z]* = \"#[0-9a-f]\{6\}\"\$' \$XDG_CONFIG_HOME/atuin/themes/zanvil.toml" \
        | assert_equals "atuin ($t) : 8 couleurs hex" "8"
    PY="\$HOME/.local/share/posting/themes/zanvil.yaml"; LDC="\$XDG_CONFIG_HOME/lazydocker/config.yml"
    zt "_zanvil_theme_tools $t; $YOK $PY; grep -c \"^[a-z]*: '#\" $PY" \
        | assert_equals "posting ($t) : yaml valide, 9 couleurs" "$(printf 'ok\n9')"
    zt "_zanvil_theme_tools $t; grep -c \"^gui:\" $LDC; grep -cE \"^      - '#[0-9a-f]{6}'\\$\" $LDC" \
        | assert_equals "lazydocker ($t) : config creee, 4 couleurs" "$(printf '1\n4')"
    zt "_zanvil_theme_tools $t; grep -c '^set -g [a-z-]*style \"[a-z]*=#[0-9a-f]\{6\}' $TD/tmux.conf" \
        | assert_equals "tmux ($t) : 10 styles" "10"
done
zt '_zanvil_theme_tools tokyo-night-pro; grep -E "main_bg|hi_fg" $XDG_CONFIG_HOME/btop/themes/zanvil.theme' \
    | assert_equals "btop : couleurs de la palette" "$(printf 'theme[hi_fg]="#7dcfff"\ntheme[main_bg]="#1a1b26"')"
# Selecteur : ajoute si absent (config absente ou sans selection)
zt '_zanvil_theme_tools tokyo-night-pro; cat $XDG_CONFIG_HOME/btop/btop.conf; cat $XDG_CONFIG_HOME/posting/config.yaml; cat $XDG_CONFIG_HOME/atuin/config.toml' \
    | assert_equals "configs absentes : selecteurs poses" "$(printf 'color_theme = "zanvil"\ntheme: zanvil\n[theme]\nname = "zanvil"')"
SEL='mkdir -p "$X/btop" "$X/posting" "$X/atuin"; printf "update_ms = 2000" > "$X/btop/btop.conf"; printf "layout: vertical" > "$X/posting/config.yaml"; printf "[search]\nx = 1\n" > "$X/atuin/config.toml"'
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro; cat $XDG_CONFIG_HOME/btop/btop.conf; cat $XDG_CONFIG_HOME/posting/config.yaml; cat $XDG_CONFIG_HOME/atuin/config.toml' "$SEL" \
    | assert_equals "configs sans selection : ajout une fois, reste conserve" "$(printf 'update_ms = 2000\ncolor_theme = "zanvil"\nlayout: vertical\ntheme: zanvil\n[search]\nx = 1\n[theme]\nname = "zanvil"')"
zt 'export ATUIN_CONFIG_DIR="$HOME/at"; _zanvil_theme_tools minimal; ls $HOME/at/themes; grep -c zanvil $HOME/at/config.toml' \
    | assert_equals "ATUIN_CONFIG_DIR respecte" "$(printf 'zanvil.toml\n1')"
# Autre selection : conservee, un seul avertissement sur deux passages
OTH='mkdir -p "$X/btop" "$X/posting" "$X/atuin"; printf "color_theme = \"nord\"\n" > "$X/btop/btop.conf"; printf "theme: galaxy\n" > "$X/posting/config.yaml"; printf "[theme]\nname = \"other\"\n" > "$X/atuin/config.toml"'
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro; cat $XDG_CONFIG_HOME/btop/btop.conf $XDG_CONFIG_HOME/posting/config.yaml $XDG_CONFIG_HOME/atuin/config.toml' "$OTH" \
    | grep -v 'conserve' | assert_equals "autre theme : configs inchangees" "$(printf 'color_theme = "nord"\ntheme: galaxy\n[theme]\nname = "other"')"
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro' "$OTH" \
    | grep -c 'theme .* utilisateur conserve' | assert_equals "autre theme : un avertissement par outil (3) sur deux passages" 3
# Config en lien symbolique : jamais ecrite
LNK='mkdir -p "$H/.dotfiles" "$X/btop" "$X/posting" "$X/atuin"; echo "update_ms = 1" > "$H/.dotfiles/b"; echo "layout: x" > "$H/.dotfiles/p"; echo "[search]" > "$H/.dotfiles/a"; ln -s "$H/.dotfiles/b" "$X/btop/btop.conf"; ln -s "$H/.dotfiles/p" "$X/posting/config.yaml"; ln -s "$H/.dotfiles/a" "$X/atuin/config.toml"'
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro; cat $HOME/.dotfiles/b $HOME/.dotfiles/p $HOME/.dotfiles/a' "$LNK" \
    | grep -v 'est un lien' | assert_equals "config liee aux dotfiles : intacte" "$(printf 'update_ms = 1\nlayout: x\n[search]')"
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro' "$LNK" \
    | grep -c 'est un lien' | assert_equals "config liee : un avertissement par outil sur deux passages" 3
# lazydocker : config existante intacte, avertissement une fois ; config zanvil regeneree
LD='mkdir -p "$X/lazydocker"; echo "gui: {}" > "$X/lazydocker/config.yml"'
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro; cat $XDG_CONFIG_HOME/lazydocker/config.yml' "$LD" \
    | grep -v 'lazydocker utilisateur' | assert_equals "lazydocker : config existante inchangee" "gui: {}"
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-night-pro' "$LD" \
    | grep -c 'lazydocker utilisateur' | assert_equals "lazydocker : avertissement une seule fois" 1
zt '_zanvil_theme_tools tokyo-night-pro; _zanvil_theme_tools tokyo-light-pro; grep -c "#2e7de9" $XDG_CONFIG_HOME/lazydocker/config.yml' \
    | assert_equals "lazydocker : config zanvil suit le theme" "2"
# Outils absents : rien
zt '_zanvil_theme_tools tokyo-night-pro; find "$HOME" "$XDG_CONFIG_HOME" -type f | wc -l | tr -d " "' "" "$NOBIN" \
    | assert_equals "outils absents : aucun fichier" "0"
# tmux : source-file seulement si tmux tourne ET que sa config inclut le fichier
INC='echo "source-file ~/.config/zanvil/theme/tmux.conf" > "$H/.tmux.conf"'
TMUXRUN=1 zt '_zanvil_theme_tools tokyo-night-pro; cat "$TMUXLOG" | sed "s#$XDG_CONFIG_HOME#X#"' "$INC; rm -f \"\$TMUXLOG\"" \
    | assert_equals "tmux actif + config incluse : source-file" "source-file X/zanvil/theme/tmux.conf"
TMUXRUN=1 zt '_zanvil_theme_tools tokyo-night-pro; cat "$TMUXLOG" 2>/dev/null; echo fin' 'rm -f "$TMUXLOG"; echo "set -g mouse on" > "$H/.tmux.conf"' \
    | assert_equals "tmux actif, config sans inclusion : pas de source-file" "fin"
zt '_zanvil_theme_tools tokyo-night-pro; cat "$TMUXLOG" 2>/dev/null; echo fin' "$INC; rm -f \"\$TMUXLOG\"" \
    | assert_equals "tmux arrete : pas de source-file" "fin"
# Modeles neutres : aucun selecteur avant le premier passage du generateur
zt 'grep -c "^theme:" "$ZANVIL_DIR/config/posting/config.yaml"; grep -c "^\[theme\]" "$ZANVIL_DIR/config/atuin/config.toml"' \
    | assert_equals "modeles posting et atuin : aucun selecteur de theme" "$(printf '0\n0')"
zt 'cp "$ZANVIL_DIR/config/posting/config.yaml" "$HOME/p.yaml"; cp "$ZANVIL_DIR/config/atuin/config.toml" "$HOME/a.toml"; export POSTING_CONFIG_FILE="$HOME/p.yaml" ATUIN_CONFIG_DIR="$HOME/at"; mkdir -p "$HOME/at"; cp "$HOME/a.toml" "$HOME/at/config.toml"; _zanvil_theme_tools tokyo-night-pro; grep -c "^theme: zanvil$" "$HOME/p.yaml"; grep -c "^name = \"zanvil\"" "$HOME/at/config.toml"' \
    | assert_equals "modeles + un passage du generateur : selecteurs presents" "$(printf '1\n1')"
# btop : color_theme = "Default" (ecrit par btop a sa premiere sortie) n'est pas un choix
zt '_zanvil_theme_tools tokyo-night-pro; cat $XDG_CONFIG_HOME/btop/btop.conf' 'mkdir -p "$X/btop"; printf "update_ms = 2000\ncolor_theme = \"Default\"\ntheme_background = True\n" > "$X/btop/btop.conf"' \
    | assert_equals "btop Default : remplace par zanvil" "$(printf 'update_ms = 2000\ncolor_theme = "zanvil"\ntheme_background = True')"
# bat : une valeur utilisateur survit (demarrage et generateur)
zt 'echo "$BAT_THEME_LIGHT $BAT_THEME_DARK"' "$MK; export BAT_THEME_LIGHT=mien" \
    | assert_equals "bat : BAT_THEME_LIGHT utilisateur survit au demarrage" "mien tokyonight_night"
zt '_zanvil_theme_tools tokyo-night-pro; echo "$BAT_THEME_LIGHT $BAT_THEME_DARK"' 'export BAT_THEME_DARK=mien' \
    | assert_equals "bat : BAT_THEME_DARK utilisateur survit au generateur" "tokyonight_day mien"
# Avertissements : marqueur seulement si visibles (sans terminal : pas de marqueur, avertissement repete plus tard)
ZANVIL_THEME_TTY= zt '_zanvil_theme_tools tokyo-night-pro >/dev/null; find $XDG_CONFIG_HOME/zanvil -name "*notice" | wc -l | tr -d " "; ZANVIL_THEME_TTY=1 _zanvil_theme_tools tokyo-night-pro | grep -c "conserv"' "$OTH; mkdir -p \"\$X/eza\" \"\$X/lazydocker\"; : > \"\$X/eza/theme.yml\"; echo 'gui: {}' > \"\$X/lazydocker/config.yml\"" \
    | assert_equals "sans terminal : aucun marqueur, avertissement au passage suivant" "$(printf '0\n5')"
zt '_zanvil_theme_tools tokyo-night-pro >/dev/null; find $XDG_CONFIG_HOME/zanvil -name "*notice" | wc -l | tr -d " "' "$OTH; mkdir -p \"\$X/eza\" \"\$X/lazydocker\"; : > \"\$X/eza/theme.yml\"; echo 'gui: {}' > \"\$X/lazydocker/config.yml\"" \
    | assert_equals "avec terminal : marqueurs crees (btop, posting, atuin, eza, lazydocker)" "5"
# PATH : ~/.local/bin trouve par le generateur, PATH de l'appelant intact
zt 'P0=$PATH; _zanvil_theme_tools tokyo-night-pro; [[ $PATH == $P0 ]] && echo intact; ls $XDG_CONFIG_HOME/btop/themes' 'mkdir -p "$H/.local/bin"; cp "$TEST_TMPDIR/bin/btop" "$H/.local/bin/btop"' "$NOBIN" \
    | assert_equals "~/.local/bin : outil trouve, PATH inchange" "$(printf 'intact\nzanvil.theme')"
echo

echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
