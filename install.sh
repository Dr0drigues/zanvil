#!/bin/bash
# ==============================================================================
# Script : install.sh
# Description : Bootstrapping de l'environnement de développement (Zsh, Tools)
# Support : MacOS (Homebrew), Debian/Ubuntu (apt), Fedora (dnf)
# ==============================================================================

# --- Couleurs & UI ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Gestion des Arguments ---
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo -e "${BOLD}USAGE${NC}"
            echo "    $0 [OPTIONS]"
            echo ""
            echo -e "${BOLD}OPTIONS${NC}"
            echo "    --default     Installation sans configuration interactive"
            echo "    --check       Verifie les dependances sans rien installer"
            echo "    -h, --help    Affiche cette aide"
            exit 0
            ;;
        --default)
            INTERACTIVE=false
            shift
            ;;
        --check)
            CHECK_MODE=true
            shift
            ;;
        *)
            log_error "Option inconnue: $1"
            exit 1
            ;;
    esac
done

# --- Avertissement si exécuté en tant que root ---
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    log_warn "Ce script est execute en tant que root. Il est recommande de l'executer avec votre utilisateur normal."
    log_warn "Les fichiers de configuration seront crees dans /root au lieu de votre \$HOME."
fi

# --- Vérification de sudo ---
_sudo_available() {
    if command -v sudo &> /dev/null; then
        return 0
    else
        log_error "sudo n'est pas disponible. Impossible d'executer les commandes privilegiees."
        log_error "Installez sudo ou executez ce script en tant que root."
        return 1
    fi
}

# --- Mode --check : vérification des dépendances ---
if [[ "${CHECK_MODE:-false}" = true ]]; then
    # Détection de la plateforme pour affichage
    case "$(uname -s)" in
        Darwin*) _check_platform="macOS (brew)" ;;
        Linux*)
            if [[ -f /etc/debian_version ]]; then _check_platform="Linux (apt)"
            elif [[ -f /etc/fedora-release ]]; then _check_platform="Linux (dnf)"
            else _check_platform="Linux (inconnu)"; fi
            ;;
        *) _check_platform="inconnu" ;;
    esac

    echo -e "${BOLD}=== Verification des dependances ===${NC}"
    echo -e "Plateforme : ${CYAN}${_check_platform}${NC}\n"

    _check_installed=0
    _check_missing=0

    # Liste des outils attendus (nom binaire)
    _check_deps=(
        git curl zsh jq tmux
        eza starship zoxide fzf bat nu direnv trash mise
        sops age
        kubectl kubelogin az helm
        atuin lazygit delta posting docker
    )

    for _dep in "${_check_deps[@]}"; do
        if command -v "$_dep" &> /dev/null; then
            _ver=$("$_dep" --version 2>/dev/null | head -1 || echo "?")
            echo -e "  ${GREEN}✓${NC} $_dep  ${CYAN}${_ver}${NC}"
            ((_check_installed++))
        else
            echo -e "  ${RED}✗${NC} $_dep  ${RED}manquant${NC}"
            ((_check_missing++))
        fi
    done

    echo ""
    echo -e "${BOLD}Resume :${NC} ${GREEN}${_check_installed} installes${NC}, ${RED}${_check_missing} manquants${NC}"
    exit 0
fi

# --- Détection OS & Package Manager ---
OS="$(uname -s)"
PKG_MANAGER=""
INSTALL_CMD=""

detect_platform() {
    case "${OS}" in
        Linux*)
            if [[ -f /etc/debian_version ]]; then
                PKG_MANAGER="apt"
                INSTALL_CMD="sudo apt-get install -y"
                log_info "Système détecté : Linux (Debian/Ubuntu)"
            elif [[ -f /etc/fedora-release ]]; then
                PKG_MANAGER="dnf"
                INSTALL_CMD="sudo dnf install -y"
                log_info "Système détecté : Linux (Fedora)"
            else
                log_error "Distribution Linux non supportée automatiquement."
                exit 1
            fi
            ;;
        Darwin*)
            PKG_MANAGER="brew"
            INSTALL_CMD="brew install"
            log_info "Système détecté : MacOS"
            
            # Vérification présence Homebrew
            if ! command -v brew &> /dev/null; then
                log_warn "Homebrew n'est pas installé. Installation en cours..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            ;;
        *)
            log_error "OS inconnu : ${OS}"
            exit 1
            ;;
    esac
}

# --- Fonction d'installation générique ---
install_tool() {
    local tool_name=$1      # Nom pour l'affichage
    local brew_pkg=$2       # Nom du paquet Brew
    local apt_pkg=$3        # Nom du paquet Apt
    local dnf_pkg=$4        # Nom du paquet Dnf (souvent idem apt)
    
    # Si le binaire existe déjà, on skip (sauf demande de force update, mais restons simple)
    if command -v "$tool_name" &> /dev/null; then
        log_success "$tool_name est déjà installé."
        return
    fi

    echo -ne "${YELLOW}Installation de $tool_name...${NC} "
    
    local pkg=""
    case "$PKG_MANAGER" in
        brew) pkg="$brew_pkg" ;;
        apt)  pkg="$apt_pkg" ;;
        dnf)  pkg="$dnf_pkg" ;;
    esac

    # Si le nom du paquet est vide pour cet OS, on tente une install manuelle ou on skip
    if [[ -z "$pkg" ]]; then
        echo ""
        log_warn "Pas de paquet connu pour $tool_name sur $PKG_MANAGER."
        return
    fi

    # Vérifier sudo pour les gestionnaires qui en ont besoin
    if [[ "$PKG_MANAGER" == "apt" || "$PKG_MANAGER" == "dnf" ]]; then
        if ! _sudo_available; then
            return 1
        fi
    fi

    # Exécution de l'installation (rediriger stderr vers stdout pour le log si besoin)
    if $INSTALL_CMD "$pkg" &> /dev/null; then
        echo -e "${GREEN}Fait.${NC}"
    else
        echo -e "${RED}Échec.${NC}"
        log_error "Impossible d'installer $pkg"
    fi
}

# --- Main Script ---

echo -e "${BOLD}=== Initialisation de l'environnement de Dev ===${NC}\n"

detect_platform

# Mise à jour des index de paquets (Linux uniquement)
if [[ "$PKG_MANAGER" == "apt" ]]; then
    if _sudo_available; then
        log_info "Mise à jour des dépôts apt..."
        sudo apt-get update -qq
    fi
fi

echo ""
log_info "Vérification des outils core..."

# Liste des outils : Nom_Binaire | Paquet_Brew | Paquet_Apt | Paquet_Dnf

# 1. Shell & Utils de base
install_tool "git"      "git"       "git"       "git"
install_tool "curl"     "curl"      "curl"      "curl"
install_tool "zsh"      "zsh"       "zsh"       "zsh"
install_tool "jq"       "jq"        "jq"        "jq"

# 2. Modern Tools (La demande utilisateur)
install_tool "eza"      "eza"       "eza"       "eza"  # Sur Debian/Ubuntu récent, sinon voir cargo
install_tool "starship" "starship"  ""          ""     # Souvent absent des vieux repos apt
install_tool "zoxide"   "zoxide"    "zoxide"    "zoxide"
install_tool "fzf"      "fzf"       "fzf"       "fzf"
install_tool "bat"      "bat"       "bat"       "bat"  # "cat" avec des ailes
install_tool "nu"       "nushell"   "nushell"   "nushell"
install_tool "direnv"   "direnv"    "direnv"    "direnv"  # Charge .envrc automatiquement
# Note: Sur Linux (trash-cli), la commande est souvent 'trash-put'
install_tool "trash"    "trash"     "trash-cli" "trash-cli"

# 5. Gestionnaire de versions (mise - remplace NVM + SDKMAN)
install_tool "mise"     "mise"      ""          ""

# 3. Outils de chiffrement (pour kubeconfig, secrets, etc.)
install_tool "sops"     "sops"      "sops"      "sops"
install_tool "age"      "age"       "age"       "age"

# 4. Outils Kubernetes / Azure
install_tool "kubectl"    "kubectl"     "kubectl"     "kubectl"
install_tool "kubelogin"  "kubelogin"   ""            ""
install_tool "az"         "azure-cli"   ""            ""
install_tool "helm"       "helm"        "helm"        "helm"

# --- Outils optionnels modules/tools/* ---
# Installés automatiquement si le module est activé dans config.zsh mais le binaire absent.
_config_file="${ZSH_ENV_DIR:-$HOME/.zsh_env}/config.zsh"
if [[ -f "${_config_file}" ]]; then
    _optional_tools=(
        "ZSH_ENV_MODULE_ATUIN:atuin:atuin:atuin:atuin"
        "ZSH_ENV_MODULE_LAZYGIT:lazygit:lazygit:lazygit:lazygit"
        "ZSH_ENV_MODULE_DELTA:delta:git-delta:git-delta:git-delta"
        "ZSH_ENV_MODULE_POSTING:posting:posting:posting:posting"
    )
    for _entry in "${_optional_tools[@]}"; do
        _guard=$(echo "$_entry" | cut -d: -f1)
        _bin=$(echo "$_entry"   | cut -d: -f2)
        _brew=$(echo "$_entry"  | cut -d: -f3)
        _apt=$(echo "$_entry"   | cut -d: -f4)
        _dnf=$(echo "$_entry"   | cut -d: -f5)
        _val=$(grep "^${_guard}=" "${_config_file}" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"' ')
        if [[ "${_val}" == "true" ]] && ! command -v "${_bin}" &>/dev/null; then
            log_warn "${_bin} requis par ${_guard} mais absent — installation..."
            install_tool "${_bin}" "${_brew}" "${_apt}" "${_dnf}"
        fi
    done
    unset _entry _guard _bin _brew _apt _dnf _val _optional_tools
fi
unset _config_file

# --- Installation manuelle pour les outils souvent absents d'APT/DNF ---

# Starship (Script officiel si non trouvé via gestionnaire)
if ! command -v starship &> /dev/null; then
    log_info "Installation manuelle de Starship..."
    log_warn "Le script d'installation est telecharge depuis starship.rs (HTTPS)"
    curl -sS --proto '=https' --tlsv1.2 https://starship.rs/install.sh | sh -s -- -y
fi

# mise (Script officiel si non trouve via gestionnaire)
if ! command -v mise &> /dev/null; then
    log_info "Installation manuelle de mise..."
    log_warn "Le script d'installation est telecharge depuis mise.jdx.dev (HTTPS)"
    curl -sS --proto '=https' --tlsv1.2 https://mise.jdx.dev/install.sh | sh
fi

# Configuration de mise pour supporter .nvmrc et .sdkmanrc
if command -v mise &> /dev/null; then
    mise settings set idiomatic_version_file true 2>/dev/null
fi

# Nushell (Si non trouvé via gestionnaire de paquets)
if ! command -v nu &> /dev/null; then
    log_info "Installation manuelle de Nushell..."
    # On télécharge la dernière release via GitHub (binaire statique)
    log_warn "Le binaire Nushell est telecharge depuis GitHub Releases (HTTPS)"
    nu_tmp_dir=$(mktemp -d)
    trap "rm -rf '$nu_tmp_dir'" EXIT
    nu_url=$(curl -s --proto '=https' --tlsv1.2 https://api.github.com/repos/nushell/nushell/releases/latest | \
        jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-musl.tar.gz")) | .browser_download_url')
    if [[ -n "$nu_url" && "$nu_url" == https://* ]]; then
        curl --proto '=https' --tlsv1.2 -L -o "$nu_tmp_dir/nu.tar.gz" "$nu_url"
    else
        log_error "URL de telechargement Nushell invalide"
    fi

    tar -xzf "$nu_tmp_dir/nu.tar.gz" -C "$nu_tmp_dir"
    # Deplacement du binaire
    nu_bin=$(find "$nu_tmp_dir" -maxdepth 2 -name "nu" -type f 2>/dev/null | head -1)
    if [[ -n "$nu_bin" ]]; then
        if _sudo_available; then
            sudo mv "$nu_bin" /usr/local/bin/
            log_success "Nushell installe."
        fi
    else
        log_error "Binaire Nushell non trouve apres extraction."
    fi
    rm -rf "$nu_tmp_dir"
    trap - EXIT
fi


# --- Configuration Automatique du .zshrc ---
echo ""
log_info "Configuration du shell..."

ZSHRC="$HOME/.zshrc"

# Dossier où se trouve ce script actuellement
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.zsh_env"

# 1. Vérification de l'emplacement
if [[ "$CURRENT_DIR" != "$TARGET_DIR" ]]; then
    log_warn "Le repo n'est pas dans $TARGET_DIR (Actuel: $CURRENT_DIR)"
    log_warn "Pour une installation standard, il est recommandé de cloner dans ~/.zsh_env"
    # On continue quand même en utilisant le chemin actuel pour la config
    TARGET_DIR="$CURRENT_DIR"
fi

# 2. Injection dans .zshrc
if grep -q "ZSH_ENV_DIR" "$ZSHRC"; then
    log_success "Votre .zshrc est déjà configuré."
else
    log_info "Modification de $ZSHRC..."

    # Backup de sécurité avec format identifiable
    BACKUP_FILE="$ZSHRC.dr0.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$ZSHRC" "$BACKUP_FILE"
    log_info "Backup créé: $BACKUP_FILE"

    cat <<EOF >> "$ZSHRC"

# =======================================================
# ZSH ENV CONFIGURATION
# =======================================================
# Init from zsh_env/install.sh
export ZSH_ENV_DIR="$TARGET_DIR"

if [[ -f "\$ZSH_ENV_DIR/rc.zsh" ]]; then
    source "\$ZSH_ENV_DIR/rc.zsh"
else
    echo "WARNING: ZSH_ENV_DIR not found at \$ZSH_ENV_DIR"
fi
# =======================================================
EOF
    log_success "Configuration injectée dans $ZSHRC"
fi

# --- Finalisation ---
# Vérification du dossier scripts
SCRIPTS_DIR="$TARGET_DIR/scripts"
if [[ ! -d "$SCRIPTS_DIR" ]]; then
    mkdir -p "$SCRIPTS_DIR"
fi

# --- Configuration SSL/TLS (certificats entreprise) ---
echo ""
log_info "Configuration SSL/TLS..."
if [[ -x "$TARGET_DIR/scripts/ssl-setup.sh" ]]; then
    "$TARGET_DIR/scripts/ssl-setup.sh"
else
    log_warn "Script ssl-setup.sh non trouve, etape ignoree"
fi

# --- Detection Contexte Work (reseau interne) ---
echo ""

# URL de probe interne (definir ZSH_ENV_WORK_NEXUS_URL dans env.d/work.zsh ou env)
NEXUS_URL="${ZSH_ENV_WORK_NEXUS_URL:-}"
WORK_DETECTED="false"

if [[ -n "$NEXUS_URL" ]]; then
    log_info "Detection du contexte Work (probe: $NEXUS_URL)..."
    _install_curl_opts="-s --connect-timeout 2 --max-time 2"
    [[ -f "$HOME/.ssl/ca-bundle.pem" ]] && _install_curl_opts+=" --cacert $HOME/.ssl/ca-bundle.pem"
    if curl $_install_curl_opts -o /dev/null -w "%{http_code}" "$NEXUS_URL" 2>/dev/null | grep -q "^[23]"; then
        log_success "Contexte Work detecte (probe accessible)"
        WORK_DETECTED="true"

        # Si SOPS est configure et les fichiers en clair existent sans .enc
        if command -v sops &>/dev/null && [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then
            WORK_DIR="$TARGET_DIR/work"
            mkdir -p "$WORK_DIR"

            # Chiffrer settings.xml si .enc n'existe pas
            if [[ -f "$WORK_DIR/settings.xml" ]] && [[ ! -f "$WORK_DIR/settings.xml.enc" ]]; then
                log_info "Chiffrement de settings.xml..."
                if sops -e "$WORK_DIR/settings.xml" > "$WORK_DIR/settings.xml.enc" 2>/dev/null; then
                    log_success "settings.xml.enc cree"
                else
                    log_warn "Echec du chiffrement de settings.xml"
                fi
            fi

            # Chiffrer certificates_unix.sh si .enc n'existe pas
            if [[ -f "$WORK_DIR/certificates_unix.sh" ]] && [[ ! -f "$WORK_DIR/certificates_unix.sh.enc" ]]; then
                log_info "Chiffrement de certificates_unix.sh..."
                if sops -e "$WORK_DIR/certificates_unix.sh" > "$WORK_DIR/certificates_unix.sh.enc" 2>/dev/null; then
                    log_success "certificates_unix.sh.enc cree"
                else
                    log_warn "Echec du chiffrement de certificates_unix.sh"
                fi
            fi
        fi
    else
        log_info "Hors contexte Work (mode personnel)"
    fi
else
    log_info "Aucune URL de probe Work configuree (voir env.d/work.zsh)"
fi

# --- Configuration Interactive des Modules ---
echo ""
echo -e "${BOLD}=== Configuration des Modules ===${NC}"

if [[ "$INTERACTIVE" = true ]]; then
    echo -e "Choisissez les modules a activer (Entree = valeur par defaut)\n"

    # Fonction pour poser une question oui/non
    ask_module() {
        local module_name="$1"
        local module_desc="$2"
        local default="$3"

        local prompt_default="O/n"
        [[ "$default" = "false" ]] && prompt_default="o/N"

        # Afficher sur stderr pour ne pas etre capture par $()
        printf "  ${CYAN}%s${NC} - %s [%s]: " "$module_name" "$module_desc" "$prompt_default" >&2
        read -r answer

        if [[ -z "$answer" ]]; then
            echo "$default"
        elif [[ "$answer" =~ ^[oOyY]$ ]]; then
            echo "true"
        else
            echo "false"
        fi
    }

    # Poser les questions pour les modules
    MODULE_GITLAB=$(ask_module "GitLab" "Scripts et fonctions GitLab (trigger-jobs, clone-projects)" "true")
    MODULE_DOCKER=$(ask_module "Docker" "Utilitaires Docker (dex, etc.)" "true")
    MODULE_MISE=$(ask_module "Mise" "Gestionnaire de versions (Node, Java, Maven, etc.)" "true")

    MODULE_NUSHELL=$(ask_module "Nushell" "Integration Nushell (aliases nu)" "true")
    MODULE_KUBE=$(ask_module "Kube" "Gestionnaire de configs Kubernetes (kube_select)" "true")

    # Configuration SOPS/Age (si module Kube actif)
    SOPS_CONFIGURED="false"
    if [[ "$MODULE_KUBE" = "true" ]]; then
        echo "" >&2
        echo -e "${BOLD}Configuration SOPS/Age:${NC}" >&2
        echo -e "  SOPS permet de chiffrer vos kubeconfig pour les versionner dans Git." >&2
        SETUP_SOPS=$(ask_module "SOPS" "Configurer le chiffrement avec age" "true")

        if [[ "$SETUP_SOPS" = "true" ]]; then
            AGE_KEY_DIR="$HOME/.config/sops/age"
            AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"

            if [[ -f "$AGE_KEY_FILE" ]]; then
                echo -e "  ${GREEN}Cle age existante detectee${NC}" >&2
                SOPS_CONFIGURED="true"
            elif command -v age-keygen &> /dev/null; then
                echo -e "  Generation d'une nouvelle cle age..." >&2
                mkdir -p "$AGE_KEY_DIR"
                age-keygen -o "$AGE_KEY_FILE" 2>&1 | head -2 >&2
                chmod 600 "$AGE_KEY_FILE"
                echo -e "  ${GREEN}Cle generee: $AGE_KEY_FILE${NC}" >&2
                SOPS_CONFIGURED="true"

                # Recupere la cle publique pour .sops.yaml
                AGE_PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" 2>/dev/null | awk '{print $NF}')
            else
                echo -e "  ${YELLOW}age-keygen non disponible, configuration SOPS ignoree${NC}" >&2
            fi
        fi
    fi

    # Theme Starship
    echo "" >&2
    echo -e "${BOLD}Theme Starship:${NC}" >&2
    if command -v starship &> /dev/null; then
        echo -e "  Choisissez un theme pour votre prompt:" >&2
        echo -e "    ${CYAN}1)${NC} minimal   - Prompt minimaliste" >&2
        echo -e "    ${CYAN}2)${NC} default   - Configuration equilibree (recommande)" >&2
        echo -e "    ${CYAN}3)${NC} powerline - Style powerline avec separateurs" >&2
        echo -e "    ${CYAN}4)${NC} plain     - Sans icones (compatible tous terminaux)" >&2
        echo -e "    ${CYAN}5)${NC} Garder ma configuration actuelle" >&2
        printf "  Choix [2]: " >&2
        read -r theme_choice
        case "$theme_choice" in
            1) STARSHIP_THEME="minimal" ;;
            3) STARSHIP_THEME="powerline" ;;
            4) STARSHIP_THEME="plain" ;;
            5) STARSHIP_THEME="" ;;
            *) STARSHIP_THEME="default" ;;
        esac
    else
        echo -e "  ${YELLOW}Starship non installe, theme ignore${NC}" >&2
        STARSHIP_THEME=""
    fi

    # Auto-update
    echo "" >&2
    echo -e "${BOLD}Auto-Update:${NC}" >&2
    AUTO_UPDATE=$(ask_module "Auto-Update" "Verifier les mises a jour automatiquement" "true")

    if [[ "$AUTO_UPDATE" = "true" ]]; then
        echo -e "  Frequence de verification:" >&2
        echo -e "    ${CYAN}1)${NC} Chaque demarrage" >&2
        echo -e "    ${CYAN}2)${NC} Tous les 7 jours (recommande)" >&2
        echo -e "    ${CYAN}3)${NC} Tous les 30 jours" >&2
        printf "  Choix [2]: " >&2
        read -r freq_choice
        case "$freq_choice" in
            1) UPDATE_FREQ=0 ;;
            3) UPDATE_FREQ=30 ;;
            *) UPDATE_FREQ=7 ;;
        esac

        echo -e "  Mode de mise a jour:" >&2
        echo -e "    ${CYAN}1)${NC} Demander confirmation (recommande)" >&2
        echo -e "    ${CYAN}2)${NC} Automatique (silencieux)" >&2
        printf "  Choix [1]: " >&2
        read -r mode_choice
        case "$mode_choice" in
            2) UPDATE_MODE="auto" ;;
            *) UPDATE_MODE="prompt" ;;
        esac
    else
        UPDATE_FREQ=7
        UPDATE_MODE="prompt"
    fi
else
    log_info "Mode --default : tous les modules actives"
    MODULE_GITLAB="true"
    MODULE_DOCKER="true"
    MODULE_MISE="true"
    MODULE_NUSHELL="true"
    MODULE_KUBE="true"
    STARSHIP_THEME="default"
    AUTO_UPDATE="true"
    UPDATE_FREQ=7
    UPDATE_MODE="prompt"
    SOPS_CONFIGURED="false"

    # Configuration SOPS automatique en mode default
    AGE_KEY_DIR="$HOME/.config/sops/age"
    AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"
    if [[ -f "$AGE_KEY_FILE" ]]; then
        SOPS_CONFIGURED="true"
    elif command -v age-keygen &> /dev/null; then
        mkdir -p "$AGE_KEY_DIR"
        age-keygen -o "$AGE_KEY_FILE" 2>/dev/null
        chmod 600 "$AGE_KEY_FILE"
        SOPS_CONFIGURED="true"
    fi
fi

# --- Docker BuildKit (si module Docker actif) ---
if [[ "$MODULE_DOCKER" = "true" ]]; then
    if ! docker buildx version &>/dev/null 2>&1; then
        log_info "Installation de docker-buildx (BuildKit)..."
        install_tool "docker-buildx" "docker-buildx" "docker-buildx-plugin" "docker-buildx-plugin"

        # Fallback : installation manuelle depuis GitHub si le paquet n'est pas disponible
        if ! docker buildx version &>/dev/null 2>&1; then
            log_info "Installation manuelle de docker-buildx..."
            local buildx_version="v0.21.1"
            local buildx_arch
            case "$(uname -m)" in
                x86_64)  buildx_arch="amd64" ;;
                arm64|aarch64) buildx_arch="arm64" ;;
                *) log_warn "Architecture non supportee pour buildx: $(uname -m)"; buildx_arch="" ;;
            esac

            if [[ -n "$buildx_arch" ]]; then
                local buildx_os
                case "$(uname -s)" in
                    Darwin) buildx_os="darwin" ;;
                    Linux)  buildx_os="linux" ;;
                esac
                local buildx_url="https://github.com/docker/buildx/releases/download/${buildx_version}/buildx-${buildx_version}.${buildx_os}-${buildx_arch}"
                local buildx_dir="$HOME/.docker/cli-plugins"
                mkdir -p "$buildx_dir"
                if curl -sSL "$buildx_url" -o "$buildx_dir/docker-buildx"; then
                    chmod +x "$buildx_dir/docker-buildx"
                    log_success "docker-buildx installe dans $buildx_dir"
                else
                    log_warn "Impossible de telecharger docker-buildx — BuildKit ne sera pas disponible"
                fi
            fi
        fi
    else
        log_success "docker-buildx est deja installe."
    fi

    # --- Configuration Colima pour contexte Work ---
    if [[ "$WORK_DETECTED" = "true" ]] && command -v colima &>/dev/null; then
        local colima_config="$HOME/.colima/default/colima.yaml"
        local colima_pool="${ZSH_ENV_DOCKER_ADDRESS_POOL:-172.20.0.0/16}"
        local colima_pool_escaped="${colima_pool//\//\\/}"

        if [[ -f "$colima_config" ]]; then
            log_info "Configuration de Colima pour le contexte Work..."

            # Docker daemon config (remplace docker: {})
            if grep -q "^docker: {}" "$colima_config" 2>/dev/null; then
                sed -i.bak "s/^docker: {}/docker:\\
  debug: true\\
  default-address-pools:\\
    - base: \"${colima_pool_escaped}\"\\
      size: 24\\
  experimental: false\\
  insecure-registries: []\\
  registry-mirrors: []/" "$colima_config" && rm -f "${colima_config}.bak"
                log_success "Docker daemon configure (address-pools, debug)"
            else
                log_info "Docker daemon deja configure dans colima.yaml"
            fi

            # Provision script pour injecter le CA corporate dans la VM
            if grep -q "^provision: null" "$colima_config" 2>/dev/null || grep -q "^provision: \[\]" "$colima_config" 2>/dev/null; then
                sed -i.bak '/^provision: .*$/c\
provision:\
  - mode: system\
    script: |\
      CA_BUNDLE="/Users/'"$USER"'/.ssl/ca-bundle.pem"\
      DEST="/usr/local/share/ca-certificates/corporate-ca.crt"\
      if [ -f "$CA_BUNDLE" ]; then\
        if ! cmp -s "$CA_BUNDLE" "$DEST" 2>/dev/null; then\
          cp "$CA_BUNDLE" "$DEST"\
          update-ca-certificates\
          systemctl restart docker\
        fi\
      fi' "$colima_config" && rm -f "${colima_config}.bak"
                log_success "Provision CA corporate configure"
            else
                log_info "Provision deja configure dans colima.yaml"
            fi

            echo ""
            log_warn "Redemarrer Colima pour appliquer : colima stop && colima start"
        else
            log_info "Colima detecte mais pas encore initialise (lancer 'colima start' d'abord)"
        fi
    fi
fi

# Generer le fichier config.zsh
CONFIG_FILE="$TARGET_DIR/config.zsh"
echo ""
log_info "Generation de $CONFIG_FILE..."

cat > "$CONFIG_FILE" << EOF
# ==============================================================================
# Configuration ZSH_ENV - Generee par install.sh
# ==============================================================================
# Modifiez ce fichier pour activer/desactiver des modules
# Rechargez avec: ss (ou source ~/.zshrc)
# ==============================================================================

# Modules (true = active, false = desactive)
ZSH_ENV_MODULE_GITLAB=$MODULE_GITLAB
ZSH_ENV_MODULE_DOCKER=$MODULE_DOCKER
ZSH_ENV_MODULE_MISE=$MODULE_MISE
ZSH_ENV_MODULE_NUSHELL=$MODULE_NUSHELL
ZSH_ENV_MODULE_KUBE=$MODULE_KUBE

# Plugins
ZSH_ENV_PLUGINS_ORG=zsh-users
ZSH_ENV_PLUGINS=(
    zsh-syntax-highlighting
    zsh-autosuggestions
)

# Auto-Update
ZSH_ENV_AUTO_UPDATE=$AUTO_UPDATE
ZSH_ENV_UPDATE_FREQUENCY=$UPDATE_FREQ
ZSH_ENV_UPDATE_MODE="$UPDATE_MODE"

# Contexte Work (detecte a l'installation)
ZSH_ENV_WORK_DETECTED=$WORK_DETECTED
EOF

log_success "Configuration sauvegardee"

# Creation du fichier .sops.yaml si SOPS configure
if [[ "$SOPS_CONFIGURED" = "true" ]] && [[ -n "$AGE_PUBLIC_KEY" ]]; then
    SOPS_CONFIG="$TARGET_DIR/.sops.yaml"
    if [[ ! -f "$SOPS_CONFIG" ]]; then
        log_info "Creation de $SOPS_CONFIG..."
        cat > "$SOPS_CONFIG" << SOPSEOF
# Configuration SOPS pour le chiffrement des fichiers sensibles
# Generee par install.sh
creation_rules:
  - path_regex: .*\.sops\.ya?ml$
    age: $AGE_PUBLIC_KEY
  - path_regex: kube/.*\.sops$
    age: $AGE_PUBLIC_KEY
SOPSEOF
        log_success "Configuration SOPS creee"
    fi

    # Cree le dossier kube/ pour les configs chiffrees
    mkdir -p "$TARGET_DIR/kube"
fi

# Appliquer le theme Starship si choisi
if [[ -n "$STARSHIP_THEME" ]]; then
    mkdir -p "$HOME/.config"
    if [[ -f "$TARGET_DIR/themes/$STARSHIP_THEME/prompt.toml" ]]; then
        cp "$TARGET_DIR/themes/$STARSHIP_THEME/prompt.toml" "$HOME/.config/starship.toml"
    elif [[ -f "$TARGET_DIR/themes/$STARSHIP_THEME.toml" ]]; then
        cp "$TARGET_DIR/themes/$STARSHIP_THEME.toml" "$HOME/.config/starship.toml"
    fi
    echo "$STARSHIP_THEME" > "$TARGET_DIR/.current_theme"
    log_success "Theme Starship '$STARSHIP_THEME' applique"
fi

# Build du CLI Rust (optionnel, necessite cargo)
if command -v cargo &>/dev/null; then
    log_info "Build de zsh-env-cli..."
    if (cd "$TARGET_DIR/cli" && cargo build --release 2>/dev/null); then
        mkdir -p "$HOME/.local/bin"
        cp "$TARGET_DIR/cli/target/release/zsh-env-cli" "$HOME/.local/bin/"
        log_success "zsh-env-cli installe dans ~/.local/bin/"
    else
        log_warn "Build de zsh-env-cli echoue (optionnel, les commandes zsh fonctionnent sans)"
    fi
else
    log_info "cargo non trouve — zsh-env-cli non installe (optionnel)"
fi

# Resume
echo ""
echo -e "${CYAN}Modules actives:${NC}"
[[ "$MODULE_GITLAB" = "true" ]] && echo -e "  ${GREEN}✓${NC} GitLab"
[[ "$MODULE_DOCKER" = "true" ]] && echo -e "  ${GREEN}✓${NC} Docker"
[[ "$MODULE_MISE" = "true" ]] && echo -e "  ${GREEN}✓${NC} Mise (Node, Java, Maven)"
[[ "$MODULE_NUSHELL" = "true" ]] && echo -e "  ${GREEN}✓${NC} Nushell"
[[ "$MODULE_KUBE" = "true" ]] && echo -e "  ${GREEN}✓${NC} Kube (kubeconfig manager)"

echo -e "${CYAN}Modules desactives:${NC}"
[[ "$MODULE_GITLAB" = "false" ]] && echo -e "  ${RED}✗${NC} GitLab"
[[ "$MODULE_DOCKER" = "false" ]] && echo -e "  ${RED}✗${NC} Docker"
[[ "$MODULE_MISE" = "false" ]] && echo -e "  ${RED}✗${NC} Mise"
[[ "$MODULE_NUSHELL" = "false" ]] && echo -e "  ${RED}✗${NC} Nushell"
[[ "$MODULE_KUBE" = "false" ]] && echo -e "  ${RED}✗${NC} Kube"

echo ""
echo -e "${CYAN}Theme Starship:${NC}"
if [[ -n "$STARSHIP_THEME" ]]; then
    echo -e "  ${GREEN}✓${NC} $STARSHIP_THEME"
else
    echo -e "  ${YELLOW}○${NC} Non modifie"
fi

echo ""
echo -e "${CYAN}Auto-Update:${NC}"
if [[ "$AUTO_UPDATE" = "true" ]]; then
    echo -e "  ${GREEN}✓${NC} Active (tous les ${UPDATE_FREQ} jours, mode: ${UPDATE_MODE})"
else
    echo -e "  ${RED}✗${NC} Desactive"
fi

echo ""
echo -e "${CYAN}Chiffrement SOPS/Age:${NC}"
if [[ "$SOPS_CONFIGURED" = "true" ]]; then
    echo -e "  ${GREEN}✓${NC} Configure"
    echo -e "  Cle: ~/.config/sops/age/keys.txt"
    if [[ -n "$AGE_PUBLIC_KEY" ]]; then
        echo -e "  Public: $AGE_PUBLIC_KEY"
    fi
else
    echo -e "  ${YELLOW}○${NC} Non configure (utilisez 'age-keygen' pour creer une cle)"
fi

echo -e "\n${BOLD}=== Installation Terminee ===${NC}"
echo -e "Redemarrez votre terminal ou lancez : ${BOLD}source ~/.zshrc${NC}"
echo -e "Pour modifier les modules : ${BOLD}nano ~/.zsh_env/config.zsh${NC}"