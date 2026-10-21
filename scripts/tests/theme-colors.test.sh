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
FAKE_RUNNING="borders" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' "$BORDERS" \
    | assert_equals "borders tourne : bordersrc execute" "borders"
FAKE_RUNNING="" zc 'zanvil-theme minimal >/dev/null; cat "$LOG"' "$BORDERS" \
    | assert_equals "borders arrete : bordersrc non execute" ""
FAKE_RUNNING="borders" zc 'zanvil-theme minimal >/dev/null; echo rc=$?; cat "$LOG"' \
    | assert_equals "bordersrc absent : aucun appel, aucune erreur" "rc=0"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
