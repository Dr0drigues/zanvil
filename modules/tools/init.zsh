[[ "${ZSH_ENV_MODULE_TOOLS:-true}" != "true" ]] && return 0

source "$ZSH_ENV_DIR/modules/tools/mise_hooks.zsh"
source "$ZSH_ENV_DIR/modules/tools/test_runner.zsh"
source "$ZSH_ENV_DIR/modules/tools/zsh_profile.zsh"
