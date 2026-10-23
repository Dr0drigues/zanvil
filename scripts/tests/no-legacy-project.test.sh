#!/usr/bin/env bash
# Verifie que l'ancien code projet (proj*, zproject, zanvil project) a disparu
# et que les fichiers kube se chargent sans erreur.
# Usage : scripts/tests/no-legacy-project.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
fail=0

hits=$(cd "$ROOT" && grep -rn -E 'zproject|ZPROJECT|proj_|project_switcher|project_scaffold|ProjectAction|tm-project|tmux_session' \
    --exclude-dir=node_modules --exclude-dir=target --exclude-dir=dist --exclude-dir=.git --exclude-dir=.superpowers \
    --exclude=no-legacy-project.test.sh . | grep -v "^\./web/docs/" | cut -c1-200)
if [[ -n "$hits" ]]; then
    echo "FAIL: references a l'ancien code projet :"; echo "$hits"; fail=1
else
    echo "PASS: aucune reference a l'ancien code projet"
fi

out=$(ZR="$ROOT" zsh -f -c 'source $ZR/core/ui.zsh; for f in $ZR/modules/kube/*.zsh; do source $f; done' 2>&1)
rc=$?
if [[ $rc -ne 0 || -n "$out" ]]; then
    echo "FAIL: chargement kube (code $rc) : $out"; fail=1
else
    echo "PASS: modules/kube se charge sans erreur"
fi
exit $fail
