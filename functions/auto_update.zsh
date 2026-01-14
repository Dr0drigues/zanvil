# ==============================================================================
# Auto-Update ZSH_ENV
# ==============================================================================

# Fichier pour stocker la date de derniere verification
ZSH_ENV_UPDATE_FILE="$ZSH_ENV_DIR/.last_update_check"

# Couleurs
_update_color_green=$'\033[0;32m'
_update_color_yellow=$'\033[1;33m'
_update_color_blue=$'\033[0;34m'
_update_color_bold=$'\033[1m'
_update_color_nc=$'\033[0m'

# Fonction pour verifier si une mise a jour est necessaire
_zsh_env_should_check_update() {
    local frequency="${ZSH_ENV_UPDATE_FREQUENCY:-7}"

    # Si frequence = 0, toujours verifier
    [ "$frequency" -eq 0 ] && return 0

    # Si le fichier n'existe pas, c'est la premiere fois
    [ ! -f "$ZSH_ENV_UPDATE_FILE" ] && return 0

    # Calculer la difference en jours
    local last_check=$(cat "$ZSH_ENV_UPDATE_FILE" 2>/dev/null)
    local now=$(date +%s)
    local diff=$(( (now - last_check) / 86400 ))

    [ "$diff" -ge "$frequency" ]
}

# Fonction pour verifier les mises a jour
_zsh_env_check_update() {
    # Verifier qu'on est dans un repo git
    [ ! -d "$ZSH_ENV_DIR/.git" ] && return 1

    # Fetch silencieux
    (cd "$ZSH_ENV_DIR" && git fetch origin --quiet 2>/dev/null) || return 1

    # Comparer avec origin
    local local_rev=$(cd "$ZSH_ENV_DIR" && git rev-parse HEAD 2>/dev/null)
    local remote_rev=$(cd "$ZSH_ENV_DIR" && git rev-parse origin/main 2>/dev/null)

    [ "$local_rev" != "$remote_rev" ]
}

# Fonction pour effectuer la mise a jour
_zsh_env_do_update() {
    echo -e "${_update_color_blue}[zsh_env]${_update_color_nc} Mise a jour en cours..."

    if (cd "$ZSH_ENV_DIR" && git pull --quiet origin main 2>/dev/null); then
        echo -e "${_update_color_green}[zsh_env]${_update_color_nc} Mise a jour terminee. Rechargez avec: ${_update_color_bold}ss${_update_color_nc}"
        return 0
    else
        echo -e "${_update_color_yellow}[zsh_env]${_update_color_nc} Erreur lors de la mise a jour."
        return 1
    fi
}

# Fonction pour afficher les nouveautes
_zsh_env_show_changes() {
    local local_rev=$(cd "$ZSH_ENV_DIR" && git rev-parse HEAD 2>/dev/null)
    local changes=$(cd "$ZSH_ENV_DIR" && git log --oneline "$local_rev"..origin/main 2>/dev/null | head -5)

    if [ -n "$changes" ]; then
        echo -e "${_update_color_blue}Nouveautes:${_update_color_nc}"
        echo "$changes" | while read line; do
            echo -e "  ${_update_color_green}*${_update_color_nc} $line"
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
        echo -e "${_update_color_yellow}[zsh_env]${_update_color_nc} Une mise a jour est disponible!"
        _zsh_env_show_changes
        echo ""

        if [ "$ZSH_ENV_UPDATE_MODE" = "auto" ]; then
            # Mode automatique
            _zsh_env_do_update
        else
            # Mode prompt
            echo -n "Mettre a jour maintenant ? [y/N] "
            read -r answer
            if [[ "$answer" =~ ^[yYoO]$ ]]; then
                _zsh_env_do_update
            else
                echo -e "${_update_color_blue}[zsh_env]${_update_color_nc} Mise a jour reportee. Lancez ${_update_color_bold}zsh-env-update${_update_color_nc} pour mettre a jour manuellement."
            fi
        fi
        echo ""
    fi
}

# Commande manuelle pour forcer la mise a jour
zsh-env-update() {
    echo -e "${_update_color_blue}[zsh_env]${_update_color_nc} Verification des mises a jour..."

    if _zsh_env_check_update; then
        _zsh_env_show_changes
        echo ""
        _zsh_env_do_update
    else
        echo -e "${_update_color_green}[zsh_env]${_update_color_nc} Vous etes deja a jour!"
    fi
}

# Commande pour voir le statut
zsh-env-status() {
    echo -e "${_update_color_bold}=== ZSH_ENV Status ===${_update_color_nc}"
    echo ""

    # Version actuelle
    local current=$(cd "$ZSH_ENV_DIR" && git log -1 --format="%h - %s" 2>/dev/null)
    echo -e "Version: ${_update_color_green}$current${_update_color_nc}"

    # Derniere verification
    if [ -f "$ZSH_ENV_UPDATE_FILE" ]; then
        local last=$(cat "$ZSH_ENV_UPDATE_FILE")
        local last_date=$(date -r "$last" "+%Y-%m-%d %H:%M" 2>/dev/null || date -d "@$last" "+%Y-%m-%d %H:%M" 2>/dev/null)
        echo -e "Derniere verification: ${_update_color_blue}$last_date${_update_color_nc}"
    fi

    # Config
    echo ""
    echo -e "${_update_color_bold}Configuration:${_update_color_nc}"
    echo "  Auto-update: $ZSH_ENV_AUTO_UPDATE"
    echo "  Frequence: ${ZSH_ENV_UPDATE_FREQUENCY:-7} jours"
    echo "  Mode: ${ZSH_ENV_UPDATE_MODE:-prompt}"

    # Modules
    echo ""
    echo -e "${_update_color_bold}Modules:${_update_color_nc}"
    [ "$ZSH_ENV_MODULE_GITLAB" = "true" ] && echo -e "  ${_update_color_green}✓${_update_color_nc} GitLab" || echo -e "  ${_update_color_yellow}✗${_update_color_nc} GitLab"
    [ "$ZSH_ENV_MODULE_DOCKER" = "true" ] && echo -e "  ${_update_color_green}✓${_update_color_nc} Docker" || echo -e "  ${_update_color_yellow}✗${_update_color_nc} Docker"
    [ "$ZSH_ENV_MODULE_NVM" = "true" ] && echo -e "  ${_update_color_green}✓${_update_color_nc} NVM" || echo -e "  ${_update_color_yellow}✗${_update_color_nc} NVM"
    [ "$ZSH_ENV_MODULE_NUSHELL" = "true" ] && echo -e "  ${_update_color_green}✓${_update_color_nc} Nushell" || echo -e "  ${_update_color_yellow}✗${_update_color_nc} Nushell"
}

# Lancer la verification au demarrage (en arriere-plan pour ne pas ralentir)
# Seulement si auto-update est active
[ "$ZSH_ENV_AUTO_UPDATE" = "true" ] && _zsh_env_auto_update &!
