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
        echo "Docker n'est pas lancé ou accessible."
        return 1
    fi

    local cid
    # Sélection du conteneur via fzf (affiche Nom et ID)
    cid=$(docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Status}}" | sed 1d | fzf -m | awk '{print $2}')

    if [[ -n "$cid" ]]; then
        local shell="${1:-bash}" # Par défaut bash, sinon l'argument passé (ex: sh)
        echo "🐳 Connexion à $cid avec $shell..."
        docker exec -it "$cid" "$shell"
    fi
}

# Nettoyage rapide (Stop all containers)
dstop() {
    if ! docker ps > /dev/null 2>&1; then
        echo "Docker n'est pas lance ou accessible."
        return 1
    fi

    local containers
    containers=$(docker ps -q)

    if [[ -z "$containers" ]]; then
        echo "Aucun conteneur en cours d'execution."
        return 0
    fi

    local count
    count=$(echo "$containers" | wc -l | tr -d ' ')
    echo "$count conteneur(s) en cours d'execution :"
    docker ps --format "  {{.Names}} ({{.Image}}) - {{.Status}}"

    if [[ -t 0 ]]; then
        local response
        read -q "response?Arreter tous ces conteneurs ? [y/N] "
        echo ""
        if [[ "$response" != "y" ]]; then
            echo "Annule."
            return 0
        fi
    fi

    docker stop $containers
}