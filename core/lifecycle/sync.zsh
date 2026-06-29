# ==============================================================================
# core/sync.zsh — Synchronisation de configuration entre machines
# ==============================================================================
# Export/import de la config portable (modules, theme, plugins, auto-update)
# Exclut : secrets, tokens, paths absolus
# ==============================================================================

zanvil-sync() {
    local action="${1:-help}"
    shift 2>/dev/null

    case "$action" in
        export) _zanvil_sync_export "$@" ;;
        import) _zanvil_sync_import "$@" ;;
        diff)   _zanvil_sync_diff "$@" ;;
        -h|--help|help) _zanvil_sync_help ;;
        *)
            _ui_msg_fail "Action inconnue: $action"
            _zanvil_sync_help
            return 1
            ;;
    esac
}

# ==============================================================================
# Export
# ==============================================================================
_zanvil_sync_export() {
    local output="${1:-$ZANVIL_DIR/sync.json}"
    local config_file="$ZANVIL_DIR/config.zsh"

    _ui_header "Zanvil Sync Export"

    # Collecter les modules
    local modules="{"
    local first=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^ZANVIL_MODULE_([A-Z_]+)=(true|false) ]]; then
            local mod_name="${match[1]}"
            local mod_val="${match[2]}"
            [[ "$first" == "true" ]] && first=false || modules+=","
            modules+="\"$mod_name\":$mod_val"
        fi
    done < "$config_file"
    modules+="}"

    # Theme actuel
    local theme=""
    [[ -f "$ZANVIL_DIR/.current_theme" ]] && theme=$(<"$ZANVIL_DIR/.current_theme")

    # Plugins
    local plugins="[]"
    local plugins_line=$(grep -E '^ZANVIL_PLUGINS=' "$config_file" 2>/dev/null)
    if [[ -n "$plugins_line" ]]; then
        # Extraire le contenu du tableau zsh
        local raw=$(echo "$plugins_line" | sed 's/ZANVIL_PLUGINS=(//' | sed 's/)//')
        plugins="["
        first=true
        for p in $(echo "$raw" | tr '\n' ' '); do
            p=$(echo "$p" | tr -d ' ')
            [[ -z "$p" ]] && continue
            [[ "$first" == "true" ]] && first=false || plugins+=","
            plugins+="\"$p\""
        done
        plugins+="]"
    fi

    # Auto-update
    local au_enabled=$(grep -E '^ZANVIL_AUTO_UPDATE=' "$config_file" 2>/dev/null | cut -d= -f2)
    local au_freq=$(grep -E '^ZANVIL_UPDATE_FREQUENCY=' "$config_file" 2>/dev/null | cut -d= -f2)
    local au_mode=$(grep -E '^ZANVIL_UPDATE_MODE=' "$config_file" 2>/dev/null | cut -d= -f2 | tr -d '"')

    # Theme dark/light
    local theme_light=$(grep -E '^ZANVIL_THEME_LIGHT=' "$config_file" 2>/dev/null | cut -d= -f2)
    local theme_dark=$(grep -E '^ZANVIL_THEME_DARK=' "$config_file" 2>/dev/null | cut -d= -f2)

    # Ecrire le JSON
    cat > "$output" <<EOF
{
  "version": "$ZANVIL_VERSION",
  "exported_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "modules": $modules,
  "theme": "${theme:-default}",
  "theme_light": "${theme_light:-}",
  "theme_dark": "${theme_dark:-}",
  "plugins": $plugins,
  "auto_update": {
    "enabled": ${au_enabled:-true},
    "frequency": ${au_freq:-7},
    "mode": "${au_mode:-prompt}"
  }
}
EOF

    _ui_msg_ok "Config exportee: $output"
    echo ""

    # Afficher un resume
    _ui_section "Version" "$ZANVIL_VERSION"
    _ui_section "Theme" "${theme:-default}"
    _ui_section "Modules" "$modules"
}

# ==============================================================================
# Import
# ==============================================================================
_zanvil_sync_import() {
    local input="$1"
    local config_file="$ZANVIL_DIR/config.zsh"

    if [[ -z "$input" || ! -f "$input" ]]; then
        _ui_msg_fail "Usage: zanvil-sync import <fichier.json>"
        return 1
    fi

    _ui_header "Zanvil Sync Import"
    _ui_section "Source" "$input"
    echo ""

    # Parser le JSON basique (sans jq si absent)
    if ! command -v jq &>/dev/null; then
        _ui_msg_fail "jq est requis pour l'import"
        return 1
    fi

    local version=$(jq -r '.version' "$input")
    _ui_section "Version" "$version"

    # Backup config
    cp "$config_file" "$config_file.pre-import"
    _ui_msg_info "Backup: $config_file.pre-import"
    echo ""

    # Appliquer les modules
    local modules=$(jq -r '.modules | to_entries[] | "\(.key)=\(.value)"' "$input")
    echo "$modules" | while IFS='=' read -r mod val; do
        [[ -z "$mod" ]] && continue
        local var="ZANVIL_MODULE_$mod"
        # Mettre a jour dans config.zsh
        if grep -q "^$var=" "$config_file"; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/^${var}=.*/${var}=${val}/" "$config_file"
            else
                sed -i "s/^${var}=.*/${var}=${val}/" "$config_file"
            fi
        else
            echo "${var}=${val}" >> "$config_file"
        fi
        printf "  %-30s %s\n" "$var" "$val"
    done

    # Appliquer le theme
    local theme=$(jq -r '.theme // empty' "$input")
    if [[ -n "$theme" ]]; then
        echo ""
        _ui_section "Theme" "$theme"
        echo "$theme" > "$ZANVIL_DIR/.current_theme"
    fi

    # Theme light/dark
    local tl=$(jq -r '.theme_light // empty' "$input")
    local td=$(jq -r '.theme_dark // empty' "$input")
    if [[ -n "$tl" ]]; then
        _zanvil_sync_set_config "ZANVIL_THEME_LIGHT" "$tl" "$config_file"
    fi
    if [[ -n "$td" ]]; then
        _zanvil_sync_set_config "ZANVIL_THEME_DARK" "$td" "$config_file"
    fi

    # Auto-update
    local au_enabled=$(jq -r '.auto_update.enabled // empty' "$input")
    local au_freq=$(jq -r '.auto_update.frequency // empty' "$input")
    local au_mode=$(jq -r '.auto_update.mode // empty' "$input")

    [[ -n "$au_enabled" ]] && _zanvil_sync_set_config "ZANVIL_AUTO_UPDATE" "$au_enabled" "$config_file"
    [[ -n "$au_freq" ]] && _zanvil_sync_set_config "ZANVIL_UPDATE_FREQUENCY" "$au_freq" "$config_file"
    [[ -n "$au_mode" ]] && _zanvil_sync_set_config "ZANVIL_UPDATE_MODE" "\"$au_mode\"" "$config_file"

    echo ""
    _ui_msg_ok "Config importee. Rechargez avec ${_ui_bold}ss${_ui_nc}"
}

# Helper : set ou update une variable dans config.zsh
_zanvil_sync_set_config() {
    local var="$1" val="$2" file="$3"
    if grep -q "^${var}=" "$file"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^${var}=.*/${var}=${val}/" "$file"
        else
            sed -i "s/^${var}=.*/${var}=${val}/" "$file"
        fi
    else
        echo "${var}=${val}" >> "$file"
    fi
}

# ==============================================================================
# Diff
# ==============================================================================
_zanvil_sync_diff() {
    local input="$1"

    if [[ -z "$input" || ! -f "$input" ]]; then
        _ui_msg_fail "Usage: zanvil-sync diff <fichier.json>"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        _ui_msg_fail "jq est requis pour le diff"
        return 1
    fi

    _ui_header "Zanvil Sync Diff"
    _ui_section "Source" "$input"
    echo ""

    local config_file="$ZANVIL_DIR/config.zsh"
    local diffs=0

    # Comparer les modules
    printf "${_ui_bold}%-30s %-12s %-12s${_ui_nc}\n" "Setting" "Local" "Import"
    _ui_separator 54

    local remote_modules=$(jq -r '.modules | to_entries[] | "\(.key)=\(.value)"' "$input")
    echo "$remote_modules" | while IFS='=' read -r mod val; do
        [[ -z "$mod" ]] && continue
        local var="ZANVIL_MODULE_$mod"
        local local_val=$(grep "^${var}=" "$config_file" 2>/dev/null | cut -d= -f2)
        [[ -z "$local_val" ]] && local_val="(absent)"

        if [[ "$local_val" != "$val" ]]; then
            printf "  ${_ui_yellow}%-28s${_ui_nc} %-12s ${_ui_cyan}%-12s${_ui_nc}\n" "$var" "$local_val" "$val"
            ((diffs++))
        else
            printf "  ${_ui_dim}%-28s %-12s %-12s${_ui_nc}\n" "$var" "$local_val" "$val"
        fi
    done

    # Theme
    local remote_theme=$(jq -r '.theme // empty' "$input")
    local local_theme=""
    [[ -f "$ZANVIL_DIR/.current_theme" ]] && local_theme=$(<"$ZANVIL_DIR/.current_theme")

    if [[ "$local_theme" != "$remote_theme" ]]; then
        printf "  ${_ui_yellow}%-28s${_ui_nc} %-12s ${_ui_cyan}%-12s${_ui_nc}\n" "theme" "${local_theme:-default}" "$remote_theme"
        ((diffs++))
    else
        printf "  ${_ui_dim}%-28s %-12s %-12s${_ui_nc}\n" "theme" "${local_theme:-default}" "$remote_theme"
    fi

    echo ""
    if [[ $diffs -gt 0 ]]; then
        printf "${_ui_yellow}%d${_ui_nc} difference(s)  ${_ui_dim}(zanvil-sync import $input)${_ui_nc}\n" "$diffs"
    else
        _ui_msg_ok "Configurations identiques"
    fi
}

# ==============================================================================
# Aide
# ==============================================================================
_zanvil_sync_help() {
    _ui_header "Zanvil Sync"
    echo ""
    printf "${_ui_bold}Usage:${_ui_nc}\n"
    echo "  zanvil-sync export [fichier]    Exporter la config (defaut: sync.json)"
    echo "  zanvil-sync import <fichier>    Importer une config"
    echo "  zanvil-sync diff <fichier>      Comparer avec la config locale"
    echo ""
    printf "${_ui_bold}Contenu exporte:${_ui_nc}\n"
    echo "  Modules actifs, theme, plugins, auto-update, theme dark/light"
    echo ""
    printf "${_ui_bold}Exclut:${_ui_nc} secrets, tokens, paths absolus\n"
}
