# Work — URLs et credentials internes (contexte professionnel)
# Detection automatique du contexte via probe sur _NEXUS_URL

# URL de probe (laissee vide = pas de detection automatique)
export ZANVIL_WORK_NEXUS_URL="${ZANVIL_WORK_NEXUS_URL:-}"
export ZANVIL_WORK_CACHE_TTL="${ZANVIL_WORK_CACHE_TTL:-300}"
export ZANVIL_WORK_TIMEOUT="${ZANVIL_WORK_TIMEOUT:-2}"

# Elasticsearch observability (work_fetch_logs, work_es_query/apps/count/tail)
export ZANVIL_WORK_ES_URL="${ZANVIL_WORK_ES_URL:-}"
export ZANVIL_WORK_ES_INDEX="${ZANVIL_WORK_ES_INDEX:-es-apis-*}"
export ZANVIL_WORK_ES_APPS_TTL="${ZANVIL_WORK_ES_APPS_TTL:-3600}"   # TTL cache work_es_apps (s)
export ZANVIL_WORK_ES_MAX_DOCS="${ZANVIL_WORK_ES_MAX_DOCS:-100000}" # seuil garde-fou work_fetch_logs
export ES_USER="${ES_USER:-}"
# ES_PASSWORD a definir dans ~/.secrets ou via SOPS, jamais ici en clair
# export ES_PASSWORD=""

# PKI entreprise — URL du bundle de certificats (certificates_unix.sh)
export ZANVIL_WORK_PKI_URL="${ZANVIL_WORK_PKI_URL:-}"

# CA issuers SSL — noms CN des CAs entreprise, separes par ':' (ssl-setup.sh)
export ZANVIL_ENTERPRISE_CA_ISSUERS="${ZANVIL_ENTERPRISE_CA_ISSUERS:-}"
