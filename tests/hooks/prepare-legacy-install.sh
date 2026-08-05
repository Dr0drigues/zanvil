#!/bin/sh
# Construit un ~/.zsh_env herite, pour que la migration ait quelque chose a migrer.
#
# La fixture porte les trois cas qui decident du comportement : un config.zsh avec un
# garde de module sous l ancien nom, un env.d/*.zsh en clair avec un reglage sous
# l ancien nom, et un env.d/*.sops.zsh qui ne doit PAS etre touche parce qu il est
# chiffre — un sed dessus le rendrait indechiffrable.
set -eu

cat >/dev/null   # drain de la charge setup

SRC="$GAVELDROP_PROJECT"
OLD="$HOME/.zsh_env"

mkdir -p "$OLD/core/lifecycle" "$OLD/env.d"
cp "$SRC/core/lifecycle/migrate_zanvil.zsh" "$OLD/core/lifecycle/"

printf 'ZSH_ENV_MODULE_KUBE=true\nZSH_ENV_MODULE_DOCKER=false\n' >"$OLD/config.zsh"
printf 'export ZSH_ENV_WORK_ES_URL="https://es.exemple.invalide"\nexport ZSH_ENV_WORK_TIMEOUT=5\n' >"$OLD/env.d/work.zsh"

# Un faux fichier chiffre : son contenu est du charabia, comme le serait une sortie sops.
# Ce qui compte est son nom, et qu il ressorte identique.
printf 'ENC[AES256_GCM,data:ZSH_ENV_FAUX_CHIFFRE,type:str]\n' >"$OLD/env.d/secrets.sops.zsh"

# Un .zshrc herite, que la migration reecrit deja.
printf 'export ZSH_ENV_DIR="$HOME/.zsh_env"\nsource "$ZSH_ENV_DIR/rc.zsh"\n' >"$HOME/.zshrc"
