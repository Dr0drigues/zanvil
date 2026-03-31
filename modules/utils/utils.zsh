# =======================================================
# UTILITAIRES GENERAUX
# =======================================================

# Cree un dossier et rentre dedans immediatement
# Usage: mkcd mon_dossier/sous_dossier
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Fonction wrapper pour 'trash' compatible Linux/Mac
# Permet d'utiliser la commande 'trash' partout
trash() {
    if command -v trash-put &> /dev/null; then
        # Version Linux (trash-cli)
        trash-put "$@"
    elif command -v trash &> /dev/null; then
        # Version Mac (brew) ou autre
        command trash "$@"
    else
        echo -e "${_ui_red}Erreur:${_ui_nc} Aucune commande 'trash' ou 'trash-put' trouvee."
        return 1
    fi
}

# Cree une copie de sauvegarde horodatee
# Usage: bak mon_fichier.conf -> cree mon_fichier.conf.2023-10-27_14h30
bak() {
    if [[ -z "$1" ]]; then
        echo -e "${_ui_bold}Usage:${_ui_nc} bak <filename>"
        return 1
    fi
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H%M%S)
    cp "$1" "$1.bak.$timestamp"
    _ui_msg_ok "Backup cree : $1.bak.$timestamp"
}

# Rend un fichier executable rapidement
# Usage: cx mon_script.sh
cx() {
    if [[ -z "$1" ]]; then
        echo -e "${_ui_bold}Usage:${_ui_nc} cx <fichier>"
        return 1
    fi

    if [[ ! -f "$1" ]]; then
        echo -e "${_ui_red}Erreur:${_ui_nc} '$1' n'est pas un fichier valide."
        return 1
    fi

    chmod +x "$1"
    _ui_msg_ok "'$1' est maintenant executable."
}
