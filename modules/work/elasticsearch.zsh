# ==============================================================================
# Work Elasticsearch — Fetch logs depuis es-internal
# ==============================================================================

_WORK_FETCH_LOGS_SCRIPT="${ZSH_ENV_DIR:-$HOME/.zsh_env}/modules/work/fetch_es_logs.sh"

blg_fetch_logs() {
    if [[ ! -x "$_WORK_FETCH_LOGS_SCRIPT" ]]; then
        _ui_msg_fail "Script introuvable ou non executable: $_WORK_FETCH_LOGS_SCRIPT"
        return 1
    fi

    if [[ -z "${ES_USER:-}" || -z "${ES_PASSWORD:-}" ]]; then
        _ui_msg_fail "ES_USER/ES_PASSWORD non definis (voir env.d/work.zsh)"
        return 1
    fi

    "$_WORK_FETCH_LOGS_SCRIPT" "$@"
}
