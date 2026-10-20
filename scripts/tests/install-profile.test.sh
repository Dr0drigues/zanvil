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
load_fn _install_work_detected

echo "_install_clone_dotfiles"
D="$TEST_TMPDIR/dot"
_install_clone_dotfiles "file:///nope" "$D" >/dev/null 2>&1; echo "rc=$?" | assert_equals "URL inexistante : code 1" "rc=1"
mkdir -p "$TEST_TMPDIR/plain"; echo keep > "$TEST_TMPDIR/plain/f"
_install_clone_dotfiles "file:///nope" "$TEST_TMPDIR/plain" >/dev/null 2>&1; echo "rc=$?" | assert_equals "dossier sans .git : code 1" "rc=1"
ls -d "$TEST_TMPDIR"/plain/* "$TEST_TMPDIR"/plain.tmp.* 2>/dev/null | xargs -n1 basename | assert_equals "dossier sans .git intact, pas de tmp" "f"
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
AUTO_UPDATE=true UPDATE_FREQ=7 UPDATE_MODE=prompt DOTFILES_REPO="" DOTFILES_DIR=""
for p in pro perso; do
    PROFILE=$p
    WORK_DETECTED=$(_install_work_detected "$p")
    CONFIG_FILE="$TEST_TMPDIR/config-$p.zsh"
    _install_write_config
    grep -c "^ZANVIL_PROFILE=$p\$" "$CONFIG_FILE" | assert_equals "$p : ZANVIL_PROFILE=$p" "1"
    grep "^ZANVIL_WORK_DETECTED=" "$CONFIG_FILE" | assert_equals "$p : ZANVIL_WORK_DETECTED" "ZANVIL_WORK_DETECTED=$WORK_DETECTED"
done
grep "^ZANVIL_DOTFILES_REPO=" "$TEST_TMPDIR/config-pro.zsh" | assert_equals "repo vide ecrit entre guillemets" 'ZANVIL_DOTFILES_REPO=""'

DOTFILES_DIR="/d/.dotfiles"
_install_write_config
grep "^ZANVIL_DOTFILES_DIR=" "$CONFIG_FILE" | assert_equals "ZANVIL_DOTFILES_DIR ecrit" 'ZANVIL_DOTFILES_DIR="/d/.dotfiles"'

echo "_install_existing_value"
load_fn _install_existing_value
_install_existing_value "$TEST_TMPDIR/absent.zsh" ZANVIL_PROFILE | assert_equals "fichier absent : vide" ""
PREV="$TEST_TMPDIR/prev.zsh"
printf 'ZANVIL_PROFILE=pro\nZANVIL_DOTFILES_REPO="git@h:me/dot.git"\nZANVIL_DOTFILES_DIR="/x/dot"\n' > "$PREV"
_install_existing_value "$PREV" ZANVIL_PROFILE | assert_equals "profil existant" "pro"
_install_existing_value "$PREV" ZANVIL_DOTFILES_REPO | assert_equals "repo existant, sans guillemets" "git@h:me/dot.git"
_install_existing_value "$PREV" ZANVIL_DOTFILES_DIR | assert_equals "dossier existant" "/x/dot"
# config.zsh relu = config.zsh ecrit : un second passage garde les valeurs
PROFILE=pro DOTFILES_REPO="git@h:me/dot.git" DOTFILES_DIR="/x/dot" WORK_DETECTED=true CONFIG_FILE="$TEST_TMPDIR/round.zsh"
_install_write_config
for v in ZANVIL_PROFILE ZANVIL_DOTFILES_REPO ZANVIL_DOTFILES_DIR; do _install_existing_value "$CONFIG_FILE" $v; done | tr '\n' ' ' \
    | assert_equals "aller-retour config.zsh" "pro git@h:me/dot.git /x/dot "

echo "_install_module_default"
load_fn _install_module_default
_install_module_default perso | assert_equals "perso : kube et docker desactives" "false"
_install_module_default pro | assert_equals "pro : actives" "true"

echo "_install_check_dotfiles_access"
load_fn _install_check_dotfiles_access
_install_check_dotfiles_access "file:///nope" 2>&1 | grep -c 'cle SSH' | assert_equals "depot inaccessible : avertit" "1"
_install_check_dotfiles_access "file://$BARE" 2>&1 | wc -l | tr -d ' ' | assert_equals "depot accessible : silencieux" "0"

echo "_install_work_detected"
_install_work_detected pro | assert_equals "pro : true" "true"
_install_work_detected perso | assert_equals "perso : false" "false"

echo "lazygit"
LGZ="$TEST_TMPDIR/lg"
lg_env() { # $1 = setup shell
    rm -rf "$LGZ"; mkdir -p "$LGZ/home/.config/lazygit" "$LGZ/bin" "$LGZ/z/config/lazygit"
    : > "$LGZ/bin/lazygit"; chmod +x "$LGZ/bin/lazygit"
    eval "$1"
    HOME="$LGZ/home" ZANVIL_DIR="$LGZ/z" ZANVIL_MODULE_LAZYGIT=true PATH="$LGZ/bin:/usr/bin:/bin" \
        zsh -f -c "source '$ROOT/modules/tools/lazygit/init.zsh'; print -r -- \"\${LG_CONFIG_FILE:-vide}\"" 2>&1
}
LNK='echo x > "$LGZ/real.yml"; ln -s "$LGZ/real.yml" "$LGZ/home/.config/lazygit/config.yml"'
lg_env ':' | assert_equals "sans lien : config zanvil" "$LGZ/z/config/lazygit/config.yml"
lg_env "$LNK" | assert_equals "lien : config dotfiles" "$LGZ/home/.config/lazygit/config.yml"
lg_env "$LNK"'; : > "$LGZ/home/.config/lazygit/config-local.yml"' \
    | assert_equals "lien + config-local" "$LGZ/home/.config/lazygit/config.yml,$LGZ/home/.config/lazygit/config-local.yml"

echo "deployeurs : un lien (dotfiles) n est jamais ecrit"
DZ="$TEST_TMPDIR/dep"
rm -rf "$DZ"; mkdir -p "$DZ/home" "$DZ/bin" "$DZ/repo"
printf '#!/bin/sh\necho delta 0\n' > "$DZ/bin/delta"; : > "$DZ/bin/k9s"; chmod +x "$DZ/bin/delta" "$DZ/bin/k9s"
echo "[user]" > "$DZ/repo/gitconfig"; ln -s "$DZ/repo/gitconfig" "$DZ/home/.gitconfig"
HOME="$DZ/home" ZANVIL_DIR="$ROOT" ZANVIL_MODULE_DELTA=true PATH="$DZ/bin:/usr/bin:/bin" zsh -f -c "
    source '$ROOT/core/ui.zsh'; source '$ROOT/modules/tools/delta/init.zsh'; delta_setup" >/dev/null 2>&1
cat "$DZ/repo/gitconfig" | assert_equals "delta : .gitconfig lie intact" "[user]"
K9D="$DZ/k9s"; mkdir -p "$K9D/plugins"
echo mine > "$DZ/repo/hotkeys.yaml"; ln -s "$DZ/repo/hotkeys.yaml" "$K9D/hotkeys.yaml"
echo mine > "$DZ/repo/zanvil.yaml"; ln -s "$DZ/repo/zanvil.yaml" "$K9D/plugins/zanvil.yaml"
HOME="$DZ/home" ZANVIL_DIR="$ROOT" ZANVIL_MODULE_KUBE=true PATH="$DZ/bin:/usr/bin:/bin" zsh -f -c "
    source '$ROOT/core/ui.zsh'; source '$ROOT/modules/kube/kube_config.zsh'
    _k9s_config_dir() { echo '$K9D'; }
    _zanvil_k9s_apply_skin() { :; }
    kube_k9s_setup" >/dev/null 2>&1
echo "$(cat "$DZ/repo/hotkeys.yaml") $(cat "$DZ/repo/zanvil.yaml")" | assert_equals "k9s : hotkeys et plugins lies intacts" "mine mine"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
