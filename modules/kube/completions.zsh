# ==============================================================================
# Kube Completions - Completions pour les commandes kube_*
# ==============================================================================

(( $+functions[compdef] )) || return 0

_kube_add() {
    _arguments \
        '1:config file:_files -g "*.yml *.yaml"'
}
compdef _kube_add kube_add

_kube_azure() {
    local clusters=(blg-dev blg-qlf blg-pprd blg-prd edt-dev edt-qlf edt-pprd edt-prd)
    _arguments \
        '1:cluster:(${clusters[@]})'
}
compdef _kube_azure kube_azure

_kube_encrypt() {
    _arguments \
        '1:config file:_files -g "*.yml *.yaml"'
}
compdef _kube_encrypt kube_encrypt

_kube_switch() {
    local contexts=()
    if command -v kubectl &>/dev/null; then
        contexts=(${(f)"$(kubectl config get-contexts -o name 2>/dev/null)"})
    fi
    _arguments '1:context:(${contexts[@]})'
}
compdef _kube_switch kube_switch

_kube_ns() {
    local namespaces=()
    if command -v kubectl &>/dev/null; then
        namespaces=(${(f)"$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')"})
    fi
    _arguments '1:namespace:(${namespaces[@]})'
}
compdef _kube_ns kube_ns
