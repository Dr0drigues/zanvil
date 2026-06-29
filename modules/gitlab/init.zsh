[[ "${ZANVIL_MODULE_GITLAB:-}" != "true" ]] && return 0

source "$ZANVIL_DIR/modules/gitlab/gitlab_logic.zsh"
source "$ZANVIL_DIR/modules/gitlab/pipeline_bulk.zsh"
