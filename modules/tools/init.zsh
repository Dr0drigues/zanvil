[[ "${ZANVIL_MODULE_TOOLS:-true}" != "true" ]] && return 0

source "$ZANVIL_DIR/modules/tools/mise_hooks.zsh"
source "$ZANVIL_DIR/modules/tools/test_runner.zsh"
source "$ZANVIL_DIR/modules/tools/zsh_profile.zsh"
