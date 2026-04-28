# Docker — CIDR pool reseau pour Colima daemon
# Utilise par install.sh lors de la configuration Colima
export ZSH_ENV_DOCKER_ADDRESS_POOL="${ZSH_ENV_DOCKER_ADDRESS_POOL:-172.20.0.0/16}"
