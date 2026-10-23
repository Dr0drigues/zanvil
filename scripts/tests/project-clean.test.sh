#!/usr/bin/env bash
# Verifie `project clean` et le menage quotidien : suppression des worktrees des MR mergees ou
# fermees, jamais de travail non pousse perdu. Vrai git sur des depots temporaires (origin = depot
# nu), faux glab/osascript qui journalisent leurs arguments.
# Usage : scripts/tests/project-clean.test.sh
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
BIN="$TEST_TMPDIR/bin"
LOG="$TEST_TMPDIR/calls.log"
BARE="$TEST_TMPDIR/origin.git"
JSON="$TEST_TMPDIR/mr.json"
# ZANVIL_DIR de test : l'horodatage du menage ne s'ecrit pas dans le depot
Z="$TEST_TMPDIR/zanvil"
mkdir -p "$H" "$BIN" "$Z"
ln -s "$ROOT/core" "$Z/core"
ln -s "$ROOT/modules" "$Z/modules"
# premier jq qui marche avec le HOME temporaire (un shim mise n'y marche plus)
for j in $(type -ap jq); do
    HOME="$H" "$j" -n 1 &>/dev/null && { ln -s "$j" "$BIN/jq"; break; }
done
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export HOME="$H" GIT_CONFIG_NOSYSTEM=1

printf '#!/bin/sh\necho "osascript $*" >> "%s"\n' "$LOG" > "$BIN/osascript"
cat > "$BIN/glab" <<EOS
#!/bin/sh
echo "glab GITLAB_HOST=\${GITLAB_HOST:-} \$*" >> "$LOG"
case " \$* " in *" \${GLAB_FAIL_BRANCH:-aucune} "*) exit 1 ;; esac
case "\$1 \$2" in
    "mr view") cat "$JSON" ;;
    "mr list") echo "\${GLAB_OPEN_MRS:-[]}" ;;
esac
EOS
chmod +x "$BIN"/*

mr_json() {  # <state> <sha>
    printf '{"state":"%s","source_branch":"feat/panier","sha":"%s"}\n' "$1" "$2" > "$JSON"
}

# depot nu avec main, feat/panier et feat/autre
DEV="$TEST_TMPDIR/dev"
git init -q -b main "$DEV"
git -C "$DEV" commit -q --allow-empty -m init
git -C "$DEV" checkout -q -b feat/panier
git -C "$DEV" commit -q --allow-empty -m panier
git -C "$DEV" checkout -q -b feat/autre main
git -C "$DEV" commit -q --allow-empty -m autre
git -C "$DEV" checkout -q main
git clone -q --bare "$DEV" "$BARE"
MR_SHA=$(git -C "$DEV" rev-parse feat/panier)

W="$TEST_TMPDIR/work"
REPO="$W/group/sub/repo"
WT="$W/group/sub/.worktrees/repo/feat-panier"
STAMP="$Z/.last_project_clean"

pc() {
    PATH="$BIN:$PATH" WORK_DIR="$W" ZANVIL_DIR="$Z" zsh -f -c \
        'source "$ZANVIL_DIR/core/ui.zsh"; source "$ZANVIL_DIR/modules/project/project.zsh"; project clean' \
        >/dev/null 2>&1
}
init_module() {  # [WORK_DIR]
    PATH="$BIN:$PATH" WORK_DIR="${1:-$W}" ZANVIL_DIR="$Z" zsh -f -c \
        'source "$ZANVIL_DIR/core/ui.zsh"; source "$ZANVIL_DIR/modules/project/init.zsh"' >/dev/null 2>&1
}
# depot principal (origin en https d'exemple, jamais contacte) + worktree de feat/panier
fresh() {
    rm -rf "$W"; mkdir -p "$W"; : > "$LOG"
    git clone -q "$BARE" "$REPO"
    git -C "$REPO" remote set-url origin https://gitlab.example.com/group/sub/repo.git
    git -C "$REPO" worktree add -q --track -b feat/panier "$WT" refs/remotes/origin/feat/panier
    # GitLab supprime la branche source au merge
    git -C "$REPO" update-ref -d refs/remotes/origin/feat/panier
}
present() { [[ -e "$1" ]] && echo present || echo absent; }
branch() { git -C "$REPO" show-ref -q --verify refs/heads/feat/panier && echo present || echo absent; }

echo "hote de origin"
for u in https://gitlab.example.com/g/r.git ssh://git@gitlab.example.com:2222/g/r.git git@gitlab.example.com:g/r.git; do
    zsh -f -c 'source "$1/modules/project/project.zsh"; _project_remote_host "$2"' _ "$ROOT" "$u" \
        | assert_equals "$u" "gitlab.example.com"
done

echo "MR mergee, worktree propre, HEAD = sha de la MR, branche distante supprimee"
fresh
mr_json merged "$MR_SHA"
pc; echo "rc=$?" | assert_equals "code 0" "rc=0"
present "$WT" | assert_equals "worktree supprime" "absent"
branch | assert_equals "branche locale supprimee" "absent"
present "$W/group/sub/.worktrees" | assert_equals ".worktrees vide supprime" "absent"
grep -c "^glab GITLAB_HOST=gitlab.example.com mr view feat/panier -R group/sub/repo -F json\$" "$LOG" \
    | assert_equals "glab sur la vraie branche et l'hote de origin" "1"
grep -c "^osascript.* 1 worktree supprime\$" "$LOG" | assert_equals "notification" "1"

echo "MR mergee, commit hors MR"
fresh
mr_json merged "$MR_SHA"
git -C "$WT" commit -q --allow-empty -m hors-mr
pc
present "$WT" | assert_equals "worktree garde" "present"
branch | assert_equals "branche locale gardee" "present"
grep -c "^osascript.*garde.*commits non pousses" "$LOG" | assert_equals "notification" "1"

echo "commit hors MR mais contenu dans une branche distante"
fresh
mr_json merged "$MR_SHA"
git -C "$WT" commit -q --allow-empty -m pousse-ailleurs
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$WT" rev-parse HEAD)"
pc
present "$WT" | assert_equals "worktree supprime" "absent"

echo "MR ouverte"
fresh
mr_json opened "$MR_SHA"
pc
present "$WT" | assert_equals "worktree garde" "present"
grep -c "^osascript" "$LOG" | assert_equals "aucune notification" "0"

echo "MR fermee, autre MR ouverte sur la meme branche"
fresh
mr_json closed "$MR_SHA"
GLAB_OPEN_MRS='[{"iid":43}]' pc
present "$WT" | assert_equals "worktree garde" "present"
grep -c "^glab GITLAB_HOST=gitlab.example.com mr list --source-branch feat/panier -R group/sub/repo -F json\$" "$LOG" \
    | assert_equals "MR ouvertes cherchees sur la branche" "1"
grep -c "^osascript" "$LOG" | assert_equals "aucune notification" "0"

echo "HEAD detache"
fresh
git -C "$WT" checkout -q --detach
pc
present "$WT" | assert_equals "worktree garde" "present"
cat "$LOG" | assert_equals "ni glab ni notification" ""

echo "verrou recent d'un autre menage"
fresh
mr_json merged "$MR_SHA"
mkdir "$Z/.project_clean.lock"
pc
present "$WT" | assert_equals "rien supprime" "present"
cat "$LOG" | assert_equals "ni glab ni notification" ""
touch -t 202001010000 "$Z/.project_clean.lock"
pc
present "$WT" | assert_equals "verrou de plus d'1 h repris" "absent"
present "$Z/.project_clean.lock" | assert_equals "verrou libere" "absent"

echo "MR fermee, modifications non commitees"
fresh
mr_json closed "$MR_SHA"
echo sale > "$WT/sale.txt"
pc
present "$WT/sale.txt" | assert_equals "worktree garde" "present"
grep -c "^osascript.*modifications en cours" "$LOG" | assert_equals "notification" "1"

echo "MR mergee, stash fait sur la branche"
fresh
mr_json merged "$MR_SHA"
echo wip > "$WT/wip.txt"
git -C "$WT" stash push -q -u -m wip
pc
present "$WT" | assert_equals "worktree garde" "present"
grep -c "^osascript.*stash" "$LOG" | assert_equals "notification" "1"

echo "MR mergee, stash fait sur une autre branche"
fresh
mr_json merged "$MR_SHA"
echo wip > "$REPO/wip.txt"
git -C "$REPO" stash push -q -u -m ailleurs
pc
present "$WT" | assert_equals "worktree supprime" "absent"

echo "glab en echec sur un worktree, l'autre traite"
fresh
mr_json merged "$MR_SHA"
WT2="$W/group/sub/.worktrees/repo/feat-autre"
git -C "$REPO" worktree add -q --track -b feat/autre "$WT2" refs/remotes/origin/feat/autre
GLAB_FAIL_BRANCH=feat/autre pc
present "$WT2" | assert_equals "worktree en echec garde" "present"
present "$WT" | assert_equals "l'autre supprime" "absent"
grep -c "^osascript" "$LOG" | assert_equals "une seule notification" "1"
grep -c "^osascript.* 1 worktree supprime\$" "$LOG" | assert_equals "sans erreur" "1"

echo "rien a faire"
rm -rf "$W"; mkdir -p "$W/group"; : > "$LOG"
pc; echo "rc=$?" | assert_equals "code 0" "rc=0"
cat "$LOG" | assert_equals "ni glab ni notification" ""

echo "menage quotidien"
fresh
mr_json merged "$MR_SHA"
echo $(( $(date +%s) - 3600 )) > "$STAMP"
before=$(cat "$STAMP")
init_module
sleep 1
cat "$LOG" | assert_equals "il y a 1 h : aucun appel" ""
cat "$STAMP" | assert_equals "horodatage inchange" "$before"
echo $(( $(date +%s) - 2 * 86400 )) > "$STAMP"
init_module
for _ in $(seq 50); do [[ -e "$WT" ]] || break; sleep 0.1; done
sleep 0.2
grep -c "^glab .*mr view feat/panier" "$LOG" | assert_equals "il y a 2 jours : menage lance" "1"
present "$WT" | assert_equals "worktree supprime en arriere-plan" "absent"
{ (( $(date +%s) - $(cat "$STAMP") < 60 )) && echo recent || echo ancien; } | assert_equals "horodatage reecrit" "recent"
rm -f "$STAMP"
init_module "$TEST_TMPDIR/absent"
present "$STAMP" | assert_equals "WORK_DIR absent : rien lance" "absent"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
