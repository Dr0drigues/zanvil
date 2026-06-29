[[ "${ZANVIL_MODULE_DOCKER:-}" != "true" ]] && return 0

source "$ZANVIL_DIR/modules/docker/docker_utils.zsh"
source "$ZANVIL_DIR/modules/docker/docker_cleanup.zsh"
