#!/usr/bin/env bash
# Verifie le script Raycast : environnement minimal, jeton lu dans ~/.gitlab_secrets, PATH
# Homebrew ajoute, lien du presse-papiers transmis a `glab mr view` sans interpolation.
# Faux pbpaste/glab. Usage : scripts/tests/project-raycast.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fail=0
check() {
    if grep -q -- "$2" "$T/calls.log"; then echo "  ok   $1"
    else echo "  FAIL $1 (attendu : $2)"; cat "$T/calls.log"; fail=1; fi
}

mkdir -p "$T/home" "$T/bin" "$T/work"
# syntaxe zsh (tableau) + sortie parasite : /bin/sh y echouerait, Raycast afficherait la sortie
printf 'export GITLAB_TOKEN=t\nx=(a b)\necho fuite\n' > "$T/home/.gitlab_secrets"
# le lien est suivi d'une injection : si le presse-papiers etait interprete, $T/pwned apparaitrait
printf '#!/bin/sh\necho "  https://gitlab.example.com/group/sub/repo/-/merge_requests/7 ;touch %s/pwned  "\n' "$T" > "$T/bin/pbpaste"
printf '#!/bin/sh\necho "glab TOKEN=$GITLAB_TOKEN PATH=$PATH ARGS=$*" >> "%s/calls.log"\nexit 1\n' "$T" > "$T/bin/glab"
printf "#!/bin/sh\nexit 0\n" > "$T/bin/jq"  # seule la presence compte : glab echoue avant
chmod +x "$T/bin/pbpaste" "$T/bin/glab" "$T/bin/jq"
# faux osascript/orca/idea/open : rien ne doit atteindre le vrai systeme (notifications, applis)
for b in osascript orca idea open; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$b" "$T" > "$T/bin/$b"
    chmod +x "$T/bin/$b"
done
touch "$T/calls.log"
for b in osascript orca idea open glab pbpaste jq; do
    [[ "$(PATH="$T/bin:/usr/bin:/bin" command -v $b)" == "$T/bin/$b" ]] || { echo "$b reel atteignable : abandon" >&2; exit 2; }
done

env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" ZANVIL_DIR="$ROOT" WORK_DIR="$T/work" \
    "$ROOT/scripts/raycast/project-open.sh" >"$T/out" 2>&1
if grep -q fuite "$T/out"; then echo "  FAIL sortie des secrets fuit"; fail=1; else echo "  ok   rien sur stdout"; fi

check "jeton lu depuis ~/.gitlab_secrets" 'TOKEN=t '
check "PATH contient /opt/homebrew/bin" 'PATH=[^ ]*/opt/homebrew/bin'
check "glab mr view appele" 'ARGS=.*mr view'
check "MR transmise a glab" 'mr view 7 -R group/sub/repo'

# presse-papiers qui n'est pas un lien de MR : la notification de project open, rien d'autre
printf '#!/bin/sh\necho "pas un lien"\n' > "$T/bin/pbpaste"
: > "$T/calls.log"
env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" ZANVIL_DIR="$ROOT" WORK_DIR="$T/work" \
    "$ROOT/scripts/raycast/project-open.sh" >/dev/null 2>&1
check "notification pour un texte qui n'est pas une MR" 'osascript.*Pas un lien de MR'
if grep -q '^glab' "$T/calls.log"; then echo "  FAIL glab appele sans lien"; fail=1; else echo "  ok   glab non appele"; fi
if [[ -e "$T/pwned" ]]; then echo "  FAIL presse-papiers interprete"; fail=1; else echo "  ok   presse-papiers non interprete"; fi
exit $fail
