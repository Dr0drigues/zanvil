[[ "${ZSH_ENV_MODULE_AI:-true}" != "true" ]] && return 0

source "$ZSH_ENV_DIR/modules/ai/ai_context.zsh"
source "$ZSH_ENV_DIR/modules/ai/ai_tokens.zsh"
