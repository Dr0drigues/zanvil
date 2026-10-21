#!/usr/bin/env bash
# Verifie le socle de zanvil-dotfiles migrate : preconditions, profil, depot, ecriture ciblee de config.zsh.
# Usage : scripts/tests/dotfiles-migrate.test.sh
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

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
H="$TEST_TMPDIR/home"; DOT="$TEST_TMPDIR/dotfiles"; BIN="$TEST_TMPDIR/bin"; CFGDIR="$TEST_TMPDIR/zdir"
mkdir -p "$H" "$BIN" "$CFGDIR/brew"
echo "" > "$CFGDIR/brew/base.Brewfile"
for t in brew stow; do printf '#!/bin/sh\nexit 0\n' > "$BIN/$t"; chmod +x "$BIN/$t"; done
GITDIR=$(dirname "$(command -v git)")

# $1 = commande, $2 = stdin ; ZD_ENV = assignations VAR=val ; ZD_PATH = PATH de remplacement
zd() {
    # shellcheck disable=SC2086
    env HOME="$H" ZANVIL_DIR="$CFGDIR" ZANVIL_DOTFILES_DIR="${ZD_DOT:-$DOT}" ${ZD_ENV:-} PATH="${ZD_PATH:-$BIN:$GITDIR:/usr/bin:/bin}" \
        zsh -f -c "
        source '$ROOT/core/ui.zsh'
        source '$ROOT/core/commands/dotfiles.zsh'
        source '$ROOT/core/commands/dotfiles_migrate.zsh'
        $1
    " 2>&1 <<<"${2:-}"
}

# --- preconditions ---
out=$(env HOME="$H" ZANVIL_DIR="$CFGDIR" PATH="$BIN:$GITDIR:/usr/bin:/bin" zsh -f -c "
    source '$ROOT/core/ui.zsh'; source '$ROOT/core/commands/dotfiles.zsh'; source '$ROOT/core/commands/dotfiles_migrate.zsh'
    _zanvil_dotfiles_migrate; echo rc=\$?" 2>&1 </dev/null)
{ [[ "$out" == *terminal* && "$out" == *rc=1 ]] && echo ok || echo "$out"; } | assert_equals "sans terminal : refus, code 1" ok

mkdir -p "$TEST_TMPDIR/nostow"; printf '#!/bin/sh\nexit 0\n' > "$TEST_TMPDIR/nostow/brew"; chmod +x "$TEST_TMPDIR/nostow/brew"
out=$(ZD_PATH="$TEST_TMPDIR/nostow:$GITDIR:/usr/bin:/bin" ZD_ENV="ZANVIL_ASSUME_TTY=1" zd '_zanvil_dotfiles_migrate; echo rc=$?')
{ [[ "$out" == *stow* && "$out" == *rc=1 ]] && echo ok || echo "$out"; } | assert_equals "stow absent : nomme, code 1" ok

# --- config_key ---
C="$TEST_TMPDIR/config.zsh"
printf '%s\n' '# ZANVIL_PROFILE=perso' 'MA_VARIABLE=1' > "$C"
zd "_zanvil_dotfiles_config_key '$C' ZANVIL_PROFILE pro" >/dev/null
{ cat "$C"; } | assert_equals "config_key : ajoute la cle, le reste intact" "# ZANVIL_PROFILE=perso
MA_VARIABLE=1
ZANVIL_PROFILE=pro"
printf '%s\n' 'ZANVIL_PROFILE=perso' > "$C"; before=$(cksum < "$C")
zd "_zanvil_dotfiles_config_key '$C' ZANVIL_PROFILE pro" >/dev/null
{ [[ "$(cksum < "$C")" == "$before" ]] && echo inchange || cat "$C"; } | assert_equals "config_key : cle deja definie respectee" inchange
rm -f "$C"
zd "_zanvil_dotfiles_config_key '$C' ZANVIL_DOTFILES_REPO 'git@x:y/z.git'" >/dev/null
{ cat "$C"; } | assert_equals "config_key : fichier absent cree, valeur quotee" 'ZANVIL_DOTFILES_REPO="git@x:y/z.git"'
printf 'A=1' > "$C"
zd "_zanvil_dotfiles_config_key '$C' ZANVIL_WORK_DETECTED true" >/dev/null
{ cat "$C"; } | assert_equals "config_key : derniere ligne sans retour chariot" "A=1
ZANVIL_WORK_DETECTED=true"

rm -f "$C"
zd "_zanvil_dotfiles_config_key '$C' ZANVIL_DOTFILES_REPO 'a \"b\" \$HOME \`x\` \\\\y'" >/dev/null
zsh -f -c "source '$C'; print -r -- \"\$ZANVIL_DOTFILES_REPO\"" | assert_equals "config_key : valeur avec espace, guillemet, \$, backtick relue a l'identique" 'a "b" $HOME `x` \y'

# --- profil ---
printf 'A=1\n' > "$CFGDIR/config.zsh"; before=$(cksum < "$CFGDIR/config.zsh")
out=$(ZD_ENV="ZANVIL_ASSUME_TTY=1 ZANVIL_PROFILE=work" zd '_zanvil_dotfiles_migrate; echo rc=$?')
{ [[ "$out" == *"'work'"* && "$out" == *rc=1 && "$(cksum < "$CFGDIR/config.zsh")" == "$before" ]] && echo ok || echo "$out"; } | assert_equals "profil invalide pre-defini : refus, config.zsh intact" ok
rm -f "$CFGDIR/config.zsh"
ZD_ENV="ZANVIL_PROFILE=perso" zd '_zanvil_dotfiles_migrate_profile; echo "REPLY=$REPLY"' | assert_equals "profil defini : aucune question" "REPLY=perso"
ZD_ENV="ZANVIL_BOULANGER_DETECTED=true" zd '_zanvil_dotfiles_migrate_profile >/dev/null; echo "REPLY=$REPLY"' "" | assert_equals "profil : defaut pro si Boulanger detecte" "REPLY=pro"
zd '_zanvil_dotfiles_migrate_profile >/dev/null; echo "REPLY=$REPLY"' "" | assert_equals "profil : defaut perso" "REPLY=perso"
zd '_zanvil_dotfiles_migrate_profile >/dev/null 2>&1; echo "rc=$?"' "autre
autre
autre" | tail -1 | assert_equals "profil : trois reponses invalides, code 1" "rc=1"

# --- depot sale ---
command git init -q "$DOT"; echo v1 > "$DOT/f"; command git -C "$DOT" add f; command git -C "$DOT" commit -qm init
command git -C "$DOT" remote add origin /nonexistent/invalid.git
echo modif > "$DOT/f"
out=$(zd '_zanvil_dotfiles_migrate_repo; echo "rc=$?"')
{ [[ "$out" == *rc=0 && "$out" != *echoue* ]] && echo ok || echo "$out"; } | assert_equals "depot sale : pull saute, code 0" ok
{ cat "$DOT/f"; } | assert_equals "depot sale : modification intacte" modif
zd '_zanvil_dotfiles_migrate_repo >/dev/null; echo "$REPLY"' | assert_equals "depot : REPLY = origin quand REPO vide" "/nonexistent/invalid.git"

# --- Brewfile manquant ---
out=$(ZD_ENV="ZANVIL_ASSUME_TTY=1 ZANVIL_PROFILE=pro" zd '_zanvil_dotfiles_migrate; echo rc=$?')
{ [[ "$out" == *"brew bundle dump"* && "$out" == *rc=1 ]] && echo ok || echo "$out"; } | assert_equals "Brewfile manquant : code 1 et brew bundle dump" ok
{ [[ "$(cat "$CFGDIR/config.zsh" 2>/dev/null)" == *ZANVIL_PROFILE=pro* ]] && echo ecrit || echo non; } | assert_equals "migrate : config.zsh ecrit dans ZANVIL_DIR" ecrit

# --- casks a adopter ---
APPS="$TEST_TMPDIR/apps"; BIN2="$TEST_TMPDIR/bin2"; BF="$TEST_TMPDIR/cask.Brewfile"; LOG="$TEST_TMPDIR/brew.log"
mkdir -p "$APPS/GitHub Desktop.app" "$APPS/Deja.app" "$BIN2"
printf '%s\n' 'cask "gh-desk"' 'cask "absente"' 'cask "deja"' 'cask "police"' 'brew "jq"' > "$BF"
cat > "$BIN2/brew" <<'FAKE'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
case "$1 $2" in
    "list --cask") echo deja ;;
    "info --cask") echo '{"formulae":[],"casks":[{"token":"gh-desk","artifacts":[{"app":["GitHub Desktop.app"]},{"zap":[]}]},{"token":"absente","artifacts":[{"app":["Absente.app"]}]},{"token":"deja","artifacts":[{"app":["Deja.app"]}]},{"token":"police","artifacts":[{"font":["x.ttf"]}]}]}' ;;
    "install --cask") [ -n "$FAKE_ADOPT_FAIL" ] && exit 1; exit 0 ;;
esac
FAKE
chmod +x "$BIN2/brew"
ZB="ZANVIL_APPLICATIONS_DIR=$APPS FAKE_LOG=$LOG"
ZD_PATH="$BIN2:$GITDIR:/usr/bin:/bin" ZD_ENV="$ZB" zd "_zanvil_dotfiles_adopt_candidates '$BF'" | assert_equals "adopt : candidat = gh-desk seul (espaces, deja gere, absente, sans app)" gh-desk
{ grep -c '^info --cask --json=v2' "$LOG"; } | assert_equals "adopt : un seul brew info" 1
: > "$LOG"
ZD_PATH="$BIN2:$GITDIR:/usr/bin:/bin" ZD_ENV="$ZB ZANVIL_ASSUME_TTY=1" zd "_zanvil_dotfiles_migrate_casks '$BF'; echo \"rc=\$? n=\$REPLY\"" oui | grep -o 'rc=.*' | assert_equals "adopt oui : code 0, 1 reussite" "rc=0 n=1"
{ grep -c '^install --cask --adopt gh-desk$' "$LOG"; } | assert_equals "adopt oui : install --adopt gh-desk" 1
: > "$LOG"
ZD_PATH="$BIN2:$GITDIR:/usr/bin:/bin" ZD_ENV="$ZB ZANVIL_ASSUME_TTY=1" zd "_zanvil_dotfiles_migrate_casks '$BF'" non >/dev/null
{ grep -c -- '--adopt' "$LOG"; } | assert_equals "adopt non : aucun --adopt" 0
out=$(ZD_PATH="$BIN2:$GITDIR:/usr/bin:/bin" ZD_ENV="$ZB ZANVIL_ASSUME_TTY=1 FAKE_ADOPT_FAIL=1" zd "_zanvil_dotfiles_migrate_casks '$BF'; echo \"rc=\$? n=\$REPLY failed=\${_ZANVIL_MIGRATE_FAILED_CASKS[*]}\"" oui)
{ [[ "$out" == *"rc=0 n=0 failed=gh-desk"* && "$out" == *"brew install --cask --adopt gh-desk"* ]] && echo ok || echo "$out"; } | assert_equals "adopt echec : code 0, liste des echecs, commande manuelle" ok

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
