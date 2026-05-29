#!/usr/bin/env zsh
[[ "${ZSH_ENV_MODULE_ZPROJECT:-true}" != "true" ]] && return 0

# zproject — active un contexte projet (kube, env, path, runtimes) par shell.
# Delegue la resolution au CLI Rust (zsh-env-cli project ...).

typeset -g ZPROJECT_STATE_DIR="${TMPDIR:-/tmp}"
typeset -g ZPROJECT_STATE_FILE="${ZPROJECT_STATE_DIR}/zproject-$$.env"

# ── helpers appeles par le shell-eval emis par le CLI ─────────────────

__zproject_cd() {
    [[ -d "$1" ]] || return 0
    # Ne pas naviguer si on est deja dans l'arbre du projet (ex: components/bff)
    [[ "$PWD" == "$1" || "$PWD" == "$1/"* ]] && return 0
    cd "$1"
}

__zproject_kube_isolate() {
    local shell_cfg="${TMPDIR:-/tmp}/zproject-kubeconfig-$$"
    [[ "${KUBECONFIG:-}" == "$shell_cfg" ]] && return 0
    command -v kubectl &>/dev/null || return 1
    kubectl config view --flatten --raw > "$shell_cfg" 2>/dev/null || return 1
    __zproject_state_append "PREV_KUBECONFIG=${KUBECONFIG:-}"
    export KUBECONFIG="$shell_cfg"
}

__zproject_kube_context() {
    # ZPROJECT_KUBE_OVERRIDE : pin manuel — prend le dessus sur le contexte du projet
    local target="${ZPROJECT_KUBE_OVERRIDE:-$1}"
    __zproject_kube_isolate
    if (( $+functions[kube_switch] )); then
        kube_switch "$target" >/dev/null 2>&1
    else
        kubectl config use-context "$target" >/dev/null 2>&1
    fi
    __zproject_state_append "KUBE_CONTEXT=$target"
}

__zproject_kube_namespace() {
    local target="${ZPROJECT_KUBE_OVERRIDE_NS:-$1}"
    if command -v kubectl &>/dev/null; then
        kubectl config set-context --current --namespace="$target" >/dev/null 2>&1
    fi
    __zproject_state_append "KUBE_NAMESPACE=$target"
}

__zproject_track_env() {
    __zproject_state_append "ENV_VAR=$1"
}

__zproject_runtime_use() {
    local tool="$1" ver="$2"
    if command -v mise &>/dev/null; then
        mise use --global "${tool}@${ver}" >/dev/null 2>&1 || true
    fi
}

__zproject_run_hook_cmd() {
    eval "$1"
    local rc=$?
    if (( rc != 0 )); then
        _ui_msg_fail "on_enter failed: $1"
        __zproject_hook_failed=1
    fi
    return $rc
}

__zproject_run_hook_script() {
    if [[ -f "$1" ]]; then
        source "$1"
        local rc=$?
        if (( rc != 0 )); then
            _ui_msg_fail "on_enter script failed: $1"
            __zproject_hook_failed=1
        fi
        return $rc
    else
        _ui_msg_warn "on_enter script not found: $1"
        return 0
    fi
}

__zproject_queue_on_leave() {
    __zproject_state_append "ON_LEAVE=$1"
}

__zproject_track_alias() {
    __zproject_state_append "ALIAS=$1"
}

__zproject_state_append() {
    print -r -- "$1" >> "$ZPROJECT_STATE_FILE"
}

__zproject_state_init() {
    : > "$ZPROJECT_STATE_FILE"
    local prev_ctx
    prev_ctx="$(kubectl config current-context 2>/dev/null)"
    [[ -n "$prev_ctx" ]] && __zproject_state_append "PREV_KUBE_CONTEXT=$prev_ctx"
    __zproject_state_append "PREV_DIR=$PWD"
}

# ── commande publique ─────────────────────────────────────────────────

zproject() {
    local cmd="${1:-}"
    case "$cmd" in
        ""|-h|--help)
            if [[ -n "${ZPROJECT_NAME:-}" ]]; then
                # Projet actif : afficher le status
                __zproject_status_inline
            else
                # Pas de projet : picker fzf
                __zproject_pick
            fi
            return $?
            ;;
        list)
            zsh-env-cli project list
            return $?
            ;;
        config)
            shift
            zsh-env-cli project config "$@"
            return $?
            ;;
        doctor)
            shift
            zsh-env-cli project doctor "$@"
            return $?
            ;;
        diff)
            shift
            zsh-env-cli project diff "$@"
            return $?
            ;;
        scan)
            shift
            zsh-env-cli project scan "$@"
            return $?
            ;;
        status)
            zsh-env-cli project status
            return $?
            ;;
        envs)
            shift
            zsh-env-cli project envs "$@"
            return $?
            ;;
        edit)
            shift
            __zproject_edit "$@"
            return $?
            ;;
        run)
            shift
            local cmd_name="${1:-}"
            if [[ -z "$cmd_name" ]]; then
                _ui_msg_fail "usage: zproject run <cmd>"
                return 1
            fi
            local cmd_line
            cmd_line="$(zsh-env-cli project run "$cmd_name" 2>&1)"
            if (( $? != 0 )); then
                _ui_msg_fail "$cmd_line"
                return 1
            fi
            eval "$cmd_line"
            return $?
            ;;
        stacks)
            zsh-env-cli project stacks
            return $?
            ;;
        stack)
            shift
            __zproject_stack "$@"
            return $?
            ;;
        exit)
            __zproject_exit
            return $?
            ;;
        *)
            # Activation: zproject <name> [env]
            __zproject_activate "$1" "${2:-}"
            return $?
            ;;
    esac
}

# ── picker fzf interactif (zproject sans args, aucun projet actif) ────

__zproject_pick() {
    if ! command -v zsh-env-cli &>/dev/null; then
        _ui_msg_fail "zsh-env-cli requis"
        return 1
    fi
    local projects_dir="${HOME}/.zsh-env/projects"
    local -a projects
    projects=($(ls -1 "$projects_dir" 2>/dev/null | grep -v '^_' | grep -v '^stacks$' | grep -v '^local$' | grep -v '\.'))
    if [[ ${#projects[@]} -eq 0 ]]; then
        _ui_msg_warn "Aucun projet configure dans $projects_dir"
        return 1
    fi

    local selected env_selected
    if command -v fzf &>/dev/null; then
        # Deux passes : 1) projet  2) env
        selected=$(printf '%s\n' "${projects[@]}" | fzf \
            --prompt="projet> " \
            --height=40% \
            --reverse \
            --preview="zsh-env-cli project config {} 2>/dev/null | head -30" \
            --preview-window=right:50% \
            --header="ENTER pour activer, TAB pour preview")
        [[ -z "$selected" ]] && return 0

        local -a envs
        envs=($(zsh-env-cli project envs "$selected" 2>/dev/null))
        if [[ ${#envs[@]} -gt 1 ]]; then
            env_selected=$(printf '%s\n' "${envs[@]}" | fzf \
                --prompt="env> " \
                --height=20% \
                --reverse \
                --header="Env pour ${selected}")
            [[ -z "$env_selected" ]] && env_selected=""
            # Retire le suffixe " (default)" si présent
            env_selected="${env_selected%% *}"
        elif [[ ${#envs[@]} -eq 1 ]]; then
            env_selected="${envs[1]%% *}"
        fi
    else
        # Fallback sans fzf
        _ui_header "zproject"
        local i=1
        for p in "${projects[@]}"; do
            printf "  %2d) %s\n" $i "$p"
            (( i++ ))
        done
        local choice
        printf "Projet [1-%d]: " "${#projects[@]}"
        read -r choice
        [[ -z "$choice" ]] && return 0
        if (( choice < 1 || choice > ${#projects[@]} )); then
            _ui_msg_fail "Choix invalide"
            return 1
        fi
        selected="${projects[$choice]}"
    fi

    __zproject_activate "$selected" "${env_selected:-}"
}

# ── status inline (zproject sans args, projet actif) ──────────────────

__zproject_status_inline() {
    _ui_header "zproject status"
    zsh-env-cli project status
}

# ── edit ──────────────────────────────────────────────────────────────

__zproject_edit() {
    local name="${1:-${ZPROJECT_NAME:-}}"
    if [[ -z "$name" ]]; then
        _ui_msg_fail "usage: zproject edit <name>  (ou activer un projet d'abord)"
        return 1
    fi
    local manifest="${HOME}/.zsh-env/projects/${name}/project.toml"
    if [[ ! -f "$manifest" ]]; then
        _ui_msg_fail "Manifest introuvable: $manifest"
        return 1
    fi
    local editor="${EDITOR:-vi}"
    "$editor" "$manifest"
}

# ── activation ────────────────────────────────────────────────────────

__zproject_activate() {
    local name="$1" env="$2"
    if [[ -z "$name" ]]; then
        _ui_msg_fail "usage: zproject <name> [env]"
        return 1
    fi
    if [[ -n "${ZPROJECT_NAME:-}" ]]; then
        __zproject_exit
    fi
    __zproject_state_init
    local activate_script
    if [[ -n "$env" ]]; then
        activate_script="$(zsh-env-cli project activate "$name" -e "$env" 2>&1)"
    else
        activate_script="$(zsh-env-cli project activate "$name" 2>&1)"
    fi
    local rc=$?
    if (( rc != 0 )); then
        _ui_msg_fail "${activate_script}"
        rm -f "$ZPROJECT_STATE_FILE"
        return 1
    fi
    __zproject_hook_failed=0
    eval "$activate_script"
    if (( __zproject_hook_failed )); then
        _ui_msg_warn "on_enter hook failed — rolling back"
        __zproject_exit
        unset __zproject_hook_failed
        return 1
    fi
    unset __zproject_hook_failed
    _ui_msg_ok "zproject: ${ZPROJECT_NAME}${ZPROJECT_ENV:+ (${ZPROJECT_ENV})}"
}

# ── exit ──────────────────────────────────────────────────────────────

__zproject_exit() {
    if [[ -z "${ZPROJECT_NAME:-}" ]]; then
        return 0
    fi
    local prev_name="$ZPROJECT_NAME"

    # 1) Rejoue les on_leave (meilleur-effort)
    if [[ -f "$ZPROJECT_STATE_FILE" ]]; then
        local line key value
        while IFS= read -r line; do
            key="${line%%=*}"
            value="${line#*=}"
            case "$key" in
                ON_LEAVE)
                    case "$value" in
                        CMD:*) eval "${value#CMD:}" 2>/dev/null ;;
                        SCRIPT:*)
                            local sp="${value#SCRIPT:}"
                            [[ -f "$sp" ]] && source "$sp" 2>/dev/null
                            ;;
                    esac
                    ;;
            esac
        done < "$ZPROJECT_STATE_FILE"
    fi

    # 2) Unset env vars / aliases, restore kube, restore PREV_DIR
    if [[ -f "$ZPROJECT_STATE_FILE" ]]; then
        local line key value
        while IFS= read -r line; do
            key="${line%%=*}"
            value="${line#*=}"
            case "$key" in
                ENV_VAR) unset "$value" 2>/dev/null ;;
                ALIAS)   unalias "$value" 2>/dev/null ;;
                PREV_DIR)
                    [[ -d "$value" ]] && cd "$value"
                    ;;
                PREV_KUBECONFIG)
                    local shell_cfg="${TMPDIR:-/tmp}/zproject-kubeconfig-$$"
                    rm -f "$shell_cfg" 2>/dev/null
                    if [[ -n "$value" ]]; then
                        export KUBECONFIG="$value"
                    else
                        unset KUBECONFIG
                    fi
                    ;;
                PREV_KUBE_CONTEXT)
                    if (( $+functions[kube_switch] )); then
                        kube_switch "$value" >/dev/null 2>&1
                    else
                        kubectl config use-context "$value" >/dev/null 2>&1
                    fi
                    ;;
            esac
        done < "$ZPROJECT_STATE_FILE"
    fi

    unset ZPROJECT_NAME ZPROJECT_ENV ZPROJECT_PATH ZPROJECT_KUBE_CONTEXT ZPROJECT_KUBE_NAMESPACE
    rm -f "$ZPROJECT_STATE_FILE"
    _ui_msg_ok "zproject: exited ${prev_name}"
}

# ── stack (tmux) ──────────────────────────────────────────────────────

__zproject_stack() {
    local name="${1:-}" env="${2:-}"
    if [[ -z "$name" ]]; then
        _ui_msg_fail "usage: zproject stack <name> [env]"
        return 1
    fi
    if ! command -v tmux &>/dev/null; then
        _ui_msg_fail "tmux is required for stacks"
        return 1
    fi
    local resolved
    if [[ -n "$env" ]]; then
        resolved="$(zsh-env-cli project stack-resolve "$name" -e "$env" 2>&1)"
    else
        resolved="$(zsh-env-cli project stack-resolve "$name" 2>&1)"
    fi
    if (( $? != 0 )); then
        _ui_msg_fail "$resolved"
        return 1
    fi

    local session="zproject-${name}"
    if tmux has-session -t "$session" 2>/dev/null; then
        _ui_msg_info "stack '$name' already running — attaching"
        tmux attach -t "$session"
        return $?
    fi

    local first=1 member_name member_env member_path activation
    while IFS=$'\t' read -r member_name member_env member_path; do
        [[ -z "$member_name" ]] && continue
        if [[ -n "$member_env" ]]; then
            activation="zproject ${member_name} ${member_env}"
        else
            activation="zproject ${member_name}"
        fi
        if (( first )); then
            tmux new-session -d -s "$session" -n "$member_name" -c "$member_path"
            tmux send-keys -t "${session}:${member_name}" "$activation" C-m
            first=0
        else
            tmux new-window -t "$session" -n "$member_name" -c "$member_path"
            tmux send-keys -t "${session}:${member_name}" "$activation" C-m
        fi
    done <<< "$resolved"

    _ui_msg_ok "stack '$name' started in tmux session '$session'"
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session"
    else
        tmux attach -t "$session"
    fi
}

# ── auto chpwd ────────────────────────────────────────────────────────

typeset -g ZPROJECT_AUTO="${ZPROJECT_AUTO:-on}"

zproject-auto() {
    case "${1:-}" in
        on|off) ZPROJECT_AUTO="$1"; echo "zproject auto: $1" ;;
        *) echo "$ZPROJECT_AUTO" ;;
    esac
}

__zproject_chpwd() {
    [[ "$ZPROJECT_AUTO" != "on" ]] && return 0
    command -v zsh-env-cli &>/dev/null || return 0
    local target
    target="$(zsh-env-cli project find-path "$PWD" 2>/dev/null)"
    if [[ -z "$target" ]]; then
        [[ -n "${ZPROJECT_NAME:-}" ]] && __zproject_exit
        return 0
    fi
    # Detecter le composant courant depuis $PWD (pour CaaS: components/<name>)
    local current_comp=""
    if [[ -n "${ZPROJECT_PATH:-}" && "$PWD" == "${ZPROJECT_PATH}/components/"* ]]; then
        local _rest="${PWD#${ZPROJECT_PATH}/components/}"
        current_comp="${_rest%%/*}"
    fi
    # Re-activer si le projet ou le composant a change
    if [[ "$target" != "${ZPROJECT_NAME:-}" ]] || [[ "$current_comp" != "${ZPROJECT_COMPONENT:-}" ]]; then
        __zproject_activate "$target" ""
    fi
}

__zproject_cleanup_on_shell_exit() {
    [[ -f "$ZPROJECT_STATE_FILE" ]] && rm -f "$ZPROJECT_STATE_FILE"
    local shell_cfg="${TMPDIR:-/tmp}/zproject-kubeconfig-$$"
    [[ -f "$shell_cfg" ]] && rm -f "$shell_cfg"
}

autoload -Uz add-zsh-hook 2>/dev/null
if (( $+functions[add-zsh-hook] )); then
    add-zsh-hook zshexit __zproject_cleanup_on_shell_exit
    add-zsh-hook chpwd __zproject_chpwd
fi

# ── kube pin/unpin ────────────────────────────────────────────────────

# Force un contexte kubectl pour ce shell, même si zproject re-active.
# Usage: kpin <context-ou-alias>
kpin() {
    local ctx="${1:-}"
    if [[ -z "$ctx" ]]; then
        if [[ -n "${ZPROJECT_KUBE_OVERRIDE:-}" ]]; then
            echo "kube pin actif : ${ZPROJECT_KUBE_OVERRIDE}"
        else
            echo "kube pin inactif (contexte géré par zproject)"
        fi
        return 0
    fi
    export ZPROJECT_KUBE_OVERRIDE="$ctx"
    if (( $+functions[kube_switch] )); then
        kube_switch "$ctx"
    else
        kubectl config use-context "$ctx"
    fi
}

# Supprime le pin et réapplique le contexte configuré du projet courant.
kunpin() {
    unset ZPROJECT_KUBE_OVERRIDE
    unset ZPROJECT_KUBE_OVERRIDE_NS
    if [[ -n "${ZPROJECT_NAME:-}" ]]; then
        local _script _ctx
        _script="$(zsh-env-cli project activate "${ZPROJECT_NAME}" ${ZPROJECT_ENV:+-e "$ZPROJECT_ENV"} 2>/dev/null)"
        _ctx="$(echo "$_script" | grep -m1 '^__zproject_kube_context' | sed "s/__zproject_kube_context '\\([^']*\\)'.*/\\1/")"
        if [[ -n "$_ctx" ]]; then
            if (( $+functions[kube_switch] )); then
                kube_switch "$_ctx"
            else
                kubectl config use-context "$_ctx"
            fi
            return
        fi
    fi
    echo "kube pin supprimé"
}

# ── zpenv — switcher d'environnement ─────────────────────────────────
# Usage: zpenv [env]  — interactif sans argument
zpenv() {
    if [[ -z "${ZPROJECT_NAME:-}" ]]; then
        _ui_msg_fail "Aucun projet actif (lance zproject <name> d'abord)"
        return 1
    fi
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        local envs
        envs="$(zsh-env-cli project envs "${ZPROJECT_NAME}" 2>/dev/null)"
        if [[ -z "$envs" ]]; then
            _ui_msg_fail "Aucun environnement défini pour ${ZPROJECT_NAME}"
            return 1
        fi
        if command -v fzf &>/dev/null; then
            target="$(echo "$envs" | fzf \
                --header="Projet: ${ZPROJECT_NAME}  actuel: ${ZPROJECT_ENV:--}" \
                --prompt="Env > ")"
        else
            echo "$envs"
            printf "Env: "
            read -r target
        fi
        [[ -z "$target" ]] && return 0
    fi
    __zproject_activate "${ZPROJECT_NAME}" "$target"
}

# ── cdp — cd vers la racine d'un projet connu ────────────────────────
# Usage: cdp [projet]  — interactif sans argument
cdp() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        if ! command -v zsh-env-cli &>/dev/null; then
            _ui_msg_fail "zsh-env-cli requis"
            return 1
        fi
        local list
        list="$(zsh-env-cli project list 2>/dev/null | awk '{print $1}')"
        if command -v fzf &>/dev/null; then
            target="$(echo "$list" | fzf --prompt="Project > ")"
        else
            echo "$list"
            printf "Projet: "
            read -r target
        fi
        [[ -z "$target" ]] && return 0
    fi
    local script path
    script="$(zsh-env-cli project activate "$target" 2>/dev/null)"
    path="$(echo "$script" | grep "^export ZPROJECT_PATH=" | sed "s/export ZPROJECT_PATH='\\(.*\\)'/\\1/")"
    if [[ -z "$path" || ! -d "$path" ]]; then
        _ui_msg_fail "Chemin introuvable pour '$target'"
        return 1
    fi
    cd "$path"
}

# Alias courts
alias zpr='zproject'
alias zpre='zproject edit'
alias zprs='zproject status'
