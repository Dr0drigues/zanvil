# ==============================================================================
# core/admin.zsh — Fonctions d'administration ZSH_ENV
# ==============================================================================
# Fonctions : zsh-env-completions, zsh-env-completion-add,
#             zsh-env-completion-remove, zsh-env-modules, zsh-env-backup,
#             zsh-env-restore, zsh-env-config-reset
# Utilise les fonctions UI de ui.zsh (charge automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zsh-env-completion-add : Ajouter une completion personnalisee
# ==============================================================================
zsh-env-completion-add() {
    local name="$1"
    local cmd="$2"

    if [[ -z "$name" ]] || [[ -z "$cmd" ]]; then
        echo -e "${_zsh_cmd_bold}Usage:${_zsh_cmd_nc} zsh-env-completion-add <nom> <commande>"
        echo ""
        echo -e "${_zsh_cmd_cyan}Exemples:${_zsh_cmd_nc}"
        echo "  zsh-env-completion-add bun \"bun completions\""
        echo "  zsh-env-completion-add deno \"deno completions zsh\""
        echo "  zsh-env-completion-add turbo \"turbo completion zsh\""
        echo ""
        echo -e "Les completions sont stockees dans: ${_zsh_cmd_bold}~/.zsh_env/completions.zsh${_zsh_cmd_nc}"
        return 1
    fi

    local config_file="$ZSH_ENV_DIR/completions.zsh"

    # Vérifier si la completion existe déjà
    if grep -q "\"$name:" "$config_file" 2>/dev/null; then
        echo -e "${_zsh_cmd_yellow}[WARN]${_zsh_cmd_nc} La completion '$name' existe deja."
        return 1
    fi

    # Ajouter la completion au fichier
    # On insère avant la parenthèse fermante
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS : sed -i nécessite une extension explicite
        sed -i '' '/^)$/i\
    "'"$name:$cmd"'"
' "$config_file"
    else
        # Linux
        sed -i '/^)$/i\    "'"$name:$cmd"'"' "$config_file"
    fi

    echo -e "${_zsh_cmd_green}[OK]${_zsh_cmd_nc} Completion '$name' ajoutee."
    echo -e "Lancez ${_zsh_cmd_bold}zsh-env-completions${_zsh_cmd_nc} pour la charger."
}

# ==============================================================================
# zsh-env-completion-remove : Supprimer une completion personnalisee
# ==============================================================================
zsh-env-completion-remove() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo -e "${_zsh_cmd_bold}Usage:${_zsh_cmd_nc} zsh-env-completion-remove <nom>"
        echo ""
        # Lister les completions disponibles
        local config_file="$ZSH_ENV_DIR/completions.zsh"
        if [[ -f "$config_file" ]]; then
            local available
            available=$(grep -oP '"\K[^:]+(?=:)' "$config_file" 2>/dev/null)
            if [[ -n "$available" ]]; then
                echo -e "${_zsh_cmd_cyan}Completions installees:${_zsh_cmd_nc}"
                echo "$available" | while read -r comp; do
                    echo "  $comp"
                done
            fi
        fi
        return 1
    fi

    local config_file="$ZSH_ENV_DIR/completions.zsh"

    if ! grep -q "\"$name:" "$config_file" 2>/dev/null; then
        echo -e "${_zsh_cmd_yellow}[WARN]${_zsh_cmd_nc} La completion '$name' n'existe pas."
        return 1
    fi

    # Supprimer la ligne contenant cette completion
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/\"$name:/d" "$config_file"
    else
        sed -i "/\"$name:/d" "$config_file"
    fi

    echo -e "${_zsh_cmd_green}[OK]${_zsh_cmd_nc} Completion '$name' supprimee."
}

# ==============================================================================
# zsh-env-completions : Charger les auto-completions
# ==============================================================================
zsh-env-completions() {
    # Initialiser le système de completion AVANT de charger les completions
    autoload -Uz compinit && compinit -u -C

    _zsh_header "ZSH_ENV Completions"

    local loaded=0

    # Docker
    if command -v docker &> /dev/null; then
        if docker completion zsh &> /dev/null; then
            source <(docker completion zsh)
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Docker"
            ((loaded++))
        fi
    fi

    # kubectl
    if command -v kubectl &> /dev/null; then
        source <(kubectl completion zsh)
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Kubectl"
        ((loaded++))
    fi

    # helm
    if command -v helm &> /dev/null; then
        source <(helm completion zsh)
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Helm"
        ((loaded++))
    fi

    # gh (GitHub CLI)
    if command -v gh &> /dev/null; then
        source <(gh completion -s zsh)
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} GitHub CLI"
        ((loaded++))
    fi

    # glab (GitLab CLI)
    if command -v glab &> /dev/null; then
        source <(glab completion -s zsh)
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} GitLab CLI"
        ((loaded++))
    fi

    # terraform
    if command -v terraform &> /dev/null; then
        complete -o nospace -C terraform terraform
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Terraform"
        ((loaded++))
    fi

    # aws
    if command -v aws_completer &> /dev/null; then
        complete -C aws_completer aws
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} AWS CLI"
        ((loaded++))
    fi

    # gcloud
    if [[ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]]; then
        source "$HOME/google-cloud-sdk/completion.zsh.inc"
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Google Cloud SDK"
        ((loaded++))
    fi

    # npm (eval au lieu de source pour éviter l'erreur _arguments)
    if command -v npm &> /dev/null; then
        eval "$(npm completion 2>/dev/null)" 2>/dev/null
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} npm"
        ((loaded++))
    fi

    # pnpm
    if command -v pnpm &> /dev/null; then
        source <(pnpm completion zsh 2>/dev/null)
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} pnpm"
        ((loaded++))
    fi

    # rustup & cargo
    if command -v rustup &> /dev/null; then
        { source <(rustup completions zsh 2>/dev/null); } 2>/dev/null
        { source <(rustup completions zsh cargo 2>/dev/null); } 2>/dev/null
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Rustup/Cargo"
        ((loaded++))
    fi

    # Completions personnalisées
    local custom_file="$ZSH_ENV_DIR/completions.zsh"
    if [[ -f "$custom_file" ]]; then
        source "$custom_file"

        local custom_loaded=0
        for entry in "${_ZSH_ENV_CUSTOM_COMPLETIONS[@]}"; do
            # Ignorer les lignes vides ou commentées
            [[ -z "$entry" || "$entry" == \#* ]] && continue

            local name="${entry%%:*}"
            local cmd="${entry#*:}"

            if command -v "$name" &> /dev/null; then
                # Capture la sortie de la commande puis eval avec stderr supprimé
                local comp_script=""
                comp_script="$(${(z)cmd} 2>/dev/null)"
                if [[ -n "$comp_script" ]]; then
                    { eval "$comp_script"; } 2>/dev/null
                    echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} $name ${_zsh_cmd_cyan}(custom)${_zsh_cmd_nc}"
                    ((loaded++))
                    ((custom_loaded++))
                else
                    echo -e "  ${_zsh_cmd_red}✗${_zsh_cmd_nc} $name ${_zsh_cmd_yellow}(erreur)${_zsh_cmd_nc}"
                fi
            fi
        done

        if [[ $custom_loaded -gt 0 ]]; then
            echo -e "\n  ${_zsh_cmd_dim}$custom_loaded completion(s) personnalisee(s)${_zsh_cmd_nc}"
        fi
    fi

    echo ""
    _zsh_separator 44
    echo -e "${_zsh_cmd_green}$loaded${_zsh_cmd_nc} completions chargees"

}

# ==============================================================================
# zsh-env-modules : Gestion des modules
# ==============================================================================
zsh-env-modules() {
    if command -v zsh-env-cli &>/dev/null; then
        zsh-env-cli modules "$@"; return $?
    fi
    local config_file="${ZSH_ENV_DIR:-$HOME/.zsh_env}/config.zsh"

    # Description de chaque module
    typeset -A module_desc
    module_desc=(
        [GITLAB]="Alias GitLab, clone groupes, statut PAT"
        [DOCKER]="Utilitaires Docker (dex, dstop)"
        [MISE]="Gestionnaire de versions (Node, Java...)"
        [NUSHELL]="Integration Nushell (nush, nuc)"
        [KUBE]="Gestion kubeconfig (kube_select, Azure/AWS/GCP)"
    )

    local action="${1:-list}"
    local module_name="${2:u}" # uppercase

    case "$action" in
        list|ls)
            _ui_header "Modules ZSH_ENV"
            printf "${_ui_bold}%-12s %-8s %s${_ui_nc}\n" "Module" "Statut" "Description"
            _ui_separator

            for mod in GITLAB DOCKER MISE NUSHELL KUBE; do
                local var_name="ZSH_ENV_MODULE_${mod}"
                local mod_state="${(P)var_name}"
                local desc="${module_desc[$mod]}"
                if [[ "$mod_state" == "true" ]]; then
                    printf "  %-10s ${_ui_green}%-8s${_ui_nc} ${_ui_dim}%s${_ui_nc}\n" "$mod" "actif" "$desc"
                else
                    printf "  %-10s ${_ui_red}%-8s${_ui_nc} ${_ui_dim}%s${_ui_nc}\n" "$mod" "inactif" "$desc"
                fi
            done
            _ui_separator
            echo -e "  ${_ui_dim}Modifier: zsh-env-modules enable|disable <module>${_ui_nc}"
            ;;

        enable|on)
            if [[ -z "$module_name" ]]; then
                _ui_msg_fail "Usage: zsh-env-modules enable <module>"
                return 1
            fi
            if [[ -z "${module_desc[$module_name]}" ]]; then
                _ui_msg_fail "Module inconnu: $module_name"
                _ui_msg_info "Modules disponibles: ${(kj:, :)module_desc}"
                return 1
            fi
            if [[ ! -f "$config_file" ]]; then
                _ui_msg_fail "Fichier config introuvable: $config_file"
                return 1
            fi
            if [[ "$OSTYPE" == darwin* ]]; then
                sed -i '' "s/^ZSH_ENV_MODULE_${module_name}=.*/ZSH_ENV_MODULE_${module_name}=true/" "$config_file"
            else
                sed -i "s/^ZSH_ENV_MODULE_${module_name}=.*/ZSH_ENV_MODULE_${module_name}=true/" "$config_file"
            fi
            _ui_msg_ok "Module $module_name active"
            _ui_msg_info "Rechargez avec: ss"
            ;;

        disable|off)
            if [[ -z "$module_name" ]]; then
                _ui_msg_fail "Usage: zsh-env-modules disable <module>"
                return 1
            fi
            if [[ -z "${module_desc[$module_name]}" ]]; then
                _ui_msg_fail "Module inconnu: $module_name"
                _ui_msg_info "Modules disponibles: ${(kj:, :)module_desc}"
                return 1
            fi
            if [[ ! -f "$config_file" ]]; then
                _ui_msg_fail "Fichier config introuvable: $config_file"
                return 1
            fi
            if [[ "$OSTYPE" == darwin* ]]; then
                sed -i '' "s/^ZSH_ENV_MODULE_${module_name}=.*/ZSH_ENV_MODULE_${module_name}=false/" "$config_file"
            else
                sed -i "s/^ZSH_ENV_MODULE_${module_name}=.*/ZSH_ENV_MODULE_${module_name}=false/" "$config_file"
            fi
            _ui_msg_ok "Module $module_name desactive"
            _ui_msg_info "Rechargez avec: ss"
            ;;

        *)
            _ui_msg_fail "Action inconnue: $action"
            echo "Usage: zsh-env-modules [list|enable|disable] [module]"
            return 1
            ;;
    esac
}

# ==============================================================================
# zsh-env-backup / zsh-env-restore : Sauvegarde et restauration
# ==============================================================================
zsh-env-backup() {
    local backup_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local dest="$backup_dir/$timestamp"

    mkdir -p "$dest"

    # Fichiers a sauvegarder
    local -a files=(
        "${ZSH_ENV_DIR:-$HOME/.zsh_env}/config.zsh"
        "${ZSH_ENV_DIR:-$HOME/.zsh_env}/completions.zsh"
        "$HOME/.secrets"
        "$HOME/.gitlab_secrets"
    )

    _ui_header "ZSH_ENV Backup"

    local count=0
    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            cp "$f" "$dest/"
            chmod 600 "$dest/$(basename "$f")"
            _ui_msg_ok "$(basename "$f")"
            ((count++))
        else
            echo -e "  ${_ui_dim}$(basename "$f") (absent)${_ui_nc}"
        fi
    done

    _ui_separator
    if [[ $count -gt 0 ]]; then
        _ui_msg_ok "$count fichier(s) sauvegarde(s) dans $dest"
    else
        _ui_msg_warn "Aucun fichier a sauvegarder"
        rmdir "$dest" 2>/dev/null
    fi
}

zsh-env-restore() {
    local backup_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}/backups"

    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        _ui_msg_fail "Aucun backup disponible dans $backup_dir"
        return 1
    fi

    _ui_header "ZSH_ENV Restore"

    local selected="$1"

    if [[ -z "$selected" ]]; then
        # Selection interactive
        local -a backups
        backups=($(ls -1r "$backup_dir"))

        if command -v fzf &>/dev/null; then
            selected=$(printf '%s\n' "${backups[@]}" | fzf --header="Choisir un backup" --prompt="Restore > ")
        else
            _ui_msg_info "Backups disponibles:"
            local i=1
            for b in "${backups[@]}"; do
                local file_count=$(ls -1 "$backup_dir/$b" 2>/dev/null | wc -l | tr -d ' ')
                printf "  ${_ui_bold}%d)${_ui_nc} %s ${_ui_dim}(%s fichiers)${_ui_nc}\n" $i "$b" "$file_count"
                ((i++))
            done
            echo ""
            echo -n "Numero: "
            read choice
            [[ "$choice" =~ ^[0-9]+$ ]] && selected="${backups[$choice]}"
        fi
    fi

    [[ -z "$selected" ]] && return 0

    local src="$backup_dir/$selected"
    if [[ ! -d "$src" ]]; then
        _ui_msg_fail "Backup introuvable: $selected"
        return 1
    fi

    _ui_msg_info "Restauration depuis $selected:"
    echo ""

    for f in "$src"/*; do
        local name="$(basename "$f")"
        local target

        case "$name" in
            config.zsh|completions.zsh)
                target="${ZSH_ENV_DIR:-$HOME/.zsh_env}/$name" ;;
            .secrets|.gitlab_secrets)
                target="$HOME/$name" ;;
            *)
                target="${ZSH_ENV_DIR:-$HOME/.zsh_env}/$name" ;;
        esac

        if [[ -f "$target" ]]; then
            local diff_out=$(diff "$target" "$f" 2>/dev/null)
            if [[ -z "$diff_out" ]]; then
                echo -e "  ${_ui_dim}$name (identique)${_ui_nc}"
                continue
            fi
        fi

        cp "$f" "$target"
        chmod 600 "$target"
        _ui_msg_ok "$name → $target"
    done

    _ui_separator
    _ui_msg_info "Rechargez avec: ss"
}

# ==============================================================================
# zsh-env-config-reset : Restaurer la config par defaut
# ==============================================================================
zsh-env-config-reset() {
    local config_file="${ZSH_ENV_DIR:-$HOME/.zsh_env}/config.zsh"
    local default_file="${ZSH_ENV_DIR:-$HOME/.zsh_env}/config.zsh.example"

    if [[ ! -f "$default_file" ]]; then
        _ui_msg_fail "Template introuvable: $default_file"
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        cp "$default_file" "$config_file"
        _ui_msg_ok "Config creee depuis le template"
        return 0
    fi

    # Afficher les differences
    local diff_output
    diff_output=$(diff "$config_file" "$default_file" 2>/dev/null)
    if [[ -z "$diff_output" ]]; then
        _ui_msg_ok "La config est deja aux valeurs par defaut"
        return 0
    fi

    _ui_msg_warn "Differences detectees:"
    echo "$diff_output"
    echo ""

    local response
    read -q "response?Restaurer aux valeurs par defaut ? [y/N] "
    echo ""
    if [[ "$response" != "y" ]]; then
        _ui_msg_info "Annule."
        return 0
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp "$config_file" "${config_file}.bak.${timestamp}"
    cp "$default_file" "$config_file"
    _ui_msg_ok "Config restauree (backup: config.zsh.bak.${timestamp})"
    _ui_msg_info "Rechargez avec: ss"
}

# ==============================================================================
# zsh-env-switch : Switch rapide d'environnement
# ==============================================================================
# Combine kubeconfig + variables en un seul geste
# Profiles definis dans ~/.zsh_env/profiles/*.zsh
zsh-env-switch() {
    local profiles_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}/profiles"
    local profile="$1"

    if [[ ! -d "$profiles_dir" ]]; then
        mkdir -p "$profiles_dir"
    fi

    # Sans argument : selection interactive
    if [[ -z "$profile" ]] || [[ "$profile" == "list" ]]; then
        _ui_header "Environnements"

        local -a profiles=()
        for f in "$profiles_dir"/*.zsh(N); do
            profiles+=($(basename "$f" .zsh))
        done

        if [[ ${#profiles[@]} -eq 0 ]]; then
            _ui_msg_info "Aucun profil configure dans $profiles_dir"
            echo ""
            echo -e "  ${_ui_dim}Creez un fichier .zsh dans profiles/ :"
            echo -e "  Exemple: profiles/blg-dev.zsh${_ui_nc}"
            echo ""
            echo -e "  ${_ui_dim}Contenu type :${_ui_nc}"
            echo -e "  ${_ui_dim}  export KUBECONFIG=~/.kube/configs.d/blg-dev.yml${_ui_nc}"
            echo -e "  ${_ui_dim}  kubectl config use-context blg-dev${_ui_nc}"
            return 0
        fi

        if command -v fzf &>/dev/null; then
            profile=$(printf '%s\n' "${profiles[@]}" | fzf --header="Choisir un environnement" --prompt="Switch > ")
            [[ -z "$profile" ]] && return 0
        else
            _ui_msg_info "Profils disponibles:"
            local i=1
            for p in "${profiles[@]}"; do
                printf "  ${_ui_bold}%d)${_ui_nc} %s\n" $i "$p"
                ((i++))
            done
            echo ""
            echo -n "Numero: "
            read choice
            [[ "$choice" =~ ^[0-9]+$ ]] && profile="${profiles[$choice]}"
            [[ -z "$profile" ]] && return 0
        fi
    fi

    local profile_file="$profiles_dir/${profile}.zsh"
    if [[ ! -f "$profile_file" ]]; then
        _ui_msg_fail "Profil '$profile' introuvable ($profile_file)"
        return 1
    fi

    source "$profile_file"
    _ui_msg_ok "Environnement '$profile' active"
}
