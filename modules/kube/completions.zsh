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
