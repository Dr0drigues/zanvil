#!/usr/bin/env bash
# Verifie le rendu de k9s-log-fmt.sh. Autonome, sans dependance.
# Usage : scripts/tests/k9s-log-fmt.test.sh
set -uo pipefail

# Ce fichier ne couvre plus que ce qui reste hors de portee des cas gaveldrop — 57 cas
# couvrent desormais le rendu, les egalites, les comptages et le viewer.
#
# Restent ici les seules mesures qui exigent de decouper la sortie avant de comparer :
# `cut -f2-` pour isoler le JSON source, et `awk -F'\t' '{print NF}'` pour compter les
# champs. Une egalite sur la ligne entiere les couvrirait, mais l attendu porterait une
# tabulation litterale au milieu d un JSON — illisible dans un fichier de cas.
#
# S y ajoute le contrat --pairs verifie sur la fixture de dix lignes, ou l assertion porte
# sur le rapport entre le nombre de lignes entrantes et sortantes.
#
# Ces assertions ne sont donc pas un oubli de migration.

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
FMT="$ROOT/scripts/k9s-log-fmt.sh"
FIXTURES="$ROOT/config/k9s/fixtures/logs-sample.jsonl"

# Repertoire temporaire pour les compteurs : les assertions tournent en fin de
# pipeline (donc dans une sous-shell) ou une simple variable ne survivrait pas a l issue
# du pipe ; on passe donc par des fichiers.
TEST_TMPDIR=$(mktemp -d) || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
echo 0 > "$TEST_TMPDIR/pass"
echo 0 > "$TEST_TMPDIR/fail"

# Retire les codes ANSI : les assertions portent sur le texte, pas les couleurs.
strip_ansi() { sed $'s/\033\\[[0-9;]*m//g'; }

# assert_contains <libelle> <attendu>, entree sur stdin
assert_contains() {
    local label="$1" needle="$2" out
    out=$(strip_ansi)
    if [[ "$out" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        echo $(($(cat "$TEST_TMPDIR/pass") + 1)) > "$TEST_TMPDIR/pass"
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        echo $(($(cat "$TEST_TMPDIR/fail") + 1)) > "$TEST_TMPDIR/fail"
    fi
}

# assert_equals <libelle> <attendu>, entree sur stdin
assert_equals() {
    local label="$1" needle="$2" out
    out=$(strip_ansi)
    if [[ "$out" == "$needle" ]]; then
        printf '  ok   %s\n' "$label"
        echo $(($(cat "$TEST_TMPDIR/pass") + 1)) > "$TEST_TMPDIR/pass"
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        echo $(($(cat "$TEST_TMPDIR/fail") + 1)) > "$TEST_TMPDIR/fail"
    fi
}

echo "== thread et logger =="

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.FooService","message":"Demarrage termine"}' \
    | "$FMT" | assert_contains "thread entre crochets, logger, separateur" \
    "08:00:00.123 INFO  [main] com.boulanger.foo.FooService - Demarrage termine"

echo
echo "== stack trace =="

STACK_JSON='{"level":"ERROR","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)\n\t... 24 more"}'

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "premiere ligne de la stack indentee de 2 espaces" \
    "  java.lang.IllegalStateException: Boom"

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "dernier cadre" "      ... 24 more"

echo
echo "== mode --pairs =="

PAIRS_JSON='{"@timestamp":"2026-07-28T08:00:01.456Z","level":"ERROR","thread_name":"main","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)","retry":2}'

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | cut -f1 \
    | assert_contains "extras concatenes en fin de ligne" "retry=2"

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | cut -f2- \
    | assert_equals "2e champ = JSON source intact" "$PAIRS_JSON"

echo
echo "== contrat --pairs sur les fixtures =="

n_in=$(wc -l < "$FIXTURES" | tr -d ' ')
n_out=$("$FMT" --pairs < "$FIXTURES" | wc -l | tr -d ' ')
printf '%s\n' "$n_out" | assert_equals "$n_in ligne(s) en entree, autant en sortie" "$n_in"

"$FMT" --pairs < "$FIXTURES" | awk -F'\t' '{print NF}' | sort -u | tr '\n' ' ' | sed 's/ $//' \
    | assert_equals "chaque ligne porte exactement 2 champs" "2"

printf '%s\n' '{"level":"INFO","message":"x"}' | "$FMT" --oops 2>/dev/null
printf '%s\n' "$?" | assert_equals "option inconnue : code de sortie 2" "2"

printf '%s\n' '{"level":"ERROR","message":"x","stack_trace":"weird trace\tsans colon ni point\nmore"}' \
    | "$FMT" --pairs | awk -F'\t' '{print NF}' \
    | assert_equals "stack avec tabulation : champ rendu sans tab" "2"

printf '%s\n' '{"level":"INFO","message":"Ligne1\rLigne2"}' | "$FMT" --pairs | cut -f1 | grep -c $'\r' \
    | assert_equals "carriage return neutralise" "0"

printf '%s\n' $'col1\tcol2 texte brut' | "$FMT" --pairs | cut -f2- \
    | assert_equals "texte brut avec tabulation : source intacte" $'col1\tcol2 texte brut'

echo
echo "== thread et logger : identifiants sur une seule ligne =="

printf '%s\n' '{"level":"INFO","thread_name":"pool\t1","message":"x"}' \
    | "$FMT" --pairs | awk -F'\t' '{print NF}' \
    | assert_equals "thread avec tabulation : deux champs" "2"

printf '%s\n' '{"level":"INFO","logger_name":"com.A\tB","message":"x"}' \
    | "$FMT" --pairs | awk -F'\t' '{print NF}' \
    | assert_equals "logger avec tabulation : deux champs" "2"

echo
pass=$(cat "$TEST_TMPDIR/pass")
fail=$(cat "$TEST_TMPDIR/fail")
printf '%d ok, %d echec(s)\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
