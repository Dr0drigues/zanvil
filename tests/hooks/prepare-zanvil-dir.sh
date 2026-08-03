#!/bin/sh
# Construit un ZANVIL_DIR a l interieur de l isolation gaveldrop.
#
# Un cas qui declare `exec: ./tests/hooks/prepare-zanvil-dir.sh` et
# `env: { ZANVIL_DIR: "$HOME/zanvil" }` obtient un depot minimal mais complet,
# dont l etat est fixe. Le depot reel reste en lecture seule.
#
# Quatre raisons, toutes mesurees :
#   - .current_theme et config.zsh sont gitignores : un cas qui les lirait dans le
#     depot rendrait un verdict dependant de la machine ;
#   - delta_setup ecrit dans $ZANVIL_DIR/config/lazygit/config.yml ;
#   - rc.zsh ecrit .last_update_check et .work_context_cache dans $ZANVIL_DIR ;
#   - le depot pese 1,9 Go — entierement cli/target — donc la copie est selective.
#
# Le hook est resolu depuis la racine du depot mais s execute avec la racine
# isolee comme repertoire courant : ce qu il ecrit atterrit dans l isolation.
set -eu

# Drain de la charge setup, envoyee en JSON sur stdin.
cat >/dev/null

SRC="$GAVELDROP_PROJECT"
DST="$HOME/zanvil"

mkdir -p "$DST"
for d in core modules config scripts examples; do
    cp -R "$SRC/$d" "$DST/"
done
for f in rc.zsh plugins.zsh completions.zsh; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DST/"
done

# Pas un seul plugin : plugins.zsh ferait un `git clone`, donc atteindrait le
# reseau, et le verdict en dependrait. ZANVIL_MODULE_DOCKER=false est deliberement
# le seul a false — le cas `modules list` a besoin d un module inactif pour que son
# assertion sur « inactif » prouve quelque chose.
{
    printf 'ZANVIL_PLUGINS=()\n'
    printf 'ZANVIL_MODULE_KUBE=true\n'
    printf 'ZANVIL_MODULE_DOCKER=false\n'
    # GITLAB actif et SECURITY absent, tous deux volontairement : ni l un ni l autre
    # ne declare de `binary` dans son .module.toml, donc `doctor` les classe dans sa
    # section Modules, dont le symbole ne depend QUE de ce fichier. Les modules a
    # binaire — KUBE et kubectl, DOCKER et docker — passent par command_exists
    # (doctor.rs:258), donc leur symbole depend du runner : kubectl est sur l image
    # ubuntu et pas sur celle de macOS, ce qui a fait echouer ce cas sur un seul des
    # deux systemes.
    printf 'ZANVIL_MODULE_GITLAB=true\n'
    printf 'ZANVIL_MODULE_POSTING=true\n'
    printf 'ZANVIL_MODULE_DELTA=true\n'
    printf 'ZANVIL_MODULE_LAZYGIT=true\n'
    printf 'ZANVIL_MODULE_ATUIN=true\n'
} >"$DST/config.zsh"

printf 'minimal\n' >"$DST/.current_theme"

mkdir -p "$HOME/.config" "$HOME/.kube" "$HOME/work"

# Un jeton GitLab factice, parce que l isolation doit representer un poste CONFIGURE.
# Sans ce fichier, modules/gitlab/gitlab_logic.zsh:11 previent au chargement et son
# avertissement se melange a la sortie du sujet — le rapport HTML de gaveldrop l a
# montre. Avec lui, le cas de chargement peut asserter que rien ne previent, ce qui est
# plus strict : si le module se remettait a le faire malgre un fichier present, le cas
# rougirait.
printf "export GITLAB_TOKEN='jeton-de-test-sans-valeur'\n" >"$HOME/.gitlab_secrets"
