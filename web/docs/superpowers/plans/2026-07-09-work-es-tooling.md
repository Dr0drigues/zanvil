# Outillage Elasticsearch du module work — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter au module `work` 4 commandes ES génériques (`work_es_query`, `work_es_apps`, `work_es_count`, `work_es_tail`), un garde-fou volumétrique sur `work_fetch_logs` et un volet Elasticsearch dans `work_status`.

**Architecture:** Tout en zsh dans `modules/work/elasticsearch.zsh` (helpers privés `_work_es_*` partagés + commandes publiques). Le script bash `fetch_es_logs.sh` reste intact ; le garde-fou vit dans le wrapper zsh. Spec : `web/docs/superpowers/specs/2026-07-09-work-es-tooling-design.md`.

**Tech Stack:** zsh, curl, jq. Pas de shellspec (décision commit `8135460`) : chaque tâche se vérifie par `zsh -n` + assertions fonctionnelles hors réseau.

## Global Constraints

- Branche de travail : `feature/work-es-tooling` (existe déjà, spec commitée).
- Dépendances : curl + jq uniquement. Jamais d'appel réseau pendant une complétion.
- Ne PAS modifier : `modules/work/fetch_es_logs.sh`, `work_is_context`, le cache Nexus.
- UI : uniquement les helpers `_ui_*` de `core/ui.zsh` (`_ui_msg_fail`, `_ui_msg_warn`, `_ui_msg_info`, `_ui_section`, `_ui_separator`, variables `$_ui_green/$_ui_red/$_ui_yellow/$_ui_bold/$_ui_nc`). Jamais de `\033[...` en dur.
- Env : `ES_URL` puis `ZANVIL_WORK_ES_URL` (défaut `https://es-observability.prd.api.udb.azr.intranet`) ; `ES_USER`/`ES_PASSWORD` requis avant tout appel ; index `${ZANVIL_WORK_ES_INDEX:-es-apis-*}` ; `SSL_CERT_FILE` → `--cacert`.
- Toute fonction publique `work_*` nouvelle → `modules/work/.lazy` + complétion.
- Messages/commentaires : français sans accents dans le code (convention des fichiers du module).
- Test hors réseau : utiliser `ES_URL=https://127.0.0.1:9` (échec immédiat, pas de hang).
- Harness de test fonctionnel (réutilisé dans chaque tâche) :

```bash
# Depuis ~/.zanvil — charge ui + module dans un zsh propre puis exécute $ASSERT
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
'"$ASSERT"
```

---

### Task 1: Helpers ES de base (require, url, index, curl, json)

**Files:**
- Modify: `modules/work/elasticsearch.zsh` (ajouter les helpers après la déclaration de `_WORK_FETCH_LOGS_SCRIPT`, avant `work_fetch_logs`)

**Interfaces:**
- Consumes: `_ui_msg_fail` (core/ui.zsh), `ES_USER`/`ES_PASSWORD`/`SSL_CERT_FILE` (env)
- Produces:
  - `_work_es_url` → echo l'URL ES résolue (string, sans slash final)
  - `_work_es_index` → echo l'index (string)
  - `_work_es_require` → return 0 si curl+jq+creds OK, sinon message `_ui_msg_fail` + return 1
  - `_work_es_curl METHOD PATH [BODY] [MAX_TIME]` → stdout = `HTTP_CODE\nBODY`, return = code curl
  - `_work_es_json METHOD PATH [BODY] [MAX_TIME]` → stdout = corps seul ; return 1 si curl KO ou HTTP >= 400

- [ ] **Step 1: Écrire les helpers dans `modules/work/elasticsearch.zsh`**

Insérer après la ligne `_WORK_FETCH_LOGS_SCRIPT=...` :

```zsh
# --- Configuration ES (surchargeable via env.d/work.zsh) ---

_work_es_url() {
    echo "${ES_URL:-${ZANVIL_WORK_ES_URL:-https://es-observability.prd.api.udb.azr.intranet}}"
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
```

- [ ] **Step 2: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh`
Expected: aucune sortie, exit 0

- [ ] **Step 3: Tests fonctionnels hors réseau**

```bash
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
# 1. resolution URL: defaut puis overrides
[[ $(_work_es_url) == "https://es-observability.prd.api.udb.azr.intranet" ]] || { echo "FAIL url defaut"; exit 1 }
ZANVIL_WORK_ES_URL=https://a _work_es_url | grep -qx "https://a" || { echo "FAIL url zanvil"; exit 1 }
ES_URL=https://b ZANVIL_WORK_ES_URL=https://a _work_es_url | grep -qx "https://b" || { echo "FAIL priorite ES_URL"; exit 1 }
[[ $(_work_es_index) == "es-apis-*" ]] || { echo "FAIL index"; exit 1 }
# 2. garde creds
unset ES_USER ES_PASSWORD
_work_es_require 2>&1 | grep -q "ES_USER/ES_PASSWORD" || { echo "FAIL require"; exit 1 }
# 3. echec reseau propre et rapide
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
_work_es_json GET _cluster/health "" 2 && { echo "FAIL json aurait du echouer"; exit 1 }
echo OK'
```
Expected: `OK` (en < 3 s)

- [ ] **Step 4: Commit**

```bash
git add modules/work/elasticsearch.zsh
git commit -m "feat(work): helpers ES partages (require, curl, json)"
```

---

### Task 2: Helpers durées et dates (duplication annotée du script bash)

**Files:**
- Modify: `modules/work/elasticsearch.zsh` (après les helpers de la Task 1)

**Interfaces:**
- Consumes: rien de nouveau
- Produces:
  - `_work_es_parse_duration "30m"` → echo secondes (int), return 1 si format invalide
  - `_work_es_epoch_to_iso EPOCH` → echo `YYYY-mm-ddTHH:MM:SS.000Z`
  - `_work_es_iso_to_epoch ISO` → echo epoch (int)
  - `_work_es_paris_to_epoch "YYYY-mm-ddTHH:MM:SS"` → echo epoch UTC (DST auto)
  - `_work_es_window SINCE FROM TO` → return 1 + message si invalide ; sinon remplit les globales `_work_es_gte`, `_work_es_lte` (ISO UTC) et `_work_es_display` (libellé humain)

- [ ] **Step 1: Écrire les helpers**

Ajouter à la suite de `_work_es_json` :

```zsh
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
```

- [ ] **Step 2: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh`
Expected: exit 0

- [ ] **Step 3: Tests fonctionnels (aucun réseau)**

```bash
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
[[ $(_work_es_parse_duration 45s) == 45 ]] || { echo "FAIL 45s"; exit 1 }
[[ $(_work_es_parse_duration 30m) == 1800 ]] || { echo "FAIL 30m"; exit 1 }
[[ $(_work_es_parse_duration 2h) == 7200 ]] || { echo "FAIL 2h"; exit 1 }
[[ $(_work_es_parse_duration 7d) == 604800 ]] || { echo "FAIL 7d"; exit 1 }
_work_es_parse_duration 3x && { echo "FAIL 3x accepte"; exit 1 }
# round-trip epoch <-> iso
[[ $(_work_es_epoch_to_iso 1750000000) == "2025-06-15T15:06:40.000Z" ]] || { echo "FAIL epoch_to_iso"; exit 1 }
[[ $(_work_es_iso_to_epoch "2025-06-15T15:06:40.000Z") == 1750000000 ]] || { echo "FAIL iso_to_epoch"; exit 1 }
# DST: ete = UTC+2, hiver = UTC+1
[[ $(_work_es_paris_to_epoch "2026-07-01T12:00:00") == $(_work_es_iso_to_epoch "2026-07-01T10:00:00Z") ]] || { echo "FAIL DST ete"; exit 1 }
[[ $(_work_es_paris_to_epoch "2026-01-15T12:00:00") == $(_work_es_iso_to_epoch "2026-01-15T11:00:00Z") ]] || { echo "FAIL DST hiver"; exit 1 }
# fenetre --since / --from / erreurs
_work_es_window 1h "" "" || { echo "FAIL window since"; exit 1 }
[[ -n "$_work_es_gte" && -n "$_work_es_lte" ]] || { echo "FAIL globales vides"; exit 1 }
_work_es_window "" "2026-01-15T12:00:00" "2026-01-15T13:00:00" || { echo "FAIL window from/to"; exit 1 }
[[ "$_work_es_gte" == "2026-01-15T11:00:00.000Z" ]] || { echo "FAIL gte hiver: $_work_es_gte"; exit 1 }
_work_es_window bad "" "" 2>/dev/null && { echo "FAIL since invalide accepte"; exit 1 }
_work_es_window "" garbage "" 2>/dev/null && { echo "FAIL from invalide accepte"; exit 1 }
echo OK'
```
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add modules/work/elasticsearch.zsh
git commit -m "feat(work): helpers dates Europe/Paris et durees (port zsh du script bash)"
```

---

### Task 3: `work_es_query`

**Files:**
- Modify: `modules/work/elasticsearch.zsh` (section « Commandes publiques », avant `work_fetch_logs`)

**Interfaces:**
- Consumes: `_work_es_require`, `_work_es_curl`
- Produces: `work_es_query [METHOD] PATH [BODY|-]` → corps sur stdout (jq pretty si TTY), return 1 si HTTP >= 400 ou réseau KO

- [ ] **Step 1: Écrire la commande**

```zsh
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
        [[ -n "$resp" ]] && { print -r -- "$resp" | jq . 2>/dev/null || print -r -- "$resp" }
        return 1
    fi
    if [[ -t 1 && -n "$resp" ]]; then
        print -r -- "$resp" | jq . 2>/dev/null || print -r -- "$resp"
    elif [[ -n "$resp" ]]; then
        print -r -- "$resp"
    fi
    return 0
}
```

- [ ] **Step 2: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh`
Expected: exit 0

- [ ] **Step 3: Tests fonctionnels hors réseau**

```bash
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
# sans creds -> garde
unset ES_USER ES_PASSWORD
work_es_query _cluster/health 2>&1 | grep -q "ES_USER" || { echo "FAIL garde creds"; exit 1 }
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
# sans PATH -> usage
work_es_query 2>&1 | grep -q "usage:" || { echo "FAIL usage"; exit 1 }
# reseau KO -> message clair + rc 1, rapide
work_es_query _cluster/health 2>&1 | grep -q "injoignable" || { echo "FAIL injoignable"; exit 1 }
work_es_query _cluster/health 2>/dev/null; [[ $? == 1 ]] || { echo "FAIL rc"; exit 1 }
# body "-" lit stdin sans erreur de parsing d arguments
echo "{}" | work_es_query POST "x/_search" - 2>&1 | grep -q "injoignable" || { echo "FAIL stdin"; exit 1 }
echo OK'
```
Expected: `OK` (en < 5 s)

- [ ] **Step 4: Commit**

```bash
git add modules/work/elasticsearch.zsh
git commit -m "feat(work): work_es_query — wrapper curl ES generique"
```

---

### Task 4: `work_es_apps` (cache + .gitignore)

**Files:**
- Modify: `modules/work/elasticsearch.zsh`
- Modify: `.gitignore` (après la ligne 68 `.work_context_cache`)

**Interfaces:**
- Consumes: `_work_es_require`, `_work_es_json`, `_work_es_parse_duration`, `_work_es_index`
- Produces:
  - variable `_WORK_ES_APPS_CACHE` (chemin du cache, utilisé aussi par les complétions Task 9)
  - `work_es_apps [RANGE] [--refresh]` → lignes `app<TAB>doc_count` triées par volume décroissant
  - format cache : ligne 1 = epoch, ligne 2 = plage, lignes 3+ = données

- [ ] **Step 1: Écrire la commande**

Ajouter la variable près de `_WORK_FETCH_LOGS_SCRIPT` :

```zsh
_WORK_ES_APPS_CACHE="${ZANVIL_DIR:-$HOME/.zanvil}/.work_es_apps_cache"
```

Puis la commande après `work_es_query` :

```zsh
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
```

- [ ] **Step 2: Ajouter le cache au `.gitignore`**

Après la ligne `.work_context_cache` :

```
.work_es_apps_cache
```

- [ ] **Step 3: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh`
Expected: exit 0

- [ ] **Step 4: Tests fonctionnels (cache fabriqué, aucun réseau)**

```bash
zsh -f -c '
export ZANVIL_DIR=$(mktemp -d)
source $HOME/.zanvil/core/ui.zsh
source $HOME/.zanvil/modules/work/work_context.zsh
source $HOME/.zanvil/modules/work/elasticsearch.zsh
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
# plage invalide -> erreur
work_es_apps nope 2>&1 | grep -q "Plage invalide" || { echo "FAIL plage"; exit 1 }
# cache frais + bonne plage -> lu sans reseau
printf "%s\n24h\napp-un\t900\napp-deux\t10\n" $(date +%s) > "$_WORK_ES_APPS_CACHE"
[[ $(work_es_apps | head -1) == $'"'"'app-un\t900'"'"' ]] || { echo "FAIL lecture cache"; exit 1 }
# plage differente -> cache ignore -> tentative reseau -> echec propre
work_es_apps 7d 2>&1 | grep -q "echec" || { echo "FAIL invalidation plage"; exit 1 }
# --refresh -> cache ignore -> echec reseau propre
work_es_apps --refresh 2>&1 | grep -q "echec" || { echo "FAIL refresh"; exit 1 }
# cache perime -> tentative reseau
printf "1\n24h\nvieille-app\t1\n" > "$_WORK_ES_APPS_CACHE"
work_es_apps 2>&1 | grep -q "echec" || { echo "FAIL TTL"; exit 1 }
rm -rf "$ZANVIL_DIR"
echo OK'
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add modules/work/elasticsearch.zsh .gitignore
git commit -m "feat(work): work_es_apps — decouverte des applications avec cache TTL"
```

---

### Task 5: `work_es_count` + `_work_es_count_query`

**Files:**
- Modify: `modules/work/elasticsearch.zsh`

**Interfaces:**
- Consumes: `_work_es_require`, `_work_es_json`, `_work_es_window` (globales `_work_es_gte/_work_es_lte/_work_es_display`), `_work_es_iso_to_epoch`, `_ui_section`
- Produces:
  - `_work_es_count_query APP GTE LTE [SEARCH]` → JSON ES brut (total + aggs min_ts/max_ts) sur stdout, return 1 si échec — **réutilisé par le garde-fou (Task 6)**
  - `work_es_count --app APP [--since X | --from D [--to D]] [--search TEXT]` → affichage `_ui_section`

- [ ] **Step 1: Écrire les fonctions**

```zsh
# Requete de comptage (size 0 + track_total_hits + aggs min/max sur @timestamp).
# Usage: _work_es_count_query APP GTE LTE [SEARCH]. Sortie: JSON ES brut.
_work_es_count_query() {
    local app=$1 gte=$2 lte=$3 search="${4:-}"
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
        { \"term\": { \"application\": \"$app\" }},
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
            --app)    app="${2:-}";    shift 2 ;;
            --since)  since="${2:-}";  shift 2 ;;
            --from)   from="${2:-}";   shift 2 ;;
            --to)     to="${2:-}";     shift 2 ;;
            --search) search="${2:-}"; shift 2 ;;
            *) _ui_msg_fail "Option inconnue: $1"; return 1 ;;
        esac
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
```

- [ ] **Step 2: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh`
Expected: exit 0

- [ ] **Step 3: Tests fonctionnels hors réseau**

```bash
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
work_es_count 2>&1 | grep -q "usage:" || { echo "FAIL app obligatoire"; exit 1 }
work_es_count --app a --since 1h --from x 2>&1 | grep -q "incompatible" || { echo "FAIL exclusivite"; exit 1 }
work_es_count --app a 2>&1 | grep -q "fournir" || { echo "FAIL plage requise"; exit 1 }
work_es_count --app a --since bad 2>&1 | grep -q -- "--since invalide" || { echo "FAIL since invalide"; exit 1 }
work_es_count --app a --since 1h 2>&1 | grep -q "echec" || { echo "FAIL echec reseau"; exit 1 }
echo OK'
```
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add modules/work/elasticsearch.zsh
git commit -m "feat(work): work_es_count — comptage pre-vol sans scroll"
```

---

### Task 6: Garde-fou volumétrique dans `work_fetch_logs`

**Files:**
- Modify: `modules/work/elasticsearch.zsh` (remplacer le corps de `work_fetch_logs`)

**Interfaces:**
- Consumes: `_work_es_window`, `_work_es_count_query`, `_ui_msg_warn`
- Produces: `work_fetch_logs [--yes] <options du script>` — comportement identique, plus confirmation si total > `ZANVIL_WORK_ES_MAX_DOCS` (défaut 100000). Fail-open si le comptage échoue. `fetch_es_logs.sh` n'est PAS modifié.

- [ ] **Step 1: Remplacer `work_fetch_logs`**

Le corps actuel (vérification script exécutable + creds + délégation) devient :

```zsh
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
    local skip_guard=false app="" since="" from="" to="" search=""
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
        if _work_es_window "$since" "$from" "$to" 2>/dev/null; then
            local resp
            resp=$(_work_es_count_query "$app" "$_work_es_gte" "$_work_es_lte" "$search" 2>/dev/null) \
                && total=$(print -r -- "$resp" | jq -r '.hits.total.value // .hits.total // empty' 2>/dev/null)
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
```

- [ ] **Step 2: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh`
Expected: exit 0

- [ ] **Step 3: Tests fonctionnels hors réseau**

```bash
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
# --help passe au script sans garde (pas de --app) et rend son usage
work_fetch_logs --help | grep -q -- "--search" || { echo "FAIL help"; exit 1 }
# comptage KO -> fail-open: warning puis le script prend la main (erreur reseau du script attendue)
out=$(work_fetch_logs --app a --since 1h 2>&1)
echo "$out" | grep -q "Comptage prealable impossible" || { echo "FAIL fail-open"; exit 1 }
# --yes saute le comptage: aucun warning de comptage
out=$(work_fetch_logs --yes --app a --since 1h 2>&1)
echo "$out" | grep -q "Comptage prealable" && { echo "FAIL --yes"; exit 1 }
# --yes n est PAS transmis au script (sinon "Option inconnue")
echo "$out" | grep -q "Option inconnue" && { echo "FAIL --yes transmis"; exit 1 }
echo OK'
```
Expected: `OK`

Note : le déclenchement réel de la confirmation (total > seuil) n'est testable qu'en contexte work — à faire manuellement avec `ZANVIL_WORK_ES_MAX_DOCS=1 work_fetch_logs --app <app> --since 5m`.

- [ ] **Step 4: Commit**

```bash
git add modules/work/elasticsearch.zsh
git commit -m "feat(work): garde-fou volumetrique dans work_fetch_logs (--yes)"
```

---

### Task 7: Volet Elasticsearch dans `work_status`

**Files:**
- Modify: `modules/work/elasticsearch.zsh` (fonction `_work_es_status_section`)
- Modify: `modules/work/work_context.zsh` (fin de `work_status`, après la section Modules, ligne ~205)

**Interfaces:**
- Consumes: `work_is_context` (work_context.zsh), `_work_es_json`, `_ui_section`, `_ui_separator`, `$_ui_bold/$_ui_green/$_ui_yellow/$_ui_red/$_ui_nc`
- Produces: `_work_es_status_section` → bloc d'affichage, toujours return 0 (jamais bloquant)

- [ ] **Step 1: Écrire la section dans `elasticsearch.zsh`**

```zsh
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
```

- [ ] **Step 2: Brancher dans `work_status` (work_context.zsh)**

À la fin de `work_status`, après la ligne `_ui_section "Mise" "Non installe"` et son `fi` :

```zsh
    # Volet Elasticsearch (defini dans elasticsearch.zsh)
    (( $+functions[_work_es_status_section] )) && _work_es_status_section
```

- [ ] **Step 3: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh && zsh -n modules/work/work_context.zsh`
Expected: exit 0

- [ ] **Step 4: Test fonctionnel hors réseau (dégradation silencieuse)**

```bash
zsh -f -c '
export ZANVIL_DIR=$(mktemp -d)
source $HOME/.zanvil/core/ui.zsh
source $HOME/.zanvil/modules/work/work_context.zsh
source $HOME/.zanvil/modules/work/elasticsearch.zsh
# hors contexte (pas de nexus URL) -> "hors reseau", rc 0, pas de hang
out=$(_work_es_status_section) || { echo "FAIL rc"; exit 1 }
echo "$out" | grep -q "hors reseau" || { echo "FAIL hors reseau"; exit 1 }
# work_status complet ne plante pas et contient le volet
work_status | grep -q "Elasticsearch" || { echo "FAIL work_status"; exit 1 }
rm -rf "$ZANVIL_DIR"
echo OK'
```
Expected: `OK` (< 5 s)

- [ ] **Step 5: Commit**

```bash
git add modules/work/elasticsearch.zsh modules/work/work_context.zsh
git commit -m "feat(work): volet Elasticsearch dans work_status"
```

---

### Task 8: `work_es_tail`

**Files:**
- Modify: `modules/work/elasticsearch.zsh`

**Interfaces:**
- Consumes: `_work_es_require`, `_work_es_json`, `_work_es_index`, `_ui_msg_info`, `_ui_msg_warn`
- Produces: `work_es_tail --app APP [--search TEXT] [--interval N]` — boucle infinie (Ctrl-C pour sortir), aucun fichier temporaire

- [ ] **Step 1: Écrire la commande**

```zsh
# Suivi quasi temps reel. Usage: work_es_tail --app APP [--search TEXT] [--interval N]
# Poll toutes les N secondes (defaut 5, min 2) via search_after sur @timestamp asc.
# Aucun fichier temporaire: Ctrl-C interrompt proprement la boucle.
work_es_tail() {
    emulate -L zsh
    _work_es_require || return 1

    local app="" search="" interval=5
    while (( $# > 0 )); do
        case "$1" in
            --app)      app="${2:-}";      shift 2 ;;
            --search)   search="${2:-}";   shift 2 ;;
            --interval) interval="${2:-}"; shift 2 ;;
            *) _ui_msg_fail "Option inconnue: $1"; return 1 ;;
        esac
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
            { \"term\": { \"application\": \"$app\" }}$search_clause
          ]}}
        }" "$interval") || {
            _ui_msg_warn "ES injoignable — nouvel essai dans ${interval}s"
            sleep "$interval"
            continue
        }

        count=$(print -r -- "$resp" | jq -r '.hits.hits | length' 2>/dev/null)
        if [[ "$count" == <-> ]] && (( count > 0 )); then
            width=${COLUMNS:-120}
            print -r -- "$resp" | jq -r '.hits.hits[]._source
                | "\(.["@timestamp"] // "" | .[11:19]) [\(.level // "-")] \(.message // "" | gsub("[\r\n]+"; " "))"' \
                2>/dev/null | cut -c1-$width
            last_sort=$(print -r -- "$resp" | jq -r '.hits.hits[-1].sort[0]')
            if (( count >= 1000 )); then
                _ui_msg_warn "Filtre trop large (>= 1000 docs/iteration) — saut a now"
                last_sort=$(( $(date -u +%s) * 1000 ))
            fi
        fi
        sleep "$interval"
    done
}
```

- [ ] **Step 2: Vérifier la syntaxe**

Run: `zsh -n modules/work/elasticsearch.zsh`
Expected: exit 0

- [ ] **Step 3: Tests fonctionnels hors réseau (validation d'arguments + boucle bornée)**

```bash
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
work_es_tail 2>&1 | grep -q "usage:" || { echo "FAIL app obligatoire"; exit 1 }
work_es_tail --app a --interval abc 2>&1 | grep -q "entier" || { echo "FAIL interval"; exit 1 }
echo OK'
# La boucle elle-meme: lancer 7s puis tuer — doit afficher des retries, pas de stacktrace
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
work_es_tail --app a --interval 2' > /tmp/work-es-tail-test.log 2>&1 &
TAIL_PID=$!
sleep 7
kill $TAIL_PID 2>/dev/null
head -5 /tmp/work-es-tail-test.log
rm -f /tmp/work-es-tail-test.log
```
Expected: premier bloc `OK` ; le log du second bloc affiche `Tail de a` puis des lignes `ES injoignable — nouvel essai dans 2s`, sans erreur zsh brute.

- [ ] **Step 4: Commit**

```bash
git add modules/work/elasticsearch.zsh
git commit -m "feat(work): work_es_tail — suivi quasi temps reel par search_after"
```

---

### Task 9: Complétions, `.lazy`, exemple env.d

**Files:**
- Modify: `modules/work/completions.zsh`
- Modify: `modules/work/.lazy`
- Modify: `examples/env.d/work.zsh`

**Interfaces:**
- Consumes: format du cache apps (Task 4 : lignes 3+ = `app<TAB>count`)
- Produces: complétions `work_es_query`, `work_es_apps`, `work_es_count`, `work_es_tail` ; `--app` dynamique + `--yes` sur `work_fetch_logs`

- [ ] **Step 1: Réécrire `modules/work/completions.zsh`**

Contenu complet du fichier :

```zsh
# ==============================================================================
# Work Completions
# ==============================================================================

(( $+functions[compdef] )) || return 0

# Applications depuis le cache de work_es_apps — lecture fichier uniquement,
# JAMAIS d'appel reseau pendant la completion. Cache perime accepte.
_work_es_cached_apps() {
    local cache="${ZANVIL_DIR:-$HOME/.zanvil}/.work_es_apps_cache"
    if [[ -f "$cache" ]]; then
        local -a apps
        apps=(${(f)"$(tail -n +3 "$cache" 2>/dev/null | cut -f1)"})
        if (( ${#apps} )); then
            _describe -t applications 'application' apps
            return
        fi
    fi
    _message 'application (lancer work_es_apps pour alimenter la completion)'
}

_work_fetch_logs() {
    _arguments \
        '--app[Application a interroger]:app:_work_es_cached_apps' \
        '--since[Plage relative: Xs/Xm/Xh/Xd (ex: 30s, 2h, 7d)]:duration:' \
        '--from[Debut, heure locale Europe/Paris avec DST auto (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--to[Fin, heure locale Europe/Paris avec DST auto (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--search[Recherche TEXT dans .message, restreint la fenetre aux matches]:text:' \
        '--margin[Padding autour des matches --search (defaut: 1m)]:duration:' \
        '--target-dir[Repertoire de sortie]:directory:_directories' \
        '--format[Format de sortie]:format:(ndjson json text)' \
        '--yes[Passer le garde-fou volumetrique]' \
        '(-h --help)'{-h,--help}'[Afficher l aide]'
}
compdef _work_fetch_logs work_fetch_logs

_work_es_query() {
    _arguments \
        '1:methode ou chemin:(GET POST PUT DELETE HEAD)' \
        '2:chemin ES (ex es-apis-*/_search):' \
        '3:body JSON ou - pour stdin:'
}
compdef _work_es_query work_es_query

_work_es_apps() {
    _arguments \
        '--refresh[Forcer le rafraichissement du cache]' \
        '1:plage Xm/Xh/Xd (defaut 24h):(1h 6h 24h 7d)'
}
compdef _work_es_apps work_es_apps

_work_es_count() {
    _arguments \
        '--app[Application a interroger]:app:_work_es_cached_apps' \
        '--since[Plage relative: Xs/Xm/Xh/Xd]:duration:' \
        '--from[Debut, heure locale Europe/Paris avec DST auto]:date:' \
        '--to[Fin, heure locale Europe/Paris avec DST auto]:date:' \
        '--search[Phrase a chercher dans .message]:text:'
}
compdef _work_es_count work_es_count

_work_es_tail() {
    _arguments \
        '--app[Application a suivre]:app:_work_es_cached_apps' \
        '--search[Phrase a chercher dans .message]:text:' \
        '--interval[Intervalle de poll en secondes (defaut 5, min 2)]:secondes:(2 5 10 30)'
}
compdef _work_es_tail work_es_tail
```

- [ ] **Step 2: Mettre à jour `modules/work/.lazy`**

Ajouter à la fin (contenu final du fichier) :

```
work_is_context
work_refresh
work_init
work_status
work_fetch_logs
work_es_query
work_es_apps
work_es_count
work_es_tail
```

- [ ] **Step 3: Documenter les variables dans `examples/env.d/work.zsh`**

Remplacer le bloc « Elasticsearch observability » par :

```zsh
# Elasticsearch observability (work_fetch_logs, work_es_query/apps/count/tail)
export ZANVIL_WORK_ES_URL="${ZANVIL_WORK_ES_URL:-}"
export ZANVIL_WORK_ES_INDEX="${ZANVIL_WORK_ES_INDEX:-es-apis-*}"
export ZANVIL_WORK_ES_APPS_TTL="${ZANVIL_WORK_ES_APPS_TTL:-3600}"   # TTL cache work_es_apps (s)
export ZANVIL_WORK_ES_MAX_DOCS="${ZANVIL_WORK_ES_MAX_DOCS:-100000}" # seuil garde-fou work_fetch_logs
export ES_USER="${ES_USER:-}"
# ES_PASSWORD a definir dans ~/.secrets ou via SOPS, jamais ici en clair
# export ES_PASSWORD=""
```

- [ ] **Step 4: Vérifier syntaxe + chargement complétions**

```bash
zsh -n modules/work/completions.zsh && zsh -n examples/env.d/work.zsh
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
autoload -Uz compinit && compinit -C -d /tmp/zcompdump-test-$$
source $ZANVIL_DIR/modules/work/completions.zsh || { echo "ERREUR chargement"; exit 1 }
for f in _work_fetch_logs _work_es_query _work_es_apps _work_es_count _work_es_tail _work_es_cached_apps; do
    (( $+functions[$f] )) || { echo "FAIL $f absent"; exit 1 }
done
for c in work_fetch_logs work_es_query work_es_apps work_es_count work_es_tail; do
    [[ -n "$_comps[$c]" ]] || { echo "FAIL compdef $c"; exit 1 }
done
rm -f /tmp/zcompdump-test-$$
echo OK'
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add modules/work/completions.zsh modules/work/.lazy examples/env.d/work.zsh
git commit -m "feat(work): completions ES + lazy loading + variables documentees"
```

---

### Task 10: Vérification finale intégrée

**Files:** aucun nouveau — validation de l'ensemble.

- [ ] **Step 1: Syntaxe de tous les fichiers modifiés**

```bash
for f in modules/work/elasticsearch.zsh modules/work/work_context.zsh \
         modules/work/completions.zsh examples/env.d/work.zsh; do
    zsh -n "$f" || echo "FAIL $f"
done
```
Expected: aucune sortie

- [ ] **Step 2: `.lazy` — les 4 nouvelles fonctions, rien d'autre**

```bash
diff <(sort modules/work/.lazy) <(printf '%s\n' work_is_context work_refresh work_init work_status work_fetch_logs work_es_query work_es_apps work_es_count work_es_tail | sort)
```
Expected: aucune différence

- [ ] **Step 3: Chargement complet du module en zsh propre (via init.zsh comme le loader)**

```bash
zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/init.zsh
for fn in work_es_query work_es_apps work_es_count work_es_tail work_fetch_logs; do
    (( $+functions[$fn] )) || { echo "FAIL $fn non defini"; exit 1 }
done
echo OK'
```
Expected: `OK`

- [ ] **Step 4: Hors réseau — aucune commande ne hang**

```bash
time zsh -f -c '
export ZANVIL_DIR=$HOME/.zanvil
source $ZANVIL_DIR/core/ui.zsh
source $ZANVIL_DIR/modules/work/work_context.zsh
source $ZANVIL_DIR/modules/work/elasticsearch.zsh
export ES_USER=x ES_PASSWORD=y ES_URL=https://127.0.0.1:9
work_es_query _cluster/health >/dev/null 2>&1
work_es_apps --refresh >/dev/null 2>&1
work_es_count --app a --since 1h >/dev/null 2>&1
_work_es_status_section >/dev/null 2>&1
exit 0'
```
Expected: total < 10 s, aucun message d'erreur zsh brut

- [ ] **Step 5: Marquer le spec comme implémenté et commit final**

Dans `web/docs/superpowers/specs/2026-07-09-work-es-tooling-design.md`, remplacer
`**Statut** : Validé (en attente d'implémentation)` par `**Statut** : Implémenté`.

```bash
git add -f web/docs/superpowers/specs/2026-07-09-work-es-tooling-design.md
git commit -m "docs(specs): work-es-tooling implemente"
```

**Rappel pour le résumé final :** les tests réseau réels (agrégation apps, comptage, tail, volet status en green) ne sont possibles qu'en contexte work — à valider manuellement : `work_es_apps`, `work_es_count --app <app> --since 1h`, `work_es_tail --app <app>`, `work_status`, et le garde-fou avec `ZANVIL_WORK_ES_MAX_DOCS=1`.
