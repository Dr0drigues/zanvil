[[ "${ZANVIL_MODULE_SECURITY:-true}" != "true" ]] && return 0

source "$ZANVIL_DIR/modules/security/security_audit.zsh"
source "$ZANVIL_DIR/modules/security/secrets_scan.zsh"
