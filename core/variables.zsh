export WORK_DIR="$HOME/work"
export SCRIPTS_DIR="$ZSH_ENV_DIR/scripts"

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
        mkdir -p "$dir" 2>/dev/null || echo "[zsh-env] Impossible de creer $dir" >&2
    fi
done