# ==============================================================================
# Auto-Update zanvil
# ==============================================================================
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

# Fichier pour stocker la date de derniere verification
ZANVIL_UPDATE_FILE="$ZANVIL_DIR/.last_update_check"

# Fonction pour verifier si une mise a jour est necessaire
_zanvil_should_check_update() {
    local frequency="${ZANVIL_UPDATE_FREQUENCY:-7}"

    # Si frequence = 0, toujours verifier
    [[ "$frequency" -eq 0 ]] && return 0

    # Si le fichier n'existe pas, c'est la premiere fois
    [[ ! -f "$ZANVIL_UPDATE_FILE" ]] && return 0

    # Calculer la difference en jours
    local last_check=$(cat "$ZANVIL_UPDATE_FILE" 2>/dev/null)
    local now=$(date +%s)
    local diff=$(( (now - last_check) / 86400 ))

    [[ "$diff" -ge "$frequency" ]]
}

# Fonction pour verifier les mises a jour
_zanvil_check_update() {
    # Verifier qu'on est dans un repo git
    [[ ! -d "$ZANVIL_DIR/.git" ]] && return 1

    # Fetch silencieux
    (cd "$ZANVIL_DIR" && git fetch origin --quiet 2>/dev/null) || return 1

    # Comparer avec origin
    local local_rev=$(cd "$ZANVIL_DIR" && git rev-parse HEAD 2>/dev/null)
    local remote_rev=$(cd "$ZANVIL_DIR" && git rev-parse origin/main 2>/dev/null)

    [[ "$local_rev" != "$remote_rev" ]]
}

# Fonction pour effectuer la mise a jour
_zanvil_do_update() {
    echo -e "${_ui_blue}[zanvil]${_ui_nc} Mise a jour en cours..."

    # Capturer la version avant mise a jour
    local old_version="${ZANVIL_VERSION:-unknown}"
    local old_help=""
    if (( $+functions[zanvil-help] )); then
        old_help=$(zanvil-help 2>/dev/null | grep -oE 'zanvil-[a-z-]+' | sort)
    fi

    if (cd "$ZANVIL_DIR" && git pull --quiet origin main 2>/dev/null); then
        echo -e "${_ui_green}[zanvil]${_ui_nc} Mise a jour terminee. Rechargez avec: ${_ui_bold}ss${_ui_nc}"

        # Detecter les nouvelles commandes apres reload du fichier
        local new_help_file="$ZANVIL_DIR/core/commands.zsh"
        if [[ -f "$new_help_file" ]]; then
            local new_cmds=$(grep -oE 'zanvil-[a-z-]+' "$new_help_file" | sort -u)
            local added=$(comm -13 <(echo "$old_help") <(echo "$new_cmds") 2>/dev/null)
            if [[ -n "$added" ]]; then
                echo ""
                echo -e "${_ui_cyan}Nouvelles commandes:${_ui_nc}"
                echo "$added" | while read cmd; do
                    echo -e "  ${_ui_green}+${_ui_nc} $cmd"
                done
            fi
        fi

        # Detecter changement de version
        local new_version=$(grep -oP 'ZANVIL_VERSION="\K[^"]+' "$ZANVIL_DIR/core/ui.zsh" 2>/dev/null)
        if [[ -n "$new_version" && "$new_version" != "$old_version" ]]; then
            echo -e "  ${_ui_bold}$old_version ${_ui_arrow} $new_version${_ui_nc}"
        fi

        # Appliquer les migrations en attente
        if [[ -d "$ZANVIL_DIR/migrations" ]] && (( $+functions[zanvil-migrate] )); then
            local state_file="$ZANVIL_DIR/.migration_version"
            local current_ver=0
            [[ -f "$state_file" ]] && current_ver=$(<"$state_file")
            local has_pending=false
            for m in "$ZANVIL_DIR/migrations"/[0-9]*.zsh(N); do
                local num=${$(basename "$m")%%_*}
                (( 10#$num > current_ver )) && { has_pending=true; break; }
            done
            if [[ "$has_pending" == "true" ]]; then
                echo ""
                zanvil-migrate
            fi
        fi

        # Splash zanvil apres une mise a jour reussie
        _zanvil_logo

        return 0
    else
        echo -e "${_ui_yellow}[zanvil]${_ui_nc} Erreur lors de la mise a jour."
        return 1
    fi
}

# Fonction pour afficher les nouveautes
_zanvil_show_changes() {
    local local_rev=$(cd "$ZANVIL_DIR" && git rev-parse HEAD 2>/dev/null)
    local changes=$(cd "$ZANVIL_DIR" && git log --oneline "$local_rev"..origin/main 2>/dev/null | head -5)

    if [[ -n "$changes" ]]; then
        echo -e "${_ui_blue}Nouveautes:${_ui_nc}"
        echo "$changes" | while read line; do
            echo -e "  ${_ui_green}*${_ui_nc} $line"
        done
    fi
}

# Fonction principale d'auto-update
_zanvil_auto_update() {
    # Verifier si on doit checker
    _zanvil_should_check_update || return 0

    # Mettre a jour le timestamp
    date +%s > "$ZANVIL_UPDATE_FILE"

    # Verifier les mises a jour disponibles
    if _zanvil_check_update; then
        echo ""
        echo -e "${_ui_yellow}[zanvil]${_ui_nc} Une mise a jour est disponible!"
        _zanvil_show_changes
        echo ""

        if [[ "$ZANVIL_UPDATE_MODE" = "auto" ]]; then
            # Mode automatique
            _zanvil_do_update
        else
            # Mode prompt
            echo -n "Mettre a jour maintenant ? [y/N] "
            read -r answer
            if [[ "$answer" =~ ^[yYoO]$ ]]; then
                _zanvil_do_update
            else
                echo -e "${_ui_blue}[zanvil]${_ui_nc} Mise a jour reportee. Lancez ${_ui_bold}zanvil-update${_ui_nc} pour mettre a jour manuellement."
            fi
        fi
        echo ""
    fi
}

# Commande manuelle pour forcer la mise a jour
zanvil-update() {
    _ui_header "Zanvil Update"

    echo -e "Verification des mises a jour..."

    if _zanvil_check_update; then
        _zanvil_show_changes
        echo ""
        _zanvil_do_update
    else
        echo -e "${_ui_green}${_ui_check}${_ui_nc} Vous etes deja a jour!"
    fi
}

# Lancer la verification au demarrage (en arriere-plan pour ne pas ralentir)
# Seulement si auto-update est active
[[ "$ZANVIL_AUTO_UPDATE" = "true" ]] && _zanvil_auto_update &!
