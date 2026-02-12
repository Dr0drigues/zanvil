# ==============================================================================
# Commandes utilitaires ZSH_ENV
# ==============================================================================
# Utilise les fonctions UI de ui.zsh (chargé automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zsh-env-list : Lister les outils installés (format tableau)
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
        "nvm:NVM:Node Version Manager"
        "sdk:SDKMAN:SDK Manager (Java, etc.)"
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
                nvm) version=$(nvm --version 2>/dev/null) ;;
                sdk) version="installed" ;;
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
    [ $missing -gt 0 ] && printf " | ${_zsh_cmd_yellow}$missing${_zsh_cmd_nc} manquants"
    echo ""

    if [ $missing -gt 0 ]; then
        echo -e "\n${_zsh_cmd_dim}Pour installer: ~/.zsh_env/install.sh${_zsh_cmd_nc}"
    fi
}

# ==============================================================================
# zsh-env-completion-add : Ajouter une completion personnalisée
# ==============================================================================
zsh-env-completion-add() {
    local name="$1"
    local cmd="$2"

    if [ -z "$name" ] || [ -z "$cmd" ]; then
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
# zsh-env-completion-remove : Supprimer une completion personnalisée
# ==============================================================================
zsh-env-completion-remove() {
    local name="$1"

    if [ -z "$name" ]; then
        echo -e "${_zsh_cmd_bold}Usage:${_zsh_cmd_nc} zsh-env-completion-remove <nom>"
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
    if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then
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
        source <(rustup completions zsh 2>/dev/null)
        source <(rustup completions zsh cargo 2>/dev/null)
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Rustup/Cargo"
        ((loaded++))
    fi

    # Completions personnalisées
    local custom_file="$ZSH_ENV_DIR/completions.zsh"
    if [ -f "$custom_file" ]; then
        source "$custom_file"

        local custom_loaded=0
        for entry in "${_ZSH_ENV_CUSTOM_COMPLETIONS[@]}"; do
            # Ignorer les lignes vides ou commentées
            [[ -z "$entry" || "$entry" == \#* ]] && continue

            local name="${entry%%:*}"
            local cmd="${entry#*:}"

            if command -v "$name" &> /dev/null; then
                # Capture la sortie de la commande puis eval avec stderr supprimé
                local comp_script
                comp_script=$($cmd 2>/dev/null)
                if [ -n "$comp_script" ]; then
                    { eval "$comp_script"; } 2>/dev/null
                    echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} $name ${_zsh_cmd_cyan}(custom)${_zsh_cmd_nc}"
                    ((loaded++))
                    ((custom_loaded++))
                else
                    echo -e "  ${_zsh_cmd_red}✗${_zsh_cmd_nc} $name ${_zsh_cmd_yellow}(erreur)${_zsh_cmd_nc}"
                fi
            fi
        done

        if [ $custom_loaded -gt 0 ]; then
            echo -e "\n  ${_zsh_cmd_dim}$custom_loaded completion(s) personnalisee(s)${_zsh_cmd_nc}"
        fi
    fi

    echo ""
    _zsh_separator 44
    echo -e "${_zsh_cmd_green}$loaded${_zsh_cmd_nc} completions chargees"

    # Recharger le système de completion
    autoload -Uz compinit && compinit -C
}

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
    if [ -z "$theme" ] || [ "$theme" = "list" ]; then
        _zsh_header "Themes Starship"

        if [ ! -d "$themes_dir" ]; then
            echo -e "${_zsh_cmd_yellow}Aucun theme trouve dans $themes_dir${_zsh_cmd_nc}"
            return 1
        fi

        # Theme actuel
        local current=""
        if [ -f "$starship_config" ]; then
            current=$(head -1 "$starship_config" 2>/dev/null | sed -n 's/.*Theme: \([a-zA-Z0-9_-]*\).*/\1/p' || echo "")
        fi

        for theme_file in "$themes_dir"/*.toml; do
            [ -f "$theme_file" ] || continue
            local name=$(basename "$theme_file" .toml)
            local desc=$(grep -m1 "^# Starship Theme:" "$theme_file" 2>/dev/null | sed 's/^# Starship Theme: //' || echo "")

            if [ "$name" = "$current" ]; then
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

    if [ ! -f "$theme_file" ]; then
        echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Theme '$theme' non trouve."
        echo -e "Themes disponibles: $(ls "$themes_dir"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/.toml//' | tr '\n' ' ')"
        return 1
    fi

    # Créer le dossier .config si nécessaire
    mkdir -p "$HOME/.config"

    # Backup de l'ancienne config si elle existe et n'est pas un de nos themes
    if [ -f "$starship_config" ]; then
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
# zsh-env-doctor : Diagnostic compact de l'installation
# ==============================================================================
zsh-env-doctor() {
    _zsh_header "ZSH_ENV Doctor"

    local issues=0
    local warnings=0

    # --- Config files (inline) ---
    local config_status=""
    [ -f "$ZSH_ENV_DIR/rc.zsh" ] && config_status+="rc.zsh ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { config_status+="rc.zsh ${_zsh_cmd_red}✗${_zsh_cmd_nc}  "; ((issues++)); }
    [ -f "$ZSH_ENV_DIR/aliases.zsh" ] && config_status+="aliases ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { config_status+="aliases ${_zsh_cmd_red}✗${_zsh_cmd_nc}  "; ((issues++)); }
    [ -f "$ZSH_ENV_DIR/variables.zsh" ] && config_status+="variables ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { config_status+="variables ${_zsh_cmd_red}✗${_zsh_cmd_nc}  "; ((issues++)); }
    [ -f "$ZSH_ENV_DIR/functions.zsh" ] && config_status+="functions ${_zsh_cmd_green}✓${_zsh_cmd_nc}" || { config_status+="functions ${_zsh_cmd_red}✗${_zsh_cmd_nc}"; ((issues++)); }
    _zsh_section "Config" "$config_status"

    # --- .zshrc integration ---
    local zshrc_status=""
    if [ -f "$HOME/.zshrc" ] && grep -q "ZSH_ENV_DIR" "$HOME/.zshrc"; then
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
            [ -n "$ver" ] && kube_status+="$dep ${_zsh_cmd_green}✓${_zsh_cmd_nc}${_zsh_cmd_dim}$ver${_zsh_cmd_nc}  " || kube_status+="$dep ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
        else
            kube_status+="${_zsh_cmd_dim}$dep ○${_zsh_cmd_nc}  "
        fi
    done
    _zsh_section "Kubernetes" "$kube_status"

    echo ""

    # --- Modules (inline) ---
    local mod_status=""
    [ "$ZSH_ENV_MODULE_GITLAB" = "true" ] && mod_status+="GitLab ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || mod_status+="${_zsh_cmd_dim}GitLab ○${_zsh_cmd_nc}  "
    [ "$ZSH_ENV_MODULE_DOCKER" = "true" ] && mod_status+="Docker ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || mod_status+="${_zsh_cmd_dim}Docker ○${_zsh_cmd_nc}  "
    if [ "$ZSH_ENV_MODULE_NVM" = "true" ]; then
        [ "$ZSH_ENV_NVM_LAZY" = "true" ] && mod_status+="NVM ${_zsh_cmd_green}✓${_zsh_cmd_nc}${_zsh_cmd_dim}(lazy)${_zsh_cmd_nc}  " || mod_status+="NVM ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
    else
        mod_status+="${_zsh_cmd_dim}NVM ○${_zsh_cmd_nc}  "
    fi
    [ "$ZSH_ENV_MODULE_NUSHELL" = "true" ] && mod_status+="Nushell ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || mod_status+="${_zsh_cmd_dim}Nushell ○${_zsh_cmd_nc}  "
    [ "$ZSH_ENV_MODULE_KUBE" = "true" ] && mod_status+="Kube ${_zsh_cmd_green}✓${_zsh_cmd_nc}" || mod_status+="${_zsh_cmd_dim}Kube ○${_zsh_cmd_nc}"
    _zsh_section "Modules" "$mod_status"

    # --- NVM details (if active) ---
    if [ "$ZSH_ENV_MODULE_NVM" = "true" ]; then
        local nvm_info=""
        if [ -d "$NVM_DIR" ]; then
            nvm_info="~/.nvm ${_zsh_cmd_green}✓${_zsh_cmd_nc}"
            [ "$ZSH_ENV_NVM_LAZY" = "true" ] && nvm_info+="  ${_zsh_cmd_dim}lazy-loading actif${_zsh_cmd_nc}"
        else
            nvm_info="~/.nvm ${_zsh_cmd_yellow}○${_zsh_cmd_nc} ${_zsh_cmd_dim}(non installe)${_zsh_cmd_nc}"
            ((warnings++))
        fi
        _zsh_section "NVM" "$nvm_info"
    fi

    # --- Kubernetes details (if active) ---
    if [ "$ZSH_ENV_MODULE_KUBE" = "true" ]; then
        local kube_info=""
        [ -f "$HOME/.kube/config.minimal.yml" ] && kube_info+="config.minimal ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || kube_info+="${_zsh_cmd_dim}config.minimal ○${_zsh_cmd_nc}  "
        if [ -d "$HOME/.kube/configs.d" ]; then
            local config_count=$(find "$HOME/.kube/configs.d" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | wc -l | tr -d ' ')
            kube_info+="${_zsh_cmd_dim}${config_count} configs.d/${_zsh_cmd_nc}  "
        fi
        [ -n "$KUBECONFIG" ] && kube_info+="KUBECONFIG ${_zsh_cmd_green}✓${_zsh_cmd_nc}" || kube_info+="${_zsh_cmd_dim}KUBECONFIG ○${_zsh_cmd_nc}"
        _zsh_section "Kubernetes" "$kube_info"

        # Azure status
        if command -v az &> /dev/null; then
            local az_account=$(az account show 2>/dev/null)
            if [ -n "$az_account" ]; then
                local az_user=$(echo "$az_account" | jq -r '.user.name // "inconnu"')
                _zsh_section "Azure" "Connecte: ${_zsh_cmd_cyan}$az_user${_zsh_cmd_nc}"
            else
                _zsh_section "Azure" "${_zsh_cmd_yellow}Non connecte${_zsh_cmd_nc} ${_zsh_cmd_dim}(az login)${_zsh_cmd_nc}"
            fi
        fi
    fi

    # --- GitLab details (if active) ---
    if [ "$ZSH_ENV_MODULE_GITLAB" = "true" ]; then
        local gl_info=""
        [ -n "$GITLAB_TOKEN" ] && gl_info+="TOKEN ${_zsh_cmd_green}✓${_zsh_cmd_nc}  " || { gl_info+="TOKEN ${_zsh_cmd_yellow}○${_zsh_cmd_nc}  "; ((warnings++)); }
        [ -n "$GITLAB_URL" ] && gl_info+="${_zsh_cmd_dim}$GITLAB_URL${_zsh_cmd_nc}" || gl_info+="${_zsh_cmd_dim}gitlab.com${_zsh_cmd_nc}"
        _zsh_section "GitLab" "$gl_info"
    fi

    # --- SOPS/Age (if available) ---
    if command -v sops &> /dev/null && command -v age &> /dev/null; then
        local sops_info=""
        local age_key_file="$HOME/.config/sops/age/keys.txt"
        if [ -f "$age_key_file" ]; then
            local pub_key=$(grep "public key:" "$age_key_file" 2>/dev/null | awk '{print $NF}')
            sops_info+="cle ${_zsh_cmd_green}✓${_zsh_cmd_nc}  "
            [ -n "$pub_key" ] && sops_info+="${_zsh_cmd_dim}${pub_key:0:16}...${_zsh_cmd_nc}"
        else
            sops_info+="cle ${_zsh_cmd_yellow}○${_zsh_cmd_nc} ${_zsh_cmd_dim}(age-keygen -o ~/.config/sops/age/keys.txt)${_zsh_cmd_nc}"
            ((warnings++))
        fi
        _zsh_section "SOPS/Age" "$sops_info"
    fi

    echo ""

    # --- Summary ---
    _zsh_separator 44
    if [ $issues -eq 0 ] && [ $warnings -eq 0 ]; then
        echo -e "${_zsh_cmd_green}✓ Tout est OK${_zsh_cmd_nc}"
    elif [ $issues -eq 0 ]; then
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
    if [ -d "$ZSH_ENV_DIR/.git" ]; then
        local branch=$(git -C "$ZSH_ENV_DIR" branch --show-current 2>/dev/null)
        local commit=$(git -C "$ZSH_ENV_DIR" rev-parse --short HEAD 2>/dev/null)
        _zsh_section "Git" "${_zsh_cmd_cyan}$branch${_zsh_cmd_nc} ${_zsh_cmd_dim}($commit)${_zsh_cmd_nc}"
    fi

    # Modules actifs
    local modules=""
    [ "$ZSH_ENV_MODULE_GITLAB" = "true" ] && modules+="GitLab "
    [ "$ZSH_ENV_MODULE_DOCKER" = "true" ] && modules+="Docker "
    [ "$ZSH_ENV_MODULE_NVM" = "true" ] && modules+="NVM "
    [ "$ZSH_ENV_MODULE_NUSHELL" = "true" ] && modules+="Nushell "
    [ "$ZSH_ENV_MODULE_KUBE" = "true" ] && modules+="Kube "
    [ -z "$modules" ] && modules="${_zsh_cmd_dim}aucun${_zsh_cmd_nc}"
    _zsh_section "Modules" "$modules"

    # NVM Node version
    if [ "$ZSH_ENV_MODULE_NVM" = "true" ] && command -v node &> /dev/null; then
        _zsh_section "Node" "$(node --version 2>/dev/null)"
    fi

    # Shell
    _zsh_section "Shell" "zsh $ZSH_VERSION"

    echo ""
    echo -e "${_zsh_cmd_dim}Diagnostic complet: zsh-env-doctor${_zsh_cmd_nc}"
}

# ==============================================================================
# zsh-env-ghostty : Gestion des themes Ghostty
# ==============================================================================
zsh-env-ghostty() {
    local themes_dir="$ZSH_ENV_DIR/ghostty/themes"
    local ghostty_config="$HOME/.config/ghostty/config"
    local theme="$1"

    # Sans argument ou "list" : afficher les themes disponibles
    if [ -z "$theme" ] || [ "$theme" = "list" ]; then
        _zsh_header "Themes Ghostty"

        if [ ! -d "$themes_dir" ]; then
            echo -e "${_zsh_cmd_yellow}Aucun theme trouve dans $themes_dir${_zsh_cmd_nc}"
            return 1
        fi

        # Theme actuel (lit la ligne config-file de la config Ghostty)
        local current=""
        if [ -f "$ghostty_config" ]; then
            current=$(grep "^config-file" "$ghostty_config" 2>/dev/null | sed 's/.*themes\///' | tr -d ' ')
        fi

        for theme_file in "$themes_dir"/*; do
            [ -f "$theme_file" ] || continue
            local name=$(basename "$theme_file")
            local desc=$(grep -m1 "^# Ghostty Theme:" "$theme_file" 2>/dev/null | sed 's/^# Ghostty Theme: //' || echo "")

            if [ "$name" = "$current" ]; then
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
    if [ "$theme" = "sync" ]; then
        local src_config="$ZSH_ENV_DIR/ghostty/config"
        local dest_dir="$HOME/.config/ghostty"

        if [ ! -f "$src_config" ]; then
            echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Config source non trouvee: $src_config"
            return 1
        fi

        mkdir -p "$dest_dir"

        # Backup si existe et différent
        if [ -f "$ghostty_config" ] && ! diff -q "$src_config" "$ghostty_config" &>/dev/null; then
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

    if [ ! -f "$theme_file" ]; then
        echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Theme '$theme' non trouve."
        echo -e "Themes disponibles: $(ls "$themes_dir" 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    # Mettre à jour le fichier config local (dans zsh_env)
    local local_config="$ZSH_ENV_DIR/ghostty/config"

    if [ -f "$local_config" ]; then
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
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-update" "Mise a jour zsh_env"
    printf "${_zsh_cmd_cyan}%-28s${_zsh_cmd_nc} %s\n" "zsh-env-help" "Cette aide"

    echo ""
    _zsh_separator 50
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Config" "~/.zsh_env/config.zsh"
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Completions" "~/.zsh_env/completions.zsh"
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Themes" "~/.zsh_env/themes/"
    printf "${_zsh_cmd_dim}%-14s${_zsh_cmd_nc} %s\n" "Recharger" "ss (ou source ~/.zshrc)"
}
