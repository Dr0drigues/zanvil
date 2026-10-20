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
    HOME="$H" ZANVIL_DIR="$ROOT" ZANVIL_DOTFILES_DIR="${ZD_DOT:-$DOT}" ZANVIL_PROFILE="${ZD_PROFILE:-pro}" \
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
echo "$out" | grep -c '^cannot stow .*a\.conf' | tr -d ' ' | assert_equals "conflit : une ligne par conflit, qui nomme a.conf" "1"
{ cat "$H/.config/demo/a.conf"; } | assert_equals "conflit : le fichier local est intact" "local"
{ kind "$H/.config/demo/b.conf"; } | assert_equals "conflit : rien n'est lie" "absent"

out=$(zd 'zanvil-dotfiles adopt .config/demo/a.conf; echo "rc=$?"')
echo "$out" | tail -1 | assert_equals "adopt sur une copie differente du depot : code 1" "rc=1"
{ [[ "$out" == *"diff "* ]] && echo diff || echo "$out"; } | assert_equals "adopt refuse : propose diff" "diff"
{ echo "$(cat "$DOT/stow/common/.config/demo/a.conf") $(kind "$H/.config/demo/a.conf")"; } \
    | assert_equals "adopt refuse : depot et fichier local intacts" "repo-a reel"
echo local > "$DOT/stow/common/.config/demo/a.conf"
zd 'zanvil-dotfiles adopt .config/demo/a.conf' >/dev/null
{ cat "$DOT/stow/common/.config/demo/a.conf"; } | assert_equals "adopt : le depot contient le contenu local" "local"
{ kind "$H/.config/demo/a.conf"; } | assert_equals "adopt : le fichier de HOME est un lien" "lien"

echo secret > "$H/.zshrc"
zd 'zanvil-dotfiles adopt .zshrc >/dev/null 2>&1; echo "rc=$?"' | assert_equals "adopt .zshrc : code 1" "rc=1"
{ kind "$H/.zshrc"; } | assert_equals "adopt .zshrc : fichier non deplace" "reel"
mkdir -p "$H/.ssh"
echo key > "$H/.ssh/config"
for p in ./.zshrc .//.ssh/config .ZSHRC .SSH/config; do
    zd "zanvil-dotfiles adopt '$p' >/dev/null 2>&1; echo \"rc=\$?\"" | assert_equals "adopt $p : code 1" "rc=1"
done
{ echo "$(kind "$H/.zshrc") $(kind "$H/.ssh/config") $(kind "$DOT/stow/common/.zshrc")"; } \
    | assert_equals "adopt chemins deguises : rien n'est deplace" "reel reel absent"
mkdir -p "$H/.config/gh"
echo tok > "$H/.config/gh/hosts.yml"
zd 'zanvil-dotfiles adopt .config/gh/hosts.yml >/dev/null 2>&1; echo "rc=$?"' | assert_equals "adopt gh/hosts.yml : code 1" "rc=1"
{ kind "$H/.config/gh/hosts.yml"; } | assert_equals "adopt gh/hosts.yml : fichier non deplace" "reel"

rm "$H/.config/demo/a.conf"
zd 'zanvil-dotfiles apply >/dev/null 2>&1; echo "rc=$?"' | assert_equals "apply hors depot git : code 1" "rc=1"
{ kind "$H/.config/demo/a.conf"; } | assert_equals "apply hors depot git : aucun lien" "absent"

echo "perso sans dossier stow/perso"
rm -rf "$H"; mkdir -p "$H"
ZD_PROFILE=perso zd 'zanvil-dotfiles link >/dev/null 2>&1; echo "rc=$?"' | assert_equals "perso sans stow/perso : code 0" "rc=0"
{ echo "$(kind "$H/.config/demo/a.conf") $(kind "$H/.config/demo/b.conf")"; } \
    | assert_equals "perso : common lie, pro ignore" "lien absent"
mkdir -p "$TEST_TMPDIR/empty/stow"
ZD_DOT="$TEST_TMPDIR/empty" zd 'zanvil-dotfiles link; echo "rc=$?"' > "$TEST_TMPDIR/out"
tail -1 "$TEST_TMPDIR/out" | assert_equals "aucun paquet : code 0" "rc=0"
grep -c 'rien a lier' "$TEST_TMPDIR/out" | tr -d ' ' | assert_equals "aucun paquet : info" "1"

echo "pull : clone si absent"
BARE="$TEST_TMPDIR/remote.git"
SEED="$TEST_TMPDIR/seed"
GC=(-c user.name=t -c user.email=t@t)
mkdir -p "$SEED/stow/common/.config/demo" "$SEED/brew"
echo repo-a > "$SEED/stow/common/.config/demo/a.conf"
: > "$SEED/brew/common.Brewfile"; : > "$SEED/brew/pro.Brewfile"
git init -q "$SEED"
git -C "$SEED" add -A
git -C "$SEED" "${GC[@]}" commit -q -m seed
git clone -q --bare "$SEED" "$BARE"
CL="$TEST_TMPDIR/clone"
ZD_DOT="$CL" ZANVIL_DOTFILES_REPO="file://$BARE" zd 'zanvil-dotfiles pull >/dev/null 2>&1; echo "rc=$?"' \
    | assert_equals "pull dossier absent : code 0" "rc=0"
{ [[ -d "$CL/.git" ]] && echo oui || echo non; } | assert_equals "pull dossier absent : depot clone" "oui"
mkdir -p "$TEST_TMPDIR/plain"; echo keep > "$TEST_TMPDIR/plain/f"
ZD_DOT="$TEST_TMPDIR/plain" ZANVIL_DOTFILES_REPO="file://$BARE" zd 'zanvil-dotfiles pull >/dev/null 2>&1; echo "rc=$?"' \
    | assert_equals "pull dossier sans .git : code 1" "rc=1"
ls "$TEST_TMPDIR/plain" | assert_equals "pull dossier sans .git : intact" "f"
ls -d "$TEST_TMPDIR"/*.tmp.* 2>/dev/null | wc -l | tr -d ' ' | assert_equals "pull : pas de dossier temporaire restant" "0"

echo "apply : pull, install, link, cleanup"
BIN="$TEST_TMPDIR/bin"; LOG="$TEST_TMPDIR/brew.log"; mkdir -p "$BIN"
cat > "$BIN/brew" <<EOF2
#!/bin/sh
echo "\$*" >> "$LOG"
case "\$*" in
    *"bundle install"*) [ -n "\$FAKE_INSTALL_FAIL" ] && exit 1; exit 0 ;;
    *"bundle cleanup"*--force*) exit 0 ;;
    *"bundle cleanup"*) printf 'Would uninstall formulae:\nredis\n'; exit 1 ;;
esac
EOF2
chmod +x "$BIN/brew"
rm -rf "$H"; mkdir -p "$H"; : > "$LOG"
PATH="$BIN:$PATH" ZD_DOT="$CL" zd 'zanvil-dotfiles apply </dev/null >/dev/null 2>&1; echo "rc=$?"' | assert_equals "apply : code 0" "rc=0"
sed 's/ --file=.*//' "$LOG" | tr '\n' ';' | assert_equals "apply : install puis cleanup (simulation seule hors terminal)" \
    "bundle install --no-upgrade;bundle cleanup --formula --cask --tap;"
kind "$H/.config/demo/a.conf" | assert_equals "apply : lien cree" "lien"
rm -rf "$H"; mkdir -p "$H"; : > "$LOG"
FAKE_INSTALL_FAIL=1 PATH="$BIN:$PATH" ZD_DOT="$CL" zd 'zanvil-dotfiles apply </dev/null >/dev/null 2>&1; echo "rc=$?"' | assert_equals "apply install en echec : code 1" "rc=1"
grep -c 'bundle cleanup' "$LOG" | tr -d ' ' | assert_equals "apply install en echec : pas de cleanup" "0"
kind "$H/.config/demo/a.conf" | assert_equals "apply install en echec : pas de lien" "absent"

zd 'zanvil-dotfiles status' | grep -c 'Brewfile' | tr -d ' ' | assert_equals "status : liste les 3 Brewfile" "3"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
