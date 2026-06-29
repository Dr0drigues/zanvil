# Skip si module desactive
[[ "$ZANVIL_MODULE_DOCKER" != "true" ]] && return

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
        _ui_msg_info "Connexion a $cid avec $shell..."
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
            _ui_msg_info "Annule."
            return 0
        fi
    fi

    docker stop $(echo "$containers")
}

# ==============================================================================
# Docker Build avec injection CA corporate
# ==============================================================================
# Wrapper docker build qui monte le CA bundle corporate via BuildKit secret.
# Le Dockerfile doit inclure la ligne suivante (avant pip install, apt, etc.) :
#
#   RUN --mount=type=secret,id=ca-bundle,target=/usr/local/share/ca-certificates/corporate.crt \
#       update-ca-certificates && pip install -r requirements.txt
#
# Usage : dbuild -t mon-image .
#         dbuild -t mon-image -f Dockerfile.dev ./app
# ==============================================================================

dbuild() {
    if ! docker info &>/dev/null 2>&1; then
        _ui_msg_fail "Docker daemon non accessible"
        return 1
    fi

    local ca_bundle="$HOME/.ssl/ca-bundle.pem"

    if [[ -f "$ca_bundle" ]]; then
        _ui_msg_info "Injection du CA corporate dans le build (BuildKit secret)"
        DOCKER_BUILDKIT=1 docker build --secret id=ca-bundle,src="$ca_bundle" "$@"
    else
        docker build "$@"
    fi
}