#!/usr/bin/env bash
# Verifie l'analyse des liens de MR, les chemins sous WORK_DIR et la notification du module project.
# Usage : scripts/tests/project-paths.test.sh
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
mkdir -p "$H" "$BIN"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\n' "$LOG" > "$BIN/osascript"
chmod +x "$BIN/osascript"
[[ "$(PATH="$BIN:$PATH" command -v osascript)" == "$BIN/osascript" ]] || { echo "osascript reel atteignable : abandon" >&2; exit 2; }

zc() {
    HOME="$H" PATH="$BIN:$PATH" WORK_DIR=/w ZANVIL_DIR="$ROOT" LOG="$LOG" zsh -f -c \
        'source "$ZANVIL_DIR/core/ui.zsh"; source "$ZANVIL_DIR/modules/project/project.zsh"; '"$1" 2>&1
}

echo "_project_parse_mr"
B=https://gitlab.example.com/group/sub/repo/-/merge_requests/42
for suffix in "" /diffs / "?tab=pipelines" "#note_7"; do
    zc "_project_parse_mr '$B$suffix' && print -r -- \"\$reply\"" \
        | assert_equals "lien $B$suffix" "gitlab.example.com group/sub/repo 42"
done
zc "_project_parse_mr https://gitlab.example.com/group/sub/repo/-/issues/42; echo rc=\$?" \
    | assert_equals "ticket : code 1" "rc=1"
zc "_project_parse_mr https://gitlab.example.com/group/sub/repo; echo rc=\$?" \
    | assert_equals "depot : code 1" "rc=1"
for p in ../../etc group/./repo group//repo group/..; do
    zc "_project_parse_mr https://gitlab.example.com/$p/-/merge_requests/1; echo rc=\$?" \
        | assert_equals "chemin $p : code 1" "rc=1"
done

echo "chemins"
zc '_project_repo_dir group/sub/repo' | assert_equals "repo_dir" "/w/group/sub/repo"
zc '_project_worktree_dir group/sub/repo feat/panier' \
    | assert_equals "worktree_dir" "/w/group/sub/.worktrees/repo/feat-panier"
zc '_project_worktree_dir group/repo main' \
    | assert_equals "worktree_dir un niveau" "/w/group/.worktrees/repo/main"

echo "_project_notify"
: > "$LOG"
zc '_project_notify "x" >/dev/null; tail -n 1 "$LOG"' \
    | assert_equals "message en dernier argument" 'x'
: > "$LOG"
zc '_project_notify "x" >/dev/null; grep -c "display notification (item 1 of a)" "$LOG"' \
    | assert_equals "script sans le message" '1'
MSG='a\" & (do shell script "id") & \"b'
: > "$LOG"
zc '_project_notify '"'$MSG'"' >/dev/null; tail -n 1 "$LOG"' \
    | assert_equals "message hostile identique" "$MSG"
: > "$LOG"
zc '_project_notify '"'$MSG'"' >/dev/null; grep -c "do shell script" "$LOG"' \
    | assert_equals "message hostile : une seule ligne, l'argument" '1'
zc 'project open >/dev/null; echo rc=$?' | assert_equals "open indisponible : code 1" "rc=1"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
