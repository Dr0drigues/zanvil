#!/usr/bin/env bash
# Verifie le rendu de k9s-log-fmt.sh. Autonome, sans dependance.
# Usage : scripts/tests/k9s-log-fmt.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
FMT="$ROOT/scripts/k9s-log-fmt.sh"
FIXTURES="$ROOT/config/k9s/fixtures/logs-sample.jsonl"

# Temp directory pour les compteurs (escape subshell issue)
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

echo "== rendu de base =="

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","message":"Demarrage termine"}' \
    | "$FMT" | assert_contains "horodatage court + niveau complete" "08:00:00.123 INFO  Demarrage termine"

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:01.456Z","level":"error","message":"Boom"}' \
    | "$FMT" | assert_contains "niveau en majuscules" "08:00:01.456 ERROR Boom"

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:02.000Z","severity":"WARN","msg":"Alerte"}' \
    | "$FMT" | assert_contains "champs severity et msg reconnus" "08:00:02.000 WARN  Alerte"

printf '%s\n' '{"message":"Sans horodatage"}' \
    | "$FMT" | assert_contains "niveau par defaut INFO, colonne heure vide" "             INFO  Sans horodatage"

printf '%s\n' 'ligne de texte brut' \
    | "$FMT" | assert_equals "texte brut reemis a l identique" "ligne de texte brut"

printf '%s\n' '{"level":"INFO","message":"accolade manquante"' \
    | "$FMT" | assert_equals "JSON malforme traite comme du texte brut" '{"level":"INFO","message":"accolade manquante"'

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:03+02:00","level":"INFO","message":"Offset"}' \
    | "$FMT" | assert_contains "horodatage sans millisecondes" "08:00:03.000 INFO  Offset"

echo
echo "== thread et logger =="

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.FooService","message":"Demarrage termine"}' \
    | "$FMT" | assert_contains "thread entre crochets, logger, separateur" \
    "08:00:00.123 INFO  [main] com.boulanger.foo.FooService - Demarrage termine"

printf '%s\n' '{"level":"DEBUG","logger_name":"com.boulanger.foo.bar.baz.qux.EnormousServiceImplementation","message":"x"}' \
    | "$FMT" | assert_contains "logger de plus de 36 caracteres abrege" \
    "…b.b.q.EnormousServiceImplementation - x"

printf '%s\n' '{"level":"TRACE","thread_name":"http-nio-8080-exec-with-a-very-long-name","logger_name":"com.Pool","message":"x"}' \
    | "$FMT" | assert_contains "thread de plus de 20 caracteres tronque" \
    "[http-nio-8080-exec-…] com.Pool - x"

printf '%s\n' '{"level":"INFO","logger_name":"com.boulanger.foo.FooService","message":"Sans thread"}' \
    | "$FMT" | assert_contains "thread absent : pas de crochets vides" \
    "INFO  com.boulanger.foo.FooService - Sans thread"

printf '%s\n' '{"level":"INFO","thread_name":"main","message":"Sans logger"}' \
    | "$FMT" | assert_contains "logger absent : thread conserve" \
    "INFO  [main] - Sans logger"

printf '%s\n' '{"level":"INFO","message":"Ni thread ni logger"}' \
    | "$FMT" | assert_contains "thread et logger absents : pas de tiret orphelin" \
    "INFO  Ni thread ni logger"

printf '%s\n' '{"level":"DEBUG","logger_name":"UneClasseSansAucunPointDontLeNomDepasseTrenteSixCaracteres","message":"x"}' \
    | "$FMT" | assert_contains "logger sans point de plus de 36 caracteres tronque" \
    "…DontLeNomDepasseTrenteSixCaracteres - x"

echo
echo "== stack trace =="

STACK_JSON='{"level":"ERROR","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)\n\t... 24 more"}'

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "premiere ligne de la stack indentee de 2 espaces" \
    "  java.lang.IllegalStateException: Boom"

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "cadres indentes, tabulations converties" \
    "      at com.Foo.bar(Foo.java:17)"

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "dernier cadre" "      ... 24 more"

printf '%s\n' "$STACK_JSON" | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "un evenement avec stack occupe 4 lignes" "4"

printf '%s\n' '{"level":"ERROR","message":"Boom","exception":"java.lang.NullPointerException: null"}' \
    | "$FMT" | assert_contains "champ exception reconnu" "  java.lang.NullPointerException: null"

printf '%s\n' '{"level":"ERROR","message":"Boom","throwable":"java.io.IOException: broken pipe"}' \
    | "$FMT" | assert_contains "champ throwable reconnu" "  java.io.IOException: broken pipe"

printf '%s\n' '{"level":"INFO","message":"Rien a signaler"}' \
    | "$FMT" | assert_equals "sans stack : une seule ligne" \
    "             INFO  Rien a signaler"

printf '%s\n' '{"level":"ERROR","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)\n"}' \
    | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "stack avec newline final : pas de ligne parasite" "3"

echo
echo "== champs extra (MDC) =="

printf '%s\n' '{"level":"WARN","thread_name":"main","logger_name":"com.Cleanup","message":"3 orphelins","http.status":503,"retry":2}' \
    | "$FMT" | assert_contains "champs extra en cle=valeur" "http.status=503  retry=2"

printf '%s\n' '{"level":"WARN","thread_name":"main","logger_name":"com.Cleanup","message":"3 orphelins","retry":2}' \
    | "$FMT" | assert_contains "2e ligne alignee sous le message" \
    "                                        retry=2"

printf '%s\n' '{"level":"INFO","message":"x","trace_id":"4bf92f35","span_id":"00f067aa","trace_flags":"01"}' \
    | "$FMT" | assert_equals "trace_id, span_id et trace_flags masques" \
    "             INFO  x"

printf '%s\n' '{"level":"INFO","message":"x","nested":{"a":1}}' \
    | "$FMT" | assert_contains "valeur structuree serialisee" 'nested={"a":1}'

printf '%s\n' '{"level":"ERROR","message":"Boom","stack_trace":"java.lang.Error: Boom","retry":2}' \
    | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "extras et stack : 3 lignes" "3"

echo
echo "== mode --pairs =="

PAIRS_JSON='{"@timestamp":"2026-07-28T08:00:01.456Z","level":"ERROR","thread_name":"main","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)","retry":2}'

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "un evenement avec stack et extras tient sur une ligne" "1"

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | cut -f1 \
    | assert_contains "stack reduite au nom court de l exception" "⤷ IllegalStateException"

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | cut -f1 \
    | assert_contains "extras concatenes en fin de ligne" "retry=2"

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | cut -f2- \
    | assert_equals "2e champ = JSON source intact" "$PAIRS_JSON"

printf '%s\n' '{"level":"INFO","message":"Ligne 1\nLigne 2"}' | "$FMT" --pairs | strip_ansi | cut -f1 \
    | assert_contains "retours a la ligne du message remplaces par un symbole" "Ligne 1↵Ligne 2"

printf '%s\n' 'texte brut' | "$FMT" --pairs | assert_equals "texte brut duplique dans les deux champs" \
    "$(printf 'texte brut\ttexte brut')"

echo
echo "== contrat --pairs sur les fixtures =="

n_in=$(wc -l < "$FIXTURES" | tr -d ' ')
n_out=$("$FMT" --pairs < "$FIXTURES" | wc -l | tr -d ' ')
printf '%s\n' "$n_out" | assert_equals "$n_in ligne(s) en entree, autant en sortie" "$n_in"

"$FMT" --pairs < "$FIXTURES" | awk -F'\t' '{print NF}' | sort -u | tr '\n' ' ' | sed 's/ $//' \
    | assert_equals "chaque ligne porte exactement 2 champs" "2"

printf '%s\n' '{"level":"INFO","message":"x"}' | "$FMT" --oops 2>/dev/null
printf '%s\n' "$?" | assert_equals "option inconnue : code de sortie 2" "2"

echo
pass=$(cat "$TEST_TMPDIR/pass")
fail=$(cat "$TEST_TMPDIR/fail")
printf '%d ok, %d echec(s)\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
