#!/usr/bin/env bash
# Verifie _zanvil_cached : la sortie d'un generateur (init, completions) est
# reutilisee tant que le binaire ne change pas, sans relancer le binaire.
# Usage : scripts/tests/startup-cache.test.sh
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

BIN="$TEST_TMPDIR/bin"
mkdir -p "$BIN" "$TEST_TMPDIR/v1" "$TEST_TMPDIR/v2"

# Faux generateur : compte ses lancements et emet une fonction zsh
for v in v1 v2; do
    cat > "$TEST_TMPDIR/$v/gen" <<EOF
#!/bin/sh
echo x >> "$TEST_TMPDIR/runs"
echo "gen_says() { echo $v; }"
EOF
    chmod +x "$TEST_TMPDIR/$v/gen"
done
ln -sf "$TEST_TMPDIR/v1/gen" "$BIN/gen"
printf '#!/bin/sh\nexit 3\n' > "$BIN/broken"; chmod +x "$BIN/broken"

# Charge le helper dans un zsh vierge, puis source le cache comme les appelants
zc() {
    PATH="$BIN:/usr/bin:/bin" XDG_CACHE_HOME="$TEST_TMPDIR/cache" zsh -f -c "
        source '$ROOT/core/cache.zsh'
        $1
    " 2>&1
}
runs() { [[ -f "$TEST_TMPDIR/runs" ]] && wc -l < "$TEST_TMPDIR/runs" | tr -d ' ' || echo 0; }

echo "_zanvil_cached"

zc '_zanvil_cached gen gen && source "$REPLY" && gen_says' | assert_equals "1er appel : genere et source" "v1"
runs | assert_equals "1er appel : binaire lance une fois" "1"

zc '_zanvil_cached gen gen && source "$REPLY" && gen_says' | assert_equals "2e appel : meme sortie" "v1"
runs | assert_equals "2e appel : binaire PAS relance" "1"

touch -t 203001010000 "$TEST_TMPDIR/v1/gen"
zc '_zanvil_cached gen gen && source "$REPLY" && gen_says' >/dev/null
runs | assert_equals "binaire plus recent que le cache : regenere" "2"

# Upgrade brew : le lien pointe vers un autre Cellar, mtime plus ancien
ln -sf "$TEST_TMPDIR/v2/gen" "$BIN/gen"
touch -t 200001010000 "$TEST_TMPDIR/v2/gen"
zc '_zanvil_cached gen gen && source "$REPLY" && gen_says' | assert_equals "binaire deplace (upgrade) : nouvelle sortie" "v2"

zc '_zanvil_cached broken broken; echo "rc=$?"' | assert_equals "generateur en echec : code 1" "rc=1"
{ [[ -e "$TEST_TMPDIR/cache/zanvil/broken.zsh" ]] && echo present || echo absent; } \
    | assert_equals "generateur en echec : aucun cache garde" "absent"

zc '_zanvil_cached nope nope; echo "rc=$?"' | assert_equals "binaire absent : code 1" "rc=1"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
