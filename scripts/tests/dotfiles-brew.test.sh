#!/usr/bin/env bash
# Verifie les Brewfiles par couches de zanvil-dotfiles et le nettoyage confirme :
# brew bundle cleanup --force ne part qu'apres une reponse explicite sur un terminal.
# Usage : scripts/tests/dotfiles-brew.test.sh
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

BIN="$TEST_TMPDIR/bin"
DOT="$TEST_TMPDIR/dotfiles"
LOG="$TEST_TMPDIR/brew.log"
mkdir -p "$BIN" "$DOT/brew"

# Faux brew : journalise ses arguments, simule la liste de cleanup
cat > "$BIN/brew" <<EOF2
#!/bin/sh
echo "\$*" >> "$LOG"
case "\$*" in
    *"bundle cleanup"*--force*) [ -n "\$FAKE_FORCE_FAIL" ] && exit 1; exit 0 ;;
    *"bundle cleanup"*)
        [ -n "\$FAKE_DRY_FAIL" ] && { echo "Error: boom" >&2; exit 1; }
        printf 'Would uninstall formulae:\nredis\n'; exit 1 ;;
esac
EOF2
chmod +x "$BIN/brew"
echo 'brew "common-tool"' > "$DOT/brew/common.Brewfile"
echo 'brew "pro-only-tool"' > "$DOT/brew/pro.Brewfile"

# Lance une commande dans un zsh vierge qui ne depend que de core/ui.zsh
# $1 = profil, $2 = commande, $3 = stdin (defaut : vide), $4 = ZANVIL_ASSUME_TTY
zd() {
    : > "$LOG"
    printf '%s' "${3:-}" | PATH="$BIN:/usr/bin:/bin" ZANVIL_DIR="$ROOT" \
        ZANVIL_DOTFILES_DIR="$DOT" ZANVIL_PROFILE="$1" ZANVIL_ASSUME_TTY="${4:-}" \
        zsh -f -c "
        source '$ROOT/core/ui.zsh'
        source '$ROOT/core/commands/dotfiles.zsh'
        $2
    " 2>&1
}
forced() { grep -c -- '--force' "$LOG" | tr -d ' '; }

echo "zanvil-dotfiles brew"

zd pro '_zanvil_dotfiles_brewfiles | wc -l' | tr -d ' ' | assert_equals "profil pro : 3 fichiers" "3"
zd pro '_zanvil_dotfiles_brewfiles | tail -1' | sed 's|.*/brew/|/brew/|' | assert_equals "profil pro : 3e = pro.Brewfile" "/brew/pro.Brewfile"
zd "" '_zanvil_dotfiles_brewfiles >/dev/null 2>&1; echo "rc=$?"' | assert_equals "profil vide : code 1" "rc=1"
zd autre '_zanvil_dotfiles_brewfiles >/dev/null 2>&1; echo "rc=$?"' | assert_equals "profil autre : code 1" "rc=1"

zd pro '_zanvil_dotfiles_merged && cat "$REPLY"' > "$TEST_TMPDIR/merged"
grep -c -e '^brew "stow"$' -e '^brew "pro-only-tool"$' "$TEST_TMPDIR/merged" | assert_equals "fusion : base + pro" "2"

zd pro 'zanvil-dotfiles cleanup' "oui
" 1 >/dev/null
forced | assert_equals "cleanup + oui sur terminal : --force" "1"
zd pro 'zanvil-dotfiles cleanup' "
" 1 >/dev/null
forced | assert_equals "cleanup + reponse vide : pas de --force" "0"
zd pro 'zanvil-dotfiles cleanup' "oui
" >/dev/null
forced | assert_equals "cleanup hors terminal : pas de --force" "0"

zd pro 'zanvil-dotfiles cleanup >/dev/null 2>&1; echo "rc=$?"' "oui
" 1 | tail -1 | assert_equals "cleanup + oui : code 0 malgre le code 1 de la simulation" "rc=0"
FAKE_DRY_FAIL=1 zd pro 'zanvil-dotfiles cleanup >/dev/null 2>&1; echo "rc=$?"' "oui
" 1 | tail -1 | assert_equals "simulation en echec : code non nul" "rc=1"
forced | assert_equals "simulation en echec : pas de --force" "0"
FAKE_FORCE_FAIL=1 zd pro 'zanvil-dotfiles cleanup >/dev/null 2>&1; echo "rc=$?"' "oui
" 1 | tail -1 | assert_equals "--force en echec : code non nul" "rc=1"

mv "$DOT/brew/pro.Brewfile" "$DOT/brew/pro.Brewfile.off"
zd pro 'zanvil-dotfiles cleanup' "oui
" 1 >/dev/null
{ [[ -s "$LOG" ]] && echo "brew lance" || echo "brew jamais lance"; } | assert_equals "Brewfile manquant : brew jamais lance" "brew jamais lance"
zd pro '_zanvil_dotfiles_brewfiles >/dev/null 2>&1; echo "rc=$?"' | assert_equals "Brewfile manquant : code 1" "rc=1"
mv "$DOT/brew/pro.Brewfile.off" "$DOT/brew/pro.Brewfile"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
