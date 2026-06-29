# ==============================================================================
# core/migrate.zsh — Systeme de migration de configuration
# ==============================================================================
# Applique des migrations numeriques pour gerer les breaking changes
# Etat stocke dans .migration_version
# ==============================================================================

zanvil-migrate() {
    local action="${1:-run}"

    case "$action" in
        run)       _zanvil_migrate_run ;;
        --list)    _zanvil_migrate_list ;;
        --status)  _zanvil_migrate_status ;;
        -h|--help) _zanvil_migrate_help ;;
        *)
            _ui_msg_fail "Action inconnue: $action"
            _zanvil_migrate_help
            return 1
            ;;
    esac
}

# ==============================================================================
# Run : detecte et applique les migrations en attente
# ==============================================================================
_zanvil_migrate_run() {
    local migrations_dir="$ZANVIL_DIR/migrations"
    local state_file="$ZANVIL_DIR/.migration_version"
    local current_version=0

    [[ -f "$state_file" ]] && current_version=$(<"$state_file")

    if [[ ! -d "$migrations_dir" ]]; then
        _ui_msg_ok "Aucun dossier de migrations"
        return 0
    fi

    # Lister les migrations disponibles (format: NNN_description.zsh)
    local -a pending=()
    for migration in "$migrations_dir"/[0-9]*.zsh(N); do
        [[ ! -f "$migration" ]] && continue
        local filename=$(basename "$migration")
        local num=${filename%%_*}
        # Retirer les leading zeros pour la comparaison
        num=$((10#$num))
        if (( num > current_version )); then
            pending+=("$migration")
        fi
    done

    if [[ ${#pending[@]} -eq 0 ]]; then
        _ui_msg_ok "Aucune migration en attente (version: $current_version)"
        return 0
    fi

    _ui_header "Zanvil Migration"
    _ui_section "Version" "$current_version"
    _ui_section "En attente" "${#pending[@]} migration(s)"
    echo ""

    local ok=0 fail=0

    for migration in "${pending[@]}"; do
        local filename=$(basename "$migration")
        local num=${filename%%_*}
        local desc=${filename#*_}
        desc=${desc%.zsh}
        desc=${desc//_/ }

        printf "  %-4s %-40s " "$num" "$desc"

        # Executer la migration
        if source "$migration" 2>/dev/null; then
            _ui_ok ""
            echo ""
            ((ok++))
            # Mettre a jour la version
            echo "$((10#$num))" > "$state_file"
        else
            _ui_fail "" "erreur"
            echo ""
            ((fail++))
            # Stopper a la premiere erreur
            _ui_msg_fail "Migration $num echouee, arret"
            return 1
        fi
    done

    echo ""
    _ui_separator 44
    local new_version=$(<"$state_file")
    printf "${_ui_green}%d${_ui_nc} migration(s) appliquee(s)  version: ${_ui_bold}%s${_ui_nc}\n" "$ok" "$new_version"
}

# ==============================================================================
# List : affiche toutes les migrations
# ==============================================================================
_zanvil_migrate_list() {
    local migrations_dir="$ZANVIL_DIR/migrations"
    local state_file="$ZANVIL_DIR/.migration_version"
    local current_version=0

    [[ -f "$state_file" ]] && current_version=$(<"$state_file")

    _ui_header "Zanvil Migrations"
    _ui_section "Version" "$current_version"
    echo ""

    if [[ ! -d "$migrations_dir" ]] || [[ -z "$(ls "$migrations_dir"/[0-9]*.zsh 2>/dev/null)" ]]; then
        _ui_msg_info "Aucune migration disponible"
        return 0
    fi

    printf "${_ui_bold}%-6s %-40s %s${_ui_nc}\n" "Num" "Description" "Statut"
    _ui_separator 54

    for migration in "$migrations_dir"/[0-9]*.zsh(N); do
        local filename=$(basename "$migration")
        local num=${filename%%_*}
        local desc=${filename#*_}
        desc=${desc%.zsh}
        desc=${desc//_/ }
        local num_val=$((10#$num))

        if (( num_val <= current_version )); then
            printf "  ${_ui_dim}%-4s %-40s${_ui_nc} ${_ui_green}${_ui_check} appliquee${_ui_nc}\n" "$num" "$desc"
        else
            printf "  %-4s %-40s ${_ui_yellow}en attente${_ui_nc}\n" "$num" "$desc"
        fi
    done
}

# ==============================================================================
# Status
# ==============================================================================
_zanvil_migrate_status() {
    local state_file="$ZANVIL_DIR/.migration_version"
    local current_version=0
    [[ -f "$state_file" ]] && current_version=$(<"$state_file")

    local migrations_dir="$ZANVIL_DIR/migrations"
    local total=0 pending=0

    if [[ -d "$migrations_dir" ]]; then
        for migration in "$migrations_dir"/[0-9]*.zsh(N); do
            ((total++))
            local num=${$(basename "$migration")%%_*}
            (( 10#$num > current_version )) && ((pending++))
        done
    fi

    printf "Version: ${_ui_bold}%s${_ui_nc}  Total: %d  En attente: " "$current_version" "$total"
    if [[ $pending -gt 0 ]]; then
        printf "${_ui_yellow}%d${_ui_nc}\n" "$pending"
    else
        printf "${_ui_green}0${_ui_nc}\n"
    fi
}

# ==============================================================================
# Aide
# ==============================================================================
_zanvil_migrate_help() {
    _ui_header "Zanvil Migrate"
    echo ""
    printf "${_ui_bold}Usage:${_ui_nc}\n"
    echo "  zanvil-migrate              Appliquer les migrations en attente"
    echo "  zanvil-migrate --list       Lister toutes les migrations"
    echo "  zanvil-migrate --status     Afficher la version courante"
    echo ""
    printf "${_ui_bold}Convention:${_ui_nc}\n"
    echo "  Fichiers dans migrations/ : NNN_description.zsh"
    echo "  Exemple: 001_rename_module_vars.zsh"
}
