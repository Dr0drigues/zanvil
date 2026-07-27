#!/usr/bin/env bash
# Provenance : la source de vérité de ce script est le projet ~/work/misc/analysis-tools
# (en cours de création, il reprendra ce script comme fondation).
# Toute évolution doit se faire là-bas puis être resynchronisée ici.
set -uo pipefail

usage() {
  cat << EOF
  usage: $0 --app APP [--since DURATION | --from FROM_DATE [--to TO_DATE]] [options]

  Exporte les logs Elasticsearch pour l'application donnée.

  OPTIONS:
    --app         APP          Application à interroger (ex: bff-frontcommerce)
    --since       DURATION     Plage relative: Xs, Xm, Xh, Xd (ex: 30m, 2h, 7d)
    --from        FROM_DATE    Début de plage (heure locale Europe/Paris, DST auto)
    --to          TO_DATE      Fin de plage (heure locale Europe/Paris, défaut: now)
    --search      TEXT         Cherche TEXT dans .message ; restreint l'export à
                               la fenêtre [min, max] des matches (étendue par --margin)
    --margin      DURATION     Padding autour des matches --search (défaut: 1m)
    --target-dir  DIR          Répertoire de sortie (défaut: \$SCRIPT_DIR/logs/\$APP)
    --format      FORMAT       Format de sortie: ndjson (défaut), json, text

  DATE FORMAT (pour --from/--to):
    "2026-05-30T16:00:00" => 2026/05/30 à 16:00 Europe/Paris (DST géré)

  FORMATS:
    ndjson  Un document JSON (_source) par ligne (batch_XXXX.ndjson)
    json    Tableau JSON unique par batch           (batch_XXXX.json)
    text    Champ .message seul, un par ligne       (batch_XXXX.log)
EOF
}

APP=
FROM=
TO=
SINCE=
TARGET_DIR=
FORMAT=ndjson
SEARCH=
MARGIN=1m

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)        APP="$2";        shift 2 ;;
    --from)       FROM="$2";       shift 2 ;;
    --to)         TO="$2";         shift 2 ;;
    --since)      SINCE="$2";      shift 2 ;;
    --search)     SEARCH="$2";     shift 2 ;;
    --margin)     MARGIN="$2";     shift 2 ;;
    --target-dir) TARGET_DIR="$2"; shift 2 ;;
    --format)     FORMAT="$2";     shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$APP" ]]; then
  echo "Erreur: --app est obligatoire"
  usage
  exit 1
fi

if [[ -n "$SINCE" && ( -n "$FROM" || -n "$TO" ) ]]; then
  echo "Erreur: --since est incompatible avec --from/--to"
  exit 1
fi

if [[ -z "$SINCE" && -z "$FROM" ]]; then
  echo "Erreur: fournir soit --since, soit --from (--to optionnel)"
  usage
  exit 1
fi

case "$FORMAT" in
  ndjson|json|text) ;;
  *) echo "Erreur: --format doit être ndjson, json ou text"; exit 1 ;;
esac

# Détection GNU vs BSD date
if date --version &>/dev/null; then
  DATE_FLAVOR=gnu
else
  DATE_FLAVOR=bsd
fi

# Parse Xs/Xm/Xh/Xd -> secondes
parse_duration_to_seconds() {
  local d="$1"
  if [[ "$d" =~ ^([0-9]+)([smhd])$ ]]; then
    local num="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      s) echo "$num" ;;
      m) echo $((num * 60)) ;;
      h) echo $((num * 3600)) ;;
      d) echo $((num * 86400)) ;;
    esac
  else
    return 1
  fi
}

epoch_to_iso() {
  local epoch="$1"
  if [[ "$DATE_FLAVOR" == gnu ]]; then
    date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
  else
    date -u -j -f "%s" "$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
  fi
}

# Parse une date ISO UTC ("2025-05-30T14:00:00.000Z" ou sans ms) -> epoch
iso_to_epoch() {
  local ts="$1"
  if [[ "$DATE_FLAVOR" == gnu ]]; then
    date -u -d "$ts" +%s
  else
    local clean="${ts%.*}"
    clean="${clean%Z}"
    TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null
  fi
}

# Parse une date Europe/Paris "YYYY-mm-ddTHH:MM:SS" -> epoch UTC (DST géré)
parse_paris_to_epoch() {
  local dt="$1"
  if [[ "$DATE_FLAVOR" == gnu ]]; then
    TZ=Europe/Paris date -d "$dt" +%s
  else
    TZ=Europe/Paris date -j -f "%Y-%m-%dT%H:%M:%S" "$dt" +%s 2>/dev/null
  fi
}

if [[ -n "$SINCE" ]]; then
  seconds=$(parse_duration_to_seconds "$SINCE") || {
    echo "Erreur: format --since invalide. Attendu: Xs, Xm, Xh, Xd (ex: 30m, 2h, 7d)"
    exit 1
  }
  NOW_EPOCH=$(date -u +%s)
  FROM_EPOCH=$((NOW_EPOCH - seconds))
  GTE=$(epoch_to_iso "$FROM_EPOCH")
  LTE=$(epoch_to_iso "$NOW_EPOCH")
  RANGE_DISPLAY="depuis $SINCE (-> now)"
else
  FROM_EPOCH=$(parse_paris_to_epoch "$FROM") || {
    echo "Erreur: format --from invalide. Attendu: 2026-03-26T15:30:00"; exit 1;
  }
  if [[ -n "$TO" ]]; then
    TO_EPOCH=$(parse_paris_to_epoch "$TO") || {
      echo "Erreur: format --to invalide. Attendu: 2026-03-26T15:30:00"; exit 1;
    }
    RANGE_DISPLAY="$FROM -> $TO (Europe/Paris)"
  else
    TO_EPOCH=$(date -u +%s)
    RANGE_DISPLAY="$FROM -> now (Europe/Paris)"
  fi
  GTE=$(epoch_to_iso "$FROM_EPOCH")
  LTE=$(epoch_to_iso "$TO_EPOCH")
fi

if [[ -n "$SEARCH" ]]; then
  MARGIN_SEC=$(parse_duration_to_seconds "$MARGIN") || {
    echo "Erreur: format --margin invalide. Attendu: Xs, Xm, Xh (ex: 30s, 1m, 2m)"
    exit 1
  }
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ES_URL="${ES_URL:-https://es-observability.prd.api.udb.azr.intranet}"
INDEX="es-apis-*"
BATCH_SIZE=10000

if [[ -n "$TARGET_DIR" ]]; then
  BATCHES_DIR="$TARGET_DIR"
else
  BATCHES_DIR="$SCRIPT_DIR/logs/$APP"
fi

case "$FORMAT" in
  ndjson) EXT="ndjson" ;;
  json)   EXT="json" ;;
  text)   EXT="log" ;;
esac

draw_progress() {
  local current=$1 total=$2 batch=$3
  local pct=0
  if [[ "$total" =~ ^[0-9]+$ && "$total" -gt 0 ]]; then
    pct=$((current * 100 / total))
    [[ $pct -gt 100 ]] && pct=100
  fi
  local bar_width=40
  local filled=$((pct * bar_width / 100))
  local bar="" i
  for ((i=0; i<filled; i++)); do bar+="#"; done
  for ((i=filled; i<bar_width; i++)); do bar+="-"; done
  printf "\r[%s] %3d%% — %s/%s docs (batch %d)\033[K" "$bar" "$pct" "$current" "$total" "$batch"
}

write_batch() {
  local resp="$1" file="$2"
  case "$FORMAT" in
    ndjson) echo "$resp" | jq -c '.hits.hits[]._source' > "$file" ;;
    json)   echo "$resp" | jq  '[.hits.hits[]._source]' > "$file" ;;
    text)   echo "$resp" | jq -r '.hits.hits[]._source.message // empty' > "$file" ;;
  esac
}

echo "=== Fetch logs depuis Elasticsearch ==="
echo "App:    $APP"
echo "ES:     $ES_URL"
echo "Index:  $INDEX"
echo "Plage:  $RANGE_DISPLAY"
echo "  UTC:  $GTE -> $LTE"
echo "Format: $FORMAT"
echo "Dir:    $BATCHES_DIR"
echo ""

# Phase recherche : restreint la fenêtre à [min, max] des matches +/- margin
if [[ -n "$SEARCH" ]]; then
  # Échappement JSON minimal (\\ et ")
  SEARCH_ESC="${SEARCH//\\/\\\\}"
  SEARCH_ESC="${SEARCH_ESC//\"/\\\"}"

  echo "=== Recherche \"$SEARCH\" (margin ±$MARGIN) ==="
  search_resp=$(curl -u "$ES_USER:$ES_PASSWORD" -s "$ES_URL/$INDEX/_search" \
    -H 'Content-Type: application/json' \
    -d "{
      \"size\": 0,
      \"track_total_hits\": true,
      \"query\": {
        \"bool\": {
          \"must\": [
            { \"term\": { \"application\": \"$APP\" }},
            { \"range\": { \"@timestamp\": { \"gte\": \"$GTE\", \"lte\": \"$LTE\" }}},
            { \"match_phrase\": { \"message\": \"$SEARCH_ESC\" }}
          ]
        }
      },
      \"aggs\": {
        \"min_ts\": { \"min\": { \"field\": \"@timestamp\" }},
        \"max_ts\": { \"max\": { \"field\": \"@timestamp\" }}
      }
    }")

  match_total=$(echo "$search_resp" | jq -r '.hits.total.value // .hits.total // 0')
  min_iso=$(echo "$search_resp" | jq -r '.aggregations.min_ts.value_as_string // ""')
  max_iso=$(echo "$search_resp" | jq -r '.aggregations.max_ts.value_as_string // ""')

  if [[ "$match_total" -eq 0 || -z "$min_iso" || -z "$max_iso" ]]; then
    echo "  Aucun match dans la fenêtre initiale."
    exit 1
  fi

  min_epoch=$(iso_to_epoch "$min_iso")
  max_epoch=$(iso_to_epoch "$max_iso")
  duration=$((max_epoch - min_epoch))

  GTE=$(epoch_to_iso "$((min_epoch - MARGIN_SEC))")
  LTE=$(epoch_to_iso "$((max_epoch + MARGIN_SEC))")

  echo "  Matches: $match_total"
  echo "  Plage:   $min_iso -> $max_iso (durée: ${duration}s)"
  echo "  Étendue: $GTE -> $LTE"
  echo ""
fi

mkdir -p "$BATCHES_DIR"
rm -f "$BATCHES_DIR"/batch_*.ndjson "$BATCHES_DIR"/batch_*.json "$BATCHES_DIR"/batch_*.log

batch_num=1

# Première requête avec scroll
response=$(curl -u "$ES_USER:$ES_PASSWORD" -s "$ES_URL/$INDEX/_search?scroll=5m" \
  -H 'Content-Type: application/json' \
  -d "{
    \"size\": $BATCH_SIZE,
    \"sort\": [{\"@timestamp\": \"asc\"}],
    \"_source\": true,
    \"query\": {
      \"bool\": {
        \"must\": [
          { \"term\": { \"application\": \"$APP\" }},
          { \"range\": { \"@timestamp\": {
              \"gte\": \"$GTE\",
              \"lte\": \"$LTE\"
          }}}
        ],
        \"should\": [
          { \"term\": { \"logger\": \"auditLog\" }},
          { \"match_phrase\": { \"message\": \"ExternalHttpCall\" }},
          { \"term\": { \"type\": \"javaLog\" }}
        ],
        \"minimum_should_match\": 1
      }
    }
  }")

scroll_id=$(echo "$response" | jq -r '._scroll_id')
total=$(echo "$response" | jq -r '.hits.total.value // .hits.total')
hits=$(echo "$response" | jq -r '.hits.hits | length')

echo "Total estimé: $total documents"
echo ""

batch_file=$(printf "$BATCHES_DIR/batch_%04d.$EXT" $batch_num)
write_batch "$response" "$batch_file"
fetched=$hits
draw_progress "$fetched" "$total" "$batch_num"

# Scroll pour récupérer le reste
while [ "$hits" -gt 0 ]; do
  response=$(curl -u "$ES_USER:$ES_PASSWORD" -s "$ES_URL/_search/scroll" \
    -H 'Content-Type: application/json' \
    -d "{\"scroll\": \"5m\", \"scroll_id\": \"$scroll_id\"}")

  scroll_id=$(echo "$response" | jq -r '._scroll_id')
  hits=$(echo "$response" | jq -r '.hits.hits | length')

  if [ "$hits" -eq 0 ]; then
    break
  fi

  batch_num=$((batch_num + 1))
  batch_file=$(printf "$BATCHES_DIR/batch_%04d.$EXT" $batch_num)
  write_batch "$response" "$batch_file"
  fetched=$((fetched + hits))
  draw_progress "$fetched" "$total" "$batch_num"
done
printf "\n"

# Cleanup scroll
curl -s -X DELETE "$ES_URL/_search/scroll" \
  -H 'Content-Type: application/json' \
  -d "{\"scroll_id\": \"$scroll_id\"}" > /dev/null 2>&1

echo ""
echo "$fetched docs récupérés en $batch_num batch(es) -> $BATCHES_DIR/"
