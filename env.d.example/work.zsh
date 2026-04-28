# Work — URLs et credentials internes (contexte professionnel)
# Detection automatique du contexte via probe sur _NEXUS_URL

# URL de probe (laissee vide = pas de detection automatique)
export ZSH_ENV_WORK_NEXUS_URL="${ZSH_ENV_WORK_NEXUS_URL:-}"
export ZSH_ENV_WORK_CACHE_TTL="${ZSH_ENV_WORK_CACHE_TTL:-300}"
export ZSH_ENV_WORK_TIMEOUT="${ZSH_ENV_WORK_TIMEOUT:-2}"

# Elasticsearch observability (utilise par work_fetch_logs)
export ZSH_ENV_WORK_ES_URL="${ZSH_ENV_WORK_ES_URL:-}"
export ES_USER="${ES_USER:-}"
# ES_PASSWORD a definir dans ~/.secrets ou via SOPS, jamais ici en clair
# export ES_PASSWORD=""
