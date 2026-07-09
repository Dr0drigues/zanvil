# ==============================================================================
# Work Elasticsearch — Fetch logs depuis l'Elasticsearch interne
# ==============================================================================

_WORK_FETCH_LOGS_SCRIPT="${ZANVIL_DIR:-$HOME/.zanvil}/modules/work/fetch_es_logs.sh"
_WORK_ES_APPS_CACHE="${ZANVIL_DIR:-$HOME/.zanvil}/.work_es_apps_cache"

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

# --- Dates et durees ---
# Duplication annotee de modules/work/fetch_es_logs.sh (bash, BASH_REMATCH) :
# reecrit en zsh ($match). Garder les deux versions synchronisees.

typeset -g _WORK_ES_DATE_FLAVOR=""
_work_es_date_flavor() {
    if [[ -z "$_WORK_ES_DATE_FLAVOR" ]]; then
        if date --version &>/dev/null; then
            _WORK_ES_DATE_FLAVOR=gnu
        else
            _WORK_ES_DATE_FLAVOR=bsd
        fi
    fi
    echo "$_WORK_ES_DATE_FLAVOR"
}

# Xs/Xm/Xh/Xd -> secondes
_work_es_parse_duration() {
    local d=$1
    if [[ "$d" =~ '^([0-9]+)([smhd])$' ]]; then
        local num=$match[1] unit=$match[2]
        case $unit in
            s) echo $num ;;
            m) echo $((num * 60)) ;;
            h) echo $((num * 3600)) ;;
            d) echo $((num * 86400)) ;;
        esac
    else
        return 1
    fi
}

_work_es_epoch_to_iso() {
    local epoch=$1
    if [[ $(_work_es_date_flavor) == gnu ]]; then
        date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
    else
        date -u -j -f "%s" "$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
    fi
}

# ISO UTC ("2026-05-30T14:00:00.000Z" ou sans ms) -> epoch
_work_es_iso_to_epoch() {
    local ts=$1
    if [[ $(_work_es_date_flavor) == gnu ]]; then
        date -u -d "$ts" +%s
    else
        local clean="${ts%.*}"
        clean="${clean%Z}"
        TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null
    fi
}

# Date Europe/Paris "YYYY-mm-ddTHH:MM:SS" -> epoch UTC (DST gere)
_work_es_paris_to_epoch() {
    local dt=$1
    if [[ $(_work_es_date_flavor) == gnu ]]; then
        TZ=Europe/Paris date -d "$dt" +%s
    else
        TZ=Europe/Paris date -j -f "%Y-%m-%dT%H:%M:%S" "$dt" +%s 2>/dev/null
    fi
}

# Calcule la fenetre temporelle depuis --since / --from / --to.
# Remplit les globales _work_es_gte, _work_es_lte (ISO UTC), _work_es_display.
_work_es_window() {
    local since="${1:-}" from="${2:-}" to="${3:-}"
    typeset -g _work_es_gte="" _work_es_lte="" _work_es_display=""
    if [[ -n "$since" ]]; then
        local seconds now
        seconds=$(_work_es_parse_duration "$since") || {
            _ui_msg_fail "--since invalide: $since (attendu: Xs/Xm/Xh/Xd)"
            return 1
        }
        now=$(date -u +%s)
        _work_es_gte=$(_work_es_epoch_to_iso $((now - seconds)))
        _work_es_lte=$(_work_es_epoch_to_iso $now)
        _work_es_display="depuis $since (-> now)"
    else
        local from_epoch to_epoch
        from_epoch=$(_work_es_paris_to_epoch "$from")
        [[ "$from_epoch" == <-> ]] || {
            _ui_msg_fail "--from invalide: $from (attendu: 2026-03-26T15:30:00)"
            return 1
        }
        if [[ -n "$to" ]]; then
            to_epoch=$(_work_es_paris_to_epoch "$to")
            [[ "$to_epoch" == <-> ]] || {
                _ui_msg_fail "--to invalide: $to (attendu: 2026-03-26T15:30:00)"
                return 1
            }
            _work_es_display="$from -> $to (Europe/Paris)"
        else
            to_epoch=$(date -u +%s)
            _work_es_display="$from -> now (Europe/Paris)"
        fi
        _work_es_gte=$(_work_es_epoch_to_iso $from_epoch)
        _work_es_lte=$(_work_es_epoch_to_iso $to_epoch)
    fi
    return 0
}

# --- Commandes publiques ---

# Requete ES generique. Usage: work_es_query [METHOD] PATH [BODY|-]
# METHOD deduit si absent: GET sans body, POST avec body. BODY "-" = stdin.
work_es_query() {
    emulate -L zsh
    _work_es_require || return 1

    local method=""
    if [[ "${1:u}" == (GET|POST|PUT|DELETE|HEAD) ]]; then
        method="${1:u}"
        shift
    fi
    local path="${1:-}" body="${2:-}"
    if [[ -z "$path" ]]; then
        _ui_msg_fail "usage: work_es_query [METHOD] PATH [BODY|-]"
        return 1
    fi
    [[ "$body" == "-" ]] && body="$(cat)"
    if [[ -z "$method" ]]; then
        [[ -n "$body" ]] && method=POST || method=GET
    fi

    local out code resp
    out=$(_work_es_curl "$method" "$path" "$body") || {
        _ui_msg_fail "Elasticsearch injoignable: $(_work_es_url)"
        return 1
    }
    code="${out%%$'\n'*}"
    resp=""
    [[ "$out" == *$'\n'* ]] && resp="${out#*$'\n'}"

    if [[ "$code" == <-> ]] && (( code >= 400 )); then
        _ui_msg_fail "HTTP $code"
        if [[ -t 1 && -n "$resp" ]]; then
            print -r -- "$resp" | jq . 2>/dev/null || print -r -- "$resp"
        elif [[ -n "$resp" ]]; then
            print -r -- "$resp"
        fi
        return 1
    fi
    if [[ -t 1 && -n "$resp" ]]; then
        print -r -- "$resp" | jq . 2>/dev/null || print -r -- "$resp"
    elif [[ -n "$resp" ]]; then
        print -r -- "$resp"
    fi
    return 0
}

# Liste des applications par volume. Usage: work_es_apps [RANGE] [--refresh]
# RANGE au format Xm/Xh/Xd (defaut 24h). Cache TTL: ZANVIL_WORK_ES_APPS_TTL (3600s).
work_es_apps() {
    emulate -L zsh
    _work_es_require || return 1

    local range="24h" refresh=false arg
    for arg in "$@"; do
        case "$arg" in
            --refresh) refresh=true ;;
            *)
                if _work_es_parse_duration "$arg" >/dev/null 2>&1; then
                    range="$arg"
                else
                    _ui_msg_fail "Plage invalide: $arg (attendu: Xm/Xh/Xd)"
                    return 1
                fi
                ;;
        esac
    done

    local ttl="${ZANVIL_WORK_ES_APPS_TTL:-3600}"
    if [[ "$refresh" == false && -f "$_WORK_ES_APPS_CACHE" ]]; then
        local cached_time cached_range age
        cached_time=$(sed -n '1p' "$_WORK_ES_APPS_CACHE")
        cached_range=$(sed -n '2p' "$_WORK_ES_APPS_CACHE")
        [[ "$cached_time" == <-> ]] && age=$(( $(date +%s) - cached_time )) || age=$ttl
        if (( age < ttl )) && [[ "$cached_range" == "$range" ]]; then
            tail -n +3 "$_WORK_ES_APPS_CACHE"
            return 0
        fi
    fi

    local resp data
    resp=$(_work_es_json POST "$(_work_es_index)/_search" '{
      "size": 0,
      "query": { "range": { "@timestamp": { "gte": "now-'"$range"'" }}},
      "aggs": { "apps": { "terms": { "field": "application", "size": 500 }}}
    }') || {
        _ui_msg_fail "Requete ES en echec: $(_work_es_url)"
        return 1
    }
    data=$(print -r -- "$resp" | jq -r '.aggregations.apps.buckets[] | "\(.key)\t\(.doc_count)"' 2>/dev/null)
    if [[ -z "$data" ]]; then
        _ui_msg_fail "Reponse ES sans agregation apps (index: $(_work_es_index))"
        return 1
    fi
    { date +%s; echo "$range"; print -r -- "$data" } > "$_WORK_ES_APPS_CACHE"
    print -r -- "$data"
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
