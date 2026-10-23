#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Ouvrir la MR copiée
# @raycast.mode silent
# @raycast.packageName zanvil

# Raycast lance ce script sans PATH Homebrew ni jeton GitLab : on les rebranche ici.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; export PATH  # a la suite : un PATH deja complet garde la main
ZANVIL_DIR="${ZANVIL_DIR:-$HOME/.zanvil}"; export ZANVIL_DIR
[ -r "$HOME/.gitlab_secrets" ] && . "$HOME/.gitlab_secrets"

# le presse-papiers passe en argument ($1), jamais dans le code zsh ; un lien invalide
# finit dans la notification de `project open`
url=$(pbpaste | tr -d '[:space:]')
exec zsh -f -c '
    [[ -f "$ZANVIL_DIR/config.zsh" ]] && source "$ZANVIL_DIR/config.zsh"
    source "$ZANVIL_DIR/core/ui.zsh"
    source "$ZANVIL_DIR/modules/project/project.zsh"
    project open "$1"
' zanvil-raycast "$url"
