# ==============================================================================
# core/setup.zsh — Fonctions de configuration d'environnement
# ==============================================================================
# Fonctions : zanvil-ssl-setup
# Utilise les fonctions UI de ui.zsh (charge automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zanvil-ssl-setup : Configuration des certificats SSL/TLS entreprise
# ==============================================================================
zanvil-ssl-setup() {
    local zanvil_dir="${ZANVIL_DIR:-$HOME/.zanvil}"
    local script="$zanvil_dir/scripts/ssl-setup.sh"

    if [[ ! -x "$script" ]]; then
        _ui_msg_fail "Script ssl-setup.sh non trouve"
        return 1
    fi

    "$script" "$@"
}
