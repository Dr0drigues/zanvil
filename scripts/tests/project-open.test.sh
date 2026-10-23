#!/usr/bin/env bash
# Verifie `project open` : clone sous WORK_DIR, worktree sur la branche de la MR, depot principal
# jamais touche, travail local jamais ecrase. Vrai git sur des depots temporaires (origin = depot nu),
# faux glab/orca/idea/osascript qui journalisent leurs arguments.
# Usage : scripts/tests/project-open.test.sh
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
mkdir -p "$H" "$BIN"
# premier jq qui marche avec le HOME temporaire (un shim mise n'y marche plus)
for j in $(type -ap jq); do
    HOME="$H" "$j" -n 1 &>/dev/null && { ln -s "$j" "$BIN/jq"; break; }
done
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export HOME="$H" GIT_CONFIG_NOSYSTEM=1

# faux binaires : chaque appel ecrit "nom arg1 arg2 ..." dans $LOG
for b in orca idea osascript; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$b" "$LOG" > "$BIN/$b"
done
cat > "$BIN/glab" <<EOS
#!/bin/sh
echo "glab \$*" >> "$LOG"
[ -n "\${GLAB_FAIL:-}" ] && exit 1
case "\$1 \$2" in
    "mr view") cat "$JSON" ;;
    "repo clone") git clone -q "$BARE" "\$4" ;;
esac
EOS
chmod +x "$BIN"/*

mr_json() {  # <source_project_id>
    printf '{"state":"opened","source_branch":"feat/panier","sha":"x","source_project_id":%s,"target_project_id":7}\n' "$1" > "$JSON"
}

# depot nu avec main et feat/panier ; $DEV sert a pousser sur origin
DEV="$TEST_TMPDIR/dev"
git init -q -b main "$DEV"
git -C "$DEV" commit -q --allow-empty -m init
git -C "$DEV" checkout -q -b feat/panier
git -C "$DEV" commit -q --allow-empty -m panier
git -C "$DEV" checkout -q main
git clone -q --bare "$DEV" "$BARE"
git -C "$DEV" checkout -q feat/panier
git -C "$DEV" remote add origin "$BARE"
git -C "$DEV" fetch -q origin

URL=https://gitlab.example.com/group/sub/repo/-/merge_requests/42
W="$TEST_TMPDIR/work"
REPO="$W/group/sub/repo"
WT="$W/group/sub/.worktrees/repo/feat-panier"

po() {
    PATH="$BIN:$PATH" WORK_DIR="$W" ZANVIL_DIR="$ROOT" zsh -f -c \
        'source "$ZANVIL_DIR/core/ui.zsh"; source "$ZANVIL_DIR/modules/project/project.zsh"; project open "$1"' _ "$URL" \
        >/dev/null 2>&1
}
fresh() { rm -rf "$W"; mkdir -p "$W"; : > "$LOG"; mr_json 7; }

echo "depot absent"
fresh
po; echo "rc=$?" | assert_equals "code 0" "rc=0"
git -C "$REPO" rev-parse --is-inside-work-tree 2>&1 | assert_equals "clone sous WORK_DIR/group/sub/repo" "true"
git -C "$WT" symbolic-ref --short HEAD 2>&1 | assert_equals "worktree sur feat/panier" "feat/panier"
grep -c "^glab repo clone group/sub/repo $REPO\$" "$LOG" | assert_equals "glab repo clone <chemin> <dossier>" "1"
grep -c "^orca terminal create --worktree path:$WT --title !42 --focus\$" "$LOG" | assert_equals "onglet Orca" "1"
grep -c "^orca reference add $URL --worktree path:$WT\$" "$LOG" | assert_equals "reference Orca" "1"
grep -c "^idea $WT\$" "$LOG" | assert_equals "IDEA sur le worktree" "1"

echo "depot principal avec modifications"
fresh
git clone -q "$BARE" "$REPO"
echo sale > "$REPO/sale.txt"
git -C "$REPO" commit -q --allow-empty -m local-main
before=$(git -C "$REPO" status --porcelain; git -C "$REPO" rev-parse HEAD)
po; echo "rc=$?" | assert_equals "code 0" "rc=0"
git -C "$WT" symbolic-ref --short HEAD 2>&1 | assert_equals "worktree cree" "feat/panier"
after=$(git -C "$REPO" status --porcelain; git -C "$REPO" rev-parse HEAD)
{ [[ "$before" == "$after" ]] && echo inchange || echo change; } | assert_equals "depot principal inchange" "inchange"

echo "branche extraite dans le depot principal"
fresh
git clone -q -b feat/panier "$BARE" "$REPO"
po; echo "rc=$?" | assert_equals "code 1" "rc=1"
grep -c "^osascript.* feat/panier est extraite dans $REPO" "$LOG" | assert_equals "notification qui explique le cas" "1"
{ [[ -e "$W/group/sub/.worktrees" ]] && echo present || echo absent; } | assert_equals "aucun dossier .worktrees" "absent"

echo "branche locale divergente, non extraite"
fresh
git clone -q "$BARE" "$REPO"
git -C "$REPO" branch feat/panier "$(git -C "$REPO" commit-tree -p origin/main -m divergent 'origin/main^{tree}')"
local_branch=$(git -C "$REPO" rev-parse feat/panier)
po; echo "rc=$?" | assert_equals "code 1" "rc=1"
git -C "$REPO" rev-parse feat/panier | assert_equals "branche locale intacte" "$local_branch"
{ [[ -e "$W/group/sub/.worktrees" ]] && echo present || echo absent; } | assert_equals "aucun dossier .worktrees" "absent"

echo "relances"
fresh
po
git -C "$DEV" commit -q --allow-empty -m pousse
git -C "$DEV" push -q origin feat/panier
po; echo "rc=$?" | assert_equals "commit pousse : code 0" "rc=0"
{ [[ $(git -C "$WT" rev-parse HEAD) == $(git -C "$DEV" rev-parse HEAD) ]] && echo avance || echo retard; } \
    | assert_equals "worktree avance" "avance"
git -C "$WT" commit -q --allow-empty -m non-pousse
local_head=$(git -C "$WT" rev-parse HEAD)
po; echo "rc=$?" | assert_equals "commit non pousse : code 1" "rc=1"
git -C "$WT" rev-parse HEAD | assert_equals "commit local intact" "$local_head"

echo "force-push"
fresh
po
git -C "$DEV" commit -q --amend --allow-empty -m reecrit
git -C "$DEV" push -q -f origin feat/panier
po; echo "rc=$?" | assert_equals "code 0" "rc=0"
{ [[ $(git -C "$WT" rev-parse HEAD) == $(git -C "$DEV" rev-parse HEAD) ]] && echo aligne || echo decale; } \
    | assert_equals "worktree aligne sur origin/feat/panier" "aligne"

echo ".zanvil.local"
fresh
git clone -q "$BARE" "$REPO"
printf 'export X=1\n' > "$REPO/.zanvil.local"
po; echo "rc=$?" | assert_equals "code 0" "rc=0"
{ cmp -s "$REPO/.zanvil.local" "$WT/.zanvil.local" && echo identique || echo different; } | assert_equals "copie identique" "identique"
git -C "$WT" status --porcelain | assert_equals "ignore dans le worktree" ""
{ [[ -e "$REPO/.gitignore" || -e "$WT/.gitignore" ]] && echo touche || echo intact; } \
    | assert_equals ".gitignore versionne non touche" "intact"

echo "MR d'un fork"
fresh
mr_json 8
po; echo "rc=$?" | assert_equals "code 1" "rc=1"
grep -c "^osascript.*fork" "$LOG" | assert_equals "message fork" "1"
ls -A "$W" | assert_equals "rien cree" ""

echo "glab en echec"
fresh
GLAB_FAIL=1 po; echo "rc=$?" | assert_equals "code 1" "rc=1"
grep -c "^osascript" "$LOG" | assert_equals "notification" "1"
ls -A "$W" | assert_equals "aucun dossier sous WORK_DIR" ""

echo "clone puis fetch en echec"
fresh
sed -i.bak 's/"feat\/panier"/"absente"/' "$JSON"
po; echo "rc=$?" | assert_equals "code 1" "rc=1"
ls -A "$W" | assert_equals "clone retire" ""

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
