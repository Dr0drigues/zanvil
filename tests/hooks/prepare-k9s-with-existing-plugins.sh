#!/bin/sh
# Depose un plugins.yaml k9s DEJA present, pour que le cas puisse prouver qu il survit.
#
# `not_written` ne dit rien de l existence : un fichier jamais cree n est pas ecrit, et un
# fichier deja la et laisse tranquille non plus. Pour prouver qu une chose SURVIT, il faut
# donc la creer d abord — c est ce que ce hook fait.
set -eu

cat >/dev/null   # drain de la charge setup

SRC="$GAVELDROP_PROJECT"

# Les deux emplacements possibles : la fonction rend l un ou l autre selon la plateforme,
# et le hook ne sait pas lequel tournera. Les deux sont prepares.
for d in "$HOME/Library/Application Support/k9s" "${XDG_CONFIG_HOME:-$HOME/.config}/k9s"; do
    mkdir -p "$d"
    cat >"$d/plugins.yaml" <<'YAML'
plugins:
  mon-plugin-a-moi:
    shortCut: Ctrl-Y
    description: Un plugin que l utilisateur avait avant zanvil
    scopes: [po]
    command: echo
    args: [bonjour]
YAML
done
