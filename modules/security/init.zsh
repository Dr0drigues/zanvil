[[ "${ZSH_ENV_MODULE_SECURITY:-true}" != "true" ]] && return 0

source "$ZSH_ENV_DIR/modules/security/security_audit.zsh"
source "$ZSH_ENV_DIR/modules/security/secrets_scan.zsh"
