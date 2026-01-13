# =======================================================
# UTILITAIRES GÉNÉRAUX
# =======================================================

# Crée un dossier et rentre dedans immédiatement
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
    echo "Erreur: Aucune commande 'trash' ou 'trash-put' trouvée."
    return 1
  fi
}

# Crée une copie de sauvegarde horodatée
# Usage: bak mon_fichier.conf -> crée mon_fichier.conf.2023-10-27_14h30
bak() {
    if [ -z "$1" ]; then
        echo "Usage: bak <filename>"
        return 1
    fi
    cp "$1" "$1.bak.$(date +%Y-%m-%d_%H%M%S)"
    echo "✅ Backup créé : $1.bak.$(date +%Y-%m-%d_%H%M%S)"
}

# Rend un fichier exécutable rapidement
# Usage: cx mon_script.sh
cx() {
    if [ -z "$1" ]; then
        echo "Usage: cx <fichier>"
        return 1
    fi
    
    if [ ! -f "$1" ]; then
        echo "Erreur: '$1' n'est pas un fichier valide."
        return 1
    fi

    chmod +x "$1"
    echo "✅ '$1' est maintenant exécutable."
}