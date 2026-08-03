#!/usr/bin/env bash
# Verifie le rendu de k9s-log-fmt.sh. Autonome, sans dependance.
# Usage : scripts/tests/k9s-log-fmt.test.sh
set -uo pipefail

# Ce fichier ne couvre plus que ce que gaveldrop ne peut pas exprimer :
#   - les egalites exactes. TextExpectation n accepte que contains et absent, donc un
#     comptage asserte en contains passerait sur un mauvais resultat : contains ["2"]
#     est satisfait par une sortie 12, verifie ;
#   - les mesures indirectes qui en dependent : wc -l, awk -F'\t' NF, grep -c ;
#   - les trois sections du viewer, qui pilotent un faux fzf et son code de sortie.
#
# Le rendu est couvert par tests/cases/k9s/. Ces assertions ne sont donc pas un oubli
# de migration : voir le mur nº 4 du rapport
# web/docs/superpowers/reports/2026-08-03-gaveldrop-shell-adapter.md.

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
FMT="$ROOT/scripts/k9s-log-fmt.sh"
FIXTURES="$ROOT/config/k9s/fixtures/logs-sample.jsonl"

# Repertoire temporaire pour les compteurs : les assertions tournent en fin de
# pipeline (donc dans une sous-shell) ou une simple variable ne survivrait pas
# a l issue du pipe ; on passe donc par des fichiers.
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

printf '%s\n' 'ligne de texte brut' \
    | "$FMT" | assert_equals "texte brut reemis a l identique" "ligne de texte brut"

printf '%s\n' '{"level":"INFO","message":"accolade manquante"' \
    | "$FMT" | assert_equals "JSON malforme traite comme du texte brut" '{"level":"INFO","message":"accolade manquante"'

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:03+02:00","level":"INFO","message":"Offset"}' \
    | "$FMT" | assert_contains "horodatage sans millisecondes" "08:00:03.000 INFO  Offset"

echo
echo "== niveau numerique (pino/bunyan) =="

printf '%s\n' '{"level":30,"message":"hello"}' \
    | "$FMT" | assert_contains "niveau numerique 30 rendu INFO" "             INFO  hello"

printf '%s\n' '{"level":60,"message":"hello"}' \
    | "$FMT" | assert_contains "niveau numerique 60 rendu FATAL" "             FATAL hello"

printf '%s\n' '{"level":30,"message":"hello"}' \
    | "$FMT" | assert_equals "niveau numerique : rendu complet, pas de passthrough JSON brut" \
    "             INFO  hello"

echo
echo "== thread et logger =="

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.FooService","message":"Demarrage termine"}' \
    | "$FMT" | assert_contains "thread entre crochets, logger, separateur" \
    "08:00:00.123 INFO  [main] com.boulanger.foo.FooService - Demarrage termine"

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

printf '%s\n' '{"level":"WARN","thread_name":"main","logger_name":"com.Cleanup","message":"3 orphelins","retry":2}' \
    | "$FMT" | assert_contains "2e ligne alignee sous le message" \
    "                                        retry=2"

printf '%s\n' '{"level":"INFO","message":"x","trace_id":"4bf92f35","span_id":"00f067aa","trace_flags":"01"}' \
    | "$FMT" | assert_equals "trace_id, span_id et trace_flags masques" \
    "             INFO  x"

printf '%s\n' '{"level":"INFO","message":"x","mdc_field":"aaa\nbbb"}' \
    | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "MDC avec newline : reste sur 2 lignes (extras aplatis)" "2"

printf '%s\n' '{"level":"ERROR","message":"Boom","stack_trace":"java.lang.Error: Boom","retry":2}' \
    | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "extras et stack : 3 lignes" "3"

echo
echo "== mode --pairs =="

PAIRS_JSON='{"@timestamp":"2026-07-28T08:00:01.456Z","level":"ERROR","thread_name":"main","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)","retry":2}'

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "un evenement avec stack et extras tient sur une ligne" "1"

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

printf '%s\n' '{"level":"ERROR","message":"x","stack_trace":"weird trace\tsans colon ni point\nmore"}' \
    | "$FMT" --pairs | awk -F'\t' '{print NF}' \
    | assert_equals "stack avec tabulation : champ rendu sans tab" "2"

printf '%s\n' '{"level":"INFO","message":"Ligne1\rLigne2"}' | "$FMT" --pairs | cut -f1 | grep -c $'\r' \
    | assert_equals "carriage return neutralise" "0"

printf '%s\n' $'col1\tcol2 texte brut' | "$FMT" --pairs | cut -f2- \
    | assert_equals "texte brut avec tabulation : source intacte" $'col1\tcol2 texte brut'

echo
echo "== viewer (repli sans fzf) =="

VIEW="$ROOT/scripts/k9s-log-view.sh"

# PATH minimal sans fzf : on ne peut pas se fier a /usr/bin:/bin pour exclure
# fzf (apt l installe la-bas sur Debian/Ubuntu). On construit un bin dedie
# avec uniquement ce dont le viewer et son repli ont besoin (bash pour le
# shebang, dirname pour se localiser, sed et less pour l affichage simple).
mkdir -p "$TEST_TMPDIR/bin"
ln -s "$(command -v bash)" "$TEST_TMPDIR/bin/bash"
ln -s "$(command -v dirname)" "$TEST_TMPDIR/bin/dirname"
ln -s "$(command -v sed)" "$TEST_TMPDIR/bin/sed"
ln -s "$(command -v less)" "$TEST_TMPDIR/bin/less"

# Le viewer doit se rabattre sur un affichage simple et n afficher que le
# premier champ. LESS=-FX evite d ouvrir un pager interactif.
printf '%s\n' '{"level":"INFO","message":"Bonjour"}' \
    | "$FMT" --pairs \
    | env PATH="$TEST_TMPDIR/bin" LESS="-FX" "$VIEW" \
    | assert_contains "repli sans fzf : premier champ affiche" "INFO  Bonjour"

printf '%s\n' '{"level":"INFO","message":"Bonjour"}' \
    | "$FMT" --pairs \
    | env PATH="$TEST_TMPDIR/bin" LESS="-FX" "$VIEW" \
    | assert_equals "repli sans fzf : JSON source masque" "             INFO  Bonjour"

echo
echo "== viewer (code de sortie) =="

# k9s affiche une popup d erreur des que le plugin sort non nul. Quitter fzf par
# Esc rend 130, et un filtre sans correspondance rend 1 : deux sorties normales.
# Un faux fzf permet de verifier la normalisation sans TTY.
_fake_fzf() {
    printf '#!/bin/sh\nexit %s\n' "$1" > "$TEST_TMPDIR/bin/fzf"
    chmod +x "$TEST_TMPDIR/bin/fzf"
}

# L entree passe par un fichier, pas par un pipe, et c est la CI Linux qui l a
# impose : le faux fzf sort immediatement sans lire son entree, donc jq recevait un
# SIGPIPE et sortait en 2. Avec `pipefail` actif, le code mesure alors le pipeline
# entier au lieu du viewer — ces trois assertions verifiaient autre chose que ce
# qu elles annoncaient. Sur macOS le timing le masquait, d ou le passage inapercu.
printf '%s\n' '{"level":"INFO","message":"x"}' | "$FMT" --pairs > "$TEST_TMPDIR/pairs.txt"

_fake_fzf 130
env PATH="$TEST_TMPDIR/bin" "$VIEW" < "$TEST_TMPDIR/pairs.txt" >/dev/null 2>&1
printf '%s\n' "$?" | assert_equals "fzf annule (130) : sortie normalisee a 0" "0"

_fake_fzf 1
env PATH="$TEST_TMPDIR/bin" "$VIEW" < "$TEST_TMPDIR/pairs.txt" >/dev/null 2>&1
printf '%s\n' "$?" | assert_equals "aucune correspondance (1) : sortie normalisee a 0" "0"

_fake_fzf 2
env PATH="$TEST_TMPDIR/bin" "$VIEW" < "$TEST_TMPDIR/pairs.txt" >/dev/null 2>&1
printf '%s\n' "$?" | assert_equals "erreur fzf (2) : code preserve" "2"

rm -f "$TEST_TMPDIR/bin/fzf"

echo
echo "== viewer (raccourci de rechargement) =="

# Le viewer ignore sa source : il ne recoit qu une chaine opaque a reexecuter,
# que le plugin k9s lui passe dans ZANVIL_K9S_RELOAD. Un faux fzf qui recrache
# ses arguments suffit a verifier que le binding est construit — ou absent.
# Il ecrit sur stderr : le viewer redirige la sortie de fzf vers /dev/null.
_fake_fzf_echo_args() {
    printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a" >&2; done\n' \
        > "$TEST_TMPDIR/bin/fzf"
    chmod +x "$TEST_TMPDIR/bin/fzf"
}

_fake_fzf_echo_args

# Entree par fichier, pour la meme raison que la section precedente : ce faux fzf
# ne lit pas son entree non plus.
env PATH="$TEST_TMPDIR/bin" ZANVIL_K9S_RELOAD='kubectl logs p | fmt --pairs' \
    "$VIEW" < "$TEST_TMPDIR/pairs.txt" 2>&1 >/dev/null \
    | grep -c 'ctrl-r:reload-sync(kubectl logs p | fmt --pairs)' \
    | assert_equals "ZANVIL_K9S_RELOAD definie : binding ctrl-r construit" "1"

env PATH="$TEST_TMPDIR/bin" "$VIEW" < "$TEST_TMPDIR/pairs.txt" 2>&1 >/dev/null \
    | grep -c 'ctrl-r' \
    | assert_equals "ZANVIL_K9S_RELOAD absente : aucun binding ctrl-r" "0"

rm -f "$TEST_TMPDIR/bin/fzf"

echo
echo "== thread et logger : identifiants sur une seule ligne =="

# Un nom de thread ou de logger contenant une tabulation ou un newline casserait
# le contrat --pairs (indexation fzf par ligne) et l alignement en statique.
printf '%s\n' '{"level":"INFO","thread_name":"pool\n1","message":"x"}' \
    | "$FMT" --pairs | wc -l | tr -d ' ' \
    | assert_equals "thread avec newline : une seule ligne en --pairs" "1"

printf '%s\n' '{"level":"INFO","thread_name":"pool\t1","message":"x"}' \
    | "$FMT" --pairs | awk -F'\t' '{print NF}' \
    | assert_equals "thread avec tabulation : deux champs" "2"

printf '%s\n' '{"level":"INFO","logger_name":"com.A\tB","message":"x"}' \
    | "$FMT" --pairs | awk -F'\t' '{print NF}' \
    | assert_equals "logger avec tabulation : deux champs" "2"

printf '%s\n' '{"level":"INFO","thread_name":"pool\n1","message":"x"}' \
    | "$FMT" | wc -l | tr -d ' ' \
    | assert_equals "thread avec newline : une seule ligne en statique" "1"

echo
pass=$(cat "$TEST_TMPDIR/pass")
fail=$(cat "$TEST_TMPDIR/fail")
printf '%d ok, %d echec(s)\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
