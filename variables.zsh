export WORK_DIR="$HOME/work"
export SCRIPTS_DIR="$ZSH_ENV_DIR/scripts"

# SOPS/Age - Chemin vers la cle de chiffrement
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

# Liste des dossiers critiques à garantir
required_dirs=(
    "$WORK_DIR"
    "$HOME/.config"
    "$SCRIPTS_DIR"
)

for dir in $required_dirs; do
    if [ ! -d "$dir" ]; then
        # On crée silencieusement le dossier manquant
        mkdir -p "$dir"
    fi
done