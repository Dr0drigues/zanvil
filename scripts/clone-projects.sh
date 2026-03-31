#!/bin/bash
# ==============================================================================
# Script : clone-projects.sh
# ==============================================================================

# --- Configuration ---
GITLAB_BASE_DOMAIN="${GITLAB_BASE_DOMAIN:-gitlab.forge.tsc.azr.intranet}"
GITLAB_API_URL="https://${GITLAB_BASE_DOMAIN}/api/v4"
IGNORE_SSL_ERRORS="${GITLAB_IGNORE_SSL:-true}"

# --- Couleurs & Styles ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# --- Fonctions Utilitaires ---

show_help() {
    cat << EOF
${BOLD}USAGE${NC}
    $0 <GROUP_ID> <ACCESS_TOKEN> [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Clone ou met à jour tous les projets d'un groupe GitLab récursivement.
    Gère la pagination, le SSL interne, et les projets archivés.

${BOLD}ARGUMENTS${NC}
    GROUP_ID        ID numérique du groupe GitLab (ex: 35621)
    ACCESS_TOKEN    Token d'accès personnel (scope: read_api)

${BOLD}OPTIONS${NC}
    ssh | https     Méthode de clonage (Défaut: https)
    full | shallow  Profondeur du clone (Défaut: full).
                    'shallow' utilise --depth 1 pour plus de rapidité.

${BOLD}FLAGS${NC}
    --help, -h      Affiche ce message d'aide.
    --dry-run       Liste les projets sans exécuter git clone/pull.
    --parallel [N]  Clone/update N projets en parallèle (défaut: 4).

${BOLD}EXEMPLES${NC}
    $0 12345 glpat-xxxx ssh
    $0 12345 glpat-xxxx https shallow
    $0 12345 glpat-xxxx --dry-run
    $0 12345 glpat-xxxx --parallel 8
    $0 12345 glpat-xxxx https shallow --parallel 4 --dry-run
EOF
}

draw_progress_bar() {
    # $1: current, $2: total
    local width=30
    local percent=$(( ($1 * 100) / $2 ))
    local filled=$(( ($percent * $width) / 100 ))
    local empty=$(( $width - $filled ))

    # Construction de la barre [####-------]
    local bar=$(printf "%0.s#" $(seq 1 $filled))
    local space=$(printf "%0.s-" $(seq 1 $empty))

    # Affichage sur la même ligne (\r)
    printf "\r[${BLUE}${bar}${NC}${space}] ${percent}%% ($1/$2)"
}

# --- Gestion des Arguments ---

DRY_RUN=false
PARALLEL=0
POSITIONAL_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --help|-h)     show_help; exit 0 ;;
        --dry-run)     DRY_RUN=true ;;
        --parallel)    PARALLEL=4 ;;  # valeur par défaut si pas de N
        --parallel=*)  PARALLEL="${arg#*=}" ;;
        *)             POSITIONAL_ARGS+=("$arg") ;;
    esac
done

# Gestion --parallel N (deux mots séparés)
CLEANED_ARGS=()
SKIP_NEXT=false
for i in "${!POSITIONAL_ARGS[@]}"; do
    if $SKIP_NEXT; then SKIP_NEXT=false; continue; fi
    if [[ "${POSITIONAL_ARGS[$i]}" == "--parallel" ]] && [[ "${POSITIONAL_ARGS[$((i+1))]}" =~ ^[0-9]+$ ]]; then
        PARALLEL="${POSITIONAL_ARGS[$((i+1))]}"
        SKIP_NEXT=true
    else
        CLEANED_ARGS+=("${POSITIONAL_ARGS[$i]}")
    fi
done
POSITIONAL_ARGS=("${CLEANED_ARGS[@]}")

if [ ${#POSITIONAL_ARGS[@]} -lt 2 ]; then
    echo -e "${RED}Erreur: Arguments manquants.${NC}"
    show_help
    exit 1
fi

GROUP_ID="${POSITIONAL_ARGS[0]}"
ACCESS_TOKEN="${POSITIONAL_ARGS[1]}"
CLONE_METHOD="${POSITIONAL_ARGS[2]:-https}"
DEPTH_MODE="${POSITIONAL_ARGS[3]:-full}"

# --- Préparation ---

CURL_OPTS="-s"
GIT_OPTS=()
GIT_CLONE_ARGS=(--quiet)

if [ "$IGNORE_SSL_ERRORS" == "true" ]; then
    CURL_OPTS="$CURL_OPTS -k"
    GIT_OPTS+=(-c http.sslVerify=false)
fi

# Utiliser le header HTTP pour l'authentification (evite l'exposition du token dans ps)
if [ "$CLONE_METHOD" != "ssh" ]; then
    GIT_OPTS+=(-c "http.extraheader=PRIVATE-TOKEN: $ACCESS_TOKEN")
fi

if [ "$DEPTH_MODE" == "shallow" ]; then
    GIT_CLONE_ARGS+=(--depth 1)
fi

if ! command -v jq &> /dev/null; then echo -e "${RED}Erreur: 'jq' requis.${NC}"; exit 1; fi

# --- Étape 1 : Récupération du nombre total de projets ---

echo -e "${CYAN}--- Initialisation (Calcul du volume...) ---${NC}"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Mode DRY-RUN : aucune action ne sera exécutée${NC}"
fi
if [ "$PARALLEL" -gt 0 ]; then
    echo -e "Mode: ${BOLD}parallèle (x$PARALLEL)${NC}"
fi

# On fait un appel HEAD (ou GET léger) pour lire le header X-Total
# Note: On demande &per_page=1 pour minimiser le payload
headers=$(curl $CURL_OPTS -I --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_API_URL/groups/$GROUP_ID/projects?include_subgroups=true&archived=false&per_page=1")

# Extraction du header X-Total (insensible à la casse)
total_projects=$(echo "$headers" | grep -i "^x-total:" | awk '{print $2}' | tr -d '\r')

# Fallback si le header est manquant (API anciennes)
if [ -z "$total_projects" ]; then
    total_projects="??"
    echo -e "${YELLOW}Warning: Impossible de déterminer le nombre total de projets.${NC}"
else
    echo -e "Projets à traiter : ${BOLD}$total_projects${NC}"
fi

echo -e "${CYAN}--- Démarrage de la synchronisation ---${NC}"
echo "" # Saut de ligne pour l'affichage propre

# --- Fonction de traitement d'un projet ---

process_project() {
    local row="$1"
    local path_with_namespace repo_url abs_path

    _jq() { echo "$row" | base64 --decode | jq -r "$1"; }
    path_with_namespace=$(_jq '.path_with_namespace')

    if [ "$CLONE_METHOD" == "ssh" ]; then
        repo_url=$(_jq '.ssh_url_to_repo')
    else
        repo_url=$(_jq '.http_url_to_repo')
    fi

    abs_path="$(pwd)/$path_with_namespace"

    if [ -d "$path_with_namespace" ]; then
        if [ -d "$path_with_namespace/.git" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "DRYRUN_UPDATE|$path_with_namespace"
            elif (cd "$path_with_namespace" && git "${GIT_OPTS[@]}" pull --quiet 2>/dev/null); then
                command -v zoxide >/dev/null && zoxide add "$abs_path"
                echo "UPDATE_OK|$path_with_namespace"
            else
                echo "UPDATE_FAIL|$path_with_namespace"
            fi
        else
            echo "SKIP|$path_with_namespace"
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            echo "DRYRUN_CLONE|$path_with_namespace"
        else
            mkdir -p "$(dirname "$path_with_namespace")"
            if git "${GIT_OPTS[@]}" clone "${GIT_CLONE_ARGS[@]}" "$repo_url" "$path_with_namespace" 2>/dev/null; then
                command -v zoxide >/dev/null && zoxide add "$abs_path"
                echo "CLONE_OK|$path_with_namespace"
            else
                echo "CLONE_FAIL|$path_with_namespace"
                rmdir "$(dirname "$path_with_namespace")" 2>/dev/null
            fi
        fi
    fi
}

# --- Affichage d'un résultat ---

display_result() {
    local action="$1" path="$2"
    local status_msg=""
    case "$action" in
        CLONE_OK)       status_msg="${BLUE}✚ Clone${NC}";            ((count_new++)) ;;
        UPDATE_OK)      status_msg="${GREEN}✔ Update${NC}";          ((count_updated++)) ;;
        CLONE_FAIL)     status_msg="${RED}✘ Fail Clone${NC}";        ((count_errors++)) ;;
        UPDATE_FAIL)    status_msg="${RED}✘ Fail Pull${NC}";         ((count_errors++)) ;;
        SKIP)           status_msg="${YELLOW}⚠ Skip${NC}";           ((count_skipped++)) ;;
        DRYRUN_CLONE)   status_msg="${BLUE}○ Would Clone${NC}";      ((count_new++)) ;;
        DRYRUN_UPDATE)  status_msg="${GREEN}○ Would Update${NC}";    ((count_updated++)) ;;
    esac
    printf "%-50s : %b\n" "${path:0:50}" "$status_msg"
}

# --- Étape 2 : Collecte des projets ---

all_rows=()
page=1
while true; do
    response=$(curl $CURL_OPTS --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_API_URL/groups/$GROUP_ID/projects?include_subgroups=true&archived=false&per_page=100&page=$page")

    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        echo -e "\n${RED}Erreur critique API.${NC}"
        exit 1
    fi

    if [ "$(echo "$response" | jq length)" -eq 0 ]; then break; fi

    while IFS= read -r row; do
        all_rows+=("$row")
    done < <(echo "$response" | jq -r '.[] | @base64')

    ((page++))
done

# --- Étape 3 : Traitement ---

current_count=0
count_new=0
count_updated=0
count_errors=0
count_skipped=0

if [ "$PARALLEL" -gt 0 ] && [ ${#all_rows[@]} -gt 0 ]; then
    # --- Mode parallèle ---
    # Exporte les variables nécessaires pour les sous-shells
    export CLONE_METHOD DRY_RUN IGNORE_SSL_ERRORS ACCESS_TOKEN DEPTH_MODE
    export RED GREEN YELLOW BLUE CYAN BOLD NC

    # Reconstruit GIT_OPTS dans un format exportable
    export GIT_OPTS_STR=""
    for opt in "${GIT_OPTS[@]}"; do
        GIT_OPTS_STR+="$opt"$'\x1f'  # séparateur unit separator
    done
    export GIT_CLONE_ARGS_STR=""
    for opt in "${GIT_CLONE_ARGS[@]}"; do
        GIT_CLONE_ARGS_STR+="$opt"$'\x1f'
    done

    # Fonction wrapper pour xargs (reconstruit les tableaux)
    process_project_parallel() {
        local row="$1"
        # Reconstruit les tableaux depuis les chaînes exportées
        IFS=$'\x1f' read -ra GIT_OPTS <<< "$GIT_OPTS_STR"
        IFS=$'\x1f' read -ra GIT_CLONE_ARGS <<< "$GIT_CLONE_ARGS_STR"

        local path_with_namespace repo_url abs_path
        _jq() { echo "$row" | base64 --decode | jq -r "$1"; }
        path_with_namespace=$(_jq '.path_with_namespace')

        if [ "$CLONE_METHOD" == "ssh" ]; then
            repo_url=$(_jq '.ssh_url_to_repo')
        else
            repo_url=$(_jq '.http_url_to_repo')
        fi

        abs_path="$(pwd)/$path_with_namespace"

        if [ -d "$path_with_namespace" ]; then
            if [ -d "$path_with_namespace/.git" ]; then
                if [ "$DRY_RUN" = true ]; then
                    echo "DRYRUN_UPDATE|$path_with_namespace"
                elif (cd "$path_with_namespace" && git "${GIT_OPTS[@]}" pull --quiet 2>/dev/null); then
                    command -v zoxide >/dev/null && zoxide add "$abs_path"
                    echo "UPDATE_OK|$path_with_namespace"
                else
                    echo "UPDATE_FAIL|$path_with_namespace"
                fi
            else
                echo "SKIP|$path_with_namespace"
            fi
        else
            if [ "$DRY_RUN" = true ]; then
                echo "DRYRUN_CLONE|$path_with_namespace"
            else
                mkdir -p "$(dirname "$path_with_namespace")"
                if git "${GIT_OPTS[@]}" clone "${GIT_CLONE_ARGS[@]}" "$repo_url" "$path_with_namespace" 2>/dev/null; then
                    command -v zoxide >/dev/null && zoxide add "$abs_path"
                    echo "CLONE_OK|$path_with_namespace"
                else
                    echo "CLONE_FAIL|$path_with_namespace"
                    rmdir "$(dirname "$path_with_namespace")" 2>/dev/null
                fi
            fi
        fi
    }
    export -f process_project_parallel

    # Exécution parallèle et lecture des résultats
    while IFS='|' read -r action path; do
        ((current_count++))
        printf "\r\033[2K"
        display_result "$action" "$path"
    done < <(printf '%s\n' "${all_rows[@]}" | xargs -P "$PARALLEL" -I {} bash -c 'process_project_parallel "$@"' _ {})

else
    # --- Mode séquentiel ---
    for row in "${all_rows[@]}"; do
        ((current_count++))
        printf "\r\033[2K"

        local_result=$(process_project "$row")
        IFS='|' read -r action path <<< "$local_result"
        display_result "$action" "$path"

        # Mise à jour de la barre si on connaît le total
        if [[ "$total_projects" =~ ^[0-9]+$ ]]; then
            draw_progress_bar $current_count $total_projects
        fi
    done
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "\n\n${CYAN}=== DRY-RUN Terminé (aucune action exécutée) ===${NC}"
else
    echo -e "\n\n${CYAN}=== Terminé ===${NC}"
fi
echo -e "Traités: $current_count | ${BLUE}New: $count_new${NC} | ${GREEN}Upd: $count_updated${NC} | ${RED}Err: $count_errors${NC}"
