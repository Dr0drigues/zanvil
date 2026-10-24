#!/usr/bin/env bash
# Verifie la mise a jour automatique (core/lifecycle/auto_update.zsh) : echeance, avance rapide
# seulement (main, arbre propre, pas de divergence), notification unique par situation, verrou,
# rechargement des shells ouverts au precmd, aucun git au premier plan du demarrage.
# Vrai git sur des depots temporaires (origin = depot nu, clone = ZANVIL_DIR), faux osascript.
# Usage : scripts/tests/auto-update.test.sh
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

H="$TEST_TMPDIR/home"
BIN="$TEST_TMPDIR/bin"        # faux osascript
FGBIN="$TEST_TMPDIR/fgbin"    # faux git qui journalise
BARE="$TEST_TMPDIR/origin.git"
W="$TEST_TMPDIR/upstream"     # clone qui publie les nouvelles versions
Z="$TEST_TMPDIR/zanvil"       # ZANVIL_DIR de test : jamais le vrai depot
NLOG="$TEST_TMPDIR/notify.log"
GLOG="$TEST_TMPDIR/git.log"
mkdir -p "$H" "$BIN" "$FGBIN"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export HOME="$H" GIT_CONFIG_NOSYSTEM=1

# PATH isole : symlinks vers les seuls utilitaires systeme requis (dont le vrai git)
SYSBIN="$TEST_TMPDIR/sysbin"; mkdir -p "$SYSBIN"
for u in zsh sh bash env git cat cp mv rm ln mkdir rmdir touch chmod ls sort uniq tr sed awk grep head tail cut wc comm date dirname basename mktemp printf sleep; do
    p=$(command -v "$u" 2>/dev/null) && [[ "$p" == /* ]] && ln -sf "$p" "$SYSBIN/$u"
done
printf '#!/bin/sh\nshift 7; echo "$*" >> "%s"\n' "$NLOG" > "$BIN/osascript"   # garde le message (argv)
printf '#!/bin/sh\necho "git $*" >> "%s"\nexit 1\n' "$GLOG" > "$FGBIN/git"
chmod +x "$BIN/osascript" "$FGBIN/git"
TPATH="$BIN:$SYSBIN"
[[ "$(PATH="$TPATH" command -v osascript)" == "$BIN/osascript" ]] || { echo "osascript reel atteignable : abandon" >&2; exit 2; }
PATH="$TPATH" command -v cargo >/dev/null && { echo "cargo reel atteignable : abandon" >&2; exit 2; }

ver() { mkdir -p "$1/core"; printf 'ZANVIL_VERSION="%s"\n' "$2" > "$1/core/ui.zsh"; }

# fixture : origin a v1.0.0, Z clone sur main ; ZANVIL_DIR sans horodatage ni marqueur
fixture() {
    rm -rf "$BARE" "$W" "$Z" "$NLOG" "$GLOG"
    git init --quiet --bare -b main "$BARE"
    git clone --quiet "$BARE" "$W" 2>/dev/null
    git -C "$W" symbolic-ref HEAD refs/heads/main
    ver "$W" v1.0.0; echo a > "$W/a.txt"
    git -C "$W" add -A; git -C "$W" commit --quiet -m init; git -C "$W" push --quiet origin main
    git clone --quiet "$BARE" "$Z"
}
# publie une nouvelle version sur origin
advance() {
    ver "$W" "${1:-v1.1.0}"; git -C "$W" commit --quiet -am "release ${1:-v1.1.0}"; git -C "$W" push --quiet origin main
}
head_is_origin() { [[ "$(git -C "$Z" rev-parse HEAD)" == "$(git -C "$BARE" rev-parse main)" ]] && echo oui || echo non; }

# zu <code> : shell isole, auto_update.zsh source sans demarrage (mode off), puis <code>
zu() {
    env HOME="$H" ZANVIL_DIR="$Z" PATH="${2:-$TPATH}" zsh -f -c "
        source '$ROOT/core/ui.zsh'
        ZANVIL_UPDATE_MODE=off
        source '$ROOT/core/lifecycle/auto_update.zsh'
        ZANVIL_UPDATE_MODE=auto
        $1
    " 2>&1
}

echo "echeance"
fixture
zu '_zanvil_should_check_update && echo due' | assert_equals "aucun horodatage : due" "due"
zu 'print $EPOCHSECONDS > $ZANVIL_UPDATE_FILE; _zanvil_should_check_update || echo pas-due' | assert_equals "verifie a l'instant, frequence 1 : pas due" "pas-due"
zu 'print $((EPOCHSECONDS - 2*86400)) > $ZANVIL_UPDATE_FILE; _zanvil_should_check_update && echo due' | assert_equals "il y a 2 jours, frequence 1 (defaut) : due" "due"
zu 'ZANVIL_UPDATE_FREQUENCY=3; print $((EPOCHSECONDS - 2*86400)) > $ZANVIL_UPDATE_FILE; _zanvil_should_check_update || echo pas-due' | assert_equals "il y a 2 jours, frequence 3 : pas due" "pas-due"
zu 'ZANVIL_UPDATE_FREQUENCY=0; print $EPOCHSECONDS > $ZANVIL_UPDATE_FILE; _zanvil_should_check_update && echo due' | assert_equals "frequence 0 : toujours due" "due"

echo "arriere-plan : avance rapide"
fixture; advance; touch "$Z/non-suivi.txt"
zu '_zanvil_update_background' >/dev/null
head_is_origin | assert_equals "avance rapide appliquee (fichier non suivi ignore)" "oui"
cat "$NLOG" | assert_equals "notification de mise a jour" "zanvil mis à jour : v1.0.0 → v1.1.0"
{ [[ -e "$Z/.update.lock" ]] && echo present || echo absent; } | assert_equals "verrou libere" "absent"
rm -f "$NLOG"; zu '_zanvil_update_background' >/dev/null
cat "$NLOG" 2>/dev/null | wc -l | tr -d ' ' | assert_equals "deja a jour : aucune notification" "0"
fixture; echo b > "$W/a.txt"; git -C "$W" commit --quiet -am "meme version"; git -C "$W" push --quiet origin main
zu '_zanvil_update_background' >/dev/null
grep -cE '^zanvil mis à jour : [0-9a-f]{7} → [0-9a-f]{7}$' "$NLOG" | assert_equals "version inchangee : hashes courts" "1"

echo "arriere-plan : bloque"
fixture; advance; echo modifie >> "$Z/a.txt"
zu '_zanvil_update_background; _zanvil_update_background' >/dev/null
head_is_origin | assert_equals "arbre modifie : rien applique" "non"
cat "$NLOG" | assert_equals "arbre modifie : une seule notification sur deux passages" "zanvil : mise à jour en attente — modifications locales"
advance v1.2.0; zu '_zanvil_update_background' >/dev/null
wc -l < "$NLOG" | tr -d ' ' | assert_equals "meme HEAD, meme raison, origin a encore avance : pas de nouvelle notification" "1"
git -C "$Z" add a.txt
zu '_zanvil_update_background' >/dev/null
head_is_origin | assert_equals "modification indexee : rien applique" "non"
fixture; advance; git -C "$Z" checkout --quiet -b feat
zu '_zanvil_update_background' >/dev/null
head_is_origin | assert_equals "autre branche : rien applique" "non"
cat "$NLOG" | assert_equals "autre branche : notification" "zanvil : mise à jour en attente — branche feat"
fixture; advance; echo local > "$Z/local.txt"; git -C "$Z" add local.txt; git -C "$Z" commit --quiet -m local
before=$(git -C "$Z" rev-parse HEAD)
zu '_zanvil_update_background' >/dev/null
{ [[ "$(git -C "$Z" rev-parse HEAD)" == "$before" ]] && echo inchange; } | assert_equals "historique diverge : HEAD inchange" "inchange"
cat "$NLOG" | assert_equals "historique diverge : notification" "zanvil : mise à jour en attente — historique divergé"

echo "verrou"
fixture; advance; mkdir "$Z/.update.lock"
zu '_zanvil_update_background; echo code=$?' | assert_equals "verrou present : sortie immediate" "code=0"
head_is_origin | assert_equals "verrou present : rien applique" "non"
{ [[ -d "$Z/.update.lock" ]] && echo present; } | assert_equals "verrou d'un autre conserve" "present"
touch -t 202001010000 "$Z/.update.lock"
zu '_zanvil_update_background' >/dev/null
head_is_origin | assert_equals "verrou de plus d'1 h : repris, mise a jour appliquee" "oui"
ls -a "$Z" | grep -c '^\.update\.lock' | assert_equals "reprise : ni verrou ni dossier renomme laisses" "0"
fixture; mkdir "$Z/.update.lock"; touch -t 202001010000 "$Z/.update.lock"
zu '_zanvil_update_lock && echo A; _zanvil_update_lock || echo B-occupe; cat $_ZANVIL_UPDATE_LOCK/owner | grep -c "^[0-9]*\.[0-9]*$"' \
    | assert_equals "reprise d'un verrou perime : un seul gagnant, jeton ecrit" "$(printf 'A\nB-occupe\n1')"
fixture; mkdir "$Z/.update.lock"; echo autre > "$Z/.update.lock/owner"
zu '_zanvil_update_token=moi; _zanvil_update_unlock; cat $_ZANVIL_UPDATE_LOCK/owner' \
    | assert_equals "verrou d'un autre proprietaire : jamais retire" "autre"
zu '_zanvil_update_lock || echo occupe' | assert_equals "verrou frais d'un autre : occupe" "occupe"

echo "git non interactif"
FAKEGIT="$TEST_TMPDIR/fakegit"; ENVLOG="$TEST_TMPDIR/env.log"; mkdir -p "$FAKEGIT"
cat > "$FAKEGIT/git" <<EOS
#!/bin/sh
case " \$* " in
    *" config core.sshCommand "*) [ -n "\${FAKE_SSHCMD:-}" ] && { echo "\$FAKE_SSHCMD"; exit 0; }; exit 1 ;;
    *" fetch "*)
        { echo "args=\$*"; echo "GIT_TERMINAL_PROMPT=\$GIT_TERMINAL_PROMPT GIT_ASKPASS=\$GIT_ASKPASS SSH_ASKPASS_REQUIRE=\$SSH_ASKPASS_REQUIRE"; echo "GIT_SSH_COMMAND=\${GIT_SSH_COMMAND:-}"; } >> "$ENVLOG"
        [ -n "\${FAKE_SLEEP:-}" ] && sleep "\$FAKE_SLEEP"
        exit 1 ;;
esac
exit 1
EOS
chmod +x "$FAKEGIT/git"
fixture
zu '_zanvil_update_background' "$FAKEGIT:$TPATH" >/dev/null
sed -n 2p "$ENVLOG" | assert_equals "fetch : aucune invite possible (variables)" "GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true SSH_ASKPASS_REQUIRE=never"
sed -n 3p "$ENVLOG" | assert_equals "fetch : ssh en BatchMode avec delais" "GIT_SSH_COMMAND=ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"
grep -c -- '-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 fetch origin' "$ENVLOG" | assert_equals "fetch : abandon d'un reseau trop lent" "1"
rm -f "$ENVLOG"; FAKE_SSHCMD="ssh -i cle" zu 'export FAKE_SSHCMD; _zanvil_update_background' "$FAKEGIT:$TPATH" >/dev/null
sed -n 3p "$ENVLOG" | assert_equals "core.sshCommand defini : GIT_SSH_COMMAND non impose" "GIT_SSH_COMMAND="
zu 'print ${GIT_TERMINAL_PROMPT:-vide}' | assert_equals "variables locales a la mise a jour (shell appelant intact)" "vide"
rm -f "$ENVLOG"
( FAKE_SLEEP=1 env HOME="$H" ZANVIL_DIR="$Z" FAKE_SLEEP=1 PATH="$FAKEGIT:$TPATH" zsh -f -c "source '$ROOT/core/ui.zsh'; ZANVIL_UPDATE_MODE=off; source '$ROOT/core/lifecycle/auto_update.zsh'; _zanvil_update_background" >/dev/null 2>&1 & echo $! > "$TEST_TMPDIR/pid"; wait )&
for i in $(seq 1 60); do [[ -s "$ENVLOG" ]] && break; sleep 0.05; done
kill -TERM "$(cat "$TEST_TMPDIR/pid")"; wait
for i in $(seq 1 60); do [[ -d "$Z/.update.lock" ]] || break; sleep 0.05; done
{ [[ -d "$Z/.update.lock" ]] && echo present || echo absent; } | assert_equals "TERM pendant le fetch : verrou libere" "absent"

echo "echecs signales"
fixture; rm -f "$NLOG"
zu '_zanvil_update_background; _zanvil_update_background' "$FAKEGIT:$TPATH" >/dev/null
cat "$NLOG" 2>/dev/null | wc -l | tr -d ' ' | assert_equals "fetch en echec 2 fois : pas encore de notification" "0"
zu '_zanvil_update_background; _zanvil_update_background' "$FAKEGIT:$TPATH" >/dev/null
cat "$NLOG" | assert_equals "fetch en echec 3 fois de suite : une seule notification (4 passages)" "zanvil : échec de la mise à jour — origin injoignable (3 vérifications de suite)"
zu '_zanvil_update_background' >/dev/null
{ [[ -e "$Z/.update_fetch_failures" ]] && echo present || echo absent; } | assert_equals "fetch reussi : compteur remis a zero" "absent"
fixture; echo nouveau > "$W/new.txt"; git -C "$W" add new.txt; git -C "$W" commit --quiet -m new; git -C "$W" push --quiet origin main
echo local > "$Z/new.txt"
zu '_zanvil_update_background; _zanvil_update_background' >/dev/null
head_is_origin | assert_equals "fusion impossible (fichier non suivi ecrase) : rien applique" "non"
cat "$NLOG" | assert_equals "fusion impossible : une seule notification" "zanvil : échec de la mise à jour — fusion impossible"

echo "reconstruction du binaire"
CARGOBIN="$TEST_TMPDIR/cargobin"; mkdir -p "$CARGOBIN" "$H/.local/bin"
printf '#!/bin/sh\nmkdir -p target/release && echo nouveau > target/release/zanvil && chmod +x target/release/zanvil\n' > "$CARGOBIN/cargo"
chmod +x "$CARGOBIN/cargo"
fixture; mkdir -p "$Z/cli"; printf 'ancien\n' > "$H/.local/bin/zanvil"; chmod +x "$H/.local/bin/zanvil"
ino_before=$(ls -i "$H/.local/bin/zanvil" | awk '{print $1}')
zu '_zanvil_update_rebuild_cli' "$CARGOBIN:$TPATH" >/dev/null
cat "$H/.local/bin/zanvil" | assert_equals "binaire remplace" "nouveau"
{ [[ "$(ls -i "$H/.local/bin/zanvil" | awk '{print $1}')" != "$ino_before" ]] && echo renomme; } | assert_equals "remplacement par rename (nouvel inode, pas de reecriture en place)" "renomme"
ls "$H/.local/bin" | assert_equals "aucun fichier temporaire laisse" "zanvil"
rm -rf "$H/.local"

echo "zanvil-update (manuel, meme logique)"
fixture; advance
zu 'zanvil-update' | grep -c "v1.0.0 → v1.1.0" | assert_equals "zanvil-update annonce la version" "1"
head_is_origin | assert_equals "zanvil-update applique" "oui"
fixture; advance; echo modifie >> "$Z/a.txt"
zu 'zanvil-update; echo code=$?' | grep -E "en attente|code=" | grep -oE "en attente — modifications locales|code=[0-9]+" \
    | assert_equals "zanvil-update sur arbre modifie : refuse" "$(printf 'en attente — modifications locales\ncode=1')"

echo "revision chargee"
fixture
expected=$(git -C "$Z" rev-parse HEAD)
zu '_zanvil_update_rev; echo $REPLY' | assert_equals "ref libre" "$expected"
git -C "$Z" pack-refs --all
[[ -e "$Z/.git/refs/heads/main" ]] && echo "ref libre encore present" >&2
zu '_zanvil_update_rev; echo $REPLY' | assert_equals "ref seulement dans packed-refs" "$expected"
git -C "$Z" checkout --quiet --detach
zu '_zanvil_update_rev; echo $REPLY' | assert_equals "HEAD detache" "$expected"

echo "precmd"
fixture; advance
SCHED='sched() { print -r -- "sched $*"; }'
P='_ZANVIL_LOADED_REV=$(git -C $ZANVIL_DIR rev-parse HEAD); git -C $ZANVIL_DIR fetch -q origin; git -C $ZANVIL_DIR merge -q --ff-only origin/main;'
zu "$SCHED; $P _zanvil_update_precmd; _zanvil_update_precmd" \
    | sed 's/([0-9a-f]\{7\} → [0-9a-f]\{7\})/(A → B)/' \
    | assert_equals "revision differente : une ligne puis un seul rechargement (sched ss)" "$(printf 'zanvil mis à jour (A → B), rechargement…\nsched +0 ss')"
zu "$SCHED; _zanvil_update_precmd; echo fin" | assert_equals "meme revision : rien" "fin"
fixture; advance
zu "$SCHED; $P mkdir \$_ZANVIL_UPDATE_LOCK; _zanvil_update_precmd; echo attente; rmdir \$_ZANVIL_UPDATE_LOCK; _zanvil_update_precmd" | grep -c '^sched' \
    | assert_equals "verrou present : attend, puis recharge une fois libere" "1"
zu "$SCHED; $P mkdir \$_ZANVIL_UPDATE_LOCK; _zanvil_update_precmd; echo fin" | tail -1 | assert_equals "verrou present : rien" "fin"
fixture; advance
zu "$SCHED; $P ZANVIL_UPDATE_RELOAD=false; _zanvil_update_precmd; echo fin" | assert_equals "ZANVIL_UPDATE_RELOAD=false : rien" "fin"
zu "$SCHED; $P ZANVIL_UPDATE_MODE=off; _zanvil_update_precmd; echo fin" | assert_equals "mode off : rien" "fin"
zu '(( ${precmd_functions[(I)_zanvil_update_precmd]} )) && echo accroche || echo non' | assert_equals "shell non interactif : pas de hook precmd" "non"

echo "precmd reel (shell interactif, sched)"
fixture; advance
out=$(env HOME="$H" ZANVIL_DIR="$Z" PATH="$TPATH" zsh -fi 2>&1 <<EOF
source '$ROOT/core/ui.zsh'
print \$EPOCHSECONDS > '$Z/.last_update_check'
source '$ROOT/core/lifecycle/auto_update.zsh'
alias ss='echo RECHARGE; typeset -A RECHARGE_TABLE; RECHARGE_TABLE[k]=1'
:
git -C '$Z' fetch -q origin; git -C '$Z' merge -q --ff-only origin/main
:
:
echo "table=\${(t)RECHARGE_TABLE}"
EOF
)
grep -c '^RECHARGE' <<<"$out" | assert_equals "un seul rechargement sur plusieurs invites" "1"
grep -c 'zanvil mis à jour (' <<<"$out" | assert_equals "une seule ligne d'annonce" "1"
grep -o 'table=association' <<<"$out" | assert_equals "ss execute au niveau global (typeset non local)" "table=association"

echo "demarrage"
fixture; advance
# faux git en tete : tout appel au premier plan serait journalise
zu 'print $EPOCHSECONDS > $ZANVIL_UPDATE_FILE; ZANVIL_UPDATE_MODE=auto; source "'"$ROOT"'/core/lifecycle/auto_update.zsh"; echo fin' "$FGBIN:$TPATH" >/dev/null
cat "$GLOG" 2>/dev/null | wc -l | tr -d ' ' | assert_equals "pas due : aucun appel git" "0"
zu 'rm -f $ZANVIL_UPDATE_FILE; _zanvil_update_background() { print bg >> $ZANVIL_DIR/bg.log; }; _zanvil_update_startup
   for i in {1..40}; do [[ -s $ZANVIL_DIR/bg.log ]] && break; sleep 0.05; done; cat $ZANVIL_DIR/bg.log; [[ -s $ZANVIL_UPDATE_FILE ]] && echo horodate' "$FGBIN:$TPATH" \
    | assert_equals "due : horodatage ecrit, mise a jour lancee en arriere-plan" "$(printf 'bg\nhorodate')"
cat "$GLOG" 2>/dev/null | wc -l | tr -d ' ' | assert_equals "due : aucun appel git au premier plan" "0"
rm -f "$Z/.last_update_check"
env HOME="$H" ZANVIL_DIR="$Z" PATH="$TPATH" zsh -f -c "source '$ROOT/core/ui.zsh'; ZANVIL_UPDATE_MODE=auto; source '$ROOT/core/lifecycle/auto_update.zsh'" >/dev/null 2>&1
for i in $(seq 1 100); do [[ "$(head_is_origin)" == oui && ! -d "$Z/.update.lock" ]] && break; sleep 0.05; done
head_is_origin | assert_equals "demarrage reel : mise a jour appliquee en arriere-plan" "oui"
grep -c "zanvil mis à jour" "$Z/.update.log" | assert_equals "journal .update.log ecrit" "1"

echo
printf '  %s ok, %s echec(s)\n' "$(cat "$TEST_TMPDIR/pass")" "$(cat "$TEST_TMPDIR/fail")"
[[ "$(cat "$TEST_TMPDIR/fail")" == 0 ]]
