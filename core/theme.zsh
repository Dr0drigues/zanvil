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
    local themes_dir="$ZSH_ENV_DIR/themes"
    local starship_config="$HOME/.config/starship.toml"
    local theme="$1"

    # Vérifier que Starship est installé
    if ! command -v starship &> /dev/null; then
        echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Starship n'est pas installe."
        return 1
    fi

    # Sans argument ou "list" : afficher les themes disponibles
    if [[ -z "$theme" ]] || [[ "$theme" = "list" ]]; then
        _zsh_header "Themes Starship"

        if [[ ! -d "$themes_dir" ]]; then
            echo -e "${_zsh_cmd_yellow}Aucun theme trouve dans $themes_dir${_zsh_cmd_nc}"
            return 1
        fi

        # Theme actuel
        local current=""
        if [[ -f "$starship_config" ]]; then
            current=$(head -1 "$starship_config" 2>/dev/null | sed -n 's/.*Theme: \([a-zA-Z0-9_-]*\).*/\1/p' || echo "")
        fi

        for theme_file in "$themes_dir"/*.toml; do
            [[ -f "$theme_file" ]] || continue
            local name=$(basename "$theme_file" .toml)
            local desc=$(grep -m1 "^# Starship Theme:" "$theme_file" 2>/dev/null | sed 's/^# Starship Theme: //' || echo "")

            if [[ "$name" = "$current" ]]; then
                echo -e "  ${_zsh_cmd_green}*${_zsh_cmd_nc} ${_zsh_cmd_bold}$name${_zsh_cmd_nc} - $desc ${_zsh_cmd_cyan}(actif)${_zsh_cmd_nc}"
            else
                echo -e "  ${_zsh_cmd_cyan}○${_zsh_cmd_nc} $name - $desc"
            fi
        done

        echo ""
        echo -e "${_zsh_cmd_dim}Usage: zsh-env-theme <nom>${_zsh_cmd_nc}"
        return 0
    fi

    # Appliquer un theme
    local theme_file="$themes_dir/$theme.toml"

    if [[ ! -f "$theme_file" ]]; then
        echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Theme '$theme' non trouve."
        echo -e "Themes disponibles: $(ls "$themes_dir"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/.toml//' | tr '\n' ' ')"
        return 1
    fi

    # Créer le dossier .config si nécessaire
    mkdir -p "$HOME/.config"

    # Backup de l'ancienne config si elle existe et n'est pas un de nos themes
    if [[ -f "$starship_config" ]]; then
        if ! grep -q "^# Starship Theme:" "$starship_config" 2>/dev/null; then
            cp "$starship_config" "$starship_config.backup"
            echo -e "${_zsh_cmd_cyan}[INFO]${_zsh_cmd_nc} Backup de l'ancienne config: $starship_config.backup"
        fi
    fi

    # Copier le theme
    cp "$theme_file" "$starship_config"

    echo -e "${_zsh_cmd_green}[OK]${_zsh_cmd_nc} Theme '$theme' applique."
    echo -e "Rechargez avec ${_zsh_cmd_bold}ss${_zsh_cmd_nc} pour voir les changements."
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
