# Affiche les logs d'un pod avec selection interactive fzf si besoin.
# Usage: klog [options] [pod] [container]
#   -f / --follow        tail en continu (défaut)
#   --no-follow          afficher et quitter
#   -p / --previous      logs du container précédent (crash)
#   -n / --namespace NS  namespace cible
#   --tail N             nombre de lignes (défaut: 100)
#   -g / --grep PATTERN  filtrer par regex
#   -A / --all           tous les pods (même label app=)
#   -t / --timestamps    ajouter les timestamps kubectl
#   -o / --save FILE     tee vers un fichier
klog() {
    _kube_check_deps || return 1

    local follow=true previous=false tail=100 ns=""
    local grep_pattern="" all_pods=false timestamps=false save_file=""
    local -a positionals=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow)      follow=true; shift ;;
            --no-follow)      follow=false; shift ;;
            -p|--previous)    previous=true; shift ;;
            -n|--namespace)   ns="$2"; shift 2 ;;
            --tail)           tail="$2"; shift 2 ;;
            -g|--grep)        grep_pattern="$2"; shift 2 ;;
            -A|--all)         all_pods=true; shift ;;
            -t|--timestamps)  timestamps=true; shift ;;
            -o|--save)        save_file="$2"; shift 2 ;;
            *)                positionals+=("$1"); shift ;;
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

    # Args kubectl logs communs (sans pod ni container)
    local -a common_args=(-n "$current_ns")
    [[ "$follow" == true ]] && common_args+=(-f)
    [[ "$previous" == true ]] && common_args+=(--previous)
    [[ "$timestamps" == true ]] && common_args+=(--timestamps)
    common_args+=(--tail "$tail")

    # Mode multi-pod : --all
    if [[ "$all_pods" == true ]]; then
        local app_label
        app_label=$(kubectl get pod "$pod" -n "$current_ns" \
            -o jsonpath='{.metadata.labels.app}' 2>/dev/null)

        if [[ -z "$app_label" ]]; then
            _ui_msg_warn "Label 'app' absent sur $pod — logs du pod sélectionné uniquement"
            all_pods=false
        else
            local -a all_pod_names
            all_pod_names=($(kubectl get pods -n "$current_ns" -l "app=${app_label}" \
                -o jsonpath='{.items[*].metadata.name}' 2>/dev/null))
            _ui_msg_info "Multi-pod (app=${app_label}): ${#all_pod_names[@]} pod(s)"

            for _p in "${all_pod_names[@]}"; do
                (
                    if [[ -n "$grep_pattern" && -n "$save_file" ]]; then
                        kubectl logs "$_p" "${common_args[@]}" 2>/dev/null \
                            | sed "s/^/[${_p}] /" | grep -E "$grep_pattern" | tee -a "$save_file"
                    elif [[ -n "$grep_pattern" ]]; then
                        kubectl logs "$_p" "${common_args[@]}" 2>/dev/null \
                            | sed "s/^/[${_p}] /" | grep -E "$grep_pattern"
                    elif [[ -n "$save_file" ]]; then
                        kubectl logs "$_p" "${common_args[@]}" 2>/dev/null \
                            | sed "s/^/[${_p}] /" | tee -a "$save_file"
                    else
                        kubectl logs "$_p" "${common_args[@]}" 2>/dev/null \
                            | sed "s/^/[${_p}] /"
                    fi
                ) &
            done
            wait
            return 0
        fi
    fi

    # Mode single-pod : selection container si plusieurs
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

    # Construction et exécution
    local -a log_args=(logs "$pod" "${common_args[@]}")
    [[ -n "$container" ]] && log_args+=(-c "$container")
    _ui_msg_info "kubectl ${log_args[*]}"

    if [[ -n "$grep_pattern" && -n "$save_file" ]]; then
        kubectl "${log_args[@]}" | grep -E "$grep_pattern" | tee "$save_file"
    elif [[ -n "$grep_pattern" ]]; then
        kubectl "${log_args[@]}" | grep -E "$grep_pattern"
    elif [[ -n "$save_file" ]]; then
        kubectl "${log_args[@]}" | tee "$save_file"
    else
        kubectl "${log_args[@]}"
    fi
}
