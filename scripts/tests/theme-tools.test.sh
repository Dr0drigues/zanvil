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
FAKE
chmod +x "$BIN/k9s" "$BIN/delta" "$BIN/bat"
export BATLOG="$TEST_TMPDIR/bat.log"

# Garde : les vrais k9s, bat et delta ne doivent pas etre atteignables depuis le PATH minimal du test
for tool in k9s bat delta; do
    if PATH="$NOBIN:/usr/bin:/bin" command -v $tool >/dev/null; then
        echo "$tool reel accessible depuis le PATH de test" >&2; exit 2
    fi
done

# zt <commande> [setup] [PATH] : HOME et XDG neufs ; PATH = faux bin (defaut) ou NOBIN
zt() {
    rm -rf "$H" "$X"; mkdir -p "$H/.config" "$X"
    eval "${2:-}"
    env -u K9S_SKIN HOME="$H" XDG_CONFIG_HOME="$X" ZANVIL_DIR="$Z" PATH="${3:-$BIN}:/usr/bin:/bin" zsh -f -c "
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
zt 'echo "$BAT_THEME_LIGHT $BAT_THEME_DARK ${BAT_THEME:-vide}"' \
    | assert_equals "exports constants au demarrage, pas de BAT_THEME" "tokyonight_day tokyonight_night vide"
zt 'echo "${BAT_THEME_LIGHT:-vide}"' "" "$NOBIN" | assert_equals "pas d'export sans bat" "vide"

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

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
