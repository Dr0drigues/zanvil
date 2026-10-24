#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Thème zanvil
# @raycast.mode silent
# @raycast.packageName zanvil
# @raycast.argument1 { "type": "dropdown", "placeholder": "Thème", "data": [{"title": "auto (clair/sombre)", "value": "auto"}, {"title": "forge", "value": "forge"}, {"title": "plain", "value": "plain"}, {"title": "powerline", "value": "powerline"}, {"title": "tokyo-light-pro", "value": "tokyo-light-pro"}, {"title": "tokyo-night-pro", "value": "tokyo-night-pro"}, {"title": "default", "value": "default"}, {"title": "minimal", "value": "minimal"}, {"title": "tokyo-light", "value": "tokyo-light"}, {"title": "tokyo-night", "value": "tokyo-night"}] }

# La liste ci-dessus est statique (Raycast l'exige) : la refaire quand config/themes change.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; export PATH
ZANVIL_DIR="${ZANVIL_DIR:-$HOME/.zanvil}"; export ZANVIL_DIR

# le theme passe en argument ($1), jamais dans le code zsh ; stdout a la poubelle, l'echec
# arrive en notification.
exec zsh -f -c '
    [[ -f "$ZANVIL_DIR/config.zsh" ]] && source "$ZANVIL_DIR/config.zsh"
    source "$ZANVIL_DIR/core/ui.zsh"
    source "$ZANVIL_DIR/core/commands/theme.zsh"
    zanvil-theme "$1" && exit 0
    osascript -e "on run a" -e "display notification (item 1 of a) with title \"zanvil\"" -e "end run" \
        -- "Thème non appliqué : $1" &>/dev/null
    exit 1
' zanvil-raycast "$1" >/dev/null
