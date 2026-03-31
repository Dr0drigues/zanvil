#!/bin/bash
# ==============================================================================
# Script : trigger-jobs.sh
# Description : Lance un job specifique en masse sur les pipelines actives
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
NC=$'\033[0m'

# --- Fonctions Utilitaires ---

show_help() {
    cat << EOF
${BOLD}USAGE${NC}
    $0 -j <JOB_NAME> [CIBLE] [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Recherche les pipelines actives contenant un job specifique
    et permet de lancer ce job en masse.

${BOLD}CIBLE (une des options suivantes)${NC}
    -p, --path <group/project>    Chemin du projet (encodage auto)
    -P, --project-id <ID>         ID numerique du projet
    -g, --group-id <ID>           ID du groupe (traite tous les projets)

${BOLD}OPTIONS${NC}
    -j, --job <NAME>              Nom exact du job (obligatoire)
    -f, --force                   Lance sans confirmation
    -v, --verbose                 Mode verbose (affiche les details de debug)

${BOLD}VARIABLES D'ENVIRONNEMENT${NC}
    GITLAB_TOKEN    Token d'acces personnel (scope: api)
                    Defini dans ~/.gitlab_secrets

${BOLD}EXEMPLES${NC}
    $0 -p "mygroup/myproject" -j deploy-staging
    $0 -P 12345 -j build --force
    $0 -g 35621 -j deploy -f
EOF
}

# Fonction d'encodage URL pour les paths
url_encode() {
    local string="$1"
    # Remplace / par %2F et autres caracteres speciaux
    echo "$string" | sed 's|/|%2F|g; s| |%20|g'
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[DEBUG]${NC} $1"; }

# --- Gestion des Arguments ---

PROJECT_PATH=""
PROJECT_ID=""
GROUP_ID=""
JOB_NAME=""
FORCE_MODE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--path)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -P|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -g|--group-id)
            GROUP_ID="$2"
            shift 2
            ;;
        -j|--job)
            JOB_NAME="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            log_error "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# --- Validation ---

if [ -z "$JOB_NAME" ]; then
    log_error "Le nom du job est obligatoire (-j/--job)"
    show_help
    exit 1
fi

# Validation de la cible (une seule option parmi -p, -P, -g)
target_count=0
[ -n "$PROJECT_PATH" ] && ((target_count++))
[ -n "$PROJECT_ID" ] && ((target_count++))
[ -n "$GROUP_ID" ] && ((target_count++))

if [ "$target_count" -eq 0 ]; then
    log_error "Une cible est requise (-p, -P ou -g)"
    show_help
    exit 1
fi

if [ "$target_count" -gt 1 ]; then
    log_error "Une seule cible autorisee (-p, -P ou -g)"
    exit 1
fi

# Conversion du path en ID encode si necessaire
if [ -n "$PROJECT_PATH" ]; then
    PROJECT_ID=$(url_encode "$PROJECT_PATH")
    log_info "Path encode: $PROJECT_ID"
fi

if [ -z "$GITLAB_TOKEN" ]; then
    log_error "GITLAB_TOKEN non defini. Verifiez ~/.gitlab_secrets"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "'jq' requis mais non installe."
    exit 1
fi

# --- Preparation ---

CURL_OPTS="-s --connect-timeout 10 --max-time 60"
if [ "$IGNORE_SSL_ERRORS" == "true" ]; then
    CURL_OPTS="$CURL_OPTS -k"
fi

# Fichiers temporaires pour stocker les jobs trouves
TMP_JOBS_FILE=$(mktemp)
TMP_INFO_FILE=$(mktemp)
TMP_COUNTER_FILE=$(mktemp)
TMP_PIPELINES_FILE=$(mktemp)
trap "rm -f '$TMP_JOBS_FILE' '$TMP_INFO_FILE' '$TMP_COUNTER_FILE' '$TMP_PIPELINES_FILE'" EXIT

# --- Etape 1 : Recuperation des pipelines actives ---

echo -e "${CYAN}--- Recherche des pipelines actives ---${NC}"

# Resume des parametres en mode verbose
if [ "$VERBOSE" = true ]; then
    echo -e "${CYAN}[DEBUG]${NC} Parametres:"
    echo -e "  Job recherche: ${BOLD}$JOB_NAME${NC}"
    [ -n "$PROJECT_ID" ] && echo -e "  Project ID: ${BOLD}$PROJECT_ID${NC}"
    [ -n "$GROUP_ID" ] && echo -e "  Group ID: ${BOLD}$GROUP_ID${NC}"
    echo -e "  Force: ${BOLD}$FORCE_MODE${NC}"
    echo ""
fi

# Compteur global pour l'affichage de progression
SCAN_JOBS_FOUND=0
SCAN_PIPELINES=0

# Fonction pour afficher la progression du scan
draw_scan_progress() {
    if [ "$VERBOSE" = false ]; then
        printf "\r\033[2K  Scan en cours... Jobs trouves: ${GREEN}%d${NC} | Pipelines: ${BLUE}%d${NC}" "$SCAN_JOBS_FOUND" "$SCAN_PIPELINES"
    fi
}

# Fonction pour scanner un projet (via endpoint /jobs - plus efficace)
scan_project() {
    local proj_id="$1"
    local proj_name="$2"
    local page=1

    log_debug "Scan projet: $proj_name (ID: $proj_id)"

    # Construire les scopes de jobs a rechercher
    local job_scopes="scope[]=manual&scope[]=pending&scope[]=created"
    local url="$GITLAB_API_URL/projects/$proj_id/jobs?$job_scopes&per_page=100"

    log_debug "URL: $url"

    while true; do
        response=$(curl $CURL_OPTS --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "${url}&page=$page")

        if ! echo "$response" | jq -e . >/dev/null 2>&1; then
            log_warn "Erreur API pour le projet $proj_name"
            log_debug "Reponse brute: $response"
            return
        fi

        count=$(echo "$response" | jq 'length')
        log_debug "Page $page: $count job(s) trouve(s)"

        if [ "$count" -eq 0 ]; then
            log_debug "Aucun job sur cette page, fin du scan"
            break
        fi

        # Filtrer par nom de job directement
        echo "$response" | jq -c --arg name "$JOB_NAME" '.[] | select(.name == $name)' \
            | while IFS= read -r job_json; do

            job_id=$(echo "$job_json" | jq -r '.id')
            job_name=$(echo "$job_json" | jq -r '.name')
            job_status=$(echo "$job_json" | jq -r '.status')
            pipeline_id=$(echo "$job_json" | jq -r '.pipeline.id')
            pipeline_ref=$(echo "$job_json" | jq -r '.ref')

            log_debug "  ${GREEN}MATCH${NC}: Pipeline #$pipeline_id ($pipeline_ref) -> Job #$job_id '$job_name' [$job_status]"

            echo "${proj_id}:${job_id}" >> "$TMP_JOBS_FILE"
            echo "[$proj_name] Pipeline #$pipeline_id ($pipeline_ref) -> Job \"$JOB_NAME\" [$job_status]" >> "$TMP_INFO_FILE"

            # Incrementer compteurs (via fichier car subshell)
            echo "1" >> "$TMP_COUNTER_FILE"
        done

        # Compter les pipelines uniques
        echo "$response" | jq -r --arg name "$JOB_NAME" '.[] | select(.name == $name) | .pipeline.id' \
            | sort -u | while IFS= read -r pid; do
            [ -n "$pid" ] && echo "$pid" >> "$TMP_PIPELINES_FILE"
        done

        # Mettre a jour l'affichage
        if [ -f "$TMP_COUNTER_FILE" ]; then
            SCAN_JOBS_FOUND=$(wc -l < "$TMP_COUNTER_FILE" | tr -d ' ')
        fi
        if [ -f "$TMP_PIPELINES_FILE" ]; then
            SCAN_PIPELINES=$(sort -u "$TMP_PIPELINES_FILE" | wc -l | tr -d ' ')
        fi
        draw_scan_progress

        ((page++))
    done
}

pipeline_count=0
project_count=0

if [ -n "$GROUP_ID" ]; then
    # Mode groupe : recuperer tous les projets du groupe
    log_info "Scan du groupe $GROUP_ID..."
    page=1

    while true; do
        projects_response=$(curl $CURL_OPTS --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_API_URL/groups/$GROUP_ID/projects?include_subgroups=true&archived=false&per_page=100&page=$page")

        if ! echo "$projects_response" | jq -e . >/dev/null 2>&1; then
            log_error "Erreur API lors de la recuperation des projets du groupe."
            exit 1
        fi

        count=$(echo "$projects_response" | jq 'length')
        if [ "$count" -eq 0 ]; then break; fi

        echo "$projects_response" | jq -c '.[]' | while IFS= read -r proj_json; do
            proj_id=$(echo "$proj_json" | jq -r '.id')
            proj_name=$(echo "$proj_json" | jq -r '.path_with_namespace')
            log_debug "Scan: $proj_name"
            scan_project "$proj_id" "$proj_name"
        done

        project_count=$((project_count + count))
        ((page++))
    done
    [ "$VERBOSE" = false ] && echo ""
    log_info "Projets scannes: $project_count"
else
    # Mode projet unique
    scan_project "$PROJECT_ID" "$PROJECT_ID"
    [ "$VERBOSE" = false ] && echo ""
fi

# --- Etape 2 : Affichage des resultats ---

# Lecture des fichiers temporaires dans des arrays (compatible bash 3.x)
JOBS_TO_TRIGGER=()
JOBS_INFO=()
if [ -f "$TMP_JOBS_FILE" ]; then
    while IFS= read -r line; do
        JOBS_TO_TRIGGER+=("$line")
    done < "$TMP_JOBS_FILE"
fi
if [ -f "$TMP_INFO_FILE" ]; then
    while IFS= read -r line; do
        JOBS_INFO+=("$line")
    done < "$TMP_INFO_FILE"
fi

if [ ${#JOBS_TO_TRIGGER[@]} -eq 0 ]; then
    log_warn "Aucun job '$JOB_NAME' trouve dans les pipelines actives."
    exit 0
fi

echo -e "\n${CYAN}--- Jobs trouves ---${NC}\n"

for info in "${JOBS_INFO[@]}"; do
    echo -e "  ${GREEN}*${NC} $info"
done

echo -e "\n${BOLD}Total : ${#JOBS_TO_TRIGGER[@]} job(s) a lancer${NC}\n"

# --- Etape 3 : Confirmation ---

if [ "$FORCE_MODE" = false ]; then
    read -p "Lancer ces jobs ? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[yYoO]$ ]]; then
        log_info "Operation annulee."
        exit 0
    fi
fi

# --- Etape 4 : Lancement des jobs ---

echo -e "\n${CYAN}--- Lancement des jobs ---${NC}\n"

success_count=0
error_count=0
total=${#JOBS_TO_TRIGGER[@]}
errors_log=""

# Fonction pour dessiner la barre de progression
draw_progress() {
    local current=$1
    local total=$2
    local job_id=$3
    local status=$4
    local width=25
    local percent=$((current * 100 / total))
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=$(printf "%${filled}s" | tr ' ' '#')
    local space=$(printf "%${empty}s" | tr ' ' '-')

    printf "\r\033[2K  [${BLUE}%s${NC}%s] %d/%d - Job #%s %s" "$bar" "$space" "$current" "$total" "$job_id" "$status"
}

for i in "${!JOBS_TO_TRIGGER[@]}"; do
    # Format: project_id:job_id
    entry="${JOBS_TO_TRIGGER[$i]}"
    proj_id="${entry%%:*}"
    job_id="${entry##*:}"
    current=$((i + 1))

    draw_progress "$current" "$total" "$job_id" "..."

    result=$(curl $CURL_OPTS -X POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_API_URL/projects/$proj_id/jobs/$job_id/play")

    if echo "$result" | jq -e '.id' >/dev/null 2>&1; then
        draw_progress "$current" "$total" "$job_id" "${GREEN}OK${NC}"
        ((success_count++))
    else
        draw_progress "$current" "$total" "$job_id" "${RED}ERREUR${NC}"
        error_msg=$(echo "$result" | jq -r '.message // .error // "Erreur inconnue"')
        errors_log="${errors_log}\n  ${RED}*${NC} Job #$job_id: $error_msg"
        ((error_count++))
    fi
done

# Saut de ligne final
echo ""

# Afficher les erreurs s'il y en a
if [ -n "$errors_log" ]; then
    echo -e "\n${RED}Erreurs:${NC}$errors_log"
fi

# --- Resume ---

echo -e "\n${CYAN}=== Termine ===${NC}"
echo -e "Lances: ${GREEN}$success_count${NC} | Erreurs: ${RED}$error_count${NC}"
