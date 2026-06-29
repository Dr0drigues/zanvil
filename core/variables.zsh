export WORK_DIR="$HOME/work"
export SCRIPTS_DIR="$ZANVIL_DIR/scripts"

# Ajouter ~/.local/bin au PATH pour les outils installes localement
typeset -U path
path=("$HOME/.local/bin" $path)

# Fix XDG_DATA_DIRS : Homebrew ARM utilise /opt/homebrew/share, pas /usr/local/share
# Sans ce fix, k9s et d'autres outils XDG cherchent dans un chemin inaccessible sur macOS ARM
if [[ -d /opt/homebrew/share && "${XDG_DATA_DIRS:-}" == *"/usr/local/share"* ]]; then
    export XDG_DATA_DIRS="${XDG_DATA_DIRS/\/usr\/local\/share/\/opt\/homebrew\/share}"
fi

# =======================================================
# HISTORIQUE ZSH
# =======================================================
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000

# Options d'historique
setopt EXTENDED_HISTORY          # Enregistrer le timestamp
setopt HIST_EXPIRE_DUPS_FIRST    # Supprimer les doublons en premier si limite atteinte
setopt HIST_IGNORE_DUPS          # Ignorer les commandes consecutives identiques
setopt HIST_IGNORE_SPACE         # Ignorer les commandes commencant par espace
setopt HIST_VERIFY               # Montrer la commande avant execution depuis l'historique
setopt SHARE_HISTORY             # Partager l'historique entre sessions

# SOPS/Age et SSL/TLS sont desormais dans env.d/sops.zsh et env.d/ssl.zsh

# Liste des dossiers critiques à garantir
required_dirs=(
    "$WORK_DIR"
    "$HOME/.config"
    "$SCRIPTS_DIR"
)

for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null || echo "[zanvil] Impossible de creer $dir" >&2
    fi
done