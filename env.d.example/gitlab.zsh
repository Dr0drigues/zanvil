# GitLab — domaine, options SSL et IDs projets
export GITLAB_BASE_DOMAIN="${GITLAB_BASE_DOMAIN:-gitlab.example.com}"
export GITLAB_IGNORE_SSL="${GITLAB_IGNORE_SSL:-false}"

# IDs des projets/groupes GitLab (utilises par load_gitlab_aliases)
# Format : [environnement-composant]=ID
typeset -gA GITLAB_PROJECTS
GITLAB_PROJECTS=(
    # [env-component]="<gitlab_group_or_project_id>"
)
