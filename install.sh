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
            echo "    -h, --help    Affiche cette aide"
            exit 0
            ;;
        --default)
            INTERACTIVE=false
            shift
            ;;
        *)
            log_error "Option inconnue: $1"
            exit 1
            ;;
    esac
done

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
install_tool "tmux"     "tmux"      "tmux"      "tmux"

# 2. Modern Tools (La demande utilisateur)
install_tool "eza"      "eza"       "eza"       "eza"  # Sur Debian/Ubuntu récent, sinon voir cargo
install_tool "starship" "starship"  ""          ""     # Souvent absent des vieux repos apt
install_tool "zoxide"   "zoxide"    "zoxide"    "zoxide"
install_tool "fzf"      "fzf"       "fzf"       "fzf"
install_tool "bat"      "bat"       "bat"       "bat"  # "cat" avec des ailes
install_tool "nu"       "nushell"   "nushell"   "nushell"
# Note: Sur Linux (trash-cli), la commande est souvent 'trash-put'
install_tool "trash"    "trash"     "trash-cli" "trash-cli"

# 3. Outils de chiffrement (pour kubeconfig, secrets, etc.)
install_tool "sops"     "sops"      "sops"      "sops"
install_tool "age"      "age"       "age"       "age"

# 4. Outils Kubernetes / Azure
install_tool "kubectl"    "kubectl"     "kubectl"     "kubectl"
install_tool "kubelogin"  "kubelogin"   ""            ""
install_tool "az"         "azure-cli"   ""            ""
install_tool "helm"       "helm"        "helm"        "helm"

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

# Nushell (Si non trouvé via gestionnaire de paquets)
if ! command -v nu &> /dev/null; then
    log_info "Installation manuelle de Nushell..."
    # On télécharge la dernière release via GitHub (binaire statique)
    curl -s https://api.github.com/repos/nushell/nushell/releases/latest | \
    jq -r ".assets[] | select(.name | test(\"x86_64-unknown-linux-musl.tar.gz\")) | .browser_download_url" | \
    xargs curl -L -o /tmp/nu.tar.gz

    tar -xzf /tmp/nu.tar.gz -C /tmp
    # Déplacement du binaire (suppose sudo dispo)
    sudo mv /tmp/nu-*-linux-musl/nu /usr/local/bin/
    log_success "Nushell installé."
fi

# SDKMAN (Gestionnaire de versions pour Java, Gradle, Maven, etc.)
export SDKMAN_DIR="$HOME/.sdkman"
if [ -d "$SDKMAN_DIR" ]; then
    log_success "SDKMAN est deja installe."
else
    log_info "Installation de SDKMAN..."
    curl -s "https://get.sdkman.io?rcupdate=false" | bash
    if [ $? -eq 0 ]; then
        log_success "SDKMAN installe avec succes."
        log_info "Utilisez 'sdk install java' pour installer Java."
    else
        log_error "Echec de l'installation de SDKMAN."
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

# --- Configuration Interactive des Modules ---
echo ""
echo -e "${BOLD}=== Configuration des Modules ===${NC}"

if [ "$INTERACTIVE" = true ]; then
    echo -e "Choisissez les modules a activer (Entree = valeur par defaut)\n"

    # Fonction pour poser une question oui/non
    ask_module() {
        local module_name="$1"
        local module_desc="$2"
        local default="$3"

        local prompt_default="O/n"
        [ "$default" = "false" ] && prompt_default="o/N"

        # Afficher sur stderr pour ne pas etre capture par $()
        printf "  ${CYAN}%s${NC} - %s [%s]: " "$module_name" "$module_desc" "$prompt_default" >&2
        read -r answer

        if [ -z "$answer" ]; then
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
    MODULE_NVM=$(ask_module "NVM" "Auto-switch Node.js via .nvmrc" "true")

    # NVM Lazy loading (seulement si NVM actif)
    NVM_LAZY="true"
    if [ "$MODULE_NVM" = "true" ]; then
        NVM_LAZY=$(ask_module "NVM Lazy" "Charger NVM au premier appel node/npm (plus rapide)" "true")
    fi

    MODULE_NUSHELL=$(ask_module "Nushell" "Integration Nushell (aliases nu)" "true")
    MODULE_KUBE=$(ask_module "Kube" "Gestionnaire de configs Kubernetes (kube_select)" "true")

    # Configuration SOPS/Age (si module Kube actif)
    SOPS_CONFIGURED="false"
    if [ "$MODULE_KUBE" = "true" ]; then
        echo "" >&2
        echo -e "${BOLD}Configuration SOPS/Age:${NC}" >&2
        echo -e "  SOPS permet de chiffrer vos kubeconfig pour les versionner dans Git." >&2
        SETUP_SOPS=$(ask_module "SOPS" "Configurer le chiffrement avec age" "true")

        if [ "$SETUP_SOPS" = "true" ]; then
            AGE_KEY_DIR="$HOME/.config/sops/age"
            AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"

            if [ -f "$AGE_KEY_FILE" ]; then
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

    if [ "$AUTO_UPDATE" = "true" ]; then
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
    MODULE_NVM="true"
    MODULE_NUSHELL="true"
    MODULE_KUBE="true"
    NVM_LAZY="true"
    STARSHIP_THEME="default"
    AUTO_UPDATE="true"
    UPDATE_FREQ=7
    UPDATE_MODE="prompt"
    SOPS_CONFIGURED="false"

    # Configuration SOPS automatique en mode default
    AGE_KEY_DIR="$HOME/.config/sops/age"
    AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"
    if [ -f "$AGE_KEY_FILE" ]; then
        SOPS_CONFIGURED="true"
    elif command -v age-keygen &> /dev/null; then
        mkdir -p "$AGE_KEY_DIR"
        age-keygen -o "$AGE_KEY_FILE" 2>/dev/null
        chmod 600 "$AGE_KEY_FILE"
        SOPS_CONFIGURED="true"
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
ZSH_ENV_MODULE_NVM=$MODULE_NVM
ZSH_ENV_MODULE_NUSHELL=$MODULE_NUSHELL
ZSH_ENV_MODULE_KUBE=$MODULE_KUBE

# NVM Lazy Loading (charge au premier appel node/npm)
ZSH_ENV_NVM_LAZY=$NVM_LAZY

# Auto-Update
ZSH_ENV_AUTO_UPDATE=$AUTO_UPDATE
ZSH_ENV_UPDATE_FREQUENCY=$UPDATE_FREQ
ZSH_ENV_UPDATE_MODE="$UPDATE_MODE"
EOF

log_success "Configuration sauvegardee"

# Creation du fichier .sops.yaml si SOPS configure
if [ "$SOPS_CONFIGURED" = "true" ] && [ -n "$AGE_PUBLIC_KEY" ]; then
    SOPS_CONFIG="$TARGET_DIR/.sops.yaml"
    if [ ! -f "$SOPS_CONFIG" ]; then
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
if [ -n "$STARSHIP_THEME" ] && [ -f "$TARGET_DIR/themes/$STARSHIP_THEME.toml" ]; then
    mkdir -p "$HOME/.config"
    cp "$TARGET_DIR/themes/$STARSHIP_THEME.toml" "$HOME/.config/starship.toml"
    log_success "Theme Starship '$STARSHIP_THEME' applique"
fi

# Resume
echo ""
echo -e "${CYAN}Modules actives:${NC}"
[ "$MODULE_GITLAB" = "true" ] && echo -e "  ${GREEN}✓${NC} GitLab"
[ "$MODULE_DOCKER" = "true" ] && echo -e "  ${GREEN}✓${NC} Docker"
if [ "$MODULE_NVM" = "true" ]; then
    if [ "$NVM_LAZY" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} NVM (lazy loading)"
    else
        echo -e "  ${GREEN}✓${NC} NVM"
    fi
fi
[ "$MODULE_NUSHELL" = "true" ] && echo -e "  ${GREEN}✓${NC} Nushell"
[ "$MODULE_KUBE" = "true" ] && echo -e "  ${GREEN}✓${NC} Kube (kubeconfig manager)"

echo -e "${CYAN}Modules desactives:${NC}"
[ "$MODULE_GITLAB" = "false" ] && echo -e "  ${RED}✗${NC} GitLab"
[ "$MODULE_DOCKER" = "false" ] && echo -e "  ${RED}✗${NC} Docker"
[ "$MODULE_NVM" = "false" ] && echo -e "  ${RED}✗${NC} NVM"
[ "$MODULE_NUSHELL" = "false" ] && echo -e "  ${RED}✗${NC} Nushell"
[ "$MODULE_KUBE" = "false" ] && echo -e "  ${RED}✗${NC} Kube"

echo ""
echo -e "${CYAN}Theme Starship:${NC}"
if [ -n "$STARSHIP_THEME" ]; then
    echo -e "  ${GREEN}✓${NC} $STARSHIP_THEME"
else
    echo -e "  ${YELLOW}○${NC} Non modifie"
fi

echo ""
echo -e "${CYAN}Auto-Update:${NC}"
if [ "$AUTO_UPDATE" = "true" ]; then
    echo -e "  ${GREEN}✓${NC} Active (tous les ${UPDATE_FREQ} jours, mode: ${UPDATE_MODE})"
else
    echo -e "  ${RED}✗${NC} Desactive"
fi

echo ""
echo -e "${CYAN}Chiffrement SOPS/Age:${NC}"
if [ "$SOPS_CONFIGURED" = "true" ]; then
    echo -e "  ${GREEN}✓${NC} Configure"
    echo -e "  Cle: ~/.config/sops/age/keys.txt"
    if [ -n "$AGE_PUBLIC_KEY" ]; then
        echo -e "  Public: $AGE_PUBLIC_KEY"
    fi
else
    echo -e "  ${YELLOW}○${NC} Non configure (utilisez 'age-keygen' pour creer une cle)"
fi

echo -e "\n${BOLD}=== Installation Terminee ===${NC}"
echo -e "Redemarrez votre terminal ou lancez : ${BOLD}source ~/.zshrc${NC}"
echo -e "Pour modifier les modules : ${BOLD}nano ~/.zsh_env/config.zsh${NC}"