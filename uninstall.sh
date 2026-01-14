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
CYAN=$'\033[0;36m'
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
    Desinstalle zsh_env en restaurant le .zshrc original
    ou en nettoyant les lignes ajoutees.

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

# Fonction pour lister les backups disponibles
list_backups() {
    local backups=()
    for f in "$HOME"/.zshrc.dr0.bak.*; do
        [ -f "$f" ] && backups+=("$f")
    done
    echo "${backups[@]}"
}

# Fonction pour afficher un menu de selection
select_backup() {
    local backups=($@)
    local count=${#backups[@]}

    echo -e "\n${CYAN}Backups disponibles:${NC}\n"

    for i in "${!backups[@]}"; do
        local file="${backups[$i]}"
        local date_str=$(echo "$file" | grep -oE '[0-9]{8}_[0-9]{6}' | sed 's/_/ /' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')
        local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
        printf "  ${GREEN}%d)${NC} %s (${BLUE}%s${NC})\n" "$((i+1))" "$date_str" "$size"
    done

    echo -e "  ${YELLOW}0)${NC} Ne pas restaurer (supprimer les lignes manuellement)"
    echo ""

    while true; do
        read -p "Choix [1]: " choice
        choice=${choice:-1}

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "$count" ]; then
            if [ "$choice" -eq 0 ]; then
                echo ""
                return 1
            else
                SELECTED_BACKUP="${backups[$((choice-1))]}"
                return 0
            fi
        fi
        echo -e "${RED}Choix invalide${NC}"
    done
}

# Fonction pour nettoyer le zshrc sans backup
clean_zshrc() {
    if [ -f "$ZSHRC" ]; then
        log_info "Suppression des lignes zsh_env..."

        # Creer un backup avant modification
        cp "$ZSHRC" "$ZSHRC.before_uninstall.$(date +%Y%m%d_%H%M%S)"

        # Supprimer le bloc complet (entre les marqueurs ===)
        awk '
            /^# =+$/ { if (block) { block=0; next } }
            /ZSH.ENV|ZSH_ENV/ { block=1; next }
            !block { print }
        ' "$ZSHRC" > "$ZSHRC.tmp"

        # Si awk n'a pas bien fonctionne, fallback avec grep
        if grep -q "ZSH_ENV" "$ZSHRC.tmp" 2>/dev/null; then
            grep -v "ZSH_ENV" "$ZSHRC" | grep -v "rc.zsh" > "$ZSHRC.tmp"
        fi

        mv "$ZSHRC.tmp" "$ZSHRC"

        # Nettoyer les lignes vides consecutives
        cat -s "$ZSHRC" > "$ZSHRC.tmp" && mv "$ZSHRC.tmp" "$ZSHRC"

        log_success "Lignes zsh_env supprimees de $ZSHRC"
    else
        log_warn "$ZSHRC non trouve"
    fi
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
    echo -e "  ${RED}*${NC} Restaurer ou nettoyer $ZSHRC"
    [ "$KEEP_DIR" = false ] && echo -e "  ${RED}*${NC} Supprimer le dossier $ZSH_ENV_DIR"
    [ "$KEEP_SECRETS" = false ] && echo -e "  ${RED}*${NC} Supprimer ~/.secrets et ~/.gitlab_secrets"
    echo ""
    read -p "Continuer ? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[yYoO]$ ]]; then
        log_info "Operation annulee."
        exit 0
    fi
fi

# 1. Gestion du .zshrc
log_info "Traitement de $ZSHRC..."

BACKUPS=($(list_backups))
SELECTED_BACKUP=""

if [ ${#BACKUPS[@]} -gt 0 ] && [ "$FORCE" = false ]; then
    echo -e "\nDes backups de votre .zshrc ont ete trouves."
    echo -e "Voulez-vous restaurer un backup ou simplement supprimer les lignes zsh_env ?"

    if select_backup "${BACKUPS[@]}"; then
        # Restaurer le backup selectionne
        log_info "Restauration de $SELECTED_BACKUP..."
        cp "$ZSHRC" "$ZSHRC.before_uninstall.$(date +%Y%m%d_%H%M%S)"
        cp "$SELECTED_BACKUP" "$ZSHRC"
        log_success ".zshrc restaure depuis le backup"

        # Proposer de supprimer les vieux backups
        echo ""
        read -p "Supprimer tous les backups .dr0.bak ? [y/N] " del_backups
        if [[ "$del_backups" =~ ^[yYoO]$ ]]; then
            rm -f "$HOME"/.zshrc.dr0.bak.*
            log_success "Backups supprimes"
        fi
    else
        # Supprimer les lignes manuellement
        clean_zshrc
    fi
elif [ "$FORCE" = true ] && [ ${#BACKUPS[@]} -gt 0 ]; then
    # Mode force : restaurer le backup le plus recent
    LATEST_BACKUP="${BACKUPS[-1]}"
    log_info "Restauration du backup le plus recent: $LATEST_BACKUP"
    cp "$LATEST_BACKUP" "$ZSHRC"
    rm -f "$HOME"/.zshrc.dr0.bak.*
    log_success ".zshrc restaure"
else
    # Pas de backup : nettoyer manuellement
    clean_zshrc
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
echo -e "Redemarrez votre terminal ou lancez: ${BOLD}exec zsh${NC}"
