export WORK_DIR="$HOME/work"
export SCRIPTS_DIR="./scripts"

# Liste des dossiers critiques à garantir
required_dirs=(
    "$WORK_DIR"
    "$HOME/.config"
)

for dir in $required_dirs; do
    if [ ! -d "$dir" ]; then
        # On crée silencieusement le dossier manquant
        mkdir -p "$dir"
    fi
done