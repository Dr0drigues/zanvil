#!/usr/bin/env bash
# Verifie que zanvil-theme genere <theme_dir>/colors.sh (SketchyBar, JankyBorders) et
# recharge la barre et les bordures seulement si elles tournent. Faux binaires, HOME temporaire.
# Usage : scripts/tests/theme-colors.test.sh
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

Z="$TEST_TMPDIR/zanvil"
mkdir -p "$Z"
cp -R "$ROOT/core" "$ROOT/config" "$Z/"

H="$TEST_TMPDIR/home"
X="$TEST_TMPDIR/xdg"
LOG="$TEST_TMPDIR/calls.log"
BIN="$TEST_TMPDIR/bin"
mkdir -p "$BIN"
# pgrep : repond (code 0) pour les noms listes dans $FAKE_RUNNING
cat > "$BIN/pgrep" <<'EOS'
#!/bin/sh
case " $FAKE_RUNNING " in *" $2 "*) exit 0;; esac
exit 1
EOS
printf '#!/bin/sh\necho "sketchybar $*" >> "$LOG"\n' > "$BIN/sketchybar"
printf '#!/bin/sh\nexit 0\n' > "$BIN/starship"
# osascript : journalise le dernier argument (le chemin du fond d'ecran)
printf '#!/bin/sh\nfor a; do :; done; echo "osascript $a" >> "$LOG"\n' > "$BIN/osascript"
chmod +x "$BIN"/*

# zc <commande> [setup] : theme_dir et HOME neufs, FAKE_RUNNING via l'environnement
zc() {
    rm -rf "$H" "$X" "$LOG"; mkdir -p "$H/.config" "$X"; : > "$LOG"
    eval "${2:-}"
    HOME="$H" XDG_CONFIG_HOME="$X" ZANVIL_DIR="$Z" LOG="$LOG" PATH="$BIN:/usr/bin:/bin" zsh -f -c "
        source '$Z/core/ui.zsh'
        source '$Z/core/commands/theme.zsh'
        $1
    " 2>&1
}
BORDERS='mkdir -p "$H/.config/borders"; printf "#!/bin/sh\necho borders >> \"$LOG\"\n" > "$H/.config/borders/bordersrc"; chmod +x "$H/.config/borders/bordersrc"'
CF='cat "$XDG_CONFIG_HOME/zanvil/theme/colors.sh"'
FALLBACK=$(printf 'export ZANVIL_BAR_BG=0xe6e1e2e7\nexport ZANVIL_BAR_TEXT=0xff383e5d\nexport ZANVIL_BAR_DIM=0xff969cb4\nexport ZANVIL_ACCENT=0xff2e7de9')

echo "_zanvil_theme_hex"
zc "_zanvil_theme_hex \$'\\033[38;2;46;125;233m'" | assert_equals "sequence true color" "2e7de9"
zc "_zanvil_theme_hex \$'\\033[34m'" | assert_equals "sequence inconnue : rien" ""

echo "colors.sh"
zc "zanvil-theme tokyo-light-pro >/dev/null; $CF" | assert_equals "tokyo-light-pro" "$FALLBACK"
zc "zanvil-theme tokyo-night-pro >/dev/null; $CF" \
    | assert_equals "tokyo-night-pro : fond sombre" "$(printf 'export ZANVIL_BAR_BG=0xe61a1b26\nexport ZANVIL_BAR_TEXT=0xffa9b1d6\nexport ZANVIL_BAR_DIM=0xff565f89\nexport ZANVIL_ACCENT=0xff7aa2f7')"
zc "zanvil-theme minimal >/dev/null; $CF" | assert_equals "minimal (sans palette) : repli" "$FALLBACK"
zc "zanvil-theme tokyo-night-pro >/dev/null; zanvil-theme minimal >/dev/null; $CF" \
    | assert_equals "palette precedente ne fuit pas" "$FALLBACK"
zc "zanvil-theme tokyo-light-pro >/dev/null; sh -c '. \"\$XDG_CONFIG_HOME/zanvil/theme/colors.sh\"; echo \$ZANVIL_ACCENT'" \
    | assert_equals "sourcable par sh" "0xff2e7de9"
zc "zanvil-theme tokyo-light-pro >/dev/null; zsh -f -c '. \"\$XDG_CONFIG_HOME/zanvil/theme/colors.sh\"; echo \$ZANVIL_ACCENT'" \
    | assert_equals "sourcable par zsh" "0xff2e7de9"
zc 'zanvil-theme tokyo-light-pro >/dev/null; print -r -- ${_ui_blue//$'"'\\033'"'/E}' \
    | assert_equals "_ui_* de la session geres par le code existant" "E[38;2;46;125;233m"
zc 'zanvil-theme tokyo-light-pro >/dev/null; find "$HOME" "$XDG_CONFIG_HOME" -type f | sed "s#^$HOME/##; s#^$XDG_CONFIG_HOME/##" | sort' \
    | assert_equals "ecrit seulement dans <theme_dir>" "$(printf 'zanvil/theme/colors.sh\nzanvil/theme/starship.toml')"

echo "rechargement"
FAKE_RUNNING="sketchybar" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' \
    | assert_equals "sketchybar tourne : --reload" "sketchybar --reload"
FAKE_RUNNING="" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' \
    | assert_equals "rien ne tourne : aucun appel" ""
RECOLOR='mkdir -p "$X/sketchybar"; printf "#!/bin/sh\necho recolor >> \"$LOG\"\n" > "$X/sketchybar/recolor"; chmod +x "$X/sketchybar/recolor"'
FAKE_RUNNING="sketchybar" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' "$RECOLOR" \
    | assert_equals "recolor executable : recolor a la place de --reload" "recolor"
FAKE_RUNNING="" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' "$RECOLOR" \
    | assert_equals "recolor, barre arretee : rien" ""
FAKE_RUNNING="sketchybar" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' "$RECOLOR; chmod -x \"\$X/sketchybar/recolor\"" \
    | assert_equals "recolor non executable : --reload" "sketchybar --reload"
FAKE_RUNNING="borders" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' "$BORDERS" \
    | assert_equals "borders tourne : bordersrc execute" "borders"
FAKE_RUNNING="" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' "$BORDERS" \
    | assert_equals "borders arrete : bordersrc non execute" ""
FAKE_RUNNING="borders" zc 'zanvil-theme minimal >/dev/null; echo rc=$?; cat "$LOG"' \
    | assert_equals "bordersrc absent : aucun appel, aucune erreur" "rc=0"

echo "_zanvil_theme_wallpaper (macOS seulement)"
W='mkdir -p "$X/zanvil/wallpapers"'
zc '_zanvil_theme_wallpaper tokyo-night-pro; cat "$LOG"' "$W" \
    | assert_equals "pas d'image pour ce theme : rien" ""
if [[ "$(uname)" == Darwin ]]; then
    zc '_zanvil_theme_wallpaper tokyo-night-pro; cat "$LOG"' "$W; touch \"\$X/zanvil/wallpapers/tokyo-night-pro.png\"" \
        | assert_equals "image du theme posee" "osascript $X/zanvil/wallpapers/tokyo-night-pro.png"
    zc '_zanvil_theme_wallpaper forge; cat "$LOG"' "$W; touch \"\$X/zanvil/wallpapers/forge.png\" \"\$X/zanvil/wallpapers/forge.jpg\"" \
        | assert_equals "jpg avant png, un seul appel" "osascript $X/zanvil/wallpapers/forge.jpg"
else
    zc '_zanvil_theme_wallpaper forge; cat "$LOG"' "$W; touch \"\$X/zanvil/wallpapers/forge.jpg\"" \
        | assert_equals "hors macOS : rien" ""
fi

echo "zanvil-ghostty auto"
zc 'zanvil-ghostty auto >/dev/null; cat "$XDG_CONFIG_HOME/zanvil/theme/ghostty"' \
    | assert_equals "paire clair/sombre par defaut" "theme = light:$Z/config/ghostty/themes/tokyo-light-storm,dark:$Z/config/ghostty/themes/tokyo-night-storm"
zc 'ZANVIL_GHOSTTY_DARK=tokyo-night zanvil-ghostty auto >/dev/null; cat "$XDG_CONFIG_HOME/zanvil/theme/ghostty"' \
    | assert_equals "theme sombre choisi" "theme = light:$Z/config/ghostty/themes/tokyo-light-storm,dark:$Z/config/ghostty/themes/tokyo-night"
zc 'ZANVIL_GHOSTTY_DARK=nope zanvil-ghostty auto >/dev/null 2>&1; echo "rc=$? $([[ -f $XDG_CONFIG_HOME/zanvil/theme/ghostty ]] && echo ecrit || echo absent)"' \
    | assert_equals "theme inconnu : code 1, rien d'ecrit" "rc=1 absent"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
