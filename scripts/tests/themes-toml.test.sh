#!/usr/bin/env bash
# Verifie que chaque theme Starship (config/themes/*/prompt.toml et config/themes/*.toml) est un TOML
# valide, et, si starship est installe, qu'il rend un prompt sans erreur de configuration.
# Usage : scripts/tests/themes-toml.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
pass=0 fail=0

for f in "$ROOT"/config/themes/*/prompt.toml "$ROOT"/config/themes/*.toml; do
    [[ -f "$f" ]] || continue
    name="${f#$ROOT/config/themes/}"
    if err=$(python3 -I -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$f" 2>&1); then
        printf '  ok   TOML %s\n' "$name"; pass=$((pass + 1))
    else
        printf '  FAIL TOML %s\n       %s\n' "$name" "$(printf '%s' "$err" | tail -1)"; fail=$((fail + 1))
    fi
    if command -v starship &>/dev/null; then
        if STARSHIP_CONFIG="$f" starship prompt 2>&1 >/dev/null | grep -q 'ERROR'; then
            printf '  FAIL starship %s\n' "$name"; fail=$((fail + 1))
        else
            printf '  ok   starship %s\n' "$name"; pass=$((pass + 1))
        fi
    fi
done

echo
echo "  $pass ok, $fail echec(s)"
[[ $fail -eq 0 ]]
