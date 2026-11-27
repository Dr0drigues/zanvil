# Permet de changer en masse un auteur de commit par un autre
# ATTENTION: Cette operation reecrit l'historique Git !
function gc-author() {
    local old_email="$1"
    local new_name="$2"
    local new_email="$3"
    local range="${4:-HEAD~10..HEAD}"

    if [[ -z "$old_email" || -z "$new_name" || -z "$new_email" ]]; then
        echo -e "${_ui_bold}Usage:${_ui_nc} gc-author <OLD_EMAIL> <NEW_NAME> <NEW_EMAIL> [RANGE]"
        echo ""
        echo "  RANGE: plage de commits (defaut: HEAD~10..HEAD)"
        echo "  Exemples: develop..HEAD, HEAD~5..HEAD, --all"
        echo ""
        echo -e "${_ui_yellow}ATTENTION:${_ui_nc} Cette commande reecrit l'historique Git."
        echo "           Utilisez-la uniquement sur des branches non-publiees."
        return 1
    fi

    # Les valeurs finissent dans un mailmap et dans du shell (filter-branch) : pas de guillemets,
    # d'antislash, de $, d'accent grave, de chevrons ni de saut de ligne.
    local v
    for v in "$old_email" "$new_name" "$new_email"; do
        if [[ "$v" == *[\'\"\\\$\`\<\>$'\n']* ]]; then
            _ui_msg_fail "Caractere interdit dans : $v"
            return 1
        fi
    done

    # Affichage unifie des parametres
    echo -e "${_ui_bold}Changement d'auteur Git${_ui_nc}"
    _ui_section "Ancien email" "$old_email"
    _ui_section "Nouveau nom" "$new_name"
    _ui_section "Nouveau email" "$new_email"
    _ui_section "Plage" "$range"
    echo ""

    # Methode utilisee
    local method=""
    if command -v git-filter-repo &> /dev/null; then
        method="filter-repo"
        _ui_section "Methode" "git-filter-repo ${_ui_green}(recommande)${_ui_nc}"
    else
        method="filter-branch"
        _ui_section "Methode" "git filter-branch ${_ui_yellow}(deprecie)${_ui_nc}"
        echo -e "  ${_ui_dim}Installation recommandee: pip install git-filter-repo${_ui_nc}"
    fi
    echo ""

    local response
    printf "Continuer ? [y/N] "
    read -r response
    [[ "$response" == [yYoO]* ]] || { echo -e "${_ui_dim}Annule.${_ui_nc}"; return 0; }

    # Creer un tag de backup
    local backup_tag="backup/before-author-change-$(date +%Y%m%d-%H%M%S)"
    git tag "$backup_tag" HEAD
    _ui_msg_ok "Backup cree: $backup_tag"

    if [[ "$method" == "filter-repo" ]]; then
        # Mailmap plutot que des callbacks Python : le callback de nom ne recoit pas l'email, et
        # une valeur interpolee dans du Python est du code. --refs limite la reecriture a la
        # plage (sans lui, toutes les branches sont reecrites et origin est retire).
        local mailmap rc
        mailmap=$(mktemp) || return 1
        print -r -- "$new_name <$new_email> <$old_email>" > "$mailmap"
        local -a refs=()
        if [[ "$range" != --all ]]; then
            local branch
            branch=$(git symbolic-ref -q --short HEAD) || { _ui_msg_fail "HEAD detache : precisez une plage sur une branche"; command rm -f "$mailmap"; return 1; }
            refs=(--refs "${range//HEAD/$branch}")
        fi
        git filter-repo --mailmap "$mailmap" "${refs[@]}" --force
        rc=$?
        command rm -f "$mailmap"
        return $rc
    else
        git filter-branch --env-filter '
            if [ "$GIT_COMMITTER_EMAIL" = "'"$old_email"'" ]; then
                export GIT_COMMITTER_NAME="'"$new_name"'"
                export GIT_COMMITTER_EMAIL="'"$new_email"'"
            fi
            if [ "$GIT_AUTHOR_EMAIL" = "'"$old_email"'" ]; then
                export GIT_AUTHOR_NAME="'"$new_name"'"
                export GIT_AUTHOR_EMAIL="'"$new_email"'"
            fi
        ' --tag-name-filter cat -- "$range"
    fi
}
