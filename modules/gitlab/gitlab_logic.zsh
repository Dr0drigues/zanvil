# Skip si module desactive
[[ "$ZANVIL_MODULE_GITLAB" != "true" ]] && return

### SECURITY & CONFIGURATION ###

# 1. Chargement sécurisé du token
# Créez un fichier ~/.gitlab_secrets contenant : export GITLAB_TOKEN='votre_token'
if [[ -f "$HOME/.gitlab_secrets" ]]; then
    source "$HOME/.gitlab_secrets"
else
    echo -e "${_ui_yellow}[WARN]${_ui_nc} $HOME/.gitlab_secrets introuvable. Le token GitLab est manquant."
fi

# 2. Configuration des Group IDs (Modèle de données)
# Structure : [environnement-composant]=ID
# Definir GITLAB_PROJECTS dans env.d/gitlab.zsh (typeset -gA puis assignations)
typeset -gA GITLAB_PROJECTS
[[ -z "${GITLAB_PROJECTS+x}" || ${#GITLAB_PROJECTS[@]} -eq 0 ]] && GITLAB_PROJECTS=()

### LOGIC & ALIAS GENERATION ###

###
# Génère les alias de clonage basés sur la configuration GITLAB_PROJECTS.
# Crée des alias sous la forme : gc-<composant>-<env>
#
# Itère sur le tableau associatif pour respecter le principe DRY.
###
function load_gitlab_aliases() {
    local key id parts env component alias_name

    for key id in "${(@kv)GITLAB_PROJECTS}"; do
        # Parsing de la clé "env-composant"
        # On suppose le format 'env-composant' dans la clé du tableau
        parts=("${(@s/-/)key}")
        env=$parts[1]
        component=$parts[2]

        # Construction du nom de l'alias : gc-composant-env (pour matcher votre format actuel)
        # Ex: ptf-frontco devient gc-frontco-ptf
        alias_name="gc-${component}-${env}"

        # Création de l'alias
        alias "$alias_name"="cd $WORK_DIR && clone-projects.sh $id $GITLAB_TOKEN"
    done
}

# Exécution de la génération
load_gitlab_aliases

# Fonction utilitaire pour lister les alias générés
function list-gitlab-cmds() {
    echo -e "${_ui_bold}${_ui_blue}Commandes GitLab disponibles :${_ui_nc}"
    for key in "${(@k)GITLAB_PROJECTS}"; do
        # On refait le parsing pour l'affichage
        parts=("${(@s/-/)key}")
        echo -e "  ${_ui_green}gc-${parts[2]}-${parts[1]}${_ui_nc} -> Clone le groupe ${GITLAB_PROJECTS[$key]}"
    done | sort
}

# Un alias court pour lister les commandes
alias help-clone="list-gitlab-cmds"

### GITLAB STATUS & BROWSE ###

# Vérifie le statut du Personal Access Token GitLab
function zanvil-gitlab-status() {
    [[ -z "${GITLAB_BASE_DOMAIN:-}" ]] && { _ui_msg_fail "GITLAB_BASE_DOMAIN non defini (voir env.d/gitlab.zsh)"; return 1; }
    local gitlab_url="https://${GITLAB_BASE_DOMAIN}/api/v4"

    if [[ -z "$GITLAB_TOKEN" ]]; then
        _ui_msg_fail "GITLAB_TOKEN non défini (vérifiez ~/.gitlab_secrets)"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        _ui_msg_fail "jq est requis"
        return 1
    fi

    local response
    response=$(curl -s -k --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$gitlab_url/personal_access_tokens/self" 2>/dev/null)

    if ! echo "$response" | jq -e '.id' &>/dev/null; then
        _ui_msg_fail "Impossible de récupérer le statut du token"
        return 1
    fi

    local name active revoked scopes expires_at created_at last_used
    name=$(echo "$response" | jq -r '.name')
    active=$(echo "$response" | jq -r '.active')
    revoked=$(echo "$response" | jq -r '.revoked')
    scopes=$(echo "$response" | jq -r '.scopes | join(", ")')
    expires_at=$(echo "$response" | jq -r '.expires_at')
    created_at=$(echo "$response" | jq -r '.created_at[:10]')
    last_used=$(echo "$response" | jq -r '.last_used_at[:10]')

    _ui_header "GitLab Token"

    _ui_section "Nom" "$name"
    _ui_section "Scopes" "$scopes"
    _ui_section "Créé le" "$created_at"
    _ui_section "Dernier usage" "$last_used"

    # Statut actif/révoqué
    if [[ "$active" == "true" && "$revoked" == "false" ]]; then
        _ui_section "Statut" "${_ui_green}actif ${_ui_check}${_ui_nc}"
    elif [[ "$revoked" == "true" ]]; then
        _ui_section "Statut" "${_ui_red}révoqué ${_ui_cross}${_ui_nc}"
    else
        _ui_section "Statut" "${_ui_red}inactif ${_ui_cross}${_ui_nc}"
    fi

    # Expiration avec alerte
    _ui_section "Expiration" "$expires_at"

    if [[ "$expires_at" != "null" && -n "$expires_at" ]]; then
        local now_epoch expire_epoch days_left
        now_epoch=$(date +%s)
        if [[ "$OSTYPE" == darwin* ]]; then
            expire_epoch=$(date -j -f "%Y-%m-%d" "$expires_at" +%s 2>/dev/null)
        else
            expire_epoch=$(date -d "$expires_at" +%s 2>/dev/null)
        fi

        if [[ -n "$expire_epoch" ]]; then
            days_left=$(( (expire_epoch - now_epoch) / 86400 ))
            if (( days_left < 0 )); then
                _ui_msg_fail "Token EXPIRÉ depuis $(( -days_left )) jour(s) !"
            elif (( days_left <= 30 )); then
                _ui_msg_warn "Expire dans ${days_left} jour(s)"
            else
                _ui_msg_ok "${days_left} jours restants"
            fi
        fi
    fi

    _ui_separator
}

# Ouvre le dépôt GitLab courant dans le navigateur
function zanvil-gitlab-browse() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        _ui_msg_fail "Pas dans un dépôt Git"
        return 1
    fi

    local remote_url browse_url suffix=""

    # Support des sous-pages : -m (MRs), -p (pipelines), -i (issues)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mrs)      suffix="/-/merge_requests" ;;
            -p|--pipelines) suffix="/-/pipelines" ;;
            -i|--issues)   suffix="/-/issues" ;;
            -h|--help)
                echo "Usage: zanvil-gitlab-browse [-m|-p|-i]"
                echo "  -m  Merge Requests"
                echo "  -p  Pipelines"
                echo "  -i  Issues"
                return 0 ;;
            *) _ui_msg_fail "Option inconnue: $1"; return 1 ;;
        esac
        shift
    done

    remote_url=$(git remote get-url origin 2>/dev/null)
    if [[ -z "$remote_url" ]]; then
        _ui_msg_fail "Pas de remote 'origin' trouvé"
        return 1
    fi

    # Conversion SSH -> HTTPS
    if [[ "$remote_url" == git@* ]]; then
        browse_url="${remote_url#git@}"
        browse_url="https://${browse_url%%:*}/${browse_url#*:}"
    else
        browse_url="$remote_url"
    fi

    # Nettoyage
    browse_url="${browse_url%.git}${suffix}"

    _ui_msg_info "$browse_url"

    if [[ "$OSTYPE" == darwin* ]]; then
        open "$browse_url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$browse_url"
    else
        _ui_msg_warn "Pas d'ouverture automatique — copiez l'URL ci-dessus"
    fi
}

# Expose la liste gc-* pour la complétion
typeset -gA GC_ALIAS_DESCRIPTIONS
for key id in "${(@kv)GITLAB_PROJECTS}"; do
    local parts=("${(@s/-/)key}")
    GC_ALIAS_DESCRIPTIONS[gc-${parts[2]}-${parts[1]}]="Clone groupe $id"
done

# Alias gpr : ouvre la page de creation de MR pour la branche courante
alias gpr='zanvil-gitlab-browse -m'

# Nettoyage de la fonction pour ne pas polluer l'espace de noms global
unfunction load_gitlab_aliases

### PAT EXPIRATION CHECK (silencieux au startup) ###
# Alerte une seule fois par session si le token expire dans < 14 jours
if [[ -n "$GITLAB_TOKEN" ]] && command -v jq &>/dev/null; then
    _zanvil_pat_check() {
        [[ -z "${GITLAB_BASE_DOMAIN:-}" ]] && { _ui_msg_fail "GITLAB_BASE_DOMAIN non defini (voir env.d/gitlab.zsh)"; return 1; }
    local gitlab_url="https://${GITLAB_BASE_DOMAIN}/api/v4"
        local response expires_at
        response=$(curl -s -k --max-time 3 --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$gitlab_url/personal_access_tokens/self" 2>/dev/null)
        expires_at=$(echo "$response" | jq -r '.expires_at // empty' 2>/dev/null)

        if [[ -n "$expires_at" ]]; then
            local now_epoch expire_epoch days_left
            now_epoch=$(date +%s)
            if [[ "$OSTYPE" == darwin* ]]; then
                expire_epoch=$(date -j -f "%Y-%m-%d" "$expires_at" +%s 2>/dev/null)
            else
                expire_epoch=$(date -d "$expires_at" +%s 2>/dev/null)
            fi
            if [[ -n "$expire_epoch" ]]; then
                days_left=$(( (expire_epoch - now_epoch) / 86400 ))
                if (( days_left < 0 )); then
                    echo -e "${_ui_red}[GitLab]${_ui_nc} Token PAT ${_ui_bold}EXPIRE${_ui_nc} depuis $(( -days_left )) jour(s) !"
                elif (( days_left <= 14 )); then
                    echo -e "${_ui_yellow}[GitLab]${_ui_nc} Token PAT expire dans ${_ui_bold}${days_left}${_ui_nc} jour(s)"
                fi
            fi
        fi
    }
    _zanvil_pat_check &!
fi
