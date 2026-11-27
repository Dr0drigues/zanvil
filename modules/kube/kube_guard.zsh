[[ "${ZANVIL_MODULE_KUBE:-}" != "true" ]] && return 0

# ==============================================================================
# Garde-fou kubectl sur les contextes proteges
# ==============================================================================
# Une commande qui modifie le cluster (apply, delete, scale, drain, edit, patch, rollout
# restart|undo...) sur un contexte protege demande de retaper le nom du contexte (ou son
# alias de ~/.kube/.context_aliases) avant de partir. Lecture seule et --dry-run passent.
#
# ZANVIL_KUBE_PROTECTED : motif zsh des contextes proteges (defaut *prod*|*prd*),
#   vide pour desactiver. Sans terminal pour repondre, la commande est refusee.
# Sortie coloree par kubecolor s'il est installe et que la sortie est un terminal.
# Le garde ne couvre que l'appel interactif `kubectl` : un script lance `command kubectl`.

# Terminal ou lire la confirmation ; surchargeable par les tests seulement.
_KUBE_GUARD_TTY="${_KUBE_GUARD_TTY:-/dev/tty}"

# Usage : _kube_guard_needed <args kubectl...> ; code 0 si la commande modifie le cluster
_kube_guard_needed() {
    local -a words=("$@")
    # Premier mot qui n'est pas une option (les options globales peuvent preceder)
    local verb="" sub="" a i
    for (( i = 1; i <= $#words; i++ )); do
        a=${words[i]}
        case "$a" in
            --context|--namespace|-n|--kubeconfig|--cluster|--user|-s|--server) (( i++ )) ;;
            -*) ;;
            *) if [[ -z "$verb" ]]; then verb=$a; else sub=$a; break; fi ;;
        esac
    done
    [[ " $* " == *" --dry-run"* ]] && return 1
    case "$verb" in
        apply|create|delete|edit|patch|replace|scale|drain|cordon|uncordon|taint|set|annotate|label|autoscale) return 0 ;;
        rollout) [[ "$sub" == (restart|undo|pause|resume) ]] ;;
        *) return 1 ;;
    esac
}

# Contexte vise : --context explicite, sinon le contexte courant (un seul fork, et seulement
# pour une commande qui modifie).
_kube_guard_context() {
    local a prev=""
    for a in "$@"; do
        [[ "$prev" == --context ]] && { print -r -- "$a"; return; }
        [[ "$a" == --context=* ]] && { print -r -- "${a#--context=}"; return; }
        prev=$a
    done
    command kubectl config current-context 2>/dev/null
}

kubectl() {
    local pattern="${ZANVIL_KUBE_PROTECTED-*prod*|*prd*}"
    if [[ -n "$pattern" ]] && _kube_guard_needed "$@"; then
        local ctx alias_name="" line answer
        ctx=$(_kube_guard_context "$@")
        if [[ -n "$ctx" && "$ctx" == ${~pattern} ]]; then
            # Alias court accepte en plus du nom complet
            if [[ -r "$HOME/.kube/.context_aliases" ]]; then
                for line in "${(@f)$(<"$HOME/.kube/.context_aliases")}"; do
                    [[ "${line#*=}" == "$ctx" ]] && { alias_name=${line%%=*}; break; }
                done
            fi
            if ! { true <"$_KUBE_GUARD_TTY"; } 2>/dev/null; then
                _ui_msg_fail "Contexte protege ($ctx) et aucun terminal pour confirmer : refuse." >&2
                return 1
            fi
            _ui_msg_warn "Contexte protege : $ctx" >&2
            printf "Retapez le nom du contexte%s pour confirmer « kubectl %s » : " \
                "${alias_name:+ (ou $alias_name)}" "$*" >&2
            read -r answer <"$_KUBE_GUARD_TTY"
            if [[ -z "$answer" || ( "$answer" != "$ctx" && "$answer" != "$alias_name" ) ]]; then
                _ui_msg_info "Annule" >&2
                return 1
            fi
        fi
    fi
    if [[ -t 1 ]] && (( $+commands[kubecolor] )); then
        command kubecolor "$@"
    else
        command kubectl "$@"
    fi
}
