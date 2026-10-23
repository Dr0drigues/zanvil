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
chmod +x "$BIN/k9s"

# Garde : le vrai k9s ne doit pas etre atteignable depuis le PATH minimal du test
if PATH="$NOBIN:/usr/bin:/bin" command -v k9s >/dev/null; then
    echo "k9s reel accessible depuis le PATH de test" >&2; exit 2
fi

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
zt '_zanvil_theme_tools tokyo-night-pro; ls "$(dirname "$SK")" 2>/dev/null | wc -l | tr -d " "' "" "$NOBIN" \
    | assert_equals "k9s absent : aucun fichier" "0"
zt 'ZANVIL_K9S_AUTO_THEME=false _zanvil_theme_tools tokyo-night-pro; ls "$(dirname "$SK")" 2>/dev/null | wc -l | tr -d " "' \
    | assert_equals "ZANVIL_K9S_AUTO_THEME=false : aucun fichier" "0"
zt 'echo "${K9S_SKIN:-vide}"' "" "$NOBIN" | assert_equals "K9S_SKIN non exporte sans k9s" "vide"
zt 'ZANVIL_K9S_AUTO_THEME=false; unset K9S_SKIN; source "$ZANVIL_DIR/core/ui.zsh"; echo "${K9S_SKIN:-vide}"' \
    | assert_equals "K9S_SKIN non exporte avec l'opt-out" "vide"

echo "_zanvil_theme_palette_hex"
zt '_zanvil_theme_palette_hex tokyo-night-pro | grep -E "^(bg|blue)="' \
    | assert_equals "bg et blue de tokyo-night-pro" "$(printf 'bg=1a1b26\nblue=7aa2f7')"
zt '_zanvil_theme_palette_hex minimal | wc -l | tr -d " "; _zanvil_theme_palette_hex minimal | grep "^bg="' \
    | assert_equals "theme plat : 9 cles, repli" "$(printf '9\nbg=e1e2e7')"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
