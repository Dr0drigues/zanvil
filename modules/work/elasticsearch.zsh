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
    local method=$1 es_path=$2 body="${3:-}" max_time="${4:-30}"
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
    out=$(command curl "${opts[@]}" -w $'\n%{http_code}' "$(_work_es_url)/$es_path" 2>/dev/null)
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
#
# Il n y a plus deux versions a synchroniser. Ce bloc et son homologue de
# modules/work/fetch_es_logs.sh deleguent au meme code — `zanvil convert` et
# `zanvil es window` — donc le calcul n existe qu une fois, en Rust, avec deux appelants.
#
# Ce qui restait a maintenir en double : trois conversions ecrites chacune deux fois, une
# en zsh avec $match et une en bash avec BASH_REMATCH, chacune avec son propre
# embranchement GNU/BSD. Les deux replis les gardent, parce qu un repli doit rester
# complet, mais ils ne sont plus le chemin emprunte quand le binaire est installe.
#
# `_work_es_parse_duration` ne delegue pas : c est une regex, sans appel a `date`, donc
# elle n a jamais fait partie de la dette que ce chantier paie.

typeset -g _WORK_ES_DATE_FLAVOR=""
# Detecteur de variante `date`, garde pour le seul repli.
#
# Il existait parce que `date -d` et `date -j -f` ne coexistent pas, et le spec
# zsh-ou-rust le cite comme la dette qui justifie son critere de migration. Les trois
# fonctions ci-dessous ne l appellent plus quand le CLI est la : chrono ne depend
# d aucun binaire, donc il n y a plus deux chemins a maintenir ni de variante a deviner.
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
    if command -v zanvil &>/dev/null; then
        zanvil convert --from-epoch "$epoch"; return $?
    fi
    if [[ $(_work_es_date_flavor) == gnu ]]; then
        date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
    else
        date -u -j -f "%s" "$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
    fi
}

# ISO UTC ("2026-05-30T14:00:00.000Z" ou sans ms) -> epoch
_work_es_iso_to_epoch() {
    local ts=$1
    if command -v zanvil &>/dev/null; then
        zanvil convert --from-iso "$ts"; return $?
    fi
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
    if command -v zanvil &>/dev/null; then
        zanvil convert --from-paris "$dt"; return $?
    fi
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

    # Le calcul delegue au CLI, l affectation reste ici : remplir trois globales EST un
    # effet shell, et un binaire ne modifie pas le shell qui l appelle. C est la ligne
    # de partage du spec, appliquee au milieu d une fonction plutot qu a son entree.
    #
    # La sortie est LUE et non evaluee. Un format evaluable — `_work_es_gte='…'` passe a
    # `eval`, comme le font `starship init` ou `mise activate` — serait plus court d une
    # ligne et executerait ce que l utilisateur a ecrit dans --from, puisque le libelle
    # le reprend tel quel.
    #
    # Divergence connue et assumee : sur une heure locale qui n existe pas — 02:30 la
    # nuit ou les pendules avancent — le CLI refuse, ce repli decale silencieusement
    # d une heure. Le refus est le bon comportement ; le repli garde le sien parce que
    # le detecter en zsh demanderait deux appels a `date` de plus, dans le code meme
    # dont ce lot retire la dependance.
    if command -v zanvil &>/dev/null; then
        # Un tableau, et non `${since:+--since "$since"}` : en zsh cette forme rend un
        # mot unique, donc le CLI recevait « --from 2026-03-30T12:00:00 » comme un seul
        # argument et clap le refusait.
        local -a _w_args=(es window)
        [[ -n "$since" ]] && _w_args+=(--since "$since")
        [[ -n "$from" ]]  && _w_args+=(--from "$from")
        [[ -n "$to" ]]    && _w_args+=(--to "$to")

        local _w_out _w_rc
        _w_out=$(zanvil "${_w_args[@]}" 2>&1)
        _w_rc=$?
        if (( _w_rc != 0 )); then
            _ui_msg_fail "$_w_out"
            return 1
        fi
        local _k _v
        while IFS='=' read -r _k _v; do
            case "$_k" in
                gte)     _work_es_gte="$_v" ;;
                lte)     _work_es_lte="$_v" ;;
                display) _work_es_display="$_v" ;;
            esac
        done <<< "$_w_out"
        return 0
    fi

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
    local es_path="${1:-}" body="${2:-}"
    if [[ -z "$es_path" ]]; then
        _ui_msg_fail "usage: work_es_query [METHOD] PATH [BODY|-]"
        return 1
    fi
    [[ "$body" == "-" ]] && body="$(cat)"
    if [[ -z "$method" ]]; then
        [[ -n "$body" ]] && method=POST || method=GET
    fi

    local out code resp
    out=$(_work_es_curl "$method" "$es_path" "$body") || {
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
# RANGE au format Xs/Xm/Xh/Xd (defaut 24h). Cache TTL: ZANVIL_WORK_ES_APPS_TTL (3600s).
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
                    _ui_msg_fail "Plage invalide: $arg (attendu: Xs/Xm/Xh/Xd)"
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

# Requete de comptage (size 0 + track_total_hits + aggs min/max sur @timestamp).
# Usage: _work_es_count_query APP GTE LTE [SEARCH]. Sortie: JSON ES brut.
_work_es_count_query() {
    local app=$1 gte=$2 lte=$3 search="${4:-}"
    local app_esc="${app//\\/\\\\}"
    app_esc="${app_esc//\"/\\\"}"
    local search_clause=""
    if [[ -n "$search" ]]; then
        local esc="${search//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        search_clause=", { \"match_phrase\": { \"message\": \"$esc\" }}"
    fi
    _work_es_json POST "$(_work_es_index)/_search" "{
      \"size\": 0,
      \"track_total_hits\": true,
      \"query\": { \"bool\": { \"must\": [
        { \"term\": { \"application\": \"$app_esc\" }},
        { \"range\": { \"@timestamp\": { \"gte\": \"$gte\", \"lte\": \"$lte\" }}}$search_clause
      ]}},
      \"aggs\": {
        \"min_ts\": { \"min\": { \"field\": \"@timestamp\" }},
        \"max_ts\": { \"max\": { \"field\": \"@timestamp\" }}
      }
    }"
}

# Pre-vol avant export: total + fenetre reelle des matches, sans scroll ni fichier.
# Usage: work_es_count --app APP [--since X | --from D [--to D]] [--search TEXT]
work_es_count() {
    emulate -L zsh
    _work_es_require || return 1

    local app="" since="" from="" to="" search=""
    while (( $# > 0 )); do
        case "$1" in
            --app)    app="${2:-}" ;;
            --since)  since="${2:-}" ;;
            --from)   from="${2:-}" ;;
            --to)     to="${2:-}" ;;
            --search) search="${2:-}" ;;
            *) _ui_msg_fail "Option inconnue: $1"; return 1 ;;
        esac
        if (( $# >= 2 )); then shift 2; else shift; fi
    done
    if [[ -z "$app" ]]; then
        _ui_msg_fail "usage: work_es_count --app APP [--since X | --from D [--to D]] [--search TEXT]"
        return 1
    fi
    if [[ -n "$since" && ( -n "$from" || -n "$to" ) ]]; then
        _ui_msg_fail "--since est incompatible avec --from/--to"
        return 1
    fi
    if [[ -z "$since" && -z "$from" ]]; then
        _ui_msg_fail "fournir --since ou --from (--to optionnel)"
        return 1
    fi
    _work_es_window "$since" "$from" "$to" || return 1

    local resp
    resp=$(_work_es_count_query "$app" "$_work_es_gte" "$_work_es_lte" "$search") || {
        _ui_msg_fail "Requete ES en echec: $(_work_es_url)"
        return 1
    }
    local total min_iso max_iso
    total=$(print -r -- "$resp" | jq -r '.hits.total.value // .hits.total // 0')
    min_iso=$(print -r -- "$resp" | jq -r '.aggregations.min_ts.value_as_string // empty')
    max_iso=$(print -r -- "$resp" | jq -r '.aggregations.max_ts.value_as_string // empty')

    _ui_section "App" "$app"
    [[ -n "$search" ]] && _ui_section "Recherche" "$search"
    _ui_section "Plage" "$_work_es_display"
    _ui_section "Total" "$total documents"
    if [[ -n "$min_iso" && -n "$max_iso" ]]; then
        local dur=$(( $(_work_es_iso_to_epoch "$max_iso") - $(_work_es_iso_to_epoch "$min_iso") ))
        _ui_section "Fenetre" "$min_iso -> $max_iso"
        _ui_section "Duree" "${dur}s"
    fi
    return 0
}

# Volet Elasticsearch de work_status. Toujours non bloquant:
# hors contexte work -> "hors reseau", echec requete -> "injoignable"/"n/a".
_work_es_status_section() {
    echo ""
    echo -e "${_ui_bold}Elasticsearch${_ui_nc}"
    _ui_separator 44

    if ! work_is_context; then
        _ui_section "Statut" "${_ui_yellow}hors reseau${_ui_nc}"
        return 0
    fi

    if [[ -n "${ES_USER:-}" && -n "${ES_PASSWORD:-}" ]]; then
        _ui_section "Credentials" "${_ui_green}definis${_ui_nc}"
    else
        _ui_section "Credentials" "${_ui_red}absents (env.d/work.zsh)${_ui_nc}"
        return 0
    fi
    if ! command -v jq &>/dev/null; then
        _ui_section "Cluster" "${_ui_yellow}jq absent${_ui_nc}"
        return 0
    fi

    local health status
    health=$(_work_es_json GET "_cluster/health" "" 2)
    if [[ -n "$health" ]]; then
        status=$(print -r -- "$health" | jq -r '.status // "inconnu"')
        case "$status" in
            green)  _ui_section "Cluster" "${_ui_green}green${_ui_nc}" ;;
            yellow) _ui_section "Cluster" "${_ui_yellow}yellow${_ui_nc}" ;;
            red)    _ui_section "Cluster" "${_ui_red}red${_ui_nc}" ;;
            *)      _ui_section "Cluster" "$status" ;;
        esac
    else
        _ui_section "Cluster" "${_ui_red}injoignable${_ui_nc}"
        return 0
    fi

    local resp oldest
    resp=$(_work_es_json POST "$(_work_es_index)/_search" \
        '{"size":0,"aggs":{"oldest":{"min":{"field":"@timestamp"}}}}' 5)
    oldest=$(print -r -- "$resp" | jq -r '.aggregations.oldest.value_as_string // empty' 2>/dev/null)
    _ui_section "Retention" "${oldest:-n/a}"
    return 0
}

# Suivi quasi temps reel. Usage: work_es_tail --app APP [--search TEXT] [--interval N]
# Poll toutes les N secondes (defaut 5, min 2) via search_after sur @timestamp asc.
# Aucun fichier temporaire: Ctrl-C interrompt proprement la boucle.
work_es_tail() {
    emulate -L zsh
    _work_es_require || return 1

    local app="" search="" interval=5
    while (( $# > 0 )); do
        case "$1" in
            --app)      app="${2:-}" ;;
            --search)   search="${2:-}" ;;
            --interval) interval="${2:-}" ;;
            *) _ui_msg_fail "Option inconnue: $1"; return 1 ;;
        esac
        if (( $# >= 2 )); then shift 2; else shift; fi
    done
    if [[ -z "$app" ]]; then
        _ui_msg_fail "usage: work_es_tail --app APP [--search TEXT] [--interval N]"
        return 1
    fi
    if [[ ! "$interval" == <-> ]]; then
        _ui_msg_fail "--interval doit etre un entier (secondes)"
        return 1
    fi
    (( interval < 2 )) && interval=2

    local search_clause=""
    if [[ -n "$search" ]]; then
        local esc="${search//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        search_clause=", { \"match_phrase\": { \"message\": \"$esc\" }}"
    fi

    local app_esc="${app//\\/\\\\}"
    app_esc="${app_esc//\"/\\\"}"

    # Demarrage a now-1m (sort value = epoch millis)
    local last_sort=$(( ($(date -u +%s) - 60) * 1000 ))
    _ui_msg_info "Tail de $app — interval ${interval}s, Ctrl-C pour quitter"

    local resp count width
    while true; do
        resp=$(_work_es_json POST "$(_work_es_index)/_search" "{
          \"size\": 1000,
          \"sort\": [{\"@timestamp\": \"asc\"}],
          \"search_after\": [$last_sort],
          \"query\": { \"bool\": { \"must\": [
            { \"term\": { \"application\": \"$app_esc\" }}$search_clause
          ]}}
        }" "$interval") || {
            _ui_msg_warn "ES injoignable — nouvel essai dans ${interval}s"
            sleep "$interval"
            continue
        }

        count=$(print -r -- "$resp" | jq -r '.hits.hits | length' 2>/dev/null)
        if [[ "$count" == <-> ]] && (( count > 0 )); then
            width=${COLUMNS:-120}
            [[ "$width" == <-> ]] && (( width >= 1 )) || width=120
            print -r -- "$resp" | jq -r '.hits.hits[]._source
                | "\(.["@timestamp"] // "" | .[11:19]) [\(.level // "-")] \(.message // "" | gsub("[\r\n]+"; " "))"' \
                2>/dev/null | cut -c1-$width
            last_sort=$(print -r -- "$resp" | jq -r '.hits.hits[-1].sort[0]' 2>/dev/null)
            [[ "$last_sort" == <-> ]] || last_sort=$(( $(date -u +%s) * 1000 ))
            if (( count >= 1000 )); then
                _ui_msg_warn "Filtre trop large (>= 1000 docs/iteration) — saut a now"
                last_sort=$(( $(date -u +%s) * 1000 ))
            fi
        fi
        sleep "$interval"
    done
}

work_fetch_logs() {
    emulate -L zsh
    if [[ ! -x "$_WORK_FETCH_LOGS_SCRIPT" ]]; then
        _ui_msg_fail "Script introuvable ou non executable: $_WORK_FETCH_LOGS_SCRIPT"
        return 1
    fi
    if [[ -z "${ES_USER:-}" || -z "${ES_PASSWORD:-}" ]]; then
        _ui_msg_fail "ES_USER/ES_PASSWORD non definis (voir env.d/work.zsh)"
        return 1
    fi

    # Extraction de --yes + capture des options utiles au comptage.
    # Tout le reste part tel quel au script (qui fait sa propre validation).
    local -a pass_args
    local skip_guard=false app="" since="" from="" to="" search="" margin=""
    while (( $# > 0 )); do
        case "$1" in
            --yes) skip_guard=true; shift ;;
            --app|--since|--from|--to|--search|--margin|--target-dir|--format)
                case "$1" in
                    --app)    app="${2:-}" ;;
                    --since)  since="${2:-}" ;;
                    --from)   from="${2:-}" ;;
                    --to)     to="${2:-}" ;;
                    --search) search="${2:-}" ;;
                    --margin) margin="${2:-}" ;;
                esac
                pass_args+=("$1" "${2:-}")
                if (( $# >= 2 )); then shift 2; else shift; fi
                ;;
            *) pass_args+=("$1"); shift ;;
        esac
    done

    # Garde-fou volumetrique (fail-open: ne bloque jamais plus que le script)
    if [[ "$skip_guard" == false && -n "$app" ]] && [[ -n "$since" || -n "$from" ]] \
        && command -v jq &>/dev/null; then
        local max_docs="${ZANVIL_WORK_ES_MAX_DOCS:-100000}"
        local total=""
        if _work_es_window "$since" "$from" "$to" >/dev/null 2>&1; then
            local resp
            resp=$(_work_es_count_query "$app" "$_work_es_gte" "$_work_es_lte" "$search" 2>/dev/null) \
                && total=$(print -r -- "$resp" | jq -r '.hits.total.value // .hits.total // empty' 2>/dev/null)
            # Avec --search, le script exporte la fenetre [min,max] +/- margin des matches,
            # pas les seuls matches : re-compter sans clause search sur la fenetre elargie.
            if [[ -n "$search" && "$total" == <-> ]] && (( total > 0 )); then
                local min_iso max_iso margin_sec gte2 lte2
                min_iso=$(print -r -- "$resp" | jq -r '.aggregations.min_ts.value_as_string // empty' 2>/dev/null)
                max_iso=$(print -r -- "$resp" | jq -r '.aggregations.max_ts.value_as_string // empty' 2>/dev/null)
                margin_sec=$(_work_es_parse_duration "${margin:-1m}" 2>/dev/null) || margin_sec=60
                if [[ -n "$min_iso" && -n "$max_iso" ]]; then
                    gte2=$(_work_es_epoch_to_iso $(( $(_work_es_iso_to_epoch "$min_iso") - margin_sec )))
                    lte2=$(_work_es_epoch_to_iso $(( $(_work_es_iso_to_epoch "$max_iso") + margin_sec )))
                    resp=$(_work_es_count_query "$app" "$gte2" "$lte2" "" 2>/dev/null) \
                        && total=$(print -r -- "$resp" | jq -r '.hits.total.value // .hits.total // empty' 2>/dev/null)
                fi
            fi
        fi
        if [[ "$total" == <-> ]] && (( total > max_docs )); then
            _ui_msg_warn "Volume estime: $total documents (seuil: $max_docs)"
            if ! read -q "?Continuer l'export ? [y/N] "; then
                echo ""
                return 1
            fi
            echo ""
        elif [[ ! "$total" == <-> ]]; then
            _ui_msg_warn "Comptage prealable impossible — export lance sans garde-fou (--yes pour passer ce controle)"
        fi
    fi

    "$_WORK_FETCH_LOGS_SCRIPT" "${pass_args[@]}"
}
