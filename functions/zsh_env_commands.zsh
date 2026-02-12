# ==============================================================================
# Commandes utilitaires ZSH_ENV
# ==============================================================================

# Couleurs
_zsh_cmd_green=$'\033[0;32m'
_zsh_cmd_red=$'\033[0;31m'
_zsh_cmd_yellow=$'\033[1;33m'
_zsh_cmd_blue=$'\033[0;34m'
_zsh_cmd_cyan=$'\033[0;36m'
_zsh_cmd_bold=$'\033[1m'
_zsh_cmd_nc=$'\033[0m'

# ==============================================================================
# zsh-env-list : Lister les outils installes
# ==============================================================================
zsh-env-list() {
    echo -e "${_zsh_cmd_bold}=== Outils installes ===${_zsh_cmd_nc}\n"

    # Liste des outils a verifier
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
                eza) version=$(eza --version 2>/dev/null | head -1 | awk '{print $1}') ;;
                starship) version=$(starship --version 2>/dev/null | awk '{print $2}') ;;
                bat) version=$(bat --version 2>/dev/null | awk '{print $2}') ;;
                nu) version=$(nu --version 2>/dev/null) ;;
                fzf) version=$(fzf --version 2>/dev/null | awk '{print $1}') ;;
                jq) version=$(jq --version 2>/dev/null | sed 's/jq-//') ;;
                nvm) version=$(nvm --version 2>/dev/null) ;;
                sdk) version="installed" ;;
                docker) version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',') ;;
                kubectl) version=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}') ;;
                kubelogin) version=$(kubelogin --version 2>/dev/null | head -1 | awk '{print $2}') ;;
                az) version=$(az version 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null) ;;
                helm) version=$(helm version --short 2>/dev/null | cut -d'+' -f1) ;;
                *) version="" ;;
            esac
            printf "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} %-12s ${_zsh_cmd_cyan}%-10s${_zsh_cmd_nc} %s\n" "$name" "$version" "$desc"
            ((installed++))
        else
            printf "  ${_zsh_cmd_red}✗${_zsh_cmd_nc} %-12s ${_zsh_cmd_yellow}%-10s${_zsh_cmd_nc} %s\n" "$name" "manquant" "$desc"
            ((missing++))
        fi
    done

    echo ""
    echo -e "${_zsh_cmd_bold}Resume:${_zsh_cmd_nc} ${_zsh_cmd_green}$installed installes${_zsh_cmd_nc} | ${_zsh_cmd_yellow}$missing manquants${_zsh_cmd_nc}"

    if [[ $missing -gt 0 ]]; then
        echo -e "\nPour installer les outils manquants: ${_zsh_cmd_bold}~/.zsh_env/install.sh${_zsh_cmd_nc}"
    fi
}

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

    # Verifier si la completion existe deja
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
    echo -e "${_zsh_cmd_bold}=== Chargement des completions ===${_zsh_cmd_nc}\n"

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
        source <(rustup completions zsh 2>/dev/null)
        source <(rustup completions zsh cargo 2>/dev/null)
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Rustup/Cargo"
        ((loaded++))
    fi

    # Completions personnalisees
    local custom_file="$ZSH_ENV_DIR/completions.zsh"
    if [[ -f "$custom_file" ]]; then
        source "$custom_file"

        local custom_loaded=0
        for entry in "${_ZSH_ENV_CUSTOM_COMPLETIONS[@]}"; do
            # Ignorer les lignes vides ou commentees
            [[ -z "$entry" || "$entry" == \#* ]] && continue

            local name="${entry%%:*}"
            local cmd="${entry#*:}"

            if command -v "$name" &> /dev/null; then
                # Capture la sortie de la commande puis eval avec stderr supprimé
                local comp_script
                comp_script=$($cmd 2>/dev/null)
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
            echo ""
            echo -e "${_zsh_cmd_cyan}$custom_loaded completion(s) personnalisee(s)${_zsh_cmd_nc}"
        fi
    fi

    echo ""
    echo -e "${_zsh_cmd_bold}$loaded completions chargees${_zsh_cmd_nc}"

    # Recharger le systeme de completion
    autoload -Uz compinit && compinit -C
}

# ==============================================================================
# zsh-env-theme : Gestion des themes Starship
# ==============================================================================
zsh-env-theme() {
    local themes_dir="$ZSH_ENV_DIR/themes"
    local starship_config="$HOME/.config/starship.toml"
    local theme="$1"

    # Verifier que Starship est installe
    if ! command -v starship &> /dev/null; then
        echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Starship n'est pas installe."
        return 1
    fi

    # Sans argument ou "list" : afficher les themes disponibles
    if [[ -z "$theme" ]] || [[ "$theme" == "list" ]]; then
        echo -e "${_zsh_cmd_bold}=== Themes Starship disponibles ===${_zsh_cmd_nc}\n"

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

            if [[ "$name" == "$current" ]]; then
                echo -e "  ${_zsh_cmd_green}*${_zsh_cmd_nc} ${_zsh_cmd_bold}$name${_zsh_cmd_nc} - $desc ${_zsh_cmd_cyan}(actif)${_zsh_cmd_nc}"
            else
                echo -e "  ${_zsh_cmd_cyan}○${_zsh_cmd_nc} $name - $desc"
            fi
        done

        echo ""
        echo -e "Usage: ${_zsh_cmd_bold}zsh-env-theme <nom>${_zsh_cmd_nc}"
        return 0
    fi

    # Appliquer un theme
    local theme_file="$themes_dir/$theme.toml"

    if [[ ! -f "$theme_file" ]]; then
        echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Theme '$theme' non trouve."
        echo -e "Themes disponibles: $(ls "$themes_dir"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/.toml//' | tr '\n' ' ')"
        return 1
    fi

    # Creer le dossier .config si necessaire
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
# zsh-env-doctor : Diagnostic de l'installation
# ==============================================================================
zsh-env-doctor() {
    echo -e "${_zsh_cmd_bold}=== ZSH_ENV Doctor ===${_zsh_cmd_nc}\n"

    local issues=0
    local warnings=0

    # --- Verification des fichiers critiques ---
    echo -e "${_zsh_cmd_bold}Fichiers de configuration${_zsh_cmd_nc}"

    local critical_files=(
        "$ZSH_ENV_DIR/rc.zsh:Point d'entree principal"
        "$ZSH_ENV_DIR/aliases.zsh:Fichier d'alias"
        "$ZSH_ENV_DIR/variables.zsh:Variables d'environnement"
        "$ZSH_ENV_DIR/functions.zsh:Loader de fonctions"
    )

    for entry in "${critical_files[@]}"; do
        local file="${entry%%:*}"
        local desc="${entry#*:}"
        if [[ -f "$file" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} $desc"
        else
            echo -e "  ${_zsh_cmd_red}✗${_zsh_cmd_nc} $desc ${_zsh_cmd_yellow}(manquant: $file)${_zsh_cmd_nc}"
            ((issues++))
        fi
    done

    # Config optionnelle
    if [[ -f "$ZSH_ENV_DIR/config.zsh" ]]; then
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Configuration personnalisee"
    else
        echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} Configuration personnalisee (utilise les valeurs par defaut)"
    fi

    # --- Verification du .zshrc ---
    echo ""
    echo -e "${_zsh_cmd_bold}Integration .zshrc${_zsh_cmd_nc}"

    if [[ -f "$HOME/.zshrc" ]]; then
        if grep -q "ZSH_ENV_DIR" "$HOME/.zshrc"; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} .zshrc configure correctement"
        else
            echo -e "  ${_zsh_cmd_red}✗${_zsh_cmd_nc} .zshrc ne contient pas ZSH_ENV_DIR"
            ((issues++))
        fi
    else
        echo -e "  ${_zsh_cmd_red}✗${_zsh_cmd_nc} .zshrc non trouve"
        ((issues++))
    fi

    # --- Verification des dependances ---
    echo ""
    echo -e "${_zsh_cmd_bold}Dependances requises${_zsh_cmd_nc}"

    local required_deps=("git" "curl" "jq")
    for dep in "${required_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} $dep"
        else
            echo -e "  ${_zsh_cmd_red}✗${_zsh_cmd_nc} $dep ${_zsh_cmd_yellow}(requis)${_zsh_cmd_nc}"
            ((issues++))
        fi
    done

    # --- Verification des outils recommandes ---
    echo ""
    echo -e "${_zsh_cmd_bold}Outils recommandes${_zsh_cmd_nc}"

    local recommended_deps=("starship" "zoxide" "fzf" "eza" "bat" "sops" "age")
    for dep in "${recommended_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} $dep"
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} $dep ${_zsh_cmd_cyan}(optionnel)${_zsh_cmd_nc}"
            ((warnings++))
        fi
    done

    # --- Outils Kubernetes/Azure ---
    echo ""
    echo -e "${_zsh_cmd_bold}Outils Kubernetes/Azure${_zsh_cmd_nc}"

    local kube_deps=("kubectl" "kubelogin" "az" "helm")
    for dep in "${kube_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            local version=""
            case "$dep" in
                kubectl) version=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}') ;;
                kubelogin) version=$(kubelogin --version 2>/dev/null | head -1 | awk '{print $2}') ;;
                az) version=$(az version 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null) ;;
                helm) version=$(helm version --short 2>/dev/null | cut -d'+' -f1) ;;
            esac
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} $dep ${_zsh_cmd_cyan}$version${_zsh_cmd_nc}"
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} $dep ${_zsh_cmd_cyan}(optionnel)${_zsh_cmd_nc}"
        fi
    done

    # --- Verification des modules ---
    echo ""
    echo -e "${_zsh_cmd_bold}Modules actifs${_zsh_cmd_nc}"

    [[ "$ZSH_ENV_MODULE_GITLAB" == "true" ]] && echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} GitLab" || echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} GitLab (desactive)"
    [[ "$ZSH_ENV_MODULE_DOCKER" == "true" ]] && echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Docker" || echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} Docker (desactive)"
    [[ "$ZSH_ENV_MODULE_NVM" == "true" ]] && echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} NVM" || echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} NVM (desactive)"
    [[ "$ZSH_ENV_MODULE_NUSHELL" == "true" ]] && echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Nushell" || echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} Nushell (desactive)"
    [[ "$ZSH_ENV_MODULE_KUBE" == "true" ]] && echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Kube" || echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} Kube (desactive)"

    # --- Verification NVM si actif ---
    if [[ "$ZSH_ENV_MODULE_NVM" == "true" ]]; then
        echo ""
        echo -e "${_zsh_cmd_bold}NVM${_zsh_cmd_nc}"

        if [[ -d "$NVM_DIR" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} NVM_DIR existe ($NVM_DIR)"
            if [[ "$ZSH_ENV_NVM_LAZY" == "true" ]]; then
                echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} Mode lazy-loading actif"
            fi
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} NVM_DIR non trouve (NVM non installe?)"
            ((warnings++))
        fi
    fi

    # --- Verification GitLab si actif ---
    if [[ "$ZSH_ENV_MODULE_GITLAB" == "true" ]]; then
        echo ""
        echo -e "${_zsh_cmd_bold}GitLab${_zsh_cmd_nc}"

        if [[ -n "$GITLAB_TOKEN" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} GITLAB_TOKEN defini"
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} GITLAB_TOKEN non defini (scripts GitLab ne fonctionneront pas)"
            ((warnings++))
        fi

        if [[ -n "$GITLAB_URL" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} GITLAB_URL: $GITLAB_URL"
        else
            echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} GITLAB_URL non defini (defaut: gitlab.com)"
        fi
    fi

    # --- Verification Kube si actif ---
    if [[ "$ZSH_ENV_MODULE_KUBE" == "true" ]]; then
        echo ""
        echo -e "${_zsh_cmd_bold}Kubernetes${_zsh_cmd_nc}"

        # kubectl
        if command -v kubectl &> /dev/null; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} kubectl installe"
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} kubectl non installe"
            ((warnings++))
        fi

        # Config minimale
        if [[ -f "$HOME/.kube/config.minimal.yml" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Config minimale presente"
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} Config minimale non trouvee (~/.kube/config.minimal.yml)"
        fi

        # Dossier configs.d
        if [[ -d "$HOME/.kube/configs.d" ]]; then
            local config_count=$(ls -1 "$HOME/.kube/configs.d"/*.yml "$HOME/.kube/configs.d"/*.yaml 2>/dev/null | wc -l | tr -d ' ')
            echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} $config_count config(s) additionnelle(s) dans configs.d/"
        fi

        # KUBECONFIG actuel
        if [[ -n "$KUBECONFIG" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} KUBECONFIG defini"
        else
            echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} KUBECONFIG non defini (utilise ~/.kube/config)"
        fi

        # Azure CLI login status
        if command -v az &> /dev/null; then
            echo ""
            echo -e "${_zsh_cmd_bold}Azure${_zsh_cmd_nc}"
            local az_account=$(az account show 2>/dev/null)
            if [[ -n "$az_account" ]]; then
                local az_user=$(echo "$az_account" | jq -r '.user.name // "inconnu"')
                local az_sub=$(echo "$az_account" | jq -r '.name // "inconnu"')
                echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Connecte: $az_user"
                echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} Subscription: $az_sub"
            else
                echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} Non connecte (utilisez 'az login')"
            fi
        fi
    fi

    # --- Verification SOPS/Age ---
    if command -v sops &> /dev/null && command -v age &> /dev/null; then
        echo ""
        echo -e "${_zsh_cmd_bold}Chiffrement SOPS/Age${_zsh_cmd_nc}"

        local age_key_file="$HOME/.config/sops/age/keys.txt"
        if [[ -f "$age_key_file" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Cle age configuree"
            # Affiche la cle publique
            local pub_key=$(grep "public key:" "$age_key_file" 2>/dev/null | awk '{print $NF}')
            if [[ -n "$pub_key" ]]; then
                echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} Public: ${pub_key:0:20}..."
            fi
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} Cle age non configuree"
            echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} Generez avec: age-keygen -o ~/.config/sops/age/keys.txt"
            ((warnings++))
        fi

        # .sops.yaml
        if [[ -f "$ZSH_ENV_DIR/.sops.yaml" ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} .sops.yaml present"
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} .sops.yaml non trouve"
        fi

        # Fichiers chiffres
        local sops_files=$(ls -1 "$ZSH_ENV_DIR/kube"/*.sops* 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$sops_files" -gt 0 ]]; then
            echo -e "  ${_zsh_cmd_cyan}i${_zsh_cmd_nc} $sops_files fichier(s) chiffre(s) dans kube/"
        fi
    fi

    # --- Verification des permissions ---
    echo ""
    echo -e "${_zsh_cmd_bold}Permissions${_zsh_cmd_nc}"

    if [[ -x "$ZSH_ENV_DIR/install.sh" ]]; then
        echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} install.sh executable"
    else
        echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} install.sh non executable"
        ((warnings++))
    fi

    if [[ -d "$ZSH_ENV_DIR/scripts" ]]; then
        local non_exec=$(find "$ZSH_ENV_DIR/scripts" -name "*.sh" ! -perm -u+x 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$non_exec" -eq 0 ]]; then
            echo -e "  ${_zsh_cmd_green}✓${_zsh_cmd_nc} Scripts executables"
        else
            echo -e "  ${_zsh_cmd_yellow}○${_zsh_cmd_nc} $non_exec script(s) non executable(s)"
            ((warnings++))
        fi
    fi

    # --- Resume ---
    echo ""
    echo -e "${_zsh_cmd_bold}Resume${_zsh_cmd_nc}"

    if [[ $issues -eq 0 ]] && [[ $warnings -eq 0 ]]; then
        echo -e "  ${_zsh_cmd_green}Tout est OK!${_zsh_cmd_nc}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "  ${_zsh_cmd_green}OK${_zsh_cmd_nc} avec ${_zsh_cmd_yellow}$warnings avertissement(s)${_zsh_cmd_nc}"
    else
        echo -e "  ${_zsh_cmd_red}$issues probleme(s)${_zsh_cmd_nc} et ${_zsh_cmd_yellow}$warnings avertissement(s)${_zsh_cmd_nc}"
        echo ""
        echo -e "  Lancez ${_zsh_cmd_bold}~/.zsh_env/install.sh${_zsh_cmd_nc} pour corriger les problemes."
    fi
}

# ==============================================================================
# zsh-env-ghostty : Gestion des themes Ghostty
# ==============================================================================
zsh-env-ghostty() {
    local themes_dir="$ZSH_ENV_DIR/ghostty/themes"
    local ghostty_config="$HOME/.config/ghostty/config"
    local theme="$1"

    # Sans argument ou "list" : afficher les themes disponibles
    if [[ -z "$theme" ]] || [[ "$theme" == "list" ]]; then
        echo -e "${_zsh_cmd_bold}=== Themes Ghostty disponibles ===${_zsh_cmd_nc}\n"

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

            if [[ "$name" == "$current" ]]; then
                echo -e "  ${_zsh_cmd_green}*${_zsh_cmd_nc} ${_zsh_cmd_bold}$name${_zsh_cmd_nc} - $desc ${_zsh_cmd_cyan}(actif)${_zsh_cmd_nc}"
            else
                echo -e "  ${_zsh_cmd_cyan}○${_zsh_cmd_nc} $name - $desc"
            fi
        done

        echo ""
        echo -e "Usage: ${_zsh_cmd_bold}zsh-env-ghostty <nom>${_zsh_cmd_nc}"
        echo -e "Sync:  ${_zsh_cmd_bold}zsh-env-ghostty sync${_zsh_cmd_nc} (copie la config vers ~/.config/ghostty)"
        return 0
    fi

    # Commande "sync" : deployer la config de zsh_env vers ~/.config/ghostty
    if [[ "$theme" == "sync" ]]; then
        local src_config="$ZSH_ENV_DIR/ghostty/config"
        local dest_dir="$HOME/.config/ghostty"

        if [[ ! -f "$src_config" ]]; then
            echo -e "${_zsh_cmd_red}[ERROR]${_zsh_cmd_nc} Config source non trouvee: $src_config"
            return 1
        fi

        mkdir -p "$dest_dir"

        # Backup si existe et different
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

    # Mettre a jour le fichier config local (dans zsh_env)
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

# ==============================================================================
# zsh-env-help : Afficher l'aide
# ==============================================================================
zsh-env-help() {
    cat << EOF
${_zsh_cmd_bold}=== Commandes ZSH_ENV ===${_zsh_cmd_nc}

${_zsh_cmd_cyan}zsh-env-list${_zsh_cmd_nc}
    Liste les outils installes et leur version

${_zsh_cmd_cyan}zsh-env-completions${_zsh_cmd_nc}
    Charge les auto-completions pour les outils disponibles

${_zsh_cmd_cyan}zsh-env-completion-add <nom> <commande>${_zsh_cmd_nc}
    Ajoute une completion personnalisee
    Ex: zsh-env-completion-add bun "bun completions"

${_zsh_cmd_cyan}zsh-env-completion-remove <nom>${_zsh_cmd_nc}
    Supprime une completion personnalisee

${_zsh_cmd_cyan}zsh-env-status${_zsh_cmd_nc}
    Affiche le statut et la configuration de zsh_env

${_zsh_cmd_cyan}zsh-env-update${_zsh_cmd_nc}
    Force la verification et mise a jour de zsh_env

${_zsh_cmd_cyan}zsh-env-doctor${_zsh_cmd_nc}
    Diagnostic complet de l'installation

${_zsh_cmd_cyan}zsh-env-theme [nom]${_zsh_cmd_nc}
    Applique un theme Starship (list pour voir les themes)

${_zsh_cmd_cyan}zsh-env-ghostty [nom|sync]${_zsh_cmd_nc}
    Gestion des themes Ghostty
    - list: affiche les themes disponibles
    - sync: deploie la config vers ~/.config/ghostty
    - <nom>: selectionne un theme

${_zsh_cmd_cyan}zsh-env-help${_zsh_cmd_nc}
    Affiche cette aide

${_zsh_cmd_bold}Configuration:${_zsh_cmd_nc} ~/.zsh_env/config.zsh
${_zsh_cmd_bold}Completions:${_zsh_cmd_nc}   ~/.zsh_env/completions.zsh
${_zsh_cmd_bold}Themes:${_zsh_cmd_nc}        ~/.zsh_env/themes/ (Starship)
${_zsh_cmd_bold}Ghostty:${_zsh_cmd_nc}       ~/.zsh_env/ghostty/
${_zsh_cmd_bold}Recharger:${_zsh_cmd_nc}     ss (ou source ~/.zshrc)
EOF
}
