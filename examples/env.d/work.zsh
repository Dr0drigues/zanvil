# Work — URLs et credentials internes (contexte professionnel)
# Detection automatique du contexte via probe sur _NEXUS_URL

# URL de probe (laissee vide = pas de detection automatique)
export ZANVIL_WORK_NEXUS_URL="${ZANVIL_WORK_NEXUS_URL:-}"
export ZANVIL_WORK_CACHE_TTL="${ZANVIL_WORK_CACHE_TTL:-300}"
export ZANVIL_WORK_TIMEOUT="${ZANVIL_WORK_TIMEOUT:-2}"

# Elasticsearch observability (utilise par work_fetch_logs)
export ZANVIL_WORK_ES_URL="${ZANVIL_WORK_ES_URL:-}"
export ES_USER="${ES_USER:-}"
# ES_PASSWORD a definir dans ~/.secrets ou via SOPS, jamais ici en clair
# export ES_PASSWORD=""

# PKI entreprise — URL du bundle de certificats (certificates_unix.sh)
export ZANVIL_WORK_PKI_URL="${ZANVIL_WORK_PKI_URL:-}"

# CA issuers SSL — noms CN des CAs entreprise, separes par ':' (ssl-setup.sh)
export ZANVIL_ENTERPRISE_CA_ISSUERS="${ZANVIL_ENTERPRISE_CA_ISSUERS:-}"
