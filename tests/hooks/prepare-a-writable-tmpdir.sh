#!/bin/sh
# Un TMPDIR a l interieur de la racine isolee du cas.
#
# Le viewer deverse ses lignes dans un fichier mktemp, qu il efface a la sortie. Prouver
# qu il l efface demande de regarder la ou il l a mis — et mktemp suit TMPDIR, qui pointe
# ailleurs sur la machine (/var/folders sur macOS, /tmp sur Linux), hors de ce que le cas
# observe. Le repertoire est donc cree ici, et le cas ramene TMPDIR dedans.
set -eu

cat >/dev/null   # drain de la charge setup

mkdir -p "$HOME/tmp"
