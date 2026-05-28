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
    local -a completions=()
    # Alias d'abord (priorite)
    local alias_file="$HOME/.kube/.context_aliases"
    if [[ -f "$alias_file" ]]; then
        while IFS='=' read -r a c; do
            [[ -z "$a" || "$a" == \#* ]] && continue
            completions+=("$a:$c")
        done < "$alias_file"
    fi
    # Puis contextes kubectl
    if command -v kubectl &>/dev/null; then
        local -a ctxs=(${(f)"$(kubectl config get-contexts -o name 2>/dev/null)"})
        for c in "${ctxs[@]}"; do
            completions+=("$c")
        done
    fi
    _describe 'context' completions
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

_k_k9s() {
    local -a ctx_completions=()
    # Alias
    local alias_file="$HOME/.kube/.context_aliases"
    if [[ -f "$alias_file" ]]; then
        while IFS='=' read -r a c; do
            [[ -z "$a" || "$a" == \#* ]] && continue
            ctx_completions+=("$a:$c")
        done < "$alias_file"
    fi
    # Contextes bruts
    if command -v kubectl &>/dev/null; then
        local -a ctxs=(${(f)"$(kubectl config get-contexts -o name 2>/dev/null)"})
        for c in "${ctxs[@]}"; do
            ctx_completions+=("$c")
        done
    fi

    local -a ns_completions=(all)
    if command -v kubectl &>/dev/null; then
        ns_completions+=(${(f)"$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')"})
    fi

    _arguments \
        '1:context:->ctx' \
        '2:namespace:->ns'

    case $state in
        ctx) _describe 'context' ctx_completions ;;
        ns)  _describe 'namespace' ns_completions ;;
    esac
}
compdef _k_k9s k

_klog() {
    local current_ns
    current_ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
    current_ns="${current_ns:-default}"

    local -a pod_completions=()
    if command -v kubectl &>/dev/null; then
        pod_completions=(${(f)"$(kubectl get pods -n "$current_ns" \
            --no-headers \
            -o custom-columns='NAME:.metadata.name' 2>/dev/null)"})
    fi

    _arguments \
        '(-f --follow)'{-f,--follow}'[suivre les logs en temps reel]' \
        '--no-follow[afficher et quitter sans suivre]' \
        '(-p --previous)'{-p,--previous}'[logs du container precedent]' \
        '(-n --namespace)'{-n,--namespace}'[namespace cible]:namespace:($(kubectl get namespaces -o jsonpath="{.items[*].metadata.name}" 2>/dev/null))' \
        '--tail[nombre de lignes]:lignes:(20 50 100 500 1000)' \
        '(-g --grep)'{-g,--grep}'[filtrer par regex]:pattern:' \
        '(-A --all)'{-A,--all}'[logs de tous les pods (meme label app=)]' \
        '(-t --timestamps)'{-t,--timestamps}'[afficher les timestamps kubectl]' \
        '(-o --save)'{-o,--save}'[sauvegarder dans un fichier]:file:_files' \
        '1:pod:(${pod_completions[@]})' \
        '2:container:($(kubectl get pod ${words[2]} -n '"$current_ns"' -o jsonpath="{.spec.containers[*].name}" 2>/dev/null))'
}
compdef _klog klog
