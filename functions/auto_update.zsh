# ==============================================================================
# Auto-Update ZSH_ENV
# ==============================================================================
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

# Fichier pour stocker la date de derniere verification
ZSH_ENV_UPDATE_FILE="$ZSH_ENV_DIR/.last_update_check"

# Fonction pour verifier si une mise a jour est necessaire
_zsh_env_should_check_update() {
    local frequency="${ZSH_ENV_UPDATE_FREQUENCY:-7}"

    # Si frequence = 0, toujours verifier
    [[ "$frequency" -eq 0 ]] && return 0

    # Si le fichier n'existe pas, c'est la premiere fois
    [[ ! -f "$ZSH_ENV_UPDATE_FILE" ]] && return 0

    # Calculer la difference en jours
    local last_check=$(cat "$ZSH_ENV_UPDATE_FILE" 2>/dev/null)
    local now=$(date +%s)
    local diff=$(( (now - last_check) / 86400 ))

    [[ "$diff" -ge "$frequency" ]]
}

# Fonction pour verifier les mises a jour
_zsh_env_check_update() {
    # Verifier qu'on est dans un repo git
    [[ ! -d "$ZSH_ENV_DIR/.git" ]] && return 1

    # Fetch silencieux
    (cd "$ZSH_ENV_DIR" && git fetch origin --quiet 2>/dev/null) || return 1

    # Comparer avec origin
    local local_rev=$(cd "$ZSH_ENV_DIR" && git rev-parse HEAD 2>/dev/null)
    local remote_rev=$(cd "$ZSH_ENV_DIR" && git rev-parse origin/main 2>/dev/null)

    [[ "$local_rev" != "$remote_rev" ]]
}

# Fonction pour effectuer la mise a jour
_zsh_env_do_update() {
    echo -e "${_ui_blue}[zsh_env]${_ui_nc} Mise a jour en cours..."

    if (cd "$ZSH_ENV_DIR" && git pull --quiet origin main 2>/dev/null); then
        echo -e "${_ui_green}[zsh_env]${_ui_nc} Mise a jour terminee. Rechargez avec: ${_ui_bold}ss${_ui_nc}"
        return 0
    else
        echo -e "${_ui_yellow}[zsh_env]${_ui_nc} Erreur lors de la mise a jour."
        return 1
    fi
}

# Fonction pour afficher les nouveautes
_zsh_env_show_changes() {
    local local_rev=$(cd "$ZSH_ENV_DIR" && git rev-parse HEAD 2>/dev/null)
    local changes=$(cd "$ZSH_ENV_DIR" && git log --oneline "$local_rev"..origin/main 2>/dev/null | head -5)

    if [[ -n "$changes" ]]; then
        echo -e "${_ui_blue}Nouveautes:${_ui_nc}"
        echo "$changes" | while read line; do
            echo -e "  ${_ui_green}*${_ui_nc} $line"
        done
    fi
}

# Fonction principale d'auto-update
_zsh_env_auto_update() {
    # Verifier si on doit checker
    _zsh_env_should_check_update || return 0

    # Mettre a jour le timestamp
    date +%s > "$ZSH_ENV_UPDATE_FILE"

    # Verifier les mises a jour disponibles
    if _zsh_env_check_update; then
        echo ""
        echo -e "${_ui_yellow}[zsh_env]${_ui_nc} Une mise a jour est disponible!"
        _zsh_env_show_changes
        echo ""

        if [[ "$ZSH_ENV_UPDATE_MODE" = "auto" ]]; then
            # Mode automatique
            _zsh_env_do_update
        else
            # Mode prompt
            echo -n "Mettre a jour maintenant ? [y/N] "
            read -r answer
            if [[ "$answer" =~ ^[yYoO]$ ]]; then
                _zsh_env_do_update
            else
                echo -e "${_ui_blue}[zsh_env]${_ui_nc} Mise a jour reportee. Lancez ${_ui_bold}zsh-env-update${_ui_nc} pour mettre a jour manuellement."
            fi
        fi
        echo ""
    fi
}

# Commande manuelle pour forcer la mise a jour
zsh-env-update() {
    _ui_header "ZSH_ENV Update"

    echo -e "Verification des mises a jour..."

    if _zsh_env_check_update; then
        _zsh_env_show_changes
        echo ""
        _zsh_env_do_update
    else
        echo -e "${_ui_green}${_ui_check}${_ui_nc} Vous etes deja a jour!"
    fi
}

# Lancer la verification au demarrage (en arriere-plan pour ne pas ralentir)
# Seulement si auto-update est active
[[ "$ZSH_ENV_AUTO_UPDATE" = "true" ]] && _zsh_env_auto_update &!
