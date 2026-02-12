# Skip si module desactive
[[ "$ZSH_ENV_MODULE_DOCKER" != "true" ]] && return

# =======================================================
# DOCKER UTILITIES
# =======================================================

# Docker Exec interactif avec sélection FZF
# Usage : dex (sélectionne le conteneur)
# Usage : dex sh (force l'utilisation de sh au lieu de bash)
dex() {
    # Vérifie si docker est lancé
    if ! docker ps > /dev/null 2>&1; then
        _ui_msg_fail "Docker n'est pas lance ou accessible."
        return 1
    fi

    local cid
    # Selection du conteneur via fzf (affiche Nom et ID)
    cid=$(docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Status}}" | sed 1d | fzf -m | awk '{print $2}')

    if [[ -n "$cid" ]]; then
        local shell="${1:-bash}"
        echo -e "${_ui_dim}Connexion a $cid avec $shell...${_ui_nc}"
        docker exec -it "$cid" "$shell"
    fi
}

# Nettoyage rapide (Stop all containers)
dstop() {
    if ! docker ps > /dev/null 2>&1; then
        _ui_msg_fail "Docker n'est pas lance ou accessible."
        return 1
    fi

    local containers
    containers=$(docker ps -q)

    if [[ -z "$containers" ]]; then
        _ui_msg_info "Aucun conteneur en cours d'execution."
        return 0
    fi

    local count
    count=$(echo "$containers" | wc -l | tr -d ' ')
    _ui_msg_warn "$count conteneur(s) en cours d'execution :"
    docker ps --format "  {{.Names}} ({{.Image}}) - {{.Status}}"

    if [[ -t 0 ]]; then
        local response
        read -q "response?Arreter tous ces conteneurs ? [y/N] "
        echo ""
        if [[ "$response" != "y" ]]; then
            echo -e "${_ui_dim}Annule.${_ui_nc}"
            return 0
        fi
    fi

    docker stop $(echo "$containers")
}