# Affiche les logs d'un pod avec selection interactive fzf si besoin.
# Usage: klog [pod] [container] [--follow] [--no-follow] [--previous] [--tail N] [-n ns]
klog() {
    _kube_check_deps || return 1

    local follow=true previous=false tail=100 ns=""
    local -a positionals=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow)    follow=true; shift ;;
            --no-follow)    follow=false; shift ;;
            -p|--previous)  previous=true; shift ;;
            -n|--namespace) ns="$2"; shift 2 ;;
            --tail)         tail="$2"; shift 2 ;;
            *)              positionals+=("$1"); shift ;;
        esac
    done

    local pod="${positionals[1]:-}"
    local container="${positionals[2]:-}"

    local current_ns
    if [[ -n "$ns" ]]; then
        current_ns="$ns"
    else
        current_ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
        current_ns="${current_ns:-default}"
    fi

    # Selection interactive du pod si absent
    if [[ -z "$pod" ]]; then
        if ! command -v fzf &>/dev/null; then
            _ui_msg_fail "fzf requis pour la selection interactive"
            echo "Usage: klog <pod> [container]" >&2
            return 1
        fi

        local pods_list
        pods_list=$(kubectl get pods -n "$current_ns" \
            --no-headers \
            -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready' \
            2>/dev/null)

        if [[ -z "$pods_list" ]]; then
            _ui_msg_fail "Aucun pod trouve dans le namespace $current_ns"
            return 1
        fi

        pod=$(echo "$pods_list" | fzf \
            --header="Pods (namespace: $current_ns)" \
            --prompt="Pod > " \
            --preview="kubectl logs -n $current_ns {1} --tail=20 2>&1" \
            --preview-window=right:50% \
            | awk '{print $1}')

        [[ -z "$pod" ]] && return 0
    fi

    # Selection du container si plusieurs
    if [[ -z "$container" ]]; then
        local containers_raw
        containers_raw=$(kubectl get pod "$pod" -n "$current_ns" \
            -o jsonpath='{.spec.containers[*].name}' 2>/dev/null | tr ' ' '\n')
        local -a containers_arr=(${(f)containers_raw})

        if [[ ${#containers_arr} -gt 1 ]]; then
            if command -v fzf &>/dev/null; then
                container=$(printf '%s\n' "${containers_arr[@]}" | fzf \
                    --header="Conteneurs du pod $pod" \
                    --prompt="Container > ")
                [[ -z "$container" ]] && return 0
            else
                _ui_msg_info "Conteneurs: ${containers_arr[*]}"
                echo -n "Conteneur: "
                read container
            fi
        fi
    fi

    # Construction et execution de kubectl logs
    local -a log_args=(logs "$pod" -n "$current_ns")
    [[ -n "$container" ]] && log_args+=(-c "$container")
    [[ "$follow" == true ]] && log_args+=(-f)
    [[ "$previous" == true ]] && log_args+=(--previous)
    log_args+=(--tail "$tail")

    _ui_msg_info "kubectl ${log_args[*]}"
    kubectl "${log_args[@]}"
}
