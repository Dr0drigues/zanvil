#!/usr/bin/env bash
# Verifie le filtre regex de k9s-log-grep.sh. Autonome, sans dependance.
# Usage : scripts/tests/k9s-log-grep.test.sh
set -uo pipefail

# Le filtre a deux pieges, et c est pour eux qu il existe plutot que d etre un grep -E
# ecrit dans le binding fzf :
#
#   - il ne doit voir que le TEXTE RENDU. Les lignes portent « rendu TAB json source »,
#     et le JSON repete les memes mots : un grep naif sur la ligne entiere ramenerait la
#     ligne parce que son JSON contient « level », que l utilisateur ne voit nulle part.
#   - il doit retirer les codes ANSI avant de comparer. Le rendu est colore ; sans cela
#     « ^06:49 » ne matche jamais, la ligne commencant par un code de couleur.
#
# Les deux se constatent ici, sur des paires ecrites a la main.

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
GREP="$ROOT/scripts/k9s-log-grep.sh"

TEST_TMPDIR=$(mktemp -d) || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
echo 0 > "$TEST_TMPDIR/pass"
echo 0 > "$TEST_TMPDIR/fail"

# assert_equals <libelle> <attendu>, entree sur stdin
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

# Trois paires : le rendu est colore, le JSON source porte des mots (« level », « msg »)
# qui n apparaissent pas dans le rendu.
PAIRS="$TEST_TMPDIR/pairs.txt"
{
    printf '\033[36m06:49:46.865\033[0m \033[31mERROR\033[0m InsuranceContractDatasource - Error getting claims\t{"level":"ERROR","message":"Error getting claims"}\n'
    printf '\033[36m06:49:46.826\033[0m \033[32mINFO\033[0m  platodin/externalHTTPCallLog - GET http://gravitee/sales\t{"level":"INFO","message":"GET http://gravitee/sales"}\n'
    printf '\033[36m07:02:11.004\033[0m \033[32mINFO\033[0m  auditLog - [getQualireparBonus] BL136851 affected\t{"level":"INFO","msg":"[getQualireparBonus] BL136851 affected"}\n'
} > "$PAIRS"

echo "== le filtre ne voit que le texte rendu =="

"$GREP" "$PAIRS" 'level' | wc -l | tr -d ' ' \
    | assert_equals "un mot present seulement dans le JSON source ne ramene rien" "0"

"$GREP" "$PAIRS" 'InsuranceContract' | wc -l | tr -d ' ' \
    | assert_equals "un mot du texte rendu ramene sa ligne" "1"

"$GREP" "$PAIRS" 'InsuranceContract' | awk -F'\t' '{print NF}' \
    | assert_equals "la ligne rendue sort entiere, JSON source compris" "2"

echo
echo "== les codes ANSI ne genent pas la comparaison =="

"$GREP" "$PAIRS" '^06:49' | wc -l | tr -d ' ' \
    | assert_equals "ancrage en debut de ligne malgre la couleur" "2"

"$GREP" "$PAIRS" 'affected$' | wc -l | tr -d ' ' \
    | assert_equals "ancrage en fin de ligne" "1"

"$GREP" "$PAIRS" '31m' | wc -l | tr -d ' ' \
    | assert_equals "un code de couleur n est pas matchable" "0"

echo
echo "== expressions regulieres courantes =="

"$GREP" "$PAIRS" 'ERROR.*[Cc]laims' | wc -l | tr -d ' ' \
    | assert_equals "classe de caracteres et quantificateur" "1"

"$GREP" "$PAIRS" 'gravitee/(sales|supply)' | wc -l | tr -d ' ' \
    | assert_equals "alternance groupee" "1"

"$GREP" "$PAIRS" 'BL[0-9]{6}' | wc -l | tr -d ' ' \
    | assert_equals "intervalle de repetition" "1"

# Deux lignes qui ne different que par le caractere du milieu : elles separent le point
# litteral du joker. Le piege qu elles gardent : `awk -v` developpe les echappements de la
# valeur qu on lui passe, donc `46\.865` y arriverait deja reduit a `46.865` et le motif
# echappe ramenerait les deux lignes. Le motif doit passer par l environnement.
PAIRS_ESC="$TEST_TMPDIR/pairs-esc.txt"
{
    printf '06:49:46.865 INFO  litteral\t{"message":"litteral"}\n'
    printf '06:49:46x865 INFO  joker\t{"message":"joker"}\n'
} > "$PAIRS_ESC"

"$GREP" "$PAIRS_ESC" '46\.865' | wc -l | tr -d ' ' \
    | assert_equals "point echappe : ne matche que le point" "1"

"$GREP" "$PAIRS_ESC" '46.865' | wc -l | tr -d ' ' \
    | assert_equals "point non echappe : matche n importe quel caractere" "2"

echo
echo "== motif vide et motif invalide =="

"$GREP" "$PAIRS" '' | wc -l | tr -d ' ' \
    | assert_equals "motif vide : tout passe" "3"

"$GREP" "$PAIRS" 'ERROR.*[' 2>/dev/null | wc -l | tr -d ' ' \
    | assert_equals "motif invalide : aucune ligne" "0"

"$GREP" "$PAIRS" 'ERROR.*[' >/dev/null 2>&1
printf '%s\n' "$?" \
    | assert_equals "motif invalide : code de sortie 0, la frappe continue" "0"

"$GREP" "$PAIRS" 'ERROR.*[' 2>&1 >/dev/null | wc -l | tr -d ' ' \
    | assert_equals "motif invalide : rien sur stderr, fzf n a pas d ecran pour l afficher" "0"

echo
echo "== le fichier absent est une erreur, pas un silence =="

"$GREP" "$TEST_TMPDIR/nexiste-pas" 'x' >/dev/null 2>&1
printf '%s\n' "$?" \
    | assert_equals "fichier absent : code de sortie 2" "2"

echo
pass=$(cat "$TEST_TMPDIR/pass")
fail=$(cat "$TEST_TMPDIR/fail")
printf '%d ok, %d echec(s)\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
