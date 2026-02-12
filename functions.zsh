# ==============================================================================
# Chargement dynamique des fonctions
# ==============================================================================

# Charger ui.zsh en premier (fonctions utilitaires d'affichage)
if [[ -f "$ZSH_ENV_DIR/functions/ui.zsh" ]]; then
    source "$ZSH_ENV_DIR/functions/ui.zsh"
fi

# Charger tous les autres fichiers de fonctions
for file in "$ZSH_ENV_DIR/functions"/*; do
    if [[ -f "$file" && "$(basename "$file")" != "ui.zsh" ]]; then
        source "$file"
    fi
done
