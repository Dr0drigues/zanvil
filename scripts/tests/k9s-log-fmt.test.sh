#!/usr/bin/env bash
# Verifie le rendu de k9s-log-fmt.sh. Autonome, sans dependance.
# Usage : scripts/tests/k9s-log-fmt.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
FMT="$ROOT/scripts/k9s-log-fmt.sh"
FIXTURES="$ROOT/config/k9s/fixtures/logs-sample.jsonl"
pass=0 fail=0

# Retire les codes ANSI : les assertions portent sur le texte, pas les couleurs.
strip_ansi() { sed $'s/\033\\[[0-9;]*m//g'; }

# assert_contains <libelle> <attendu>, entree sur stdin
assert_contains() {
    local label="$1" needle="$2" out
    out=$(strip_ansi)
    if [[ "$out" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        fail=$((fail + 1))
    fi
}

# assert_equals <libelle> <attendu>, entree sur stdin
assert_equals() {
    local label="$1" needle="$2" out
    out=$(strip_ansi)
    if [[ "$out" == "$needle" ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        fail=$((fail + 1))
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
printf '%d ok, %d echec(s)\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
