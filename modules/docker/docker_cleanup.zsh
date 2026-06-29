# ==============================================================================
# Docker Cleanup - Nettoyage intelligent des ressources Docker
# ==============================================================================
# Dry-run par defaut, --apply pour executer
# ==============================================================================

zanvil-docker-clean() {
    command -v docker &>/dev/null || { _ui_msg_fail "Docker n'est pas installe"; return 1; }
    docker info &>/dev/null 2>&1 || { _ui_msg_fail "Docker daemon non accessible"; return 1; }

    local do_apply=false
    local include_all=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply) do_apply=true; shift ;;
            --all)   include_all=true; shift ;;
            -h|--help)
                _docker_clean_help
                return 0
                ;;
            *) shift ;;
        esac
    done

    if [[ "$do_apply" == "true" ]]; then
        _ui_header "Docker Clean"
    else
        _ui_header "Docker Clean [DRY-RUN]"
    fi
    echo ""

    local total_items=0 total_freed=""

    # --- 1. Containers stoppes ---
    local stopped=$(docker ps -a -q -f status=exited -f status=created 2>/dev/null)
    local stopped_count=0
    [[ -n "$stopped" ]] && stopped_count=$(echo "$stopped" | wc -l | tr -d ' ')

    printf "  ${_ui_bold}%-16s${_ui_nc} " "Containers"
    if [[ $stopped_count -eq 0 ]]; then
        _ui_ok "" "aucun stoppe"
        echo ""
    else
        ((total_items += stopped_count))
        if [[ "$do_apply" == "true" ]]; then
            docker container prune -f &>/dev/null
            _ui_ok "" "${stopped_count} supprime(s)"
        else
            _ui_msg_info "${stopped_count} stoppe(s)"
        fi
    fi

    # --- 2. Images dangling ---
    local dangling=$(docker images -q -f dangling=true 2>/dev/null)
    local dangling_count=0
    local dangling_size=""
    if [[ -n "$dangling" ]]; then
        dangling_count=$(echo "$dangling" | wc -l | tr -d ' ')
        dangling_size=$(docker images -f dangling=true --format '{{.Size}}' 2>/dev/null | head -5 | paste -sd ', ' -)
    fi

    printf "  ${_ui_bold}%-16s${_ui_nc} " "Images"
    if [[ $dangling_count -eq 0 ]]; then
        _ui_ok "" "aucune dangling"
        echo ""
    else
        ((total_items += dangling_count))
        if [[ "$do_apply" == "true" ]]; then
            docker image prune -f &>/dev/null
            _ui_ok "" "${dangling_count} supprimee(s)"
        else
            _ui_msg_info "${dangling_count} dangling"
        fi
    fi

    # --- 2b. Images inutilisees (avec --all) ---
    if [[ "$include_all" == "true" ]]; then
        local unused=$(docker images -q --filter "dangling=false" 2>/dev/null)
        local unused_count=0
        [[ -n "$unused" ]] && unused_count=$(echo "$unused" | wc -l | tr -d ' ')
        # Soustraire les dangling deja comptees
        local all_images=$(docker images -q 2>/dev/null)
        local all_count=0
        [[ -n "$all_images" ]] && all_count=$(echo "$all_images" | wc -l | tr -d ' ')
        local extra=$(( all_count - dangling_count ))

        printf "  ${_ui_bold}%-16s${_ui_nc} " "Images (all)"
        if [[ $extra -le 0 ]]; then
            _ui_ok "" "aucune supplementaire"
            echo ""
        else
            ((total_items += extra))
            if [[ "$do_apply" == "true" ]]; then
                docker image prune -a -f &>/dev/null
                _ui_ok "" "${extra} supprimee(s)"
            else
                _ui_msg_info "${extra} inutilisee(s)"
            fi
        fi
    fi

    # --- 3. Volumes orphelins ---
    local volumes=$(docker volume ls -q -f dangling=true 2>/dev/null)
    local vol_count=0
    [[ -n "$volumes" ]] && vol_count=$(echo "$volumes" | wc -l | tr -d ' ')

    printf "  ${_ui_bold}%-16s${_ui_nc} " "Volumes"
    if [[ $vol_count -eq 0 ]]; then
        _ui_ok "" "aucun orphelin"
        echo ""
    else
        ((total_items += vol_count))
        if [[ "$do_apply" == "true" ]]; then
            docker volume prune -f &>/dev/null
            _ui_ok "" "${vol_count} supprime(s)"
        else
            _ui_msg_info "${vol_count} orphelin(s)"
        fi
    fi

    # --- 4. Networks inutilises ---
    # Exclure les reseaux par defaut (bridge, host, none)
    local networks=$(docker network ls -q --filter type=custom 2>/dev/null)
    local net_count=0
    if [[ -n "$networks" ]]; then
        # Filtrer ceux qui ne sont utilises par aucun container
        for net_id in $(echo "$networks"); do
            local containers_using=$(docker network inspect "$net_id" --format '{{len .Containers}}' 2>/dev/null)
            [[ "$containers_using" == "0" ]] && ((net_count++))
        done
    fi

    printf "  ${_ui_bold}%-16s${_ui_nc} " "Networks"
    if [[ $net_count -eq 0 ]]; then
        _ui_ok "" "aucun inutilise"
        echo ""
    else
        ((total_items += net_count))
        if [[ "$do_apply" == "true" ]]; then
            docker network prune -f &>/dev/null
            _ui_ok "" "${net_count} supprime(s)"
        else
            _ui_msg_info "${net_count} inutilise(s)"
        fi
    fi

    # --- 5. Build cache (avec --all) ---
    if [[ "$include_all" == "true" ]]; then
        local cache_size=$(docker system df --format '{{.Size}}' 2>/dev/null | tail -1)

        printf "  ${_ui_bold}%-16s${_ui_nc} " "Build cache"
        if [[ -n "$cache_size" && "$cache_size" != "0B" ]]; then
            if [[ "$do_apply" == "true" ]]; then
                docker builder prune -f &>/dev/null
                _ui_ok "" "nettoye ($cache_size)"
            else
                _ui_msg_info "$cache_size"
            fi
        else
            _ui_ok "" "vide"
            echo ""
        fi
    fi

    # --- Resume ---
    echo ""
    _ui_separator 44

    if [[ "$do_apply" == "true" ]]; then
        if [[ $total_items -gt 0 ]]; then
            # Recuperer l'espace total reclame
            local reclaimed=$(docker system df --format 'table {{.Type}}\t{{.Reclaimable}}' 2>/dev/null | tail -1)
            _ui_msg_ok "${total_items} element(s) nettoye(s)"
        else
            _ui_msg_ok "Rien a nettoyer"
        fi
    else
        if [[ $total_items -gt 0 ]]; then
            printf "${_ui_yellow}%d${_ui_nc} element(s) a nettoyer  ${_ui_dim}(--apply pour executer)${_ui_nc}\n" "$total_items"
        else
            _ui_msg_ok "Docker est propre"
        fi
    fi
}

# ==============================================================================
# Aide
# ==============================================================================
_docker_clean_help() {
    _ui_header "Docker Clean"
    echo ""
    printf "${_ui_bold}Usage:${_ui_nc}\n"
    echo "  zanvil-docker-clean              Lister ce qui peut etre nettoye (dry-run)"
    echo "  zanvil-docker-clean --apply      Executer le nettoyage"
    echo "  zanvil-docker-clean --all        Inclure images non-dangling et build cache"
    echo ""
    printf "${_ui_bold}Elements nettoyes:${_ui_nc}\n"
    echo "  Containers stoppes, images dangling, volumes orphelins, networks inutilises"
    echo "  Avec --all : toutes les images inutilisees + build cache"
}

alias dclean='zanvil-docker-clean'
