#!/usr/bin/env bash
# Verifie qu aucune fonction ne declare en `local` un nom que zsh reserve.
# Usage : scripts/tests/zsh-special-vars.test.sh
#
# Pourquoi ce test existe : en zsh, `path` est LIEE a `PATH` (tableau <-> scalaire).
# Un `local path=...` dans une fonction remplace donc le PATH du shell pendant
# toute la fonction, et plus aucune commande externe n est trouvable. Le symptome
# est un code 127 sans message si stderr est redirige — ce qui a coute une session
# de diagnostic sur work_es_apps. `status` est en lecture seule : zsh interrompt la
# fonction sur « read-only variable: status ».
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

echo "== le piege, documente de facon executable =="

# Ces deux assertions ne testent pas zanvil mais zsh : elles fixent le
# comportement dont depend tout le reste du fichier.
zsh -c 'f() { local path=ceci-nest-pas-un-PATH; command -v ls >/dev/null 2>&1 && print trouve || print introuvable; }; f' \
    | assert_equals "local path= rend les commandes externes introuvables" "introuvable"

zsh -c 'f() { local status=x; print jamais-atteint; }; f 2>&1 | head -1' \
    | assert_equals "local status= est refuse par zsh" "f: read-only variable: status"

echo
echo "== lint : aucune declaration locale d un nom reserve =="

# Noms que zsh lie a une variable speciale ou garde en lecture seule. La liste
# est volontairement courte : uniquement ceux qu un developpeur peut choisir
# spontanement comme variable locale.
RESERVED='path|cdpath|fpath|manpath|module_path|status|argv|options|functions|aliases|dirstack|psvar|watch|histchars'

# Trois passes plutot qu une expression unique, pour rester lisible :
#   1. les lignes qui declarent quelque chose ;
#   2. tronquees a la premiere substitution de commande — sinon un argument comme
#      `docker ps -f status=exited` passerait pour une declaration ;
#   3. celles ou un nom reserve est effectivement affecte. Le dernier filtre
#      epargne les noms composes (config_path, exit_status).
hits=$(grep -rnE "(^|[[:space:];])(local|typeset)([[:space:]]+-[a-zA-Z]+)*[[:space:]]" \
        --include='*.zsh' "$ROOT/core" "$ROOT/modules" 2>/dev/null \
        | sed 's/\$(.*//' \
        | grep -E "\b(${RESERVED})=" \
        | grep -vE '\b[a-z_]+_(path|status|options|functions)=' || true)

if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits" >&2
fi
printf '%s\n' "$(printf '%s' "$hits" | grep -c . || true)" \
    | assert_equals "aucune variable reservee declaree en local" "0"

echo
echo "== verification fonctionnelle : _work_es_curl trouve curl =="

# Un faux curl repond comme le vrai avec -w '\n%{http_code}' : corps, saut de
# ligne, code. Si le PATH est detruit, il n est pas trouve et le code est 127.
mkdir -p "$TEST_TMPDIR/bin"
printf '#!/bin/sh\nprintf %s\n' "'{\"ok\":true}\n200'" > "$TEST_TMPDIR/bin/curl"
chmod +x "$TEST_TMPDIR/bin/curl"
cp /bin/cat /bin/sed "$TEST_TMPDIR/bin/" 2>/dev/null || true

zsh -c "
    PATH='$TEST_TMPDIR/bin:/usr/bin:/bin'
    ES_USER=probe ES_PASSWORD=probe
    _ui_msg_fail() { print \"FAIL: \$*\"; }
    source '$ROOT/modules/work/elasticsearch.zsh'
    out=\$(_work_es_curl POST 'es-apis-*/_search' '{\"size\":0}')
    print \"\$?\"
" 2>/dev/null | assert_equals "_work_es_curl : code de sortie 0 (curl trouve)" "0"

zsh -c "
    PATH='$TEST_TMPDIR/bin:/usr/bin:/bin'
    ES_USER=probe ES_PASSWORD=probe
    _ui_msg_fail() { print \"FAIL: \$*\"; }
    source '$ROOT/modules/work/elasticsearch.zsh'
    _work_es_curl POST 'es-apis-*/_search' '{\"size\":0}' | head -1
" 2>/dev/null | assert_equals "_work_es_curl : code HTTP en premiere ligne" "200"

echo
echo "== verification fonctionnelle : hooks_list liste un hook =="

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
( cd "$REPO" && git init -q )
printf '#!/bin/sh\nexit 0\n' > "$REPO/.git/hooks/pre-commit"
chmod +x "$REPO/.git/hooks/pre-commit"

zsh -c "
    cd '$REPO'
    source '$ROOT/core/ui.zsh' 2>/dev/null
    source '$ROOT/modules/git/git_hooks.zsh'
    hooks_list 2>&1 | grep -c 'read-only variable'
" 2>/dev/null | assert_equals "hooks_list : aucune erreur read-only" "0"

zsh -c "
    cd '$REPO'
    source '$ROOT/core/ui.zsh' 2>/dev/null
    source '$ROOT/modules/git/git_hooks.zsh'
    hooks_list 2>/dev/null | grep -c 'pre-commit'
" 2>/dev/null | assert_equals "hooks_list : le hook pre-commit est liste" "1"

echo
pass=$(cat "$TEST_TMPDIR/pass")
fail=$(cat "$TEST_TMPDIR/fail")
printf '%d ok, %d echec(s)\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
