#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Ménage des worktrees
# @raycast.mode silent
# @raycast.packageName zanvil

PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; export PATH
ZANVIL_DIR="${ZANVIL_DIR:-$HOME/.zanvil}"; export ZANVIL_DIR

# `project clean` notifie lui-meme son resume et ses erreurs ; stdout a la poubelle
# (Raycast en afficherait la derniere ligne).
exec zsh -f -c '
    setopt extendedglob
    [[ -r "$HOME/.gitlab_secrets" ]] && source "$HOME/.gitlab_secrets" >/dev/null 2>&1
    [[ -f "$ZANVIL_DIR/config.zsh" ]] && source "$ZANVIL_DIR/config.zsh"
    export WORK_DIR="${WORK_DIR:-$HOME/work}"
    source "$ZANVIL_DIR/core/ui.zsh"
    source "$ZANVIL_DIR/modules/project/project.zsh"
    out=$(project clean)
    rc=$?
    # rien a faire : project clean ne notifie pas, on le dit
    (( rc == 0 )) && [[ "$out" == *"Rien a faire"* ]] \
        && osascript -e "on run a" -e "display notification (item 1 of a) with title \"zanvil\"" -e "end run" \
            -- "Aucun worktree à retirer" &>/dev/null
    exit $rc
' zanvil-raycast >/dev/null
