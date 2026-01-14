#!/bin/bash
# ==============================================================================
# Script : uninstall.sh
# Description : Desinstallation de l'environnement zsh_env
# ==============================================================================

# --- Couleurs & UI ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Variables ---
ZSHRC="$HOME/.zshrc"
ZSH_ENV_DIR="${ZSH_ENV_DIR:-$HOME/.zsh_env}"

# --- Fonctions ---

show_help() {
    cat << EOF
${BOLD}USAGE${NC}
    $0 [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Desinstalle zsh_env en nettoyant le .zshrc et optionnellement
    en supprimant le dossier.

${BOLD}OPTIONS${NC}
    --keep-dir      Ne supprime pas le dossier ~/.zsh_env
    --keep-secrets  Ne supprime pas les fichiers secrets
    --force         Pas de confirmation
    -h, --help      Affiche cette aide

${BOLD}EXEMPLES${NC}
    $0                  # Desinstallation interactive
    $0 --keep-dir       # Garde le dossier, nettoie juste .zshrc
    $0 --force          # Tout supprimer sans confirmation
EOF
}

# --- Parse Arguments ---
KEEP_DIR=false
KEEP_SECRETS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --keep-dir)
            KEEP_DIR=true
            shift
            ;;
        --keep-secrets)
            KEEP_SECRETS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            log_error "Option inconnue: $1"
            exit 1
            ;;
    esac
done

# --- Main ---

echo -e "${BOLD}=== Desinstallation de zsh_env ===${NC}\n"

# Confirmation
if [ "$FORCE" = false ]; then
    echo -e "Cette action va:"
    echo -e "  ${RED}*${NC} Retirer la configuration de $ZSHRC"
    [ "$KEEP_DIR" = false ] && echo -e "  ${RED}*${NC} Supprimer le dossier $ZSH_ENV_DIR"
    [ "$KEEP_SECRETS" = false ] && echo -e "  ${RED}*${NC} Supprimer ~/.secrets et ~/.gitlab_secrets"
    echo ""
    read -p "Continuer ? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[yYoO]$ ]]; then
        log_info "Operation annulee."
        exit 0
    fi
fi

# 1. Nettoyer .zshrc
log_info "Nettoyage de $ZSHRC..."

if [ -f "$ZSHRC" ]; then
    # Creer un backup
    cp "$ZSHRC" "$ZSHRC.bak.$(date +%Y%m%d_%H%M%S)"
    log_info "Backup cree."

    # Supprimer le bloc ZSH_ENV (entre les marqueurs)
    # On cherche le bloc qui commence par "# ZSH ENV CONFIGURATION" ou "ZSH_ENV_DIR"
    sed -i.tmp '/# =*$/,/# =*$/{/ZSH.ENV/d}' "$ZSHRC" 2>/dev/null

    # Methode plus robuste : supprimer les lignes contenant ZSH_ENV
    grep -v "ZSH_ENV" "$ZSHRC" > "$ZSHRC.clean" 2>/dev/null
    mv "$ZSHRC.clean" "$ZSHRC"

    # Nettoyer les lignes vides consecutives
    cat -s "$ZSHRC" > "$ZSHRC.clean" && mv "$ZSHRC.clean" "$ZSHRC"

    rm -f "$ZSHRC.tmp"
    log_success "Configuration retiree de $ZSHRC"
else
    log_warn "$ZSHRC non trouve"
fi

# 2. Supprimer les secrets
if [ "$KEEP_SECRETS" = false ]; then
    log_info "Suppression des fichiers secrets..."
    [ -f "$HOME/.secrets" ] && rm -f "$HOME/.secrets" && log_success "~/.secrets supprime"
    [ -f "$HOME/.gitlab_secrets" ] && rm -f "$HOME/.gitlab_secrets" && log_success "~/.gitlab_secrets supprime"
fi

# 3. Supprimer le dossier
if [ "$KEEP_DIR" = false ]; then
    log_info "Suppression de $ZSH_ENV_DIR..."
    if [ -d "$ZSH_ENV_DIR" ]; then
        rm -rf "$ZSH_ENV_DIR"
        log_success "Dossier supprime"
    else
        log_warn "Dossier non trouve"
    fi
fi

echo -e "\n${BOLD}=== Desinstallation terminee ===${NC}"
echo -e "Redemarrez votre terminal ou lancez: ${BOLD}source ~/.zshrc${NC}"
