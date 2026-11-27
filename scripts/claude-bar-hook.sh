#!/bin/sh
# Hook Claude Code -> SketchyBar : tient a jour la liste des sessions qui attendent une reponse.
# Usage (par ai_claude_hooks install) : claude-bar-hook.sh waiting|working|end, JSON du hook sur stdin.
#   waiting : Notification, Stop        -> <etat>/<session_id> contient le nom du dossier
#   working : UserPromptSubmit          -> fichier retire
#   end     : SessionEnd                -> fichier retire
# Puis `sketchybar --trigger claude_change`. Ne sort jamais en erreur et n'ecrit rien : un hook
# qui echoue ou bavarde gene la session.
state="${XDG_CACHE_HOME:-$HOME/.cache}/zanvil/claude"
input=$(cat)

field() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$input" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
    else
        printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
    fi
}

id=$(field session_id)
# Un identifiant sert de nom de fichier : rien d'autre que [A-Za-z0-9_-].
case "$id" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac

case "${1:-}" in
    waiting)
        mkdir -p "$state" 2>/dev/null || exit 0
        cwd=$(field cwd)
        printf '%s\n' "${cwd##*/}" > "$state/$id" 2>/dev/null ;;
    working|end)
        rm -f "$state/$id" 2>/dev/null ;;
    *) exit 0 ;;
esac

command -v sketchybar >/dev/null 2>&1 && sketchybar --trigger claude_change >/dev/null 2>&1
exit 0
