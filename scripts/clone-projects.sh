#!/bin/bash
# ==============================================================================
# Script : clone-projects.sh
# Version : 3.0 (Ultimate - Progress Bar & Help)
# Auteur : Senior Dev
# ==============================================================================

# --- Configuration ---
GITLAB_BASE_DOMAIN="gitlab.example.com"
GITLAB_API_URL="https://${GITLAB_BASE_DOMAIN}/api/v4"
IGNORE_SSL_ERRORS="true"

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

${BOLD}EXEMPLES${NC}
    $0 12345 glpat-xxxx ssh
    $0 12345 glpat-xxxx https shallow
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

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [ $# -lt 2 ]; then
    echo -e "${RED}Erreur: Arguments manquants.${NC}"
    show_help
    exit 1
fi

GROUP_ID="$1"
ACCESS_TOKEN="$2"
CLONE_METHOD="${3:-https}"
DEPTH_MODE="${4:-full}"

# --- Préparation ---

CURL_OPTS="-s"
GIT_OPTS=""
GIT_CLONE_ARGS="--quiet"

if [ "$IGNORE_SSL_ERRORS" == "true" ]; then
    CURL_OPTS="$CURL_OPTS -k"
    GIT_OPTS="-c http.sslVerify=false"
fi

if [ "$DEPTH_MODE" == "shallow" ]; then
    GIT_CLONE_ARGS="$GIT_CLONE_ARGS --depth 1"
fi

if ! command -v jq &> /dev/null; then echo -e "${RED}Erreur: 'jq' requis.${NC}"; exit 1; fi

# --- Étape 1 : Récupération du nombre total de projets ---

echo -e "${CYAN}--- Initialisation (Calcul du volume...) ---${NC}"

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

# --- Étape 2 : Boucle Principale ---

current_count=0
count_new=0
count_updated=0
count_errors=0
count_skipped=0

page=1
while true; do
    response=$(curl $CURL_OPTS --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_API_URL/groups/$GROUP_ID/projects?include_subgroups=true&archived=false&per_page=100&page=$page")

    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        echo -e "\n${RED}Erreur critique API.${NC}"
        exit 1
    fi

    if [ "$(echo "$response" | jq length)" -eq 0 ]; then break; fi

    for row in $(echo "$response" | jq -r '.[] | @base64'); do
        ((current_count++))
        
        # Décodage
        _jq() { echo "$row" | base64 --decode | jq -r "$1"; }
        path_with_namespace=$(_jq '.path_with_namespace')
        
        if [ "$CLONE_METHOD" == "ssh" ]; then
            repo_url=$(_jq '.ssh_url_to_repo')
        else
            http_url=$(_jq '.http_url_to_repo')
            clean_url=${http_url#https://}
            repo_url="https://oauth2:${ACCESS_TOKEN}@${clean_url}"
        fi

        # Pour ne pas casser la barre de progression, on efface la ligne courante,
        # on affiche le message de log, et on saute une ligne pour la future barre.
        # \033[2K efface la ligne entière
        printf "\r\033[2K" 
        
        # Action
        status_msg=""
        abs_path="$(pwd)/$path_with_namespace"

        if [ -d "$path_with_namespace" ]; then
            if [ -d "$path_with_namespace/.git" ]; then
                if (cd "$path_with_namespace" && git $GIT_OPTS pull --quiet); then
                    status_msg="${GREEN}✔ Update${NC}"
                    ((count_updated++))

                    # Ajout dans zoxide si disponible
                    command -v zoxide >/dev/null && zoxide add "$abs_path"
                else
                    status_msg="${RED}✘ Fail Pull${NC}"
                    ((count_errors++))
                fi
            else
                status_msg="${YELLOW}⚠ Skip${NC}"
                ((count_skipped++))
            fi
        else
            mkdir -p "$(dirname "$path_with_namespace")"
            if git $GIT_OPTS clone $GIT_CLONE_ARGS "$repo_url" "$path_with_namespace"; then
                status_msg="${BLUE}✚ Clone${NC}"
                ((count_new++))

                # Ajout dans zoxide si disponible
                command -v zoxide >/dev/null && zoxide add "$abs_path"
            else
                status_msg="${RED}✘ Fail Clone${NC}"
                ((count_errors++))
                rmdir "$(dirname "$path_with_namespace")" 2>/dev/null
            fi
        fi

        # Affichage Log Compact
        printf "%-50s : %b\n" "${path_with_namespace:0:50}" "$status_msg"

        # Mise à jour de la barre si on connaît le total
        if [[ "$total_projects" =~ ^[0-9]+$ ]]; then
            draw_progress_bar $current_count $total_projects
        fi

    done
    ((page++))
done

echo -e "\n\n${CYAN}=== Terminé ===${NC}"
echo -e "Traités: $current_count | ${BLUE}New: $count_new${NC} | ${GREEN}Upd: $count_updated${NC} | ${RED}Err: $count_errors${NC}"