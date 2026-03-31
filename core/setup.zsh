# ==============================================================================
# core/setup.zsh — Fonctions de configuration d'environnement
# ==============================================================================
# Fonctions : zsh-env-ssl-setup
# Utilise les fonctions UI de ui.zsh (charge automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zsh-env-ssl-setup : Configuration des certificats SSL/TLS entreprise
# ==============================================================================
zsh-env-ssl-setup() {
    local zsh_env_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}"
    local script="$zsh_env_dir/scripts/ssl-setup.sh"

    if [[ ! -x "$script" ]]; then
        _ui_msg_fail "Script ssl-setup.sh non trouve"
        return 1
    fi

    "$script" "$@"
}
