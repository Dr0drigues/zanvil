#!/usr/bin/env bash
# Demarrage (#155) : le theme automatique n'est applique que par un shell a la fois, et un
# env.d/*.sops.zsh indechiffrable est signale au lieu de disparaitre en silence.
# Usage : scripts/tests/startup-guards.test.sh
set -uo pipefail
ROOT="${ZANVIL_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [[ "$2" == "$3" ]]; then echo "  ok   $1"; pass=$((pass+1)); else printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

hook=$(sed -n '/^# Hook auto dark\/light au startup/,/^fi$/p' "$ROOT/core/commands/theme.zsh")
auto() {
    zsh -f -c "
        ZANVIL_DIR='$T'; ZANVIL_THEME_LIGHT=clair; ZANVIL_THEME_DARK=sombre
        zanvil-theme() { print x >> '$T/calls'; sleep \${SLOW:-0}; }
        _zanvil_detect_appearance() { echo dark; }
        $hook"
}

echo "theme automatique"
: > "$T/calls"
for i in 1 2 3; do SLOW=1 auto & done; wait
check "trois shells ensemble : un seul applique" "1" "$(wc -l < "$T/calls" | tr -d ' ')"
check "verrou libere" "absent" "$([[ -d $T/.theme.lock ]] && echo present || echo absent)"
: > "$T/calls"; mkdir "$T/.theme.lock"; auto
check "verrou frais d'un autre shell : rien" "0" "$(wc -l < "$T/calls" | tr -d ' ')"
touch -t 202001010000 "$T/.theme.lock"; auto
check "verrou de plus de 5 min : repris" "1" "$(wc -l < "$T/calls" | tr -d ' ')"

echo "env.d chiffre"
mkdir -p "$T/env.d" "$T/bin"; echo ENC > "$T/env.d/secrets.sops.zsh"
envd=$(sed -n '/^if \[\[ -d "\$ZANVIL_DIR\/env.d" \]\]; then/,/^fi$/p' "$ROOT/rc.zsh")
printf '#!/bin/sh\necho "contenu-secret" >&2; exit 1\n' > "$T/bin/sops"; chmod +x "$T/bin/sops"
out=$(PATH="$T/bin:/usr/bin:/bin" zsh -f -c "ZANVIL_DIR='$T'; $envd" 2>&1)
check "echec signale, sans le message de sops" "[zanvil] dechiffrement impossible : env.d/secrets.sops.zsh (variables non chargees)" "$out"
printf '#!/bin/sh\necho "export OK_VAR=1"\n' > "$T/bin/sops"
check "succes : variables chargees" "1" "$(PATH="$T/bin:/usr/bin:/bin" zsh -f -c "ZANVIL_DIR='$T'; $envd; print \$OK_VAR" 2>&1)"

echo; printf '  %s ok, %s echec(s)\n' "$pass" "$fail"; [[ $fail == 0 ]]
