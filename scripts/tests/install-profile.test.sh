#!/usr/bin/env bash
# Teste les morceaux isolables d'install.sh : options, clone du depot dotfiles,
# config.zsh genere. Les fonctions sont extraites d'install.sh (jamais execute en entier).
# Usage : scripts/tests/install-profile.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
INSTALL="$ROOT/install.sh"

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

echo "options"
bash "$INSTALL" --profile autre >/dev/null 2>&1; echo "rc=$?" | assert_equals "--profile autre : code 1" "rc=1"
bash "$INSTALL" --profile >/dev/null 2>&1; echo "rc=$?" | assert_equals "--profile sans valeur : code 1" "rc=1"
bash "$INSTALL" --help 2>&1 | grep -c -e '--profile' -e '--dotfiles' | assert_equals "--help documente les deux flags" "2"

# Charge une fonction d'install.sh sans executer le script
load_fn() { eval "$(sed -n "/^$1()/,/^}/p" "$INSTALL")"; }
RED= GREEN= YELLOW= BLUE= NC=
log_warn() { echo "WARN $1"; }
log_info() { :; }
log_success() { :; }
load_fn _install_clone_dotfiles
load_fn _install_write_config

echo "_install_clone_dotfiles"
D="$TEST_TMPDIR/dot"
_install_clone_dotfiles "file:///nope" "$D" >/dev/null 2>&1; echo "rc=$?" | assert_equals "URL inexistante : code 1" "rc=1"
ls -d "$D" "$D".tmp.* 2>/dev/null | wc -l | tr -d ' ' | assert_equals "rien ne reste apres l'echec" "0"
_install_clone_dotfiles "file:///nope" "$D" 2>&1 | grep -c 'cle SSH' | assert_equals "avertit avec la cause probable" "1"

BARE="$TEST_TMPDIR/remote.git"
SEED="$TEST_TMPDIR/seed"
GC=(-c user.name=t -c user.email=t@t)
git init -q --bare "$BARE"
git -C "$BARE" symbolic-ref HEAD refs/heads/main
git init -q "$SEED"
git -C "$SEED" "${GC[@]}" commit -q --allow-empty -m seed
git -C "$SEED" push -q "$BARE" HEAD:refs/heads/main
_install_clone_dotfiles "file://$BARE" "$D" >/dev/null 2>&1; echo "rc=$?" | assert_equals "depot valide : code 0" "rc=0"
[[ -d "$D/.git" ]] && echo oui | assert_equals "<dir>/.git existe" "oui"
git -C "$SEED" "${GC[@]}" commit -q --allow-empty -m two
git -C "$SEED" push -q "$BARE" HEAD:refs/heads/main
_install_clone_dotfiles "file://$BARE" "$D" >/dev/null 2>&1; echo "rc=$?" | assert_equals "dossier existant : pull, code 0" "rc=0"
git -C "$D" log --oneline | wc -l | tr -d ' ' | assert_equals "le pull a recupere le commit" "2"

echo "_install_write_config"
MODULE_GITLAB=true MODULE_DOCKER=true MODULE_MISE=true MODULE_NUSHELL=true MODULE_KUBE=true
AUTO_UPDATE=true UPDATE_FREQ=7 UPDATE_MODE=prompt DOTFILES_REPO=""
for p in pro perso; do
    PROFILE=$p
    WORK_DETECTED=false
    [[ $p = pro ]] && WORK_DETECTED=true
    CONFIG_FILE="$TEST_TMPDIR/config-$p.zsh"
    _install_write_config
    grep -c "^ZANVIL_PROFILE=$p\$" "$CONFIG_FILE" | assert_equals "$p : ZANVIL_PROFILE=$p" "1"
    grep "^ZANVIL_WORK_DETECTED=" "$CONFIG_FILE" | assert_equals "$p : ZANVIL_WORK_DETECTED" "ZANVIL_WORK_DETECTED=$WORK_DETECTED"
done
grep "^ZANVIL_DOTFILES_REPO=" "$TEST_TMPDIR/config-pro.zsh" | assert_equals "repo vide ecrit entre guillemets" 'ZANVIL_DOTFILES_REPO=""'

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
