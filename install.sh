#!/bin/bash
# ==============================================================================
# Script : install.sh
# Description : Bootstrapping de l'environnement de développement (Zsh, Tools)
# Auteur : Concepteur & Développeur Sénior
# Support : MacOS (Homebrew), Debian/Ubuntu (apt), Fedora (dnf)
# ==============================================================================

# --- Couleurs & UI ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Détection OS & Package Manager ---
OS="$(uname -s)"
PKG_MANAGER=""
INSTALL_CMD=""

detect_platform() {
    case "${OS}" in
        Linux*)
            if [ -f /etc/debian_version ]; then
                PKG_MANAGER="apt"
                INSTALL_CMD="sudo apt-get install -y"
                log_info "Système détecté : Linux (Debian/Ubuntu)"
            elif [ -f /etc/fedora-release ]; then
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
    if [ -z "$pkg" ]; then
        echo ""
        log_warn "Pas de paquet connu pour $tool_name sur $PKG_MANAGER."
        return
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
if [ "$PKG_MANAGER" == "apt" ]; then
    log_info "Mise à jour des dépôts apt..."
    sudo apt-get update -qq
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
# Note: Sur Linux (trash-cli), la commande est souvent 'trash-put'
install_tool "trash"    "trash"     "trash-cli" "trash-cli"

# --- Installation manuelle pour les outils souvent absents d'APT/DNF ---

# Starship (Script officiel si non trouvé via gestionnaire)
if ! command -v starship &> /dev/null; then
    log_info "Installation manuelle de Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

# Installation de NVM (Node Version Manager)
if [ -d "$NVM_DIR" ]; then
    log_success "NVM est déjà installé."
else
    log_info "Installation de NVM..."
    
    if [ "$PKG_MANAGER" == "brew" ]; then
        # Sur MacOS, on préfère brew pour la maintenance
        brew install nvm
    else
        # Sur Linux : Installation via le script officiel (Version Dynamique)
        log_info "Récupération de la dernière version via GitHub API..."
        
        # Note : jq est déjà installé plus haut dans le script
        curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | \
        jq -r '.tag_name' | \
        xargs -I {} curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/{}/install.sh | bash
        
        if [ $? -eq 0 ]; then
            log_success "NVM installé avec succès."
        else
            log_error "Échec de l'installation de NVM."
        fi
    fi
fi

# --- Configuration Automatique du .zshrc ---
echo ""
log_info "Configuration du shell..."

ZSHRC="$HOME/.zshrc"

# Dossier où se trouve ce script actuellement
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.zsh_env"

# 1. Vérification de l'emplacement
if [ "$CURRENT_DIR" != "$TARGET_DIR" ]; then
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
    
    # Backup de sécurité
    cp "$ZSHRC" "$ZSHRC.bak.$(date +%Y%m%d_%H%M%S)"
    log_info "Backup créé."

    cat <<EOF >> "$ZSHRC"

# =======================================================
# ZSH ENV CONFIGURATION
# =======================================================
# Init from zsh_env/install.sh
export ZSH_ENV_DIR="$TARGET_DIR"

if [ -f "\$ZSH_ENV_DIR/rc.zsh" ]; then
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
if [ ! -d "$SCRIPTS_DIR" ]; then
    mkdir -p "$SCRIPTS_DIR"
fi

echo -e "\n${BOLD}=== Installation Terminée ===${NC}"
echo -e "Redémarrez votre terminal ou lancez : ${BOLD}source ~/.zshrc${NC}"