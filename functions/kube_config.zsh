# ==============================================================================
# Kube Config Manager - Gestion des fichiers kubeconfig
# ==============================================================================
# Fonctions pour charger/selectionner des configurations Kubernetes
# Supporte le chiffrement via sops/age
# ==============================================================================

# --- Configuration ---
KUBE_DIR="$HOME/.kube"
KUBE_CONFIGS_DIR="$KUBE_DIR/configs.d"
KUBE_MINIMAL_CONFIG="$KUBE_DIR/config.minimal.yml"
KUBE_SOPS_SOURCE="$ZSH_ENV_DIR/kube"

# --- Fonctions internes ---

# Verifie que les outils necessaires sont installes
_kube_check_deps() {
    if ! command -v kubectl &> /dev/null; then
        echo "kubectl n'est pas installe." >&2
        return 1
    fi
    return 0
}

# Verifie si sops/age sont disponibles
_kube_has_sops() {
    command -v sops &> /dev/null && command -v age &> /dev/null
}

# Dechiffre un fichier .sops vers la destination
_kube_decrypt_sops() {
    local src="$1"
    local dest="$2"

    if ! _kube_has_sops; then
        echo "sops ou age non installe, impossible de dechiffrer $src" >&2
        return 1
    fi

    if sops -d "$src" > "$dest" 2>/dev/null; then
        return 0
    else
        echo "Echec du dechiffrement de $src" >&2
        return 1
    fi
}

# Liste toutes les configs disponibles (dechiffrees + locales)
_kube_list_configs() {
    local configs=()

    # Config minimale (toujours en premier)
    if [[ -f "$KUBE_MINIMAL_CONFIG" ]]; then
        configs+=("config.minimal.yml")
    fi

    # Configs dans configs.d/ (tous les fichiers réguliers)
    if [[ -d "$KUBE_CONFIGS_DIR" ]]; then
        for f in "$KUBE_CONFIGS_DIR"/*(N.); do
            configs+=("configs.d/$(basename "$f")")
        done
    fi

    printf '%s\n' "${configs[@]}"
}

# Verifie si une config est actuellement chargee dans KUBECONFIG
_kube_is_loaded() {
    local config_path="$1"
    [[ ":$KUBECONFIG:" == *":$config_path:"* ]]
}

# --- Fonctions publiques ---

# Initialise l'environnement kube (cree les dossiers, dechiffre si necessaire)
kube_init() {
    # Creation des dossiers
    [[ ! -d "$KUBE_DIR" ]] && mkdir -p "$KUBE_DIR"
    [[ ! -d "$KUBE_CONFIGS_DIR" ]] && mkdir -p "$KUBE_CONFIGS_DIR"

    # Dechiffrement des fichiers sops si presents
    if [[ -d "$KUBE_SOPS_SOURCE" ]] && _kube_has_sops; then
        local sops_files=("$KUBE_SOPS_SOURCE"/*.sops.yml(N) "$KUBE_SOPS_SOURCE"/*.sops.yaml(N))
        for sops_file in "${sops_files[@]}"; do
            [[ ! -f "$sops_file" ]] && continue

            local basename=$(basename "$sops_file")
            # Retire l'extension .sops.yml ou .sops.yaml
            local dest_name
            if [[ "$basename" == *.sops.yml ]]; then
                dest_name="${basename%.sops.yml}.yml"
            elif [[ "$basename" == *.sops.yaml ]]; then
                dest_name="${basename%.sops.yaml}.yaml"
            else
                # Fallback: retire juste .sops
                dest_name="${basename%.sops}"
            fi

            local dest_path="$KUBE_DIR/$dest_name"

            if [[ ! -f "$dest_path" ]] || [[ "$sops_file" -nt "$dest_path" ]]; then
                echo "Dechiffrement de $basename..."
                _kube_decrypt_sops "$sops_file" "$dest_path"
            fi
        done
    fi

    # Charge la config minimale par defaut
    if [[ -f "$KUBE_MINIMAL_CONFIG" ]]; then
        export KUBECONFIG="$KUBE_MINIMAL_CONFIG"
        echo "Config minimale chargee: $KUBE_MINIMAL_CONFIG"
    else
        echo "Aucune config minimale trouvee dans $KUBE_MINIMAL_CONFIG"
    fi
}

# Selecteur interactif de configs avec fzf
kube_select() {
    if ! command -v fzf &> /dev/null; then
        echo "fzf est requis pour cette fonction." >&2
        echo "Utilisez 'kube_add <fichier>' pour ajouter manuellement." >&2
        return 1
    fi

    local configs=()
    local display_lines=()

    # Config minimale
    if [[ -f "$KUBE_MINIMAL_CONFIG" ]]; then
        configs+=("$KUBE_MINIMAL_CONFIG")
        if _kube_is_loaded "$KUBE_MINIMAL_CONFIG"; then
            display_lines+=("● config.minimal.yml (base)")
        else
            display_lines+=("○ config.minimal.yml (base)")
        fi
    fi

    # Configs additionnelles
    if [[ -d "$KUBE_CONFIGS_DIR" ]]; then
        for f in "$KUBE_CONFIGS_DIR"/*(N.); do
            configs+=("$f")
            local name
            name=$(basename "$f")
            if _kube_is_loaded "$f"; then
                display_lines+=("● $name")
            else
                display_lines+=("○ $name")
            fi
        done
    fi

    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "Aucune configuration trouvee."
        echo "Placez vos fichiers dans: $KUBE_CONFIGS_DIR/"
        return 1
    fi

    # Selection avec fzf
    local header="●/○ = etat actuel | TAB: toggle | Ctrl-A: tout | Ctrl-N: rien"
    local selected
    selected=$(printf '%s\n' "${display_lines[@]}" | fzf --multi \
        --header="$header" \
        --prompt="Configs > " \
        --bind="ctrl-a:select-all" \
        --bind="ctrl-n:deselect-all")

    if [[ -z "$selected" ]]; then
        echo "Selection annulee. KUBECONFIG inchange."
        return 0
    fi

    # Construction du nouveau KUBECONFIG
    local new_kubeconfig=""

    while IFS= read -r line; do
        # Extrait le nom (retire le prefixe ● ou ○)
        local clean_name
        clean_name=$(echo "$line" | sed 's/^[●○] //')

        # Trouve le chemin complet
        for ((i=1; i<=${#display_lines[@]}; i++)); do
            local check_name
            check_name=$(echo "${display_lines[$i]}" | sed 's/^[●○] //')
            if [[ "$check_name" == "$clean_name" ]]; then
                if [[ -n "$new_kubeconfig" ]]; then
                    new_kubeconfig="$new_kubeconfig:${configs[$i]}"
                else
                    new_kubeconfig="${configs[$i]}"
                fi
                break
            fi
        done
    done <<< "$selected"

    if [[ -z "$new_kubeconfig" ]]; then
        unset KUBECONFIG
        echo "KUBECONFIG vide (utilise ~/.kube/config par defaut)."
    else
        export KUBECONFIG="$new_kubeconfig"
        echo "KUBECONFIG mis a jour:"
        kube_status
    fi
}

# Affiche les configs actuellement chargees
kube_status() {
    echo "Configs actives:"
    if [[ -z "$KUBECONFIG" ]]; then
        echo "  (aucune - utilise ~/.kube/config par defaut)"
        return
    fi

    IFS=':' read -rA configs <<< "$KUBECONFIG"
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            echo "  - $config"
        else
            echo "  - $config (MANQUANT)"
        fi
    done

    # Affiche le contexte actuel si kubectl est disponible
    if command -v kubectl &> /dev/null; then
        local ctx=$(kubectl config current-context 2>/dev/null)
        [[ -n "$ctx" ]] && echo "Contexte actuel: $ctx"
    fi
}

# Ajoute une config a KUBECONFIG
kube_add() {
    local config_file="$1"

    if [[ -z "$config_file" ]]; then
        echo "Usage: kube_add <fichier_config>" >&2
        return 1
    fi

    # Resout le chemin absolu
    if [[ ! "$config_file" = /* ]]; then
        config_file="$PWD/$config_file"
    fi

    if [[ ! -f "$config_file" ]]; then
        echo "Fichier non trouve: $config_file" >&2
        return 1
    fi

    if _kube_is_loaded "$config_file"; then
        echo "Config deja chargee: $config_file"
        return 0
    fi

    if [[ -n "$KUBECONFIG" ]]; then
        export KUBECONFIG="$KUBECONFIG:$config_file"
    else
        export KUBECONFIG="$config_file"
    fi

    echo "Config ajoutee: $config_file"
}

# Remet KUBECONFIG a la config minimale uniquement
kube_reset() {
    if [[ -f "$KUBE_MINIMAL_CONFIG" ]]; then
        export KUBECONFIG="$KUBE_MINIMAL_CONFIG"
        echo "KUBECONFIG reinitialise a la config minimale."
    else
        unset KUBECONFIG
        echo "KUBECONFIG vide (utilise ~/.kube/config par defaut)."
    fi
}

# Liste les configs disponibles
kube_list() {
    echo "Configs disponibles:"
    echo ""

    if [[ -f "$KUBE_MINIMAL_CONFIG" ]]; then
        if _kube_is_loaded "$KUBE_MINIMAL_CONFIG"; then
            echo "  [ACTIF] $KUBE_MINIMAL_CONFIG"
        else
            echo "         $KUBE_MINIMAL_CONFIG"
        fi
    fi

    if [[ -d "$KUBE_CONFIGS_DIR" ]]; then
        for f in "$KUBE_CONFIGS_DIR"/*(N.); do
            if _kube_is_loaded "$f"; then
                echo "  [ACTIF] $f"
            else
                echo "          $f"
            fi
        done
    fi

    # Fichiers sops non dechiffres
    if [[ -d "$KUBE_SOPS_SOURCE" ]]; then
        local has_sops=false
        for f in "$KUBE_SOPS_SOURCE"/*.sops "$KUBE_SOPS_SOURCE"/*.sops.yml "$KUBE_SOPS_SOURCE"/*.sops.yaml; do
            [[ ! -f "$f" ]] && continue
            if ! $has_sops; then
                echo ""
                echo "Fichiers chiffres (utilisez kube_init pour dechiffrer):"
                has_sops=true
            fi
            echo "          $f"
        done
    fi
}

# Chiffre une config existante avec sops/age
kube_encrypt() {
    local config_file="$1"

    if [[ -z "$config_file" ]]; then
        echo "Usage: kube_encrypt <fichier_config>" >&2
        return 1
    fi

    if ! _kube_has_sops; then
        echo "sops et age sont requis pour le chiffrement." >&2
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        echo "Fichier non trouve: $config_file" >&2
        return 1
    fi

    # Cree le dossier kube/ dans zsh_env si necessaire
    [[ ! -d "$KUBE_SOPS_SOURCE" ]] && mkdir -p "$KUBE_SOPS_SOURCE"

    local basename=$(basename "$config_file")
    local dest="$KUBE_SOPS_SOURCE/${basename%.yml}.sops.yml"
    dest="${dest%.yaml}.sops.yml"

    if sops -e "$config_file" > "$dest"; then
        echo "Fichier chiffre: $dest"
        echo "Vous pouvez maintenant le versionner dans Git."
    else
        echo "Echec du chiffrement." >&2
        return 1
    fi
}

# ==============================================================================
# Azure AKS - Recuperation dynamique des credentials
# ==============================================================================

# Configuration des clusters Azure AKS
# Format: "label:subscription:resource-group:cluster-name"
_KUBE_AZ_CLUSTERS=(
    # BLG
    "blg-dev:sub-org-cluster:rg-org-cluster-dev:aks-org-cluster-dev"
    "blg-qlf:sub-org-cluster:rg-org-cluster-qlf:aks-org-cluster-qlf"
    "blg-pprd:sub-org-cluster:rg-org-cluster-pprd:aks-org-cluster-pprd"
    "blg-prd:sub-org-cluster:rg-org-cluster-prd:aks-org-cluster-prd"
    # EDT
    "edt-dev:sub-org-cluster:rg-org-cluster-dev:aks-org-cluster-dev"
    "edt-qlf:sub-org-cluster:rg-org-cluster-qlf:aks-org-cluster-qlf"
    "edt-pprd:sub-org-cluster:rg-org-cluster-pprd:aks-org-cluster-pprd"
    "edt-prd:sub-org-cluster:rg-org-cluster-prd:aks-org-cluster-prd"
)

# Verifie les dependances Azure
_kube_az_check_deps() {
    local missing=()
    command -v az &> /dev/null || missing+=("az")
    command -v kubelogin &> /dev/null || missing+=("kubelogin")
    command -v kubectl &> /dev/null || missing+=("kubectl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Outils manquants: ${missing[*]}" >&2
        echo "Installez-les via: brew install azure-cli kubelogin kubectl" >&2
        return 1
    fi
    return 0
}

# Verifie la connexion Azure et retourne les infos du compte
_kube_az_check_login() {
    local account_info
    account_info=$(az account show 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$account_info" ]]; then
        return 1
    fi

    echo "$account_info"
    return 0
}

# Affiche les infos du compte Azure connecte
_kube_az_show_account() {
    local account_info="$1"
    local user_name=$(echo "$account_info" | jq -r '.user.name // "inconnu"')
    local user_type=$(echo "$account_info" | jq -r '.user.type // "inconnu"')
    local tenant=$(echo "$account_info" | jq -r '.tenantId // "inconnu"')
    local subscription=$(echo "$account_info" | jq -r '.name // "inconnu"')

    echo "Compte Azure connecte:"
    echo "  Utilisateur: $user_name ($user_type)"
    echo "  Subscription: $subscription"
    echo "  Tenant: ${tenant:0:8}..."
    echo ""
}

# Recupere les credentials pour un cluster Azure AKS
kube_azure() {
    if ! _kube_az_check_deps; then
        return 1
    fi

    # Verifier la connexion Azure
    local account_info
    account_info=$(_kube_az_check_login)

    if [[ $? -ne 0 ]]; then
        echo "Vous n'etes pas connecte a Azure." >&2
        echo ""
        read -q "reply?Lancer 'az login' maintenant? [y/N] "
        echo ""
        if [[ "$reply" == "y" ]]; then
            az login
            # Re-verifier apres login
            account_info=$(_kube_az_check_login)
            if [[ $? -ne 0 ]]; then
                echo "Echec de la connexion Azure." >&2
                return 1
            fi
        else
            return 1
        fi
    fi

    # Afficher le compte connecte
    _kube_az_show_account "$account_info"

    local cluster_label="$1"

    # Mode interactif si pas d'argument
    if [[ -z "$cluster_label" ]]; then
        if ! command -v fzf &> /dev/null; then
            echo "Usage: kube_azure <cluster>" >&2
            echo "Clusters disponibles:" >&2
            for entry in "${_KUBE_AZ_CLUSTERS[@]}"; do
                echo "  - ${entry%%:*}" >&2
            done
            return 1
        fi

        # Selection interactive avec fzf
        local labels=()
        for entry in "${_KUBE_AZ_CLUSTERS[@]}"; do
            labels+=("${entry%%:*}")
        done

        cluster_label=$(printf '%s\n' "${labels[@]}" | fzf --header="Selectionner un cluster Azure AKS" --prompt="Cluster > ")

        if [[ -z "$cluster_label" ]]; then
            echo "Selection annulee."
            return 0
        fi
    fi

    # Trouver le cluster dans la config
    local found=""
    for entry in "${_KUBE_AZ_CLUSTERS[@]}"; do
        if [[ "${entry%%:*}" == "$cluster_label" ]]; then
            found="$entry"
            break
        fi
    done

    if [[ -z "$found" ]]; then
        echo "Cluster '$cluster_label' non trouve." >&2
        echo "Clusters disponibles:" >&2
        for entry in "${_KUBE_AZ_CLUSTERS[@]}"; do
            echo "  - ${entry%%:*}" >&2
        done
        return 1
    fi

    # Parser l'entree
    local subscription resource_group cluster_name
    IFS=':' read -r _ subscription resource_group cluster_name <<< "$found"

    local kubeconfig_file="$KUBE_CONFIGS_DIR/kubeconfig-${cluster_label}.yml"

    echo "Recuperation des credentials pour $cluster_label..."
    echo "  Subscription: $subscription"
    echo "  Resource Group: $resource_group"
    echo "  Cluster: $cluster_name"

    # Recuperer les credentials
    if ! az aks get-credentials \
        --subscription "$subscription" \
        --resource-group "$resource_group" \
        --name "$cluster_name" \
        --file "$kubeconfig_file" \
        --overwrite-existing; then
        echo "Echec de la recuperation des credentials." >&2
        return 1
    fi

    # Convertir pour kubelogin
    echo "Conversion pour Azure CLI auth..."
    if ! KUBECONFIG="$kubeconfig_file" kubelogin convert-kubeconfig -l azurecli; then
        echo "Echec de la conversion kubelogin." >&2
        return 1
    fi

    echo ""
    echo "Config creee: $kubeconfig_file"

    # Proposer d'ajouter a KUBECONFIG
    echo ""
    read -q "reply?Ajouter a KUBECONFIG actuel? [y/N] "
    echo ""
    if [[ "$reply" == "y" ]]; then
        kube_add "$kubeconfig_file"
    fi
}

# Affiche le statut de connexion Azure
kube_azure_status() {
    if ! command -v az &> /dev/null; then
        echo "Azure CLI non installe." >&2
        return 1
    fi

    local account_info
    account_info=$(_kube_az_check_login)

    if [[ $? -ne 0 ]]; then
        echo "Non connecte a Azure."
        echo "Utilisez 'az login' pour vous connecter."
        return 1
    fi

    _kube_az_show_account "$account_info"

    # Afficher les subscriptions disponibles
    echo "Subscriptions disponibles:"
    az account list --query "[].{Name:name, ID:id, Default:isDefault}" -o table 2>/dev/null
}

# Liste les clusters Azure disponibles
kube_azure_list() {
    echo "Clusters Azure AKS disponibles:"
    echo ""

    local current_group=""
    for entry in "${_KUBE_AZ_CLUSTERS[@]}"; do
        local label="${entry%%:*}"
        local group="${label%%-*}"

        # Affiche le header du groupe
        if [[ "$group" != "$current_group" ]]; then
            [[ -n "$current_group" ]] && echo ""
            echo "  ${group:u}:"  # :u = uppercase
            current_group="$group"
        fi

        # Verifie si le fichier existe deja
        local kubeconfig_file="$KUBE_CONFIGS_DIR/kubeconfig-${label}.yml"
        if [[ -f "$kubeconfig_file" ]]; then
            echo "    [x] $label"
        else
            echo "    [ ] $label"
        fi
    done

    echo ""
    echo "Usage: kube_azure [cluster]"
}

# Aide rapide
kube_help() {
    cat << 'EOF'
Kube Config Manager - Commandes disponibles:

  kube_init        Initialise l'environnement, dechiffre les configs sops
  kube_select      Selecteur interactif (fzf) pour choisir les configs
  kube_status      Affiche les configs actuellement chargees
  kube_list        Liste toutes les configs disponibles
  kube_add         Ajoute une config a KUBECONFIG
  kube_reset       Remet uniquement la config minimale
  kube_encrypt     Chiffre une config avec sops/age pour Git

Azure AKS:
  kube_azure        Recupere les credentials d'un cluster Azure (interactif)
  kube_azure_list   Liste les clusters Azure disponibles
  kube_azure_status Affiche le compte Azure connecte

Emplacements:
  Config minimale : ~/.kube/config.minimal.yml
  Configs add.    : ~/.kube/configs.d/
  Fichiers sops   : ~/.zsh_env/kube/
EOF
}

# ==============================================================================
# Initialisation automatique au chargement
# ==============================================================================
# Charge silencieusement la config minimale si elle existe
if [[ -f "$KUBE_MINIMAL_CONFIG" ]] && [[ -z "$KUBECONFIG" ]]; then
    export KUBECONFIG="$KUBE_MINIMAL_CONFIG"
fi
