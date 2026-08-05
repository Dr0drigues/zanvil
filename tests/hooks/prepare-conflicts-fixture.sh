#!/bin/sh
# Construit un ZANVIL_DIR dont les conflits sont connus, pour que le verdict de
# `zanvil-doctor-conflicts` soit exact et non « ce que le dépôt contient aujourd'hui ».
#
# La fixture porte un exemplaire de chaque famille détectée, plus les deux pièges qui
# ont révélé un défaut dans l'implémentation zsh : une ligne commentée, et une ligne de
# code qui *mentionne* la chaîne cherchée sans rien enregistrer.
set -eu

cat >/dev/null   # drain de la charge setup

SRC="$GAVELDROP_PROJECT"
DST="$HOME/zanvil"

mkdir -p "$DST/core/commands" "$DST/modules/premier" "$DST/modules/second"
cp "$SRC/core/ui.zsh" "$DST/core/"
cp "$SRC/core/commands/commands.zsh" "$DST/core/commands/"

# Un alias déclaré deux fois, et un déclaré une seule.
{
    printf 'alias dupliq="echo premier"\n'
    printf 'alias unique_premier="echo un"\n'
} >"$DST/modules/premier/init.zsh"
{
    printf 'alias dupliq="echo second"\n'
    printf 'alias unique_second="echo deux"\n'
} >"$DST/modules/second/init.zsh"

# Une fonction publique déclarée deux fois.
printf 'fonction_dupliquee() {\n    :\n}\n' >>"$DST/modules/premier/init.zsh"
printf 'fonction_dupliquee() {\n    :\n}\n' >>"$DST/modules/second/init.zsh"

# Un export déclaré deux fois. La detection ne regarde que modules/, pas core/.
printf 'export EXPORT_DUPLIQUE="a"\n' >>"$DST/modules/premier/init.zsh"
printf 'export EXPORT_DUPLIQUE="b"\n' >>"$DST/modules/second/init.zsh"

# Deux hooks chpwd réels, plus les deux pièges.
#
# Le premier piège est une ligne commentée : elle ne doit pas être comptée, ce que le
# filtre du compte faisait déjà.
#
# Le second est une ligne de code qui contient la chaîne sans rien enregistrer — le cas
# de `commands.zsh` lui-même, dont les deux `grep` mentionnent « add-zsh-hook chpwd ».
# L implémentation zsh la comptait mais ne l affichait pas, et n'affichait juste que
# parce que ces lignes portent un `#` dans leur propre motif.
{
    printf 'add-zsh-hook chpwd _premier_chpwd\n'
    printf '# add-zsh-hook chpwd _commente_donc_inactif\n'
} >>"$DST/modules/premier/init.zsh"
{
    printf '    add-zsh-hook chpwd _second_chpwd\n'
    printf 'echo "cette ligne parle de add-zsh-hook chpwd sans en poser un"\n'
} >>"$DST/modules/second/init.zsh"

# Un export porte le meme nom dans core/ et dans modules/. Il ne doit PAS etre signale :
# la detection des exports ne regarde que modules/, contrairement a celle des alias et des
# fonctions qui couvre les deux. Sans ce piege, elargir le perimetre par erreur ne faisait
# rougir aucun cas.
printf 'export EXPORT_HORS_PERIMETRE="cote core"\n' >"$DST/core/hors-perimetre.zsh"
printf 'export EXPORT_HORS_PERIMETRE="cote modules"\n' >>"$DST/modules/premier/init.zsh"

printf 'ZANVIL_MODULE_PREMIER=true\nZANVIL_MODULE_SECOND=true\n' >"$DST/config.zsh"
printf 'minimal\n' >"$DST/.current_theme"
