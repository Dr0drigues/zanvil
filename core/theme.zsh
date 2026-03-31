# ==============================================================================
# core/theme.zsh — Gestion des themes (Starship et Ghostty)
# ==============================================================================
# Fonctions : zsh-env-theme, zsh-env-ghostty
# Utilise les fonctions UI de ui.zsh (charge automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zsh-env-theme : Gestion des themes Starship
# ==============================================================================
zsh-env-theme() {
    # Delegation au CLI Rust si disponible
    if command -v zsh-env-cli &>/dev/null; then
        zsh-env-cli theme "$@"
        local rc=$?
        # Sourcer la palette pour la session courante apres apply
        if [[ $rc -eq 0 && "$1" != "list" && "$1" != "current" && -n "$1" ]]; then
            local _p="$ZSH_ENV_DIR/themes/$1/palette.zsh"
            [[ -f "$_p" ]] && source "$_p"
        fi
        return $rc
    fi

    # --- Fallback zsh ---
    local themes_dir="$ZSH_ENV_DIR/themes"
    local starship_config="$HOME/.config/starship.toml"
    local state_file="$ZSH_ENV_DIR/.current_theme"
    local theme="$1"

    if ! command -v starship &> /dev/null; then
        _ui_msg_fail "Starship n'est pas installe."
        return 1
    fi

    # Sans argument ou "list" : afficher les themes disponibles
    if [[ -z "$theme" ]] || [[ "$theme" = "list" ]]; then
        _ui_header "Themes Starship"

        # Theme actuel depuis le fichier d'etat
        local current=""
        [[ -f "$state_file" ]] && current=$(<"$state_file")

        # Collecter les noms de themes (directory + flat, sans doublons)
        local -a theme_names=()
        # Directory themes
        for d in "$themes_dir"/*/prompt.toml(N); do
            theme_names+=($(basename $(dirname "$d")))
        done
        # Flat themes (skip si version directory existe)
        for f in "$themes_dir"/*.toml(N); do
            local name=$(basename "$f" .toml)
            (( ${theme_names[(Ie)$name]} )) || theme_names+=($name)
        done

        for name in ${(o)theme_names}; do
            local desc="" toml_file=""
            if [[ -f "$themes_dir/$name/prompt.toml" ]]; then
                toml_file="$themes_dir/$name/prompt.toml"
            else
                toml_file="$themes_dir/$name.toml"
            fi
            desc=$(grep -m1 "^# Starship Theme:" "$toml_file" 2>/dev/null | sed 's/^# Starship Theme: //')

            # Indicateur palette
            local palette_tag=""
            [[ -f "$themes_dir/$name/palette.zsh" ]] && palette_tag=" ${_ui_magenta}[palette]${_ui_nc}"

            if [[ "$name" = "$current" ]]; then
                echo -e "  ${_ui_green}*${_ui_nc} ${_ui_bold}$name${_ui_nc} - $desc ${_ui_cyan}(actif)${_ui_nc}$palette_tag"
            else
                echo -e "  ${_ui_cyan}${_ui_circle}${_ui_nc} $name - $desc$palette_tag"
            fi
        done

        echo ""
        echo -e "  ${_ui_dim}Usage: zsh-env-theme <nom>${_ui_nc}"
        return 0
    fi

    # Resoudre le theme (directory > flat)
    local toml_source=""
    if [[ -f "$themes_dir/$theme/prompt.toml" ]]; then
        toml_source="$themes_dir/$theme/prompt.toml"
    elif [[ -f "$themes_dir/$theme.toml" ]]; then
        toml_source="$themes_dir/$theme.toml"
    else
        _ui_msg_fail "Theme '$theme' non trouve."
        return 1
    fi

    mkdir -p "$HOME/.config"

    # Backup si config existante non geree
    if [[ -f "$starship_config" ]]; then
        if ! grep -q "^# Starship Theme:" "$starship_config" 2>/dev/null; then
            cp "$starship_config" "$starship_config.backup"
            _ui_msg_info "Backup: $starship_config.backup"
        fi
    fi

    # Appliquer
    cp "$toml_source" "$starship_config"
    echo "$theme" > "$state_file"

    # Sourcer la palette si disponible
    local palette="$themes_dir/$theme/palette.zsh"
    if [[ -f "$palette" ]]; then
        source "$palette"
        _ui_tag_ok "Theme '$theme' applique (prompt + palette)"
    else
        _ui_tag_ok "Theme '$theme' applique"
    fi
    _ui_msg_info "Rechargez avec ${_ui_bold}ss${_ui_nc} pour voir les changements."
}

# ==============================================================================
# zsh-env-ghostty : Gestion des themes Ghostty
# ==============================================================================
zsh-env-ghostty() {
    local themes_dir="$ZSH_ENV_DIR/ghostty/themes"
    local ghostty_config="$HOME/.config/ghostty/config"
    local theme="$1"

    # Sans argument ou "list" : afficher les themes disponibles
    if [[ -z "$theme" ]] || [[ "$theme" = "list" ]]; then
        _zsh_header "Themes Ghostty"

        if [[ ! -d "$themes_dir" ]]; then
            echo -e "${_zsh_cmd_yellow}Aucun theme trouve dans $themes_dir${_zsh_cmd_nc}"
            return 1
        fi

        # Theme actuel (lit la ligne config-file de la config Ghostty)
        local current=""
        if [[ -f "$ghostty_config" ]]; then
            current=$(grep "^config-file" "$ghostty_config" 2>/dev/null | sed 's/.*themes\///' | tr -d ' ')
        fi

        for theme_file in "$themes_dir"/*; do
            [[ -f "$theme_file" ]] || continue
            local name=$(basename "$theme_file")
            local desc=$(grep -m1 "^# Ghostty Theme:" "$theme_file" 2>/dev/null | sed 's/^# Ghostty Theme: //' || echo "")

            if [[ "$name" = "$current" ]]; then
                echo -e "  ${_zsh_cmd_green}*${_zsh_cmd_nc} ${_zsh_cmd_bold}$name${_zsh_cmd_nc} - $desc ${_zsh_cmd_cyan}(actif)${_zsh_cmd_nc}"
            else
                echo -e "  ${_zsh_cmd_cyan}○${_zsh_cmd_nc} $name - $desc"
            fi
        done

        echo ""
        echo -e "${_zsh_cmd_dim}Usage: zsh-env-ghostty <nom>${_zsh_cmd_nc}"
        echo -e "${_zsh_cmd_dim}Sync:  zsh-env-ghostty sync${_zsh_cmd_nc}"
        return 0
    fi

    # Commande "sync" : déployer la config de zsh_env vers ~/.config/ghostty
    if [[ "$theme" = "sync" ]]; then
        local src_config="$ZSH_ENV_DIR/ghostty/config"
        local dest_dir="$HOME/.config/ghostty"

        if [[ ! -f "$src_config" ]]; then
            echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Config source non trouvee: $src_config"
            return 1
        fi

        mkdir -p "$dest_dir"

        # Backup si existe et différent
        if [[ -f "$ghostty_config" ]] && ! diff -q "$src_config" "$ghostty_config" &>/dev/null; then
            cp "$ghostty_config" "$ghostty_config.backup"
            echo -e "${_zsh_cmd_cyan}[INFO]${_zsh_cmd_nc} Backup: $ghostty_config.backup"
        fi

        # Copier config et themes
        cp "$src_config" "$ghostty_config"
        cp -r "$themes_dir" "$dest_dir/"

        echo -e "${_zsh_cmd_green}[OK]${_zsh_cmd_nc} Config Ghostty synchronisee vers $dest_dir"
        echo -e "${_zsh_cmd_cyan}[INFO]${_zsh_cmd_nc} Redemarrez Ghostty pour appliquer les changements."
        return 0
    fi

    # Appliquer un theme
    local theme_file="$themes_dir/$theme"

    if [[ ! -f "$theme_file" ]]; then
        echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Theme '$theme' non trouve."
        echo -e "Themes disponibles: $(ls "$themes_dir" 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    # Mettre à jour le fichier config local (dans zsh_env)
    local local_config="$ZSH_ENV_DIR/ghostty/config"

    if [[ -f "$local_config" ]]; then
        # Remplacer la ligne config-file
        if grep -q "^config-file" "$local_config"; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|^config-file.*|config-file = themes/$theme|" "$local_config"
            else
                sed -i "s|^config-file.*|config-file = themes/$theme|" "$local_config"
            fi
        else
            echo "config-file = themes/$theme" >> "$local_config"
        fi
    fi

    echo -e "${_zsh_cmd_green}[OK]${_zsh_cmd_nc} Theme '$theme' selectionne."
    echo -e "Lancez ${_zsh_cmd_bold}zsh-env-ghostty sync${_zsh_cmd_nc} pour deployer vers ~/.config/ghostty"
}
