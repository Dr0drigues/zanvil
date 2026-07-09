# ==============================================================================
# Work Elasticsearch — Fetch logs depuis l'Elasticsearch interne
# ==============================================================================

_WORK_FETCH_LOGS_SCRIPT="${ZANVIL_DIR:-$HOME/.zanvil}/modules/work/fetch_es_logs.sh"

# --- Configuration ES (surchargeable via env.d/work.zsh) ---

_work_es_url() {
    echo "${ES_URL:-${ZANVIL_WORK_ES_URL:-https://hote-interne}}"
}

_work_es_index() {
    echo "${ZANVIL_WORK_ES_INDEX:-es-apis-*}"
}

# --- Helpers internes ---

# Garde commune : outils + credentials avant tout appel reseau
_work_es_require() {
    if ! command -v curl &>/dev/null; then
        _ui_msg_fail "curl requis"
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        _ui_msg_fail "jq requis (brew install jq / apt install jq)"
        return 1
    fi
    if [[ -z "${ES_USER:-}" || -z "${ES_PASSWORD:-}" ]]; then
        _ui_msg_fail "ES_USER/ES_PASSWORD non definis (voir env.d/work.zsh)"
        return 1
    fi
    return 0
}

# Appel ES brut. Usage: _work_es_curl METHOD PATH [BODY] [MAX_TIME]
# Sortie: 1ere ligne = code HTTP, reste = corps de reponse.
# Return: code de sortie curl (0 = reponse recue, meme en erreur HTTP).
_work_es_curl() {
    local method=$1 path=$2 body="${3:-}" max_time="${4:-30}"
    local -a opts
    opts=(-s --connect-timeout 5 --max-time "$max_time")
    (( max_time < 5 )) && opts[2,3]=(--connect-timeout "$max_time")
    [[ -n "${SSL_CERT_FILE:-}" ]] && opts+=(--cacert "$SSL_CERT_FILE")
    opts+=(-u "$ES_USER:$ES_PASSWORD" -H 'Content-Type: application/json')
    if [[ "$method" == HEAD ]]; then
        opts+=(-I)
    else
        opts+=(-X "$method")
    fi
    [[ -n "$body" ]] && opts+=(-d "$body")

    local out ret
    out=$(command curl "${opts[@]}" -w $'\n%{http_code}' "$(_work_es_url)/$path" 2>/dev/null)
    ret=$?
    (( ret != 0 )) && return $ret
    # Reordonne: code HTTP en premiere ligne, corps ensuite
    print -r -- "${out##*$'\n'}"
    local resp_body="${out%$'\n'*}"
    [[ "$resp_body" != "$out" && -n "$resp_body" ]] && print -r -- "$resp_body"
    return 0
}

# Appel ES "JSON ou rien". Usage: _work_es_json METHOD PATH [BODY] [MAX_TIME]
# Sortie: corps seul. Return 1 si reseau KO ou HTTP >= 400.
_work_es_json() {
    local out code
    out=$(_work_es_curl "$@") || return 1
    code="${out%%$'\n'*}"
    [[ "$code" == <-> ]] || return 1
    (( code >= 400 )) && return 1
    [[ "$out" == *$'\n'* ]] && print -r -- "${out#*$'\n'}"
    return 0
}

work_fetch_logs() {
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
