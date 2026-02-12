# ==============================================================================
# Security Audit - Verification de la securite des configs
# ==============================================================================
# Verifie les permissions, detecte les problemes potentiels
# Utilise les fonctions UI de ui.zsh (charge automatiquement)
# ==============================================================================

# Audit principal
zsh-env-audit() {
    _zsh_header "ZSH_ENV Security Audit"

    local issues=0
    local warnings=0

    # --- SSH ---
    local ssh_status=""
    if [[ -d "$HOME/.ssh" ]]; then
        local ssh_perms=$(_ui_get_perms "$HOME/.ssh")
        if [[ "$ssh_perms" == "700" ]]; then
            ssh_status+="~/.ssh ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        else
            ssh_status+="~/.ssh ${_zsh_cmd_red}✗${_zsh_cmd_nc}${_zsh_cmd_dim}$ssh_perms${_zsh_cmd_nc}  "
            ((issues++))
        fi

        # Clés privées
        for key in "$HOME/.ssh"/id_*(N) "$HOME/.ssh"/*.pem(N); do
            [[ ! -f "$key" ]] && continue
            [[ "$key" == *.pub ]] && continue
            local name=$(basename "$key")
            local perms=$(_ui_get_perms "$key")
            if [[ "$perms" == "600" || "$perms" == "400" ]]; then
                ssh_status+="$name ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
            else
                ssh_status+="$name ${_zsh_cmd_red}✗${_zsh_cmd_nc}${_zsh_cmd_dim}$perms${_zsh_cmd_nc}  "
                ((issues++))
            fi
        done

        # Config SSH
        if [[ -f "$HOME/.ssh/config" ]]; then
            local perms=$(_ui_get_perms "$HOME/.ssh/config")
            if [[ "$perms" == "600" || "$perms" == "644" ]]; then
                ssh_status+="config ${_zsh_cmd_green}✓${_zsh_cmd_nc}"
            else
                ssh_status+="config ${_zsh_cmd_red}✗${_zsh_cmd_nc}${_zsh_cmd_dim}$perms${_zsh_cmd_nc}"
                ((issues++))
            fi
        fi
    else
        ssh_status+="${_zsh_cmd_dim}non configure${_zsh_cmd_nc}"
    fi
    _zsh_section "SSH" "$ssh_status"

    # --- Secrets ---
    local secrets_status=""
    local secret_files=(".secrets" ".gitlab_secrets" ".env" ".netrc" ".npmrc" ".pypirc")
    local secrets_found=0

    for secret in "${secret_files[@]}"; do
        local file="$HOME/$secret"
        if [[ -f "$file" ]]; then
            ((secrets_found++))
            local perms=$(_ui_get_perms "$file")
            if [[ "$perms" == "600" || "$perms" == "400" ]]; then
                secrets_status+="$secret ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
            else
                secrets_status+="$secret ${_zsh_cmd_red}✗${_zsh_cmd_nc}${_zsh_cmd_dim}$perms${_zsh_cmd_nc}  "
                ((issues++))
            fi
        fi
    done

    if [[ $secrets_found -eq 0 ]]; then
        secrets_status="${_zsh_cmd_dim}aucun${_zsh_cmd_nc}"
    fi
    _zsh_section "Secrets" "$secrets_status"

    # --- Kubernetes ---
    local kube_status=""
    if [[ -d "$HOME/.kube" ]]; then
        local kube_perms=$(_ui_get_perms "$HOME/.kube")
        if [[ "$kube_perms" == "700" ]]; then
            kube_status+="~/.kube ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        else
            kube_status+="~/.kube ${_zsh_cmd_yellow}○${_zsh_cmd_nc}${_zsh_cmd_dim}$kube_perms${_zsh_cmd_nc}  "
            ((warnings++))
        fi

        # Config principale
        if [[ -f "$HOME/.kube/config" ]]; then
            local perms=$(_ui_get_perms "$HOME/.kube/config")
            if [[ "$perms" == "600" || "$perms" == "400" ]]; then
                kube_status+="config ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
            else
                kube_status+="config ${_zsh_cmd_yellow}○${_zsh_cmd_nc}${_zsh_cmd_dim}$perms${_zsh_cmd_nc}  "
                ((warnings++))
            fi
        fi

        # Configs.d count
        if [[ -d "$HOME/.kube/configs.d" ]]; then
            local config_count=$(find "$HOME/.kube/configs.d" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
            [[ $config_count -gt 0 ]] && kube_status+="${_zsh_cmd_dim}${config_count} configs.d/${_zsh_cmd_nc}"
        fi
    else
        kube_status="${_zsh_cmd_dim}non configure${_zsh_cmd_nc}"
    fi
    _zsh_section "Kubernetes" "$kube_status"

    # --- Git ---
    local git_status=""
    if [[ -f "$HOME/.gitconfig" ]]; then
        local helper=$(git config --global credential.helper 2>/dev/null)
        if [[ -n "$helper" ]]; then
            git_status+="credential.helper ${_zsh_cmd_green}✓${_zsh_cmd_nc}${_zsh_cmd_dim}$helper${_zsh_cmd_nc}  "
        else
            git_status+="credential.helper ${_zsh_cmd_yellow}○${_zsh_cmd_nc}  "
            ((warnings++))
        fi
    fi

    if [[ -f "$HOME/.git-credentials" ]]; then
        git_status+="${_zsh_cmd_yellow}.git-credentials${_zsh_cmd_nc} ${_zsh_cmd_dim}(clair)${_zsh_cmd_nc}"
        ((warnings++))
    fi

    [[ -z "$git_status" ]] && git_status="${_zsh_cmd_dim}non configure${_zsh_cmd_nc}"
    _zsh_section "Git" "$git_status"

    # --- Cloud ---
    local cloud_status=""

    # AWS
    if [[ -f "$HOME/.aws/credentials" ]]; then
        local perms=$(_ui_get_perms "$HOME/.aws/credentials")
        if [[ "$perms" == "600" ]]; then
            cloud_status+="AWS ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        else
            cloud_status+="AWS ${_zsh_cmd_red}✗${_zsh_cmd_nc}${_zsh_cmd_dim}$perms${_zsh_cmd_nc}  "
            ((issues++))
        fi
    else
        cloud_status+="${_zsh_cmd_dim}AWS ○${_zsh_cmd_nc}  "
    fi

    # Azure
    if [[ -d "$HOME/.azure" ]]; then
        cloud_status+="Azure ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
    else
        cloud_status+="${_zsh_cmd_dim}Azure ○${_zsh_cmd_nc}  "
    fi

    # GCP
    if [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
        local perms=$(_ui_get_perms "$HOME/.config/gcloud/application_default_credentials.json")
        if [[ "$perms" == "600" ]]; then
            cloud_status+="GCP ${_zsh_cmd_green}✓${_zsh_cmd_nc}"
        else
            cloud_status+="GCP ${_zsh_cmd_red}✗${_zsh_cmd_nc}${_zsh_cmd_dim}$perms${_zsh_cmd_nc}"
            ((issues++))
        fi
    else
        cloud_status+="${_zsh_cmd_dim}GCP ○${_zsh_cmd_nc}"
    fi
    _zsh_section "Cloud" "$cloud_status"

    # --- History ---
    local history_status=""
    local history_files=(".zsh_history" ".bash_history" ".node_repl_history")
    local hist_found=0

    for hist in "${history_files[@]}"; do
        local file="$HOME/$hist"
        if [[ -f "$file" ]]; then
            ((hist_found++))
            local perms=$(_ui_get_perms "$file")
            if [[ "$perms" == "600" ]]; then
                history_status+="$hist ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
            else
                history_status+="$hist ${_zsh_cmd_yellow}○${_zsh_cmd_nc}${_zsh_cmd_dim}$perms${_zsh_cmd_nc}  "
                ((warnings++))
            fi

            # Check for secrets in history
            if grep -qiE "(password|secret|token|api.?key)=" "$file" 2>/dev/null; then
                history_status+="${_zsh_cmd_yellow}!secrets${_zsh_cmd_nc}  "
                ((warnings++))
            fi
        fi
    done

    [[ $hist_found -eq 0 ]] && history_status="${_zsh_cmd_dim}aucun${_zsh_cmd_nc}"
    _zsh_section "History" "$history_status"

    echo ""

    # --- Résumé ---
    _zsh_separator 44

    if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${_zsh_cmd_green}✓ Tout est securise${_zsh_cmd_nc}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "${_zsh_cmd_green}✓ OK${_zsh_cmd_nc} ${_zsh_cmd_dim}($warnings avertissement(s))${_zsh_cmd_nc}"
    else
        echo -e "${_zsh_cmd_red}✗ $issues erreur(s)${_zsh_cmd_nc}, ${_zsh_cmd_yellow}$warnings avertissement(s)${_zsh_cmd_nc}"
        echo -e "${_zsh_cmd_dim}Correction auto: zsh-env-audit-fix${_zsh_cmd_nc}"
    fi

    return $issues
}

# Corrige automatiquement les permissions
zsh-env-audit-fix() {
    _zsh_header "ZSH_ENV Security Fix"

    local fixed=0

    # SSH
    echo -n "SSH          "
    if [[ -d "$HOME/.ssh" ]]; then
        chmod 700 "$HOME/.ssh" && ((fixed++))
        for key in "$HOME/.ssh"/id_*(N); do
            [[ -f "$key" && ! "$key" == *.pub ]] && chmod 600 "$key" && ((fixed++))
        done
        [[ -f "$HOME/.ssh/config" ]] && chmod 600 "$HOME/.ssh/config" && ((fixed++))
        echo -e "${_zsh_cmd_green}✓${_zsh_cmd_nc}"
    else
        echo -e "${_zsh_cmd_dim}skip${_zsh_cmd_nc}"
    fi

    # Secrets
    echo -n "Secrets      "
    local secrets_fixed=0
    [[ -f "$HOME/.secrets" ]] && chmod 600 "$HOME/.secrets" && ((secrets_fixed++))
    [[ -f "$HOME/.gitlab_secrets" ]] && chmod 600 "$HOME/.gitlab_secrets" && ((secrets_fixed++))
    [[ -f "$HOME/.env" ]] && chmod 600 "$HOME/.env" && ((secrets_fixed++))
    [[ -f "$HOME/.netrc" ]] && chmod 600 "$HOME/.netrc" && ((secrets_fixed++))
    [[ -f "$HOME/.npmrc" ]] && chmod 600 "$HOME/.npmrc" && ((secrets_fixed++))
    ((fixed += secrets_fixed))
    [[ $secrets_fixed -gt 0 ]] && echo -e "${_zsh_cmd_green}✓${_zsh_cmd_nc} ${_zsh_cmd_dim}($secrets_fixed)${_zsh_cmd_nc}" || echo -e "${_zsh_cmd_dim}skip${_zsh_cmd_nc}"

    # Kube
    echo -n "Kubernetes   "
    if [[ -d "$HOME/.kube" ]]; then
        chmod 700 "$HOME/.kube" && ((fixed++))
        for kube in "$HOME/.kube"/config*(N) "$HOME/.kube/configs.d"/*(N); do
            [[ -f "$kube" ]] && chmod 600 "$kube" && ((fixed++))
        done
        echo -e "${_zsh_cmd_green}✓${_zsh_cmd_nc}"
    else
        echo -e "${_zsh_cmd_dim}skip${_zsh_cmd_nc}"
    fi

    # AWS
    echo -n "AWS          "
    if [[ -f "$HOME/.aws/credentials" ]]; then
        chmod 600 "$HOME/.aws/credentials" && ((fixed++))
        echo -e "${_zsh_cmd_green}✓${_zsh_cmd_nc}"
    else
        echo -e "${_zsh_cmd_dim}skip${_zsh_cmd_nc}"
    fi

    # History
    echo -n "History      "
    local hist_fixed=0
    [[ -f "$HOME/.zsh_history" ]] && chmod 600 "$HOME/.zsh_history" && ((hist_fixed++))
    [[ -f "$HOME/.bash_history" ]] && chmod 600 "$HOME/.bash_history" && ((hist_fixed++))
    ((fixed += hist_fixed))
    [[ $hist_fixed -gt 0 ]] && echo -e "${_zsh_cmd_green}✓${_zsh_cmd_nc}" || echo -e "${_zsh_cmd_dim}skip${_zsh_cmd_nc}"

    echo ""
    _zsh_separator 44
    echo -e "${_zsh_cmd_green}$fixed${_zsh_cmd_nc} fichier(s) corrige(s)"
    echo -e "${_zsh_cmd_dim}Verification: zsh-env-audit${_zsh_cmd_nc}"
}
