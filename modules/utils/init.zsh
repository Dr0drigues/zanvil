source "$ZSH_ENV_DIR/modules/utils/utils.zsh"
source "$ZSH_ENV_DIR/modules/utils/extract.zsh"
source "$ZSH_ENV_DIR/modules/utils/fkill.zsh"

# net_utils : lazy (charge au premier appel de myip/port)
for _fn in myip port; do
    eval "${_fn}() { source \"$ZSH_ENV_DIR/modules/utils/net_utils.zsh\"; ${_fn} \"\$@\"; }"
done
unset _fn
