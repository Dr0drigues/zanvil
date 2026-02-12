# Permet de changer en masse un auteur de commit par un autre
# ATTENTION: Cette operation reecrit l'historique Git !
function gc-author() {
    local old_email="$1"
    local new_name="$2"
    local new_email="$3"
    local range="${4:-HEAD~10..HEAD}"

    if [[ -z "$old_email" || -z "$new_name" || -z "$new_email" ]]; then
        echo "Usage: gc-author <OLD_EMAIL> <NEW_NAME> <NEW_EMAIL> [RANGE]"
        echo ""
        echo "  RANGE: plage de commits (defaut: HEAD~10..HEAD)"
        echo "  Exemples: develop..HEAD, HEAD~5..HEAD, --all"
        echo ""
        echo "ATTENTION: Cette commande reecrit l'historique Git."
        echo "           Utilisez-la uniquement sur des branches non-publiees."
        return 1
    fi

    # Verifier que git filter-repo est disponible, sinon fallback sur filter-branch
    if command -v git-filter-repo &> /dev/null; then
        echo "Utilisation de git-filter-repo (recommande)..."
        echo "  Ancien email : $old_email"
        echo "  Nouveau nom  : $new_name"
        echo "  Nouveau email: $new_email"
        echo "  Plage        : $range"
        echo ""

        local response
        read -q "response?Continuer ? [y/N] "
        echo ""
        [[ "$response" != "y" ]] && echo "Annule." && return 0

        # Creer un tag de backup
        local backup_tag="backup/before-author-change-$(date +%Y%m%d-%H%M%S)"
        git tag "$backup_tag" HEAD
        echo "Backup cree: $backup_tag"

        git filter-repo --email-callback "
            return email if email != b'$old_email' else b'$new_email'
        " --name-callback "
            return name if email != b'$old_email' else b'$new_name'
        " --force
    else
        echo "AVERTISSEMENT: git-filter-repo n'est pas installe."
        echo "Utilisation de git filter-branch (deprecie par Git)."
        echo ""
        echo "  Installation recommandee: pip install git-filter-repo"
        echo ""
        echo "  Ancien email : $old_email"
        echo "  Nouveau nom  : $new_name"
        echo "  Nouveau email: $new_email"
        echo "  Plage        : $range"
        echo ""

        local response
        read -q "response?Continuer avec filter-branch ? [y/N] "
        echo ""
        [[ "$response" != "y" ]] && echo "Annule." && return 0

        # Creer un tag de backup
        local backup_tag="backup/before-author-change-$(date +%Y%m%d-%H%M%S)"
        git tag "$backup_tag" HEAD
        echo "Backup cree: $backup_tag"

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
