# ==============================================================================
# core/commands.zsh — Commandes informatives zanvil
# ==============================================================================
# Fonctions : zanvil-list, zanvil-doctor, zanvil-status, zanvil-help
# Utilise les fonctions UI de ui.zsh (charge automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zanvil-list : Lister les outils installes (format tableau)
# ==============================================================================
zanvil-list() {
    _ui_header "Zanvil Outils"

    # Header du tableau
    printf "${_ui_bold}%-14s %-12s %s${_ui_nc}\n" "Outil" "Version" "Description"
    _ui_separator 50

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
            printf "${_ui_green}✓${_ui_nc} %-12s ${_ui_cyan}%-12s${_ui_nc} %s\n" "$name" "$version" "$desc"
            ((installed++))
        else
            printf "${_ui_red}✗${_ui_nc} %-12s ${_ui_yellow}%-12s${_ui_nc} %s\n" "$name" "manquant" "$desc"
            ((missing++))
        fi
    done

    echo ""
    _ui_separator 50
    printf "${_ui_green}$installed${_ui_nc} installes"
    [[ $missing -gt 0 ]] && printf " | ${_ui_yellow}$missing${_ui_nc} manquants"
    echo ""

    if [[ $missing -gt 0 ]]; then
        echo -e "\n${_ui_dim}Pour installer: ~/.zanvil/install.sh${_ui_nc}"
    fi
}

# ==============================================================================
# zanvil-doctor : Diagnostic compact de l'installation
# ==============================================================================
zanvil-doctor() {
    if command -v zanvil &>/dev/null; then
        zanvil doctor; return $?
    fi
    _ui_header "Zanvil Doctor"

    local issues=0
    local warnings=0

    # --- Config files (inline) ---
    local config_status=""
    [[ -f "$ZANVIL_DIR/rc.zsh" ]] && config_status+="rc.zsh ${_ui_green}✓${_ui_nc}  " || { config_status+="rc.zsh ${_ui_red}✗${_ui_nc}  "; ((issues++)); }
    [[ -f "$ZANVIL_DIR/core/aliases.zsh" ]] && config_status+="aliases ${_ui_green}✓${_ui_nc}  " || { config_status+="aliases ${_ui_red}✗${_ui_nc}  "; ((issues++)); }
    [[ -f "$ZANVIL_DIR/core/variables.zsh" ]] && config_status+="variables ${_ui_green}✓${_ui_nc}  " || { config_status+="variables ${_ui_red}✗${_ui_nc}  "; ((issues++)); }
    [[ -f "$ZANVIL_DIR/core/loader.zsh" ]] && config_status+="loader ${_ui_green}✓${_ui_nc}" || { config_status+="loader ${_ui_red}✗${_ui_nc}"; ((issues++)); }
    _ui_section "Config" "$config_status"

    # --- .zshrc integration ---
    local zshrc_status=""
    if [[ -f "$HOME/.zshrc" ]] && grep -q "ZANVIL_DIR" "$HOME/.zshrc"; then
        zshrc_status=".zshrc ${_ui_green}✓${_ui_nc}"
    else
        zshrc_status=".zshrc ${_ui_red}✗${_ui_nc}"
        ((issues++))
    fi
    _ui_section "Integration" "$zshrc_status"

    echo ""

    # --- Required deps (inline) ---
    local req_status=""
    local required_deps=("git" "curl" "jq")
    for dep in "${required_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            req_status+="$dep ${_ui_green}✓${_ui_nc}  "
        else
            req_status+="$dep ${_ui_red}✗${_ui_nc}  "
            ((issues++))
        fi
    done
    _ui_section "Requis" "$req_status"

    # --- Recommended deps (inline) ---
    local rec_status=""
    local recommended_deps=("starship" "zoxide" "fzf" "eza" "bat" "sops" "age")
    for dep in "${recommended_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            rec_status+="$dep ${_ui_green}✓${_ui_nc}  "
        else
            rec_status+="${_ui_dim}$dep ○${_ui_nc}  "
            ((warnings++))
        fi
    done
    _ui_section "Recommandes" "$rec_status"

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
            [[ -n "$ver" ]] && kube_status+="$dep ${_ui_green}✓${_ui_nc}${_ui_dim}$ver${_ui_nc}  " || kube_status+="$dep ${_ui_green}✓${_ui_nc}  "
        else
            kube_status+="${_ui_dim}$dep ○${_ui_nc}  "
        fi
    done
    _ui_section "Kubernetes" "$kube_status"

    echo ""

    # --- Modules (inline) ---
    local mod_status=""
    [[ "$ZANVIL_MODULE_GITLAB" = "true" ]] && mod_status+="GitLab ${_ui_green}✓${_ui_nc}  " || mod_status+="${_ui_dim}GitLab ○${_ui_nc}  "
    [[ "$ZANVIL_MODULE_DOCKER" = "true" ]] && mod_status+="Docker ${_ui_green}✓${_ui_nc}  " || mod_status+="${_ui_dim}Docker ○${_ui_nc}  "
    [[ "$ZANVIL_MODULE_MISE" = "true" ]] && mod_status+="Mise ${_ui_green}✓${_ui_nc}  " || mod_status+="${_ui_dim}Mise ○${_ui_nc}  "
    [[ "$ZANVIL_MODULE_NUSHELL" = "true" ]] && mod_status+="Nushell ${_ui_green}✓${_ui_nc}  " || mod_status+="${_ui_dim}Nushell ○${_ui_nc}  "
    [[ "$ZANVIL_MODULE_KUBE" = "true" ]] && mod_status+="Kube ${_ui_green}✓${_ui_nc}" || mod_status+="${_ui_dim}Kube ○${_ui_nc}"
    _ui_section "Modules" "$mod_status"

    # --- Mise details (if active) ---
    if [[ "$ZANVIL_MODULE_MISE" = "true" ]]; then
        local mise_info=""
        if command -v mise &> /dev/null; then
            local mise_ver=$(mise --version 2>/dev/null | awk '{print $1}')
            mise_info="mise ${_ui_green}✓${_ui_nc}${_ui_dim}$mise_ver${_ui_nc}"
            local node_ver=$(mise current node 2>/dev/null)
            local java_ver=$(mise current java 2>/dev/null)
            [[ -n "$node_ver" ]] && mise_info+="  node:${_ui_cyan}$node_ver${_ui_nc}"
            [[ -n "$java_ver" ]] && mise_info+="  java:${_ui_cyan}$java_ver${_ui_nc}"
        else
            mise_info="mise ${_ui_yellow}○${_ui_nc} ${_ui_dim}(non installe)${_ui_nc}"
            ((warnings++))
        fi
        _ui_section "Mise" "$mise_info"
    fi

    # --- Kubernetes details (if active) ---
    if [[ "$ZANVIL_MODULE_KUBE" = "true" ]]; then
        local kube_info=""
        [[ -f "$HOME/.kube/config.minimal.yml" ]] && kube_info+="config.minimal ${_ui_green}✓${_ui_nc}  " || kube_info+="${_ui_dim}config.minimal ○${_ui_nc}  "
        if [[ -d "$HOME/.kube/configs.d" ]]; then
            local config_count=$(find "$HOME/.kube/configs.d" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | wc -l | tr -d ' ')
            kube_info+="${_ui_dim}${config_count} configs.d/${_ui_nc}  "
        fi
        [[ -n "$KUBECONFIG" ]] && kube_info+="KUBECONFIG ${_ui_green}✓${_ui_nc}" || kube_info+="${_ui_dim}KUBECONFIG ○${_ui_nc}"
        _ui_section "Kubernetes" "$kube_info"

        # Azure status
        if command -v az &> /dev/null; then
            local az_account=$(az account show 2>/dev/null)
            if [[ -n "$az_account" ]]; then
                local az_user=$(echo "$az_account" | jq -r '.user.name // "inconnu"')
                _ui_section "Azure" "Connecte: ${_ui_cyan}$az_user${_ui_nc}"
            else
                _ui_section "Azure" "${_ui_yellow}Non connecte${_ui_nc} ${_ui_dim}(az login)${_ui_nc}"
            fi
        fi
    fi

    # --- GitLab details (if active) ---
    if [[ "$ZANVIL_MODULE_GITLAB" = "true" ]]; then
        local gl_info=""
        [[ -n "$GITLAB_TOKEN" ]] && gl_info+="TOKEN ${_ui_green}✓${_ui_nc}  " || { gl_info+="TOKEN ${_ui_yellow}○${_ui_nc}  "; ((warnings++)); }
        [[ -n "$GITLAB_URL" ]] && gl_info+="${_ui_dim}$GITLAB_URL${_ui_nc}" || gl_info+="${_ui_dim}gitlab.com${_ui_nc}"
        _ui_section "GitLab" "$gl_info"
    fi

    # --- SOPS/Age (if available) ---
    if command -v sops &> /dev/null && command -v age &> /dev/null; then
        local sops_info=""
        local age_key_file="$HOME/.config/sops/age/keys.txt"
        if [[ -f "$age_key_file" ]]; then
            local pub_key=$(grep "public key:" "$age_key_file" 2>/dev/null | awk '{print $NF}')
            sops_info+="cle ${_ui_green}✓${_ui_nc}  "
            [[ -n "$pub_key" ]] && sops_info+="${_ui_dim}${pub_key:0:16}...${_ui_nc}"
        else
            sops_info+="cle ${_ui_yellow}○${_ui_nc} ${_ui_dim}(age-keygen -o ~/.config/sops/age/keys.txt)${_ui_nc}"
            ((warnings++))
        fi
        _ui_section "SOPS/Age" "$sops_info"
    fi

    # --- SSL/TLS ---
    local ssl_info=""
    if [[ -f "$HOME/.ssl/ca-bundle.pem" ]]; then
        local cert_count=$(grep -c "BEGIN CERTIFICATE" "$HOME/.ssl/ca-bundle.pem" 2>/dev/null)
        local enterprise_count=$(grep -c "Enterprise CA:" "$HOME/.ssl/ca-bundle.pem" 2>/dev/null)
        ssl_info+="bundle ${_ui_green}✓${_ui_nc}  "
        ssl_info+="${_ui_dim}${cert_count} CAs (${enterprise_count} entreprise)${_ui_nc}"
    else
        ssl_info+="bundle ${_ui_yellow}○${_ui_nc} ${_ui_dim}(zanvil-ssl-setup)${_ui_nc}"
        ((warnings++))
    fi
    _ui_section "SSL/TLS" "$ssl_info"

    echo ""

    # --- Summary ---
    _ui_separator 44
    if [[ $issues -eq 0 ]] && [[ $warnings -eq 0 ]]; then
        echo -e "${_ui_green}✓ Tout est OK${_ui_nc}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "${_ui_green}✓ OK${_ui_nc} ${_ui_dim}($warnings avertissement(s))${_ui_nc}"
    else
        echo -e "${_ui_red}✗ $issues erreur(s)${_ui_nc}, ${_ui_yellow}$warnings avertissement(s)${_ui_nc}"
        echo -e "${_ui_dim}Lancez ~/.zanvil/install.sh pour corriger${_ui_nc}"
    fi
}

# ==============================================================================
# zanvil-status : Statut compact de l'installation
# ==============================================================================
zanvil-status() {
    _ui_header "Zanvil Status"

    # Version et répertoire
    _ui_section "Repertoire" "$ZANVIL_DIR"

    # Git info
    if [[ -d "$ZANVIL_DIR/.git" ]]; then
        local branch=$(git -C "$ZANVIL_DIR" branch --show-current 2>/dev/null)
        local commit=$(git -C "$ZANVIL_DIR" rev-parse --short HEAD 2>/dev/null)
        _ui_section "Git" "${_ui_cyan}$branch${_ui_nc} ${_ui_dim}($commit)${_ui_nc}"
    fi

    # Modules actifs
    local modules=""
    [[ "$ZANVIL_MODULE_GITLAB" = "true" ]] && modules+="GitLab "
    [[ "$ZANVIL_MODULE_DOCKER" = "true" ]] && modules+="Docker "
    [[ "$ZANVIL_MODULE_MISE" = "true" ]] && modules+="Mise "
    [[ "$ZANVIL_MODULE_NUSHELL" = "true" ]] && modules+="Nushell "
    [[ "$ZANVIL_MODULE_KUBE" = "true" ]] && modules+="Kube "
    [[ -z "$modules" ]] && modules="${_ui_dim}aucun${_ui_nc}"
    _ui_section "Modules" "$modules"

    # Mise active tools
    if [[ "$ZANVIL_MODULE_MISE" = "true" ]] && command -v mise &> /dev/null; then
        local active_tools=$(mise current 2>/dev/null | head -3)
        [[ -n "$active_tools" ]] && _ui_section "Mise" "$active_tools"
    fi

    # Shell
    _ui_section "Shell" "zsh $ZSH_VERSION"

    echo ""
    echo -e "${_ui_dim}Diagnostic complet: zanvil-doctor${_ui_nc}"
}

# ==============================================================================
# zanvil-help : Afficher l'aide
# ==============================================================================
zanvil-help() {
    _ui_header "Zanvil Aide"

    printf "${_ui_bold}%-28s${_ui_nc} %s\n" "Commande" "Description"
    _ui_separator 50

    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-list" "Liste les outils et versions"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-doctor" "Diagnostic de l'installation"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-status" "Statut rapide"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-completions" "Charge les auto-completions"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-completion-add" "Ajoute une completion"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-completion-remove" "Supprime une completion"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-theme [nom]" "Gestion themes Starship"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-ghostty [nom|sync]" "Gestion themes Ghostty"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "mise-configure <tool>" "Hooks Work (java, maven)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-git-bulk [action]" "Operations Git en masse"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-ssl-setup" "Configure les certificats SSL"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-gitlab-status" "Statut du token GitLab PAT"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-gitlab-browse" "Ouvre le repo GitLab dans le navigateur"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-modules [action]" "Gestion des modules (list/enable/disable)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-config-reset" "Restaure la config par defaut"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-backup" "Sauvegarde configs personnalisees"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-restore" "Restaure depuis un backup"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-switch [env]" "Switch d'environnement rapide"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-update" "Mise a jour zanvil"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "zanvil-help" "Cette aide"

    echo ""
    _ui_separator 50
    printf "${_ui_dim}%-14s${_ui_nc} %s\n" "Config" "~/.zanvil/config.zsh"
    printf "${_ui_dim}%-14s${_ui_nc} %s\n" "Completions" "~/.zanvil/completions.zsh"
    printf "${_ui_dim}%-14s${_ui_nc} %s\n" "Themes" "~/.zanvil/config/themes/"
    printf "${_ui_dim}%-14s${_ui_nc} %s\n" "Recharger" "ss (ou source ~/.zshrc)"
}

# ==============================================================================
# zanvil-doctor-conflicts : Détection des conflits entre modules
# ==============================================================================
zanvil-doctor-conflicts() {
    if command -v zanvil &>/dev/null; then
        zanvil conflicts; return $?
    fi

    _ui_header "Conflicts"
    local issues=0

    # --- Aliases en double ---
    _ui_section "Aliases" ""
    local alias_dups
    alias_dups="$(grep -rh "^alias [a-z_]" "$ZANVIL_DIR/modules" "$ZANVIL_DIR/core" --include="*.zsh" 2>/dev/null \
        | sed "s/alias \([^=]*\)=.*/\1/" | sort | uniq -d)"
    if [[ -n "$alias_dups" ]]; then
        while IFS= read -r a; do
            local files=
            files="$(grep -rl "^alias ${a}=" "$ZANVIL_DIR/modules" "$ZANVIL_DIR/core" --include="*.zsh" 2>/dev/null | sed "s|$ZANVIL_DIR/||" | tr '\n' '  ')"
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
    # Les deux syntaxes : `nom() {` et `function nom() {`. La seconde manquait, donc les
    # sept fonctions de modules/gitlab/ etaient invisibles a cette detection — aucune
    # n est en double aujourd hui, mais rien ne l aurait dit.
    fn_dups="$(grep -rhE "^(function )?[a-z][a-z0-9_-]*\(\) \{" "$ZANVIL_DIR/modules" "$ZANVIL_DIR/core" --include="*.zsh" 2>/dev/null \
        | sed -e "s/^function //" -e "s/\([^(]*\)() {.*/\1/" | sort | uniq -d)"
    if [[ -n "$fn_dups" ]]; then
        while IFS= read -r f; do
            local files=
            files="$(grep -rlE "^(function )?${f}\(\) \{" "$ZANVIL_DIR/modules" "$ZANVIL_DIR/core" --include="*.zsh" 2>/dev/null | sed "s|$ZANVIL_DIR/||" | tr '\n' '  ')"
            _ui_msg_warn "'${f}' → ${files}"
            ((issues++))
        done <<< "$fn_dups"
    else
        _ui_msg_ok "Aucune fonction en double"
    fi
    echo ""

    # --- Hooks chpwd concurrents ---
    _ui_section "Hooks" ""
    # Un seul motif pour le compte et pour la liste, et il exige que la ligne COMMENCE
    # par l appel. Les deux precedents divergeaient — `grep -cv "^#"` n excluait que les
    # lignes commencant par un diese, `grep -v "^.*#"` excluait toute ligne en contenant
    # un — donc la commande annoncait 4 hooks sur ce depot et n en affichait que 2. Les
    # deux de trop etaient ses propres lignes, qui cherchent la chaine ; elles ne
    # s affichaient pas parce qu elles portent un diese dans leur motif, ce qui donnait
    # le bon resultat pour la mauvaise raison.
    #
    # Exiger l appel en tete de ligne ecarte d un coup les commentaires, les mentions
    # dans une chaine, et le code qui cherche la chaine sans rien enregistrer.
    local _chpwd_pattern="^[[:space:]]*add-zsh-hook chpwd"
    local chpwd_count
    chpwd_count="$(grep -rhE "$_chpwd_pattern" "$ZANVIL_DIR" --include="*.zsh" 2>/dev/null | grep -c .)"
    if [[ $chpwd_count -gt 1 ]]; then
        _ui_msg_warn "$chpwd_count hooks chpwd enregistrés (attention aux interactions)"
        grep -rnE "$_chpwd_pattern" "$ZANVIL_DIR" --include="*.zsh" 2>/dev/null | sed "s|$ZANVIL_DIR/||"
        ((issues++))
    else
        _ui_msg_ok "${chpwd_count} hook chpwd"
    fi
    echo ""

    # --- Exports en double ---
    _ui_section "Exports" ""
    local export_dups
    export_dups="$(grep -rh "^export [A-Z_][A-Z0-9_]*=" "$ZANVIL_DIR/modules" --include="*.zsh" 2>/dev/null \
        | sed "s/export \([^=]*\)=.*/\1/" | sort | uniq -d)"
    if [[ -n "$export_dups" ]]; then
        while IFS= read -r e; do
            local files=
            files="$(grep -rl "^export ${e}=" "$ZANVIL_DIR/modules" --include="*.zsh" 2>/dev/null | sed "s|$ZANVIL_DIR/||" | tr '\n' '  ')"
            _ui_msg_warn "'${e}' → ${files}"
            ((issues++))
        done <<< "$export_dups"
    else
        _ui_msg_ok "Aucun export en double"
    fi

    _ui_summary $issues 0
}
