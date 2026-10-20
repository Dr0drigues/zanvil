#!/usr/bin/env bash
# Verifie link/adopt/apply de zanvil-dotfiles avec un vrai stow : dossiers reels (--no-folding),
# un conflit bloque sans rien ecraser, adopt refuse les secrets.
# Usage : scripts/tests/dotfiles-stow.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"

if ! command -v stow >/dev/null 2>&1; then
    echo "  skip : stow absent"
    exit 0
fi

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

H="$TEST_TMPDIR/home"
DOT="$TEST_TMPDIR/dotfiles"
mkdir -p "$H" "$DOT/stow/common/.config/demo" "$DOT/stow/pro/.config/demo"
echo repo-a > "$DOT/stow/common/.config/demo/a.conf"
echo repo-b > "$DOT/stow/pro/.config/demo/b.conf"
mkdir -p "$DOT/stow/common/.config/solo"; echo repo-c > "$DOT/stow/common/.config/solo/c.conf"
mkdir -p "$DOT/brew"; echo "" > "$DOT/brew/common.Brewfile"; echo "" > "$DOT/brew/pro.Brewfile"

# $1 = commande, lancee dans un zsh vierge qui ne depend que de core/ui.zsh
zd() {
    HOME="$H" ZANVIL_DIR="$ROOT" ZANVIL_DOTFILES_DIR="$DOT" ZANVIL_PROFILE=pro \
        zsh -f -c "
        source '$ROOT/core/ui.zsh'
        source '$ROOT/core/commands/dotfiles.zsh'
        $1
    " 2>&1
}
kind() { # lien | reel | absent
    if [[ -L "$1" ]]; then echo lien; elif [[ -e "$1" ]]; then echo reel; else echo absent; fi
}

zd 'zanvil-dotfiles link' >/dev/null
{ echo "$(kind "$H/.config/demo/a.conf") $(kind "$H/.config/demo/b.conf")"; } \
    | assert_equals "link pro : a.conf et b.conf sont des liens" "lien lien"
{ [[ -d "$H/.config/solo" && ! -L "$H/.config/solo" ]] && echo reel || echo replie; } \
    | assert_equals "link : .config/solo (un seul paquet) est un vrai dossier" "reel"

rm "$H/.config/demo/a.conf" "$H/.config/demo/b.conf"
echo local > "$H/.config/demo/a.conf"
out=$(zd 'zanvil-dotfiles link; echo "rc=$?"')
echo "$out" | tail -1 | assert_equals "conflit : code 1" "rc=1"
{ [[ "$out" == *a.conf* ]] && echo nomme || echo muet; } | assert_equals "conflit : la sortie nomme a.conf" "nomme"
{ cat "$H/.config/demo/a.conf"; } | assert_equals "conflit : le fichier local est intact" "local"
{ kind "$H/.config/demo/b.conf"; } | assert_equals "conflit : rien n'est lie" "absent"

zd 'zanvil-dotfiles adopt .config/demo/a.conf'
{ cat "$DOT/stow/common/.config/demo/a.conf"; } | assert_equals "adopt : le depot contient le contenu local" "local"
{ kind "$H/.config/demo/a.conf"; } | assert_equals "adopt : le fichier de HOME est un lien" "lien"

echo secret > "$H/.zshrc"
zd 'zanvil-dotfiles adopt .zshrc >/dev/null 2>&1; echo "rc=$?"' | assert_equals "adopt .zshrc : code 1" "rc=1"
{ kind "$H/.zshrc"; } | assert_equals "adopt .zshrc : fichier non deplace" "reel"
mkdir -p "$H/.config/gh"
echo tok > "$H/.config/gh/hosts.yml"
zd 'zanvil-dotfiles adopt .config/gh/hosts.yml >/dev/null 2>&1; echo "rc=$?"' | assert_equals "adopt gh/hosts.yml : code 1" "rc=1"
{ kind "$H/.config/gh/hosts.yml"; } | assert_equals "adopt gh/hosts.yml : fichier non deplace" "reel"

rm "$H/.config/demo/a.conf"
zd 'zanvil-dotfiles apply >/dev/null 2>&1; echo "rc=$?"' | assert_equals "apply hors depot git : code 1" "rc=1"
{ kind "$H/.config/demo/a.conf"; } | assert_equals "apply hors depot git : aucun lien" "absent"

zd 'zanvil-dotfiles status' | grep -c 'Brewfile' | tr -d ' ' | assert_equals "status : liste les 3 Brewfile" "3"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
