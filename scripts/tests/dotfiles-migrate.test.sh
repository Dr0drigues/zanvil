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
    "info --cask") [ -n "$FAKE_INFO_FAIL" ] && { echo "Error: boom" >&2; exit 1; }; echo '{"formulae":[],"casks":[{"token":"gh-desk","artifacts":[{"app":["GitHub Desktop.app"]},{"zap":[]}]},{"token":"absente","artifacts":[{"app":["Absente.app"]}]},{"token":"deja","artifacts":[{"app":["Deja.app"]}]},{"token":"police","artifacts":[{"font":["x.ttf"]}]}]}' ;;
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
: > "$LOG"
out=$(ZD_PATH="$BIN2:$GITDIR:/usr/bin:/bin" ZD_ENV="$ZB ZANVIL_ASSUME_TTY=1 FAKE_INFO_FAIL=1" zd "_zanvil_dotfiles_migrate_casks '$BF'; echo \"rc=\$?\"" oui)
{ [[ "$out" == *"brew info a echoue"* && "$out" == *"boom"* && "$out" != *"Aucune appli"* && "$out" == *"rc=0"* && "$(grep -c -- '--adopt' "$LOG")" == 0 ]] && echo ok || echo "$out"; } | assert_equals "info en echec : avertissement, pas de faux 'aucune appli', rien adopte, code 0" ok

# --- configs en conflit ---
# Fixture fraiche dans $TEST_TMPDIR/c$1 : CH = HOME, CD = depot, CO = dossiers pointes par les liens.
mkconf() {
    local d="$TEST_TMPDIR/c$1"
    CH="$d/home"; CD="$d/dot"; CO="$d/other"
    mkdir -p "$CD/stow/common/.config/a" "$CD/stow/common/.config/b" "$CD/stow/pro/.config" "$CH/.config/a" "$CO/b"
    echo same > "$CD/stow/common/.config/a/same.conf"; echo same > "$CH/.config/a/same.conf"
    echo depot > "$CD/stow/common/.config/a/diff.conf"; echo local > "$CH/.config/a/diff.conf"
    echo new > "$CD/stow/common/.config/a/new.conf"
    echo x > "$CD/stow/common/.config/b/x.conf"; ln -s "$CO/b" "$CH/.config/b"
    echo p > "$CD/stow/pro/.config/p.conf"; echo autre > "$CO/p.conf"; ln -s "$CO/p.conf" "$CH/.config/p.conf"
    command git init -q "$CD"; command git -C "$CD" add -A; command git -C "$CD" commit -qm init
}
# $1 = reponses ; sortie de la fonction puis "rc=.. n=.. bk=.."
zconf() {
    H="$CH" ZD_DOT="$CD" ZD_ENV="ZANVIL_PROFILE=pro" zd '_zanvil_dotfiles_migrate_configs; echo "rc=$? n=$REPLY bk=$_ZANVIL_MIGRATE_BACKUP"' "$1"
}
bkdir() { ls -d "$CH"/.zanvil-backup/* 2>/dev/null; }

mkconf d; out=$(zconf d); BK=$(bkdir)
{ [[ "$out" == *"rc=0 n=2 bk=$BK" && -n "$BK" ]] && echo ok || echo "$out"; } | assert_equals "conflit d : code 0, 2 passes, REPLY et chemin de sauvegarde" ok
{ cat "$BK/.config/a/same.conf" "$BK/.config/a/diff.conf"; } | assert_equals "conflit d : identique et local sauvegardes avec leur contenu" "same
local"
{ ls -A "$CH/.config/a"; } | assert_equals "conflit d : sortis de HOME, new.conf pas cree" ""
{ [[ "$out" == *"-depot"* && "$out" == *"+local"* ]] && echo ok || echo "$out"; } | assert_equals "conflit d : diff -u affiche" ok
{ [[ "$out" == *".config/b"* && "$out" == *"p.conf"* ]] && echo ok || echo "$out"; } | assert_equals "liens : parent lie et lien ailleurs signales" ok
{ ls -A "$CO/b"; } | assert_equals "parent lie : rien ajoute sous le dossier pointe" ""
{ readlink "$CH/.config/p.conf"; } | assert_equals "lien ailleurs : intact" "$CO/p.conf"
{ cat "$CD/stow/common/.config/a/diff.conf"; } | assert_equals "conflit d : depot inchange" depot

mkconf l; out=$(zconf L); BK=$(bkdir)
{ cat "$CD/stow/common/.config/a/diff.conf"; } | assert_equals "conflit l : le depot prend la version locale" local
{ command git -C "$CD" log -1 --format=%s; } | assert_equals "conflit l : commit local" "migrate: version locale de .config/a/diff.conf"
{ command git -C "$CD" status --porcelain; } | assert_equals "conflit l : rien d'autre en attente" ""
{ cat "$BK/.config/a/diff.conf"; [[ -e "$CH/.config/a/diff.conf" ]] && echo encore-la; } | assert_equals "conflit l : original sauvegarde et sorti de HOME" local

i=0
for ans in p "" x; do
    i=$((i + 1)); mkconf "p$i"; out=$(zconf "$ans")
    { [[ "$(cat "$CH/.config/a/diff.conf")" == local && "$out" == *"rc=0 n=3 "* ]] && echo ok || echo "$out"; } | assert_equals "conflit '$ans' : passe, laisse en place, compte" ok
done

CH="$TEST_TMPDIR/cnone/home"; CD="$TEST_TMPDIR/cnone/dot"
mkdir -p "$CH/.config" "$CD/stow/common/.config"; echo v > "$CD/stow/common/.config/v.conf"
ln -s "$CD/stow/common/.config/v.conf" "$CH/.config/v.conf"
out=$(zconf "")
{ [[ "$out" == *"rc=0 n=0 bk=" && ! -e "$CH/.zanvil-backup" ]] && echo ok || echo "$out"; } | assert_equals "sans conflit : sauvegarde vide, aucun dossier cree, lien deja en place ignore" ok

mkconf ro; chmod 555 "$CH/.config/a"; out=$(zconf d); chmod 755 "$CH/.config/a"
{ [[ "$out" == *"rc=1"* && "$(cat "$CH/.config/a/same.conf")" == same ]] && echo ok || echo "$out"; } | assert_equals "deplacement impossible : code 1, fichier en place" ok; echo "$out" | grep -c "Deplacement impossible" | assert_equals "deplacement impossible : message" 1

# fichiers ignores par Stow : jamais deplaces
CH="$TEST_TMPDIR/cign/home"; CD="$TEST_TMPDIR/cign/dot"
mkdir -p "$CH" "$CD/stow/common/sub/.git" "$CD/stow/pro"
for f in .gitignore README.md sub/.git/config; do echo i > "$CD/stow/common/$f"; mkdir -p "$(dirname "$CH/$f")"; echo i > "$CH/$f"; done
echo i > "$CD/stow/pro/.x"; echo i > "$CH/.x"; echo '\.x' > "$CD/stow/pro/.stow-local-ignore"
out=$(zconf "")
{ [[ -f "$CH/.gitignore" && -f "$CH/README.md" && -f "$CH/sub/.git/config" && -f "$CH/.x" && ! -e "$CH/.zanvil-backup" ]] && echo ok || echo "$out"; } | assert_equals "ignores par Stow et .stow-local-ignore : rien deplace, aucune sauvegarde" ok
{ [[ "$out" == *".stow-local-ignore"* && "$out" == *"rc=0 n=1 "* ]] && echo ok || echo "$out"; } | assert_equals ".stow-local-ignore : signale, fichiers du paquet passes" ok
for o in noextendedglob extendedglob; do
    zd "setopt $o; for r in README.md a/README.md LICENSE.txt COPYING 'f~' '#a#' '.#x' a/CVS/b .zshrc a/RCSx; do _zanvil_dotfiles_stow_ignored \"\$r\" && printf 'I ' || printf 'L '; done" \
        | assert_equals "ignores Stow ($o) : README racine, LICENSE, COPYING, ~, #..#, .#, CVS ; pas a/README ni .zshrc" "I L I I I I I I L L "
done

# commit en echec apres l : depot restaure, local en place
mkconf lfail; echo aa > "$CD/stow/common/.config/.aa"; ln -s "$CO/p.conf" "$CH/.config/.aa" # passe avant diff.conf
command git -C "$CD" add -A; command git -C "$CD" commit -qm aa
printf '#!/bin/sh\nexit 1\n' > "$CD/.git/hooks/pre-commit"; chmod +x "$CD/.git/hooks/pre-commit"
out=$(zconf l)
{ [[ "$out" == *"rc=1 n=1 "* && "$out" == *restaure* && "$(cat "$CH/.config/a/diff.conf")" == local && "$(cat "$CD/stow/common/.config/a/diff.conf")" == depot && -z "$(command git -C "$CD" status --porcelain)" ]] && echo ok || echo "$out"; } | assert_equals "l, commit en echec : code 1, REPLY a jour, depot et index restaures, local en place" ok

# meme chemin dans deux couches : une seule question, compte une fois
CH="$TEST_TMPDIR/cdup/home"; CD="$TEST_TMPDIR/cdup/dot"
mkdir -p "$CH" "$CD/stow/common" "$CD/stow/pro"
echo c > "$CD/stow/common/.dup"; echo p > "$CD/stow/pro/.dup"; echo l > "$CH/.dup"
out=$(zconf "p
p")
{ [[ "$(grep -o '\[d\]epot' <<<"$out" | wc -l | tr -d ' ')" == 1 && "$out" == *"deux couches"* && "$out" == *"rc=0 n=1 "* ]] && echo ok || echo "$out"; } | assert_equals "deux couches : une question, signale, compte une fois" ok

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
