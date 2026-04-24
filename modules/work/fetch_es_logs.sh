#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat << EOF
  usage: $0 --app APP [--since DURATION | --from FROM_DATE [--to TO_DATE]] [options]

  Exporte les logs Elasticsearch pour l'application donnée.

  OPTIONS:
    --app         APP          Application à interroger (ex: bff-frontcommerce)
    --since       DURATION     Plage relative: Xm (minutes), Xh (heures), Xd (jours)
                               Ex: --since 30m, --since 2h, --since 7d
    --from        FROM_DATE    Début de plage en UTC+1 (Europe/Paris hiver)
    --to          TO_DATE      Fin de plage en UTC+1 (défaut: now si omis)
    --target-dir  DIR          Répertoire de sortie (défaut: \$PWD/logs/\$APP)
    --format      FORMAT       Format de sortie: ndjson (défaut), json, text

  DATE FORMAT (pour --from/--to):
    "2026-03-26T15:30:00" => 2026/03/26 à 15:30 UTC+1 (14:30 UTC)

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)        APP="$2";        shift 2 ;;
    --from)       FROM="$2";       shift 2 ;;
    --to)         TO="$2";         shift 2 ;;
    --since)      SINCE="$2";      shift 2 ;;
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

epoch_to_iso() {
  local epoch="$1"
  if [[ "$DATE_FLAVOR" == gnu ]]; then
    date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
  else
    date -u -j -f "%s" "$epoch" +"%Y-%m-%dT%H:%M:%S.000Z"
  fi
}

# Parse une date UTC+1 "YYYY-mm-ddTHH:MM:SS" -> epoch UTC
parse_utc1_to_epoch() {
  local dt="$1"
  if [[ "$DATE_FLAVOR" == gnu ]]; then
    date -u -d "$dt UTC+1" +%s
  else
    local e
    e=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$dt" +%s 2>/dev/null) || return 1
    echo $((e - 3600))
  fi
}

if [[ -n "$SINCE" ]]; then
  if [[ "$SINCE" =~ ^([0-9]+)([mhd])$ ]]; then
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
      m) seconds=$((num * 60)) ;;
      h) seconds=$((num * 3600)) ;;
      d) seconds=$((num * 86400)) ;;
    esac
  else
    echo "Erreur: format --since invalide. Attendu: Xm, Xh, ou Xd (ex: 30m, 2h, 7d)"
    exit 1
  fi
  NOW_EPOCH=$(date -u +%s)
  FROM_EPOCH=$((NOW_EPOCH - seconds))
  GTE=$(epoch_to_iso "$FROM_EPOCH")
  LTE=$(epoch_to_iso "$NOW_EPOCH")
  RANGE_DISPLAY="depuis $SINCE (-> now)"
else
  FROM_EPOCH=$(parse_utc1_to_epoch "$FROM") || {
    echo "Erreur: format --from invalide. Attendu: 2026-03-26T15:30:00"; exit 1;
  }
  if [[ -n "$TO" ]]; then
    TO_EPOCH=$(parse_utc1_to_epoch "$TO") || {
      echo "Erreur: format --to invalide. Attendu: 2026-03-26T15:30:00"; exit 1;
    }
    RANGE_DISPLAY="$FROM -> $TO (UTC+1)"
  else
    TO_EPOCH=$(date -u +%s)
    RANGE_DISPLAY="$FROM -> now (UTC+1)"
  fi
  GTE=$(epoch_to_iso "$FROM_EPOCH")
  LTE=$(epoch_to_iso "$TO_EPOCH")
fi

ES_URL="${ES_URL:-}"
INDEX="es-apis-*"
BATCH_SIZE=10000

if [[ -n "$TARGET_DIR" ]]; then
  BATCHES_DIR="$TARGET_DIR"
else
  BATCHES_DIR="$PWD/logs/$APP"
fi

case "$FORMAT" in
  ndjson) EXT="ndjson" ;;
  json)   EXT="json" ;;
  text)   EXT="log" ;;
esac

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
echo "  Batch $batch_num: $hits docs (total: $fetched) -> $(basename "$batch_file")"

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
  echo "  Batch $batch_num: $hits docs (total: $fetched) -> $(basename "$batch_file")"
done

# Cleanup scroll
curl -s -X DELETE "$ES_URL/_search/scroll" \
  -H 'Content-Type: application/json' \
  -d "{\"scroll_id\": \"$scroll_id\"}" > /dev/null 2>&1

echo ""
echo "$fetched docs récupérés en $batch_num batch(es) -> $BATCHES_DIR/"
