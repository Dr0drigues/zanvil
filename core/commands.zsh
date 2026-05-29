# ==============================================================================
# core/commands.zsh — Commandes informatives ZSH_ENV
# ==============================================================================
# Fonctions : zsh-env-list, zsh-env-doctor, zsh-env-status, zsh-env-help
# Utilise les fonctions UI de ui.zsh (charge automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zsh-env-list : Lister les outils installes (format tableau)
# ==============================================================================
zsh-env-list() {
    _zsh_header "ZSH_ENV Outils"

    # Header du tableau
    printf "${_zsh_cmd_bold}%-14s %-12s %s${_zsh_cmd_nc}\n" "Outil" "Version" "Description"
    _zsh_separator 50

    # Liste des outils à vérifier
    local tools=(
        "git:Git:Gestionnaire de versions"
        "zsh:Zsh:Shell"
        "curl:cURL:Transfert de donnees"
        "jq:jq:Processeur JSON"
        "eza:eza:ls moderne"
        "starship:Starship:Prompt personnalise"
        "zoxide:Zoxide:Navigation intelligente (z)"
        "fzf:FZF:Recherche fuzzy"
        "bat:Bat:cat avec coloration"
        "nu:Nushell:Shell moderne"
        "trash:Trash:Corbeille CLI"
        "mise:Mise:Gestionnaire de versions (Node, Java, etc.)"
        "docker:Docker:Conteneurisation"
        "kubectl:Kubectl:CLI Kubernetes"
        "kubelogin:Kubelogin:Azure AKS auth"
        "az:Azure CLI:CLI Azure"
        "helm:Helm:Package manager K8s"
    )

    local installed=0
    local missing=0

    for tool_info in "${tools[@]}"; do
        local cmd="${tool_info%%:*}"
        local rest="${tool_info#*:}"
        local name="${rest%%:*}"
        local desc="${rest#*:}"

        if command -v "$cmd" &> /dev/null; then
            local version=""
            case "$cmd" in
                git) version=$(git --version 2>/dev/null | awk '{print $3}') ;;
                zsh) version=$ZSH_VERSION ;;
                eza) version=$(eza --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1) ;;
                starship) version=$(starship --version 2>/dev/null | head -1 | awk '{print $2}') ;;
                zoxide) version=$(zoxide --version 2>/dev/null | awk '{print $2}') ;;
                bat) version=$(bat --version 2>/dev/null | awk '{print $2}') ;;
                nu) version=$(nu --version 2>/dev/null) ;;
                fzf) version=$(fzf --version 2>/dev/null | awk '{print $1}') ;;
                jq) version=$(jq --version 2>/dev/null | sed 's/jq-//') ;;
                mise) version=$(mise --version 2>/dev/null | awk '{print $1}') ;;
                docker) version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',') ;;
                kubectl) version=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}') ;;
                kubelogin) version=$(kubelogin --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1) ;;
                az) version=$(az version 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null) ;;
                helm) version=$(helm version --short 2>/dev/null | cut -d'+' -f1) ;;
                *) version="" ;;
            esac
            printf "${_zsh_cmd_green}✓${_zsh_cmd_nc} %-12s ${_zsh_cmd_cyan}%-12s${_zsh_cmd_nc} %s\n" "$name" "$version" "$desc"
            ((installed++))
        else
            printf "${_zsh_cmd_red}✗${_zsh_cmd_nc} %-12s ${_zsh_cmd_yellow}%-12s${_zsh_cmd_nc} %s\n" "$name" "manquant" "$desc"
            ((missing++))
        fi
    done

    echo ""
    _zsh_separator 50
    printf "${_zsh_cmd_green}$installed${_zsh_cmd_nc} installes"
    [[ $missing -gt 0 ]] && printf " | ${_zsh_cmd_yellow}$missing${_zsh_cmd_nc} manquants"
    echo ""

    if [[ $missing -gt 0 ]]; then
        echo -e "\n${_zsh_cmd_dim}Pour installer: ~/.zsh_env/install.sh${_zsh_cmd_nc}"
    fi
}

# ==============================================================================
# zsh-env-doctor : Diagnostic compact de l'installation
# ==============================================================================
zsh-env-doctor() {
    if command -v zsh-env-cli &>/dev/null; then
        zsh-env-cli doctor; return $?
    fi
    _zsh_header "ZSH_ENV Doctor"

    local issues=0
    local warnings=0

    # --- Config files (inline) ---
    local config_status=""
    [[ -f "$ZSH_ENV_DIR/rc.zsh" ]] && config_status+="rc.zsh ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { config_status+="rc.zsh ${_zsh_cmd_red}✗${_zsh_cmd_nc}  "; ((issues++)); }
    [[ -f "$ZSH_ENV_DIR/core/aliases.zsh" ]] && config_status+="aliases ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { config_status+="aliases ${_zsh_cmd_red}✗${_zsh_cmd_nc}  "; ((issues++)); }
    [[ -f "$ZSH_ENV_DIR/core/variables.zsh" ]] && config_status+="variables ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { config_status+="variables ${_zsh_cmd_red}✗${_zsh_cmd_nc}  "; ((issues++)); }
    [[ -f "$ZSH_ENV_DIR/core/loader.zsh" ]] && config_status+="loader ${_zsh_cmd_green}✓${_zsh_cmd_nc}" || { config_status+="loader ${_zsh_cmd_red}✗${_zsh_cmd_nc}"; ((issues++)); }
    _zsh_section "Config" "$config_status"

    # --- .zshrc integration ---
    local zshrc_status=""
    if [[ -f "$HOME/.zshrc" ]] && grep -q "ZSH_ENV_DIR" "$HOME/.zshrc"; then
        zshrc_status=".zshrc ${_zsh_cmd_green}✓${_zsh_cmd_nc}"
    else
        zshrc_status=".zshrc ${_zsh_cmd_red}✗${_zsh_cmd_nc}"
        ((issues++))
    fi
    _zsh_section "Integration" "$zshrc_status"

    echo ""

    # --- Required deps (inline) ---
    local req_status=""
    local required_deps=("git" "curl" "jq")
    for dep in "${required_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            req_status+="$dep ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        else
            req_status+="$dep ${_zsh_cmd_red}✗${_zsh_cmd_nc}  "
            ((issues++))
        fi
    done
    _zsh_section "Requis" "$req_status"

    # --- Recommended deps (inline) ---
    local rec_status=""
    local recommended_deps=("starship" "zoxide" "fzf" "eza" "bat" "sops" "age")
    for dep in "${recommended_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            rec_status+="$dep ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        else
            rec_status+="${_zsh_cmd_dim}$dep ○${_zsh_cmd_nc}  "
            ((warnings++))
        fi
    done
    _zsh_section "Recommandes" "$rec_status"

    # --- Kubernetes/Azure tools (inline with versions) ---
    local kube_status=""
    local kube_deps=("kubectl" "kubelogin" "az" "helm")
    for dep in "${kube_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            local ver=""
            case "$dep" in
                kubectl) ver=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}' | cut -c1-6) ;;
                az) ver=$(az version 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null | cut -c1-5) ;;
                helm) ver=$(helm version --short 2>/dev/null | cut -d'+' -f1 | cut -c1-6) ;;
                *) ver="" ;;
            esac
            [[ -n "$ver" ]] && kube_status+="$dep ${_zsh_cmd_green}✓${_zsh_cmd_nc}${_zsh_cmd_dim}$ver${_zsh_cmd_nc}  " || kube_status+="$dep ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        else
            kube_status+="${_zsh_cmd_dim}$dep ○${_zsh_cmd_nc}  "
        fi
    done
    _zsh_section "Kubernetes" "$kube_status"

    echo ""

    # --- Modules (inline) ---
    local mod_status=""
    [[ "$ZSH_ENV_MODULE_GITLAB" = "true" ]] && mod_status+="GitLab ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || mod_status+="${_zsh_cmd_dim}GitLab ○${_zsh_cmd_nc}  "
    [[ "$ZSH_ENV_MODULE_DOCKER" = "true" ]] && mod_status+="Docker ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || mod_status+="${_zsh_cmd_dim}Docker ○${_zsh_cmd_nc}  "
    [[ "$ZSH_ENV_MODULE_MISE" = "true" ]] && mod_status+="Mise ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || mod_status+="${_zsh_cmd_dim}Mise ○${_zsh_cmd_nc}  "
    [[ "$ZSH_ENV_MODULE_NUSHELL" = "true" ]] && mod_status+="Nushell ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || mod_status+="${_zsh_cmd_dim}Nushell ○${_zsh_cmd_nc}  "
    [[ "$ZSH_ENV_MODULE_KUBE" = "true" ]] && mod_status+="Kube ${_zsh_cmd_green}✓${_zsh_cmd_nc}" || mod_status+="${_zsh_cmd_dim}Kube ○${_zsh_cmd_nc}"
    _zsh_section "Modules" "$mod_status"

    # --- Mise details (if active) ---
    if [[ "$ZSH_ENV_MODULE_MISE" = "true" ]]; then
        local mise_info=""
        if command -v mise &> /dev/null; then
            local mise_ver=$(mise --version 2>/dev/null | awk '{print $1}')
            mise_info="mise ${_zsh_cmd_green}✓${_zsh_cmd_nc}${_zsh_cmd_dim}$mise_ver${_zsh_cmd_nc}"
            local node_ver=$(mise current node 2>/dev/null)
            local java_ver=$(mise current java 2>/dev/null)
            [[ -n "$node_ver" ]] && mise_info+="  node:${_zsh_cmd_cyan}$node_ver${_zsh_cmd_nc}"
            [[ -n "$java_ver" ]] && mise_info+="  java:${_zsh_cmd_cyan}$java_ver${_zsh_cmd_nc}"
        else
            mise_info="mise ${_zsh_cmd_yellow}○${_zsh_cmd_nc} ${_zsh_cmd_dim}(non installe)${_zsh_cmd_nc}"
            ((warnings++))
        fi
        _zsh_section "Mise" "$mise_info"
    fi

    # --- Kubernetes details (if active) ---
    if [[ "$ZSH_ENV_MODULE_KUBE" = "true" ]]; then
        local kube_info=""
        [[ -f "$HOME/.kube/config.minimal.yml" ]] && kube_info+="config.minimal ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || kube_info+="${_zsh_cmd_dim}config.minimal ○${_zsh_cmd_nc}  "
        if [[ -d "$HOME/.kube/configs.d" ]]; then
            local config_count=$(find "$HOME/.kube/configs.d" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | wc -l | tr -d ' ')
            kube_info+="${_zsh_cmd_dim}${config_count} configs.d/${_zsh_cmd_nc}  "
        fi
        [[ -n "$KUBECONFIG" ]] && kube_info+="KUBECONFIG ${_zsh_cmd_green}✓${_zsh_cmd_nc}" || kube_info+="${_zsh_cmd_dim}KUBECONFIG ○${_zsh_cmd_nc}"
        _zsh_section "Kubernetes" "$kube_info"

        # Azure status
        if command -v az &> /dev/null; then
            local az_account=$(az account show 2>/dev/null)
            if [[ -n "$az_account" ]]; then
                local az_user=$(echo "$az_account" | jq -r '.user.name // "inconnu"')
                _zsh_section "Azure" "Connecte: ${_zsh_cmd_cyan}$az_user${_zsh_cmd_nc}"
            else
                _zsh_section "Azure" "${_zsh_cmd_yellow}Non connecte${_zsh_cmd_nc} ${_zsh_cmd_dim}(az login)${_zsh_cmd_nc}"
            fi
        fi
    fi

    # --- GitLab details (if active) ---
    if [[ "$ZSH_ENV_MODULE_GITLAB" = "true" ]]; then
        local gl_info=""
        [[ -n "$GITLAB_TOKEN" ]] && gl_info+="TOKEN ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { gl_info+="TOKEN ${_zsh_cmd_yellow}○${_zsh_cmd_nc}  "; ((warnings++)); }
        [[ -n "$GITLAB_URL" ]] && gl_info+="${_zsh_cmd_dim}$GITLAB_URL${_zsh_cmd_nc}" || gl_info+="${_zsh_cmd_dim}gitlab.com${_zsh_cmd_nc}"
        _zsh_section "GitLab" "$gl_info"
    fi

    # --- SOPS/Age (if available) ---
    if command -v sops &> /dev/null && command -v age &> /dev/null; then
        local sops_info=""
        local age_key_file="$HOME/.config/sops/age/keys.txt"
        if [[ -f "$age_key_file" ]]; then
            local pub_key=$(grep "public key:" "$age_key_file" 2>/dev/null | awk '{print $NF}')
            sops_info+="cle ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
            [[ -n "$pub_key" ]] && sops_info+="${_zsh_cmd_dim}${pub_key:0:16}...${_zsh_cmd_nc}"
        else
            sops_info+="cle ${_zsh_cmd_yellow}○${_zsh_cmd_nc} ${_zsh_cmd_dim}(age-keygen -o ~/.config/sops/age/keys.txt)${_zsh_cmd_nc}"
            ((warnings++))
        fi
        _zsh_section "SOPS/Age" "$sops_info"
    fi

    # --- SSL/TLS ---
    local ssl_info=""
    if [[ -f "$HOME/.ssl/ca-bundle.pem" ]]; then
        local cert_count=$(grep -c "BEGIN CERTIFICATE" "$HOME/.ssl/ca-bundle.pem" 2>/dev/null)
        local enterprise_count=$(grep -c "Enterprise CA:" "$HOME/.ssl/ca-bundle.pem" 2>/dev/null)
        ssl_info+="bundle ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        ssl_info+="${_zsh_cmd_dim}${cert_count} CAs (${enterprise_count} entreprise)${_zsh_cmd_nc}"
    else
        ssl_info+="bundle ${_zsh_cmd_yellow}○${_zsh_cmd_nc} ${_zsh_cmd_dim}(zsh-env-ssl-setup)${_zsh_cmd_nc}"
        ((warnings++))
    fi
    _zsh_section "SSL/TLS" "$ssl_info"

    echo ""

    # --- Summary ---
    _zsh_separator 44
    if [[ $issues -eq 0 ]] && [[ $warnings -eq 0 ]]; then
        echo -e "${_zsh_cmd_green}✓ Tout est OK${_zsh_cmd_nc}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "${_zsh_cmd_green}✓ OK${_zsh_cmd_nc} ${_zsh_cmd_dim}($warnings avertissement(s))${_zsh_cmd_nc}"
    else
        echo -e "${_zsh_cmd_red}✗ $issues erreur(s)${_zsh_cmd_nc}, ${_zsh_cmd_yellow}$warnings avertissement(s)${_zsh_cmd_nc}"
        echo -e "${_zsh_cmd_dim}Lancez ~/.zsh_env/install.sh pour corriger${_zsh_cmd_nc}"
    fi
}

# ==============================================================================
# zsh-env-status : Statut compact de l'installation
# ==============================================================================
zsh-env-status() {
    _zsh_header "ZSH_ENV Status"

    # Version et répertoire
    _zsh_section "Repertoire" "$ZSH_ENV_DIR"

    # Git info
    if [[ -d "$ZSH_ENV_DIR/.git" ]]; then
        local branch=$(git -C "$ZSH_ENV_DIR" branch --show-current 2>/dev/null)
        local commit=$(git -C "$ZSH_ENV_DIR" rev-parse --short HEAD 2>/dev/null)
        _zsh_section "Git" "${_zsh_cmd_cyan}$branch${_zsh_cmd_nc} ${_zsh_cmd_dim}($commit)${_zsh_cmd_nc}"
    fi

    # Modules actifs
    local modules=""
    [[ "$ZSH_ENV_MODULE_GITLAB" = "true" ]] && modules+="GitLab "
    [[ "$ZSH_ENV_MODULE_DOCKER" = "true" ]] && modules+="Docker "
    [[ "$ZSH_ENV_MODULE_MISE" = "true" ]] && modules+="Mise "
    [[ "$ZSH_ENV_MODULE_NUSHELL" = "true" ]] && modules+="Nushell "
    [[ "$ZSH_ENV_MODULE_KUBE" = "true" ]] && modules+="Kube "
    [[ -z "$modules" ]] && modules="${_zsh_cmd_dim}aucun${_zsh_cmd_nc}"
    _zsh_section "Modules" "$modules"

    # Mise active tools
    if [[ "$ZSH_ENV_MODULE_MISE" = "true" ]] && command -v mise &> /dev/null; then
        local active_tools=$(mise current 2>/dev/null | head -3)
        [[ -n "$active_tools" ]] && _zsh_section "Mise" "$active_tools"
    fi

    # Shell
    _zsh_section "Shell" "zsh $ZSH_VERSION"

    echo ""
    echo -e "${_zsh_cmd_dim}Diagnostic complet: zsh-env-doctor${_zsh_cmd_nc}"
}

# ==============================================================================
# zsh-env-help : Afficher l'aide
# ==============================================================================
zsh-env-help() {
    _zsh_header "ZSH_ENV Aide"

    printf "${_zsh_cmd_bold}%-28s${_zsh_cmd_nc} %s\n" "Commande" "Description"
    _zsh_separator 50

    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-list" "Liste les outils et versions"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-doctor" "Diagnostic de l'installation"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-status" "Statut rapide"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-completions" "Charge les auto-completions"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-completion-add" "Ajoute une completion"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-completion-remove" "Supprime une completion"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-theme [nom]" "Gestion themes Starship"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-ghostty [nom|sync]" "Gestion themes Ghostty"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "mise-configure <tool>" "Hooks Work (java, maven)"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-git-bulk [action]" "Operations Git en masse"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-ssl-setup" "Configure les certificats SSL"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-gitlab-status" "Statut du token GitLab PAT"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-gitlab-browse" "Ouvre le repo GitLab dans le navigateur"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-modules [action]" "Gestion des modules (list/enable/disable)"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-config-reset" "Restaure la config par defaut"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-backup" "Sauvegarde configs personnalisees"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-restore" "Restaure depuis un backup"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-switch [env]" "Switch d'environnement rapide"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-update" "Mise a jour zsh_env"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-help" "Cette aide"

    echo ""
    _zsh_separator 50
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Config" "~/.zsh_env/config.zsh"
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Completions" "~/.zsh_env/completions.zsh"
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Themes" "~/.zsh_env/themes/"
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Recharger" "ss (ou source ~/.zshrc)"
}

# ==============================================================================
# zsh-env-doctor-conflicts : Détection des conflits entre modules
# ==============================================================================
zsh-env-doctor-conflicts() {
    _ui_header "Conflicts"
    local issues=0

    # --- Aliases en double ---
    _ui_section "Aliases" ""
    local alias_dups
    alias_dups="$(grep -rh "^alias [a-z_]" "$ZSH_ENV_DIR/modules" "$ZSH_ENV_DIR/core" --include="*.zsh" 2>/dev/null \
        | sed "s/alias \([^=]*\)=.*/\1/" | sort | uniq -d)"
    if [[ -n "$alias_dups" ]]; then
        while IFS= read -r a; do
            local files
            files="$(grep -rl "^alias ${a}=" "$ZSH_ENV_DIR/modules" "$ZSH_ENV_DIR/core" --include="*.zsh" 2>/dev/null | sed "s|$ZSH_ENV_DIR/||" | tr '\n' '  ')"
            _ui_msg_warn "'${a}' → ${files}"
            ((issues++))
        done <<< "$alias_dups"
    else
        _ui_msg_ok "Aucun alias en double"
    fi
    echo ""

    # --- Fonctions publiques en double ---
    _ui_section "Fonctions" ""
    local fn_dups
    fn_dups="$(grep -rh "^[a-z][a-z0-9_-]*() {" "$ZSH_ENV_DIR/modules" "$ZSH_ENV_DIR/core" --include="*.zsh" 2>/dev/null \
        | sed "s/\([^(]*\)() {.*/\1/" | sort | uniq -d)"
    if [[ -n "$fn_dups" ]]; then
        while IFS= read -r f; do
            local files
            files="$(grep -rl "^${f}() {" "$ZSH_ENV_DIR/modules" "$ZSH_ENV_DIR/core" --include="*.zsh" 2>/dev/null | sed "s|$ZSH_ENV_DIR/||" | tr '\n' '  ')"
            _ui_msg_warn "'${f}' → ${files}"
            ((issues++))
        done <<< "$fn_dups"
    else
        _ui_msg_ok "Aucune fonction en double"
    fi
    echo ""

    # --- Hooks chpwd concurrents ---
    _ui_section "Hooks" ""
    local chpwd_count
    chpwd_count="$(grep -rh "add-zsh-hook chpwd" "$ZSH_ENV_DIR" --include="*.zsh" 2>/dev/null | grep -cv "^#")"
    if [[ $chpwd_count -gt 1 ]]; then
        _ui_msg_warn "$chpwd_count hooks chpwd enregistrés (attention aux interactions)"
        grep -rn "add-zsh-hook chpwd" "$ZSH_ENV_DIR" --include="*.zsh" 2>/dev/null | grep -v "^.*#" | sed "s|$ZSH_ENV_DIR/||"
        ((issues++))
    else
        _ui_msg_ok "${chpwd_count} hook chpwd"
    fi
    echo ""

    # --- Exports en double ---
    _ui_section "Exports" ""
    local export_dups
    export_dups="$(grep -rh "^export [A-Z_][A-Z0-9_]*=" "$ZSH_ENV_DIR/modules" --include="*.zsh" 2>/dev/null \
        | sed "s/export \([^=]*\)=.*/\1/" | sort | uniq -d)"
    if [[ -n "$export_dups" ]]; then
        while IFS= read -r e; do
            local files
            files="$(grep -rl "^export ${e}=" "$ZSH_ENV_DIR/modules" --include="*.zsh" 2>/dev/null | sed "s|$ZSH_ENV_DIR/||" | tr '\n' '  ')"
            _ui_msg_warn "'${e}' → ${files}"
            ((issues++))
        done <<< "$export_dups"
    else
        _ui_msg_ok "Aucun export en double"
    fi

    _ui_summary $issues 0
}
