[[ "${ZANVIL_MODULE_KUBE:-}" != "true" ]] && return 0

source "$ZANVIL_DIR/modules/kube/kube_config.zsh"
source "$ZANVIL_DIR/modules/kube/klog.zsh"
source "$ZANVIL_DIR/modules/kube/stern.zsh"
