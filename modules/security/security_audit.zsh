[[ "${ZANVIL_MODULE_SECURITY:-true}" != "true" ]] && return 0

# ==============================================================================
# Security Audit - Verification de la securite des configs
# ==============================================================================
# Verifie les permissions, detecte les problemes potentiels
# Utilise les fonctions UI de ui.zsh (charge automatiquement)
# ==============================================================================

# Verifie les permissions d'un fichier et retourne le statut formate
# Usage: _audit_check_perms "label" "/path" "expected_perms..." -> status_string
# Incremente $issues ou $warnings selon le resultat
_audit_check_perms() {
    local label="$1"
    local file="$2"
    shift 2
    local expected=("$@")

    local perms=$(_ui_get_perms "$file")
    local match=false

    for exp in "${expected[@]}"; do
        [[ "$perms" == "$exp" ]] && match=true && break
    done

    if $match; then
        printf "%s ${_ui_green}✓${_ui_nc}  " "$label"
    else
        printf "%s ${_ui_red}✗${_ui_nc}${_ui_dim}%s${_ui_nc}  " "$label" "$perms"
        return 1
    fi
    return 0
}

# Audit principal
zanvil-audit() {
    if command -v zanvil &>/dev/null; then
        zanvil audit; return $?
    fi
    _ui_header "Zanvil Security Audit"

    local issues=0
    local warnings=0

    # --- SSH ---
    local ssh_status=""
    if [[ -d "$HOME/.ssh" ]]; then
        local ssh_perms=$(_ui_get_perms "$HOME/.ssh")
        if [[ "$ssh_perms" == "700" ]]; then
            ssh_status+="~/.ssh ${_ui_green}✓${_ui_nc}  "
        else
            ssh_status+="~/.ssh ${_ui_red}✗${_ui_nc}${_ui_dim}$ssh_perms${_ui_nc}  "
            ((issues++))
        fi

        # Cles privees
        for key in "$HOME/.ssh"/id_*(N) "$HOME/.ssh"/*.pem(N); do
            [[ ! -f "$key" ]] && continue
            [[ "$key" == *.pub ]] && continue
            local name=$(basename "$key")
            ssh_status+="$(_audit_check_perms "$name" "$key" "600" "400")"
            [[ $? -ne 0 ]] && ((issues++))
        done

        # Config SSH
        if [[ -f "$HOME/.ssh/config" ]]; then
            ssh_status+="$(_audit_check_perms "config" "$HOME/.ssh/config" "600" "644")"
            [[ $? -ne 0 ]] && ((issues++))
        fi
    else
        ssh_status+="${_ui_dim}non configure${_ui_nc}"
    fi
    _ui_section "SSH" "$ssh_status"

    # --- Secrets ---
    local secrets_status=""
    local secret_files=(".secrets" ".gitlab_secrets" ".env" ".netrc" ".npmrc" ".pypirc")
    local secrets_found=0

    for secret in "${secret_files[@]}"; do
        local file="$HOME/$secret"
        if [[ -f "$file" ]]; then
            ((secrets_found++))
            secrets_status+="$(_audit_check_perms "$secret" "$file" "600" "400")"
            [[ $? -ne 0 ]] && ((issues++))
        fi
    done

    if [[ $secrets_found -eq 0 ]]; then
        secrets_status="${_ui_dim}aucun${_ui_nc}"
    fi
    _ui_section "Secrets" "$secrets_status"

    # --- Kubernetes ---
    local kube_status=""
    if [[ -d "$HOME/.kube" ]]; then
        local kube_perms=$(_ui_get_perms "$HOME/.kube")
        if [[ "$kube_perms" == "700" ]]; then
            kube_status+="~/.kube ${_ui_green}✓${_ui_nc}  "
        else
            kube_status+="~/.kube ${_ui_yellow}○${_ui_nc}${_ui_dim}$kube_perms${_ui_nc}  "
            ((warnings++))
        fi

        # Config principale
        if [[ -f "$HOME/.kube/config" ]]; then
            local perms=$(_ui_get_perms "$HOME/.kube/config")
            if [[ "$perms" == "600" || "$perms" == "400" ]]; then
                kube_status+="config ${_ui_green}✓${_ui_nc}  "
            else
                kube_status+="config ${_ui_yellow}○${_ui_nc}${_ui_dim}$perms${_ui_nc}  "
                ((warnings++))
            fi
        fi

        # Configs.d count
        if [[ -d "$HOME/.kube/configs.d" ]]; then
            local config_count=$(find "$HOME/.kube/configs.d" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
            [[ $config_count -gt 0 ]] && kube_status+="${_ui_dim}${config_count} configs.d/${_ui_nc}"
        fi
    else
        kube_status="${_ui_dim}non configure${_ui_nc}"
    fi
    _ui_section "Kubernetes" "$kube_status"

    # --- Git ---
    local git_status=""
    if [[ -f "$HOME/.gitconfig" ]]; then
        local helper=$(git config --global credential.helper 2>/dev/null)
        if [[ -n "$helper" ]]; then
            git_status+="credential.helper ${_ui_green}✓${_ui_nc}${_ui_dim}$helper${_ui_nc}  "
        else
            git_status+="credential.helper ${_ui_yellow}○${_ui_nc}  "
            ((warnings++))
        fi
    fi

    if [[ -f "$HOME/.git-credentials" ]]; then
        git_status+="${_ui_yellow}.git-credentials${_ui_nc} ${_ui_dim}(clair)${_ui_nc}"
        ((warnings++))
    fi

    [[ -z "$git_status" ]] && git_status="${_ui_dim}non configure${_ui_nc}"
    _ui_section "Git" "$git_status"

    # --- Cloud ---
    local cloud_status=""

    # AWS
    if [[ -f "$HOME/.aws/credentials" ]]; then
        cloud_status+="$(_audit_check_perms "AWS" "$HOME/.aws/credentials" "600")"
        [[ $? -ne 0 ]] && ((issues++))
    else
        cloud_status+="${_ui_dim}AWS ○${_ui_nc}  "
    fi

    # Azure
    if [[ -d "$HOME/.azure" ]]; then
        cloud_status+="Azure ${_ui_green}✓${_ui_nc}  "
    else
        cloud_status+="${_ui_dim}Azure ○${_ui_nc}  "
    fi

    # GCP
    if [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
        cloud_status+="$(_audit_check_perms "GCP" "$HOME/.config/gcloud/application_default_credentials.json" "600")"
        [[ $? -ne 0 ]] && ((issues++))
    else
        cloud_status+="${_ui_dim}GCP ○${_ui_nc}"
    fi
    _ui_section "Cloud" "$cloud_status"

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
                history_status+="$hist ${_ui_green}✓${_ui_nc}  "
            else
                history_status+="$hist ${_ui_yellow}○${_ui_nc}${_ui_dim}$perms${_ui_nc}  "
                ((warnings++))
            fi

            # Check for secrets in history
            if grep -qiE "(password|secret|token|api.?key)=" "$file" 2>/dev/null; then
                history_status+="${_ui_yellow}!secrets${_ui_nc}  "
                ((warnings++))
            fi
        fi
    done

    [[ $hist_found -eq 0 ]] && history_status="${_ui_dim}aucun${_ui_nc}"
    _ui_section "History" "$history_status"

    echo ""

    # --- Résumé ---
    _ui_separator 44

    if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${_ui_green}✓ Tout est securise${_ui_nc}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "${_ui_green}✓ OK${_ui_nc} ${_ui_dim}($warnings avertissement(s))${_ui_nc}"
    else
        echo -e "${_ui_red}✗ $issues erreur(s)${_ui_nc}, ${_ui_yellow}$warnings avertissement(s)${_ui_nc}"
        echo -e "${_ui_dim}Correction auto: zanvil-audit-fix${_ui_nc}"
    fi

    return $issues
}

# Corrige automatiquement les permissions
zanvil-audit-fix() {
    _ui_header "Zanvil Security Fix"

    local fixed=0

    # SSH
    echo -n "SSH          "
    if [[ -d "$HOME/.ssh" ]]; then
        chmod 700 "$HOME/.ssh" && ((fixed++))
        for key in "$HOME/.ssh"/id_*(N); do
            [[ -f "$key" && ! "$key" == *.pub ]] && chmod 600 "$key" && ((fixed++))
        done
        [[ -f "$HOME/.ssh/config" ]] && chmod 600 "$HOME/.ssh/config" && ((fixed++))
        echo -e "${_ui_green}✓${_ui_nc}"
    else
        echo -e "${_ui_dim}skip${_ui_nc}"
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
    [[ $secrets_fixed -gt 0 ]] && echo -e "${_ui_green}✓${_ui_nc} ${_ui_dim}($secrets_fixed)${_ui_nc}" || echo -e "${_ui_dim}skip${_ui_nc}"

    # Kube
    echo -n "Kubernetes   "
    if [[ -d "$HOME/.kube" ]]; then
        chmod 700 "$HOME/.kube" && ((fixed++))
        for kube in "$HOME/.kube"/config*(N) "$HOME/.kube/configs.d"/*(N); do
            [[ -f "$kube" ]] && chmod 600 "$kube" && ((fixed++))
        done
        echo -e "${_ui_green}✓${_ui_nc}"
    else
        echo -e "${_ui_dim}skip${_ui_nc}"
    fi

    # AWS
    echo -n "AWS          "
    if [[ -f "$HOME/.aws/credentials" ]]; then
        chmod 600 "$HOME/.aws/credentials" && ((fixed++))
        echo -e "${_ui_green}✓${_ui_nc}"
    else
        echo -e "${_ui_dim}skip${_ui_nc}"
    fi

    # History
    echo -n "History      "
    local hist_fixed=0
    [[ -f "$HOME/.zsh_history" ]] && chmod 600 "$HOME/.zsh_history" && ((hist_fixed++))
    [[ -f "$HOME/.bash_history" ]] && chmod 600 "$HOME/.bash_history" && ((hist_fixed++))
    ((fixed += hist_fixed))
    [[ $hist_fixed -gt 0 ]] && echo -e "${_ui_green}✓${_ui_nc}" || echo -e "${_ui_dim}skip${_ui_nc}"

    echo ""
    _ui_separator 44
    echo -e "${_ui_green}$fixed${_ui_nc} fichier(s) corrige(s)"
    echo -e "${_ui_dim}Verification: zanvil-audit${_ui_nc}"
}
