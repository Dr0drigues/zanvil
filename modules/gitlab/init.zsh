[[ "${ZSH_ENV_MODULE_GITLAB:-}" != "true" ]] && return 0

source "$ZSH_ENV_DIR/modules/gitlab/gitlab_logic.zsh"
source "$ZSH_ENV_DIR/modules/gitlab/pipeline_bulk.zsh"
