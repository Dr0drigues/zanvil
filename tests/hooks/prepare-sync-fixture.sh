#!/bin/sh
# Construit un ZANVIL_DIR dont la config porte TOUT ce que sync sait exporter.
#
# `prepare-zanvil-dir.sh` ne convient pas ici : son config.zsh est volontairement
# minimal — sept modules, aucun plugin, ni auto-update ni thèmes clair/sombre. Un cas
# qui caractérise l export contre lui ne pourrait rien dire de ces trois familles de
# réglages, qui sont précisément celles où le zsh et le Rust divergent.
#
# Ce hook ne modifie pas l autre : il copie la même arborescence, puis écrit un
# config.zsh complet. Les cas existants gardent leur fixture inchangée.
set -eu

# Drain de la charge setup, envoyée en JSON sur stdin.
cat >/dev/null

SRC="$GAVELDROP_PROJECT"
DST="$HOME/zanvil"

mkdir -p "$DST"
for d in core modules config; do
    cp -R "$SRC/$d" "$DST/"
done

# Deux modules seulement, dont un inactif : assez pour que l export porte les deux
# valeurs booléennes, assez peu pour que le JSON attendu tienne dans une assertion.
# Les plugins sont deux noms inertes — rien ne les clone, la config est seulement lue.
{
    printf 'ZANVIL_PLUGINS=(zsh-autosuggestions zsh-syntax-highlighting)\n'
    printf 'ZANVIL_MODULE_KUBE=true\n'
    printf 'ZANVIL_MODULE_DOCKER=false\n'
    printf 'ZANVIL_AUTO_UPDATE=false\n'
    printf 'ZANVIL_UPDATE_FREQUENCY=14\n'
    printf 'ZANVIL_UPDATE_MODE="silent"\n'
    printf 'ZANVIL_THEME_LIGHT=minimal\n'
    printf 'ZANVIL_THEME_DARK=tokyo-night-pro\n'
} >"$DST/config.zsh"

printf 'minimal\n' >"$DST/.current_theme"

# La contrepartie a importer, ecrite ici et non dans un cas, pour deux raisons : les
# arguments de `call:` sont inertes — gaveldrop les passe entre quotes simples, donc
# `$HOME/ref.json` resterait litteral — et un cas qui declare des `steps:` n execute
# PAS le `run` de son setup, qui ne sert que de repli. Le fichier doit donc exister
# avant le premier echange. Il est ecrit dans la racine isolee, qui est aussi le
# repertoire courant du sujet : les cas y renvoient par « ref.json » tout court.
#
# Chaque valeur est l inverse de celle de la fixture ci-dessus. Sans cela, une ligne
# laissee intacte passerait pour une ligne importee.
cat >ref.json <<'JSON'
{
  "version": "v4.4.0",
  "exported_at": "2026-01-01T00:00:00Z",
  "modules": { "KUBE": false, "DOCKER": true },
  "theme": "tokyo-night-pro",
  "theme_light": "forge",
  "theme_dark": "forge",
  "plugins": [],
  "auto_update": { "enabled": true, "frequency": 3, "mode": "auto" }
}
JSON
