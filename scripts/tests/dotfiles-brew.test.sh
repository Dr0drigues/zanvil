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
    "trust --json v1") echo '{"taps":[],"formulae":["a/b/deja","felixkratz/formulae/borders"],"casks":[]}'; exit 0 ;;
    "trust "*) [ -n "\$FAKE_TRUST_FAIL" ] && exit 1; exit 0 ;;
    *"bundle install"*) [ -n "\$FAKE_BUNDLE_FAIL" ] && exit 1; exit 0 ;;
    *"bundle cleanup"*--force*) [ -n "\$FAKE_FORCE_FAIL" ] && exit 1; exit 0 ;;
    *"bundle cleanup"*)
        [ -n "\$FAKE_DRY_FAIL" ] && { echo "Error: boom" >&2; exit 1; }
        [ -n "\$FAKE_NOTHING" ] && { printf 'Would \`brew cleanup\`\nWould remove: /cache/x\n'; exit 0; }
        printf 'Would uninstall formulae:\nredis\nWould remove (empty directory): /opt/homebrew/lib/x/__pycache__\n'; exit 1 ;;
esac
EOF2
chmod +x "$BIN/brew"
printf '%s\n' 'tap "a/b"' 'brew "a/b/deja"' 'brew "a/b/neuve"' 'cask "c/d/app"' 'brew "jq"' > "$DOT/brew/common.Brewfile"
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

# brew 7 nettoie aussi vscode, npm, uv... sans filtre de type : limite a brew
zd pro 'zanvil-dotfiles cleanup' "oui
" 1 >/dev/null
grep -c -- '^bundle cleanup --formula --cask --tap ' "$LOG" | tr -d ' ' | assert_equals "cleanup : simulation et --force limites a brew" "2"
zd pro 'zanvil-dotfiles install' >/dev/null
grep -c -- '^bundle install --no-upgrade --file=' "$LOG" | tr -d ' ' | assert_equals "install : --no-upgrade" "1"

# approbation : seulement les entrees a/b/c absentes de la liste de brew, jamais --tap
grep -e '^trust --formula' -e '^trust --cask' -e '^bundle install' "$LOG" | sed 's/ --file=.*//' \
    | assert_equals "install : trust formula, trust cask, puis bundle install" "trust --formula a/b/neuve
trust --cask c/d/app
bundle install --no-upgrade"
grep '^trust' "$LOG" | grep -c -e '--tap' | tr -d ' ' | assert_equals "install : jamais trust --tap" "0"
grep '^trust' "$LOG" | grep -v -e '--json' | grep -c -e 'a/b/deja' -e 'jq' | tr -d ' ' | assert_equals "install : ni deja approuve ni jq" "0"
FAKE_TRUST_FAIL=1 zd pro 'zanvil-dotfiles install >/dev/null 2>&1; echo "rc=$?"' | tail -1 | assert_equals "trust en echec : code 1" "rc=1"
grep -c '^bundle install' "$LOG" | tr -d ' ' | assert_equals "trust en echec : pas de bundle install" "0"
printf '%s\n' 'brew "a/b/deja"' 'brew "FelixKratz/formulae/borders"' 'brew "jq"' > "$DOT/brew/common.Brewfile"
zd pro 'zanvil-dotfiles install' >/dev/null
grep '^trust' "$LOG" | grep -vc -e '--json' | tr -d ' ' | assert_equals "tout approuve : aucun trust hors --json" "0"
echo 'brew "common-tool"' > "$DOT/brew/common.Brewfile"

out=$(FAKE_NOTHING=1 zd pro 'zanvil-dotfiles cleanup' "oui
" 1)
forced | assert_equals "rien a desinstaller : pas de --force" "0"
{ [[ "$out" == *"Rien a desinstaller"* && "$out" != *"[o/N]"* ]] && echo info || echo "$out"; } \
    | assert_equals "rien a desinstaller : info, pas de question" "info"
zd pro 'zanvil-dotfiles cleanup' "non
" 1 | grep -c "Rien n a ete desinstalle" | tr -d ' ' | assert_equals "refus : info rien desinstalle" "1"
out=$(zd pro 'zanvil-dotfiles cleanup' "non
" 1)
{ [[ "$out" == *redis* && "$out" != *"empty directory"* ]] && echo filtre || echo "$out"; } \
    | assert_equals "liste affichee sans les dossiers vides de brew" "filtre"

mv "$DOT/brew/pro.Brewfile" "$DOT/brew/pro.Brewfile.off"
zd pro 'zanvil-dotfiles cleanup' "oui
" 1 >/dev/null
{ [[ -s "$LOG" ]] && echo "brew lance" || echo "brew jamais lance"; } | assert_equals "Brewfile manquant : brew jamais lance" "brew jamais lance"
zd pro '_zanvil_dotfiles_brewfiles >/dev/null 2>&1; echo "rc=$?"' | assert_equals "Brewfile manquant : code 1" "rc=1"
mv "$DOT/brew/pro.Brewfile.off" "$DOT/brew/pro.Brewfile"

echo "cleanup et approbations (brew bundle cleanup --force ne garde que les trusted: du Brewfile)"
cp "$DOT/brew/common.Brewfile" "$TEST_TMPDIR/common.save"
printf '%s\n' 'tap "a/b"' 'brew "a/b/sans"' 'brew "a/b/avec", trusted: true' 'cask "c/d/app"' 'brew "jq"' > "$DOT/brew/common.Brewfile"
out=$(zd pro 'zanvil-dotfiles cleanup' "non
" 1)
warn=$(printf '%s\n' "$out" | grep "retirera l'approbation")
{ [[ "$warn" == *a/b/sans* && "$warn" == *c/d/app* ]] && echo ok || echo "$out"; } \
    | assert_equals "cleanup : avertit pour les entrees de taps tiers sans trusted:" ok
warn_line=$(printf '%s\n' "$out" | grep -n "retirera l'approbation" | head -1 | cut -d: -f1)
ask_line=$(printf '%s\n' "$out" | grep -n '\[o/N\]' | head -1 | cut -d: -f1)
{ [[ -n "$warn_line" && -n "$ask_line" && "$warn_line" -lt "$ask_line" ]] && echo ok || echo "$out"; } \
    | assert_equals "cleanup : avertissement avant la question" ok
{ printf '%s\n' "$warn" | grep -c 'a/b/avec'; } | assert_equals "cleanup : entree avec trusted: true non signalee" 0
t=$(grep -n '^trust --formula' "$LOG" | head -1 | cut -d: -f1); c=$(grep -n 'bundle cleanup' "$LOG" | head -1 | cut -d: -f1)
{ [[ -n "$t" && -n "$c" && "$t" -lt "$c" ]] && echo ok || cat "$LOG"; } \
    | assert_equals "cleanup : approuve les entrees avant d'appeler brew bundle cleanup" ok
printf '%s\n' 'brew "a/b/avec", trusted: true' 'brew "jq"' > "$DOT/brew/common.Brewfile"
out=$(zd pro 'zanvil-dotfiles cleanup' "non
" 1)
{ printf '%s\n' "$out" | grep -c "retirera l'approbation"; } | assert_equals "cleanup : tout est declare, aucun avertissement" 0
cp "$TEST_TMPDIR/common.save" "$DOT/brew/common.Brewfile"

echo "reglages macOS (macos.sh du depot, lance par install sur macOS seulement)"
[[ "$(uname)" == Darwin ]] && on_mac=1 || on_mac=0
echo "echo ran >> '$TEST_TMPDIR/macos.log'" > "$DOT/macos.sh"
: > "$TEST_TMPDIR/macos.log"
zd pro 'zanvil-dotfiles install' >/dev/null
grep -c ran "$TEST_TMPDIR/macos.log" | tr -d ' ' | assert_equals "macos.sh lance apres install (macOS seulement)" "$on_mac"
: > "$TEST_TMPDIR/macos.log"
FAKE_BUNDLE_FAIL=1 zd pro 'zanvil-dotfiles install' >/dev/null
grep -c ran "$TEST_TMPDIR/macos.log" | tr -d ' ' | assert_equals "install en echec : macos.sh non lance" "0"
echo 'exit 3' > "$DOT/macos.sh"
zd pro 'zanvil-dotfiles install >/dev/null 2>&1; echo "rc=$?"' | tail -1 | assert_equals "macos.sh en echec : install reste a 0" "rc=0"
if (( on_mac )); then
    zd pro 'zanvil-dotfiles install' | grep -c 'Reglages macOS incomplets' | tr -d ' ' | assert_equals "macos.sh en echec : avertissement" "1"
fi
rm -f "$DOT/macos.sh"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
