#!/bin/sh
# Comme prepare-k9s-with-existing-plugins.sh, mais le config.yaml n a PAS de ligne
# `skin:` — ce qui exerce la branche d insertion de _zanvil_k9s_apply_skin au lieu de
# celle du remplacement. Les deux etaient cassees sur macOS, chacune pour une raison
# differente, et il faut donc deux cas.
#
# `not_written` ne dit rien de l existence : un fichier jamais cree n est pas ecrit, et un
# fichier deja la et laisse tranquille non plus. Pour prouver qu une chose SURVIT, il faut
# donc la creer d abord — c est ce que ce hook fait.
set -eu

cat >/dev/null   # drain de la charge setup

SRC="$GAVELDROP_PROJECT"

# Un ZANVIL_DIR isole, et non le depot lui-meme.
#
# La premiere version de ce hook posait un .current_theme dans $HOME/zanvil tout en
# laissant le cas pointer ZANVIL_DIR sur le depot : la fonction lisait donc le theme de la
# MACHINE. Le cas passait — parce qu il n assertait pas encore le skin — et aurait rendu
# un verdict different selon le theme de qui le lance, et un autre encore sur un runner ou
# le fichier n existe pas.
DST="$HOME/zanvil"
mkdir -p "$DST"
cp -R "$SRC/config" "$DST/"
cp -R "$SRC/core" "$DST/"
cp -R "$SRC/modules" "$DST/"

# Un theme actif QUI A UN SKIN : sans lui, `kube_k9s_setup` saute la branche du skin et
# trois de ses quatre fichiers ne sont jamais deposes. tokyo-night-pro et tokyo-light-pro
# sont les deux seuls a porter un k9s-skin.yaml.
printf 'tokyo-night-pro\n' >"$DST/.current_theme"

# Les deux emplacements possibles : la fonction rend l un ou l autre selon la plateforme,
# et le hook ne sait pas lequel tournera. Les deux sont prepares.
for d in "$HOME/Library/Application Support/k9s" "${XDG_CONFIG_HOME:-$HOME/.config}/k9s"; do
    mkdir -p "$d"
    # Un config.yaml qui designe DEJA un autre skin. Sans lui, k9s_apply_skin prend sa
    # branche « fichier absent » et cree le fichier d un bloc — la branche « fichier
    # existant », qui emploie `sed -i` avec un embranchement GNU/BSD, n est jamais
    # exercee. C est justement la plus fragile des deux.
    cat >"$d/config.yaml" <<'YAML'
k9s:
  liveViewAutoRefresh: false
  ui:
    noIcons: false
YAML
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
