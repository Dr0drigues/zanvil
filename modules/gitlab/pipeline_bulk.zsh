# ==============================================================================
# Pipeline Bulk - Pipelines GitLab en masse sur plusieurs repos
# ==============================================================================
# Parcourt un dossier, detecte les repos Git avec remote GitLab,
# et permet de trigger/suivre les pipelines CI en masse.
# Necessite: glab (GitLab CLI) authentifie
# ==============================================================================

# ==============================================================================
# zsh-env-pipeline-bulk : Point d'entree principal
# ==============================================================================
# Usage:
#   zsh-env-pipeline-bulk [action] [options] [dossier]
#
# Actions:
#   status   (defaut) Affiche le dernier pipeline de chaque repo
#   trigger  Declenche un pipeline sur chaque repo
#   watch    Suit en live les pipelines en cours
#
# Options:
#   -b <branch>  Branche cible (defaut: branche courante de chaque repo)
#   -d <dir>     Dossier a scanner (defaut: dossier courant)
#   -f <filtre>  Filtre par nom de repo (glob pattern)
#   -s <skip>    Exclure des repos par nom (glob pattern)
#   -w           Watch apres trigger (combine trigger + watch)
#   -h           Aide
# ==============================================================================
zsh-env-pipeline-bulk() {
    # Verifier que glab est installe
    if ! command -v glab &>/dev/null; then
        _ui_msg_fail "glab (GitLab CLI) n'est pas installe"
        echo -e "  ${_ui_dim}brew install glab${_ui_nc}"
        return 1
    fi

    local action="status"
    local target_dir="."
    local branch=""
    local filter=""
    local skip_pattern=""
    local watch_after=false

    # Parse des arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            status|trigger|watch)
                action="$1"
                shift
                ;;
            -b)
                shift
                branch="$1"
                shift
                ;;
            -d)
                shift
                target_dir="$1"
                shift
                ;;
            -f)
                shift
                filter="$1"
                shift
                ;;
            -s)
                shift
                skip_pattern="$1"
                shift
                ;;
            -w)
                watch_after=true
                shift
                ;;
            -h|--help)
                _pipeline_bulk_help
                return 0
                ;;
            *)
                if [[ -d "$1" ]]; then
                    target_dir="$1"
                else
                    _ui_msg_fail "Argument inconnu: $1"
                    _pipeline_bulk_help
                    return 1
                fi
                shift
                ;;
        esac
    done

    # Resoudre le chemin absolu (builtin cd pour eviter les hooks zoxide)
    target_dir=$(builtin cd "$target_dir" 2>/dev/null && pwd) || {
        _ui_msg_fail "Dossier introuvable: $target_dir"
        return 1
    }

    # Detecter si target_dir est lui-meme un repo Git avec remote GitLab
    local repos=()
    if [[ -d "$target_dir/.git" ]]; then
        local repo_name=$(basename "$target_dir")
        # Verifier si le repo est exclu par -s
        if [[ -n "$skip_pattern" ]] && [[ "$repo_name" == ${~skip_pattern} ]]; then
            _ui_header "Pipeline Bulk"
            _ui_msg_warn "${repo_name} est exclu par le filtre skip"
            return 0
        fi
        local remote_url
        remote_url=$(git -C "$target_dir" remote get-url origin 2>/dev/null)
        if [[ "$remote_url" == *gitlab* ]]; then
            repos=("$target_dir")
        else
            _ui_header "Pipeline Bulk"
            _ui_msg_warn "${target_dir} est un repo Git mais pas GitLab"
            return 0
        fi
    else
        # Scanner les sous-dossiers pour trouver des repos GitLab
        repos=($(_pipeline_bulk_scan "$target_dir" "$filter" "$skip_pattern"))
    fi

    if [[ ${#repos[@]} -eq 0 ]]; then
        _ui_header "Pipeline Bulk"
        _ui_msg_warn "Aucun repo GitLab trouve dans ${target_dir}"
        return 0
    fi

    # Executer l'action
    case "$action" in
        status)  _pipeline_bulk_status "${repos[@]}" ;;
        trigger) _pipeline_bulk_trigger "$branch" "$watch_after" "${repos[@]}" ;;
        watch)   _pipeline_bulk_watch "${repos[@]}" ;;
    esac
}

# ==============================================================================
# Scanner les repos avec une remote GitLab
# ==============================================================================
_pipeline_bulk_scan() {
    local dir="$1"
    local filter="$2"
    local skip="$3"

    for sub in "$dir"/*/; do
        [[ ! -d "${sub}.git" ]] && continue

        local name=$(basename "$sub")

        # Ignorer les bare repos (dossiers .git/)
        [[ "$name" == *.git ]] && continue

        # Appliquer le filtre d'inclusion si present
        if [[ -n "$filter" ]] && [[ "$name" != ${~filter} ]]; then
            continue
        fi

        # Appliquer le filtre d'exclusion si present
        if [[ -n "$skip" ]] && [[ "$name" == ${~skip} ]]; then
            continue
        fi

        # Verifier que la remote pointe vers GitLab
        local remote_url
        remote_url=$(git -C "$sub" remote get-url origin 2>/dev/null)
        if [[ "$remote_url" == *gitlab* ]]; then
            echo "${sub%/}"
        fi
    done
}

# ==============================================================================
# Executer glab depuis un repo (sous-shell isolee avec builtin cd)
# ==============================================================================
_pipeline_bulk_glab() {
    local repo="$1"
    shift
    ( builtin cd "$repo" && glab "$@" )
}

# ==============================================================================
# Action: status - Dernier pipeline de chaque repo
# ==============================================================================
_pipeline_bulk_status() {
    local repos=("$@")

    _ui_header "Pipeline Bulk Status"
    _ui_section "Dossier" "$(dirname "${repos[1]}")"
    _ui_section "Repos" "${#repos[@]} GitLab"
    echo ""

    printf "${_ui_bold}%-24s %-14s %-12s %-10s %s${_ui_nc}\n" "Repo" "Branche" "Pipeline" "Statut" "Duree"
    _ui_separator 72

    local passed=0 failed=0 running=0 other=0

    for repo in "${repos[@]}"; do
        local name=$(_ui_truncate "$(basename "$repo")" 22)
        local current_branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "detached")

        printf "  %-24s ${_ui_cyan}%-14s${_ui_nc} " "$name" "$current_branch"

        # Recuperer le dernier pipeline via glab
        local pipeline_info
        pipeline_info=$(_pipeline_bulk_glab "$repo" ci list -F json 2>/dev/null | _pipeline_bulk_parse_first 2>/dev/null)

        if [[ -z "$pipeline_info" || "$pipeline_info" == "none" ]]; then
            printf "${_ui_dim}%-12s %-10s %s${_ui_nc}\n" "--" "aucun" ""
            ((other++))
            continue
        fi

        local p_id p_status p_duration
        p_id=$(echo "$pipeline_info" | cut -d'|' -f1)
        p_status=$(echo "$pipeline_info" | cut -d'|' -f2)
        p_duration=$(echo "$pipeline_info" | cut -d'|' -f3)

        printf "%-12s " "#${p_id}"

        case "$p_status" in
            success)
                printf "${_ui_green}${_ui_check} passed${_ui_nc}    "
                ((passed++))
                ;;
            failed)
                printf "${_ui_red}${_ui_cross} failed${_ui_nc}    "
                ((failed++))
                ;;
            running)
                printf "${_ui_yellow}${_ui_circle} running${_ui_nc}   "
                ((running++))
                ;;
            pending)
                printf "${_ui_dim}${_ui_circle} pending${_ui_nc}   "
                ((running++))
                ;;
            canceled)
                printf "${_ui_dim}${_ui_cross} canceled${_ui_nc}  "
                ((other++))
                ;;
            *)
                printf "${_ui_dim}${_ui_circle} %-9s${_ui_nc} " "$p_status"
                ((other++))
                ;;
        esac

        # Duree
        if [[ -n "$p_duration" && "$p_duration" != "0" && "$p_duration" != "null" ]]; then
            printf "${_ui_dim}%s${_ui_nc}" "$(_pipeline_bulk_format_duration "$p_duration")"
        fi
        echo ""
    done

    echo ""
    _ui_separator 72
    printf "${_ui_green}%d${_ui_nc} passed  ${_ui_red}%d${_ui_nc} failed  ${_ui_yellow}%d${_ui_nc} running  ${_ui_dim}%d${_ui_nc} other\n" \
        "$passed" "$failed" "$running" "$other"
}

# ==============================================================================
# Action: trigger - Declencher un pipeline sur chaque repo
# ==============================================================================
_pipeline_bulk_trigger() {
    local branch="$1"
    local watch_after="$2"
    shift 2
    local repos=("$@")

    _ui_header "Pipeline Bulk Trigger"
    _ui_section "Dossier" "$(dirname "${repos[1]}")"
    _ui_section "Repos" "${#repos[@]} GitLab"
    [[ -n "$branch" ]] && _ui_section "Branche" "$branch"
    echo ""

    local ok=0 fail=0 skip=0
    local triggered_repos=()

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local short_name=$(_ui_truncate "$name" 22)
        printf "  %-24s " "$short_name"

        # Determiner la branche
        local target_branch="$branch"
        if [[ -z "$target_branch" ]]; then
            target_branch=$(git -C "$repo" branch --show-current 2>/dev/null)
        fi

        if [[ -z "$target_branch" ]]; then
            _ui_skip "detached HEAD"
            echo ""
            ((skip++))
            continue
        fi

        # Trigger le pipeline
        local output
        output=$(_pipeline_bulk_glab "$repo" ci run -b "$target_branch" 2>&1)
        local rc=$?

        if [[ $rc -eq 0 ]]; then
            local pipeline_id
            pipeline_id=$(echo "$output" | grep -oE '[0-9]+' | tail -1)
            if [[ -n "$pipeline_id" ]]; then
                _ui_ok "" "#${pipeline_id} on ${target_branch}"
            else
                _ui_ok "" "${target_branch}"
            fi
            echo ""
            ((ok++))
            triggered_repos+=("$repo")
        else
            # Extraire un message d'erreur propre
            local err_msg
            err_msg=$(echo "$output" | grep -v -E '^\s*$|^\s*ERROR\s*$' | head -1 | sed 's/^[[:space:]]*//' | cut -c1-40)
            _ui_fail "" "${err_msg:-erreur inconnue}"
            echo ""
            ((fail++))
        fi
    done

    echo ""
    _ui_separator 54
    printf "${_ui_green}%d${_ui_nc} triggered  ${_ui_dim}%d${_ui_nc} skipped  ${_ui_red}%d${_ui_nc} failed\n" "$ok" "$skip" "$fail"

    # Watch apres trigger si -w
    if [[ "$watch_after" == "true" && ${#triggered_repos[@]} -gt 0 ]]; then
        echo ""
        _ui_msg_info "Demarrage du suivi en live..."
        sleep 3
        _pipeline_bulk_watch "${triggered_repos[@]}"
    fi
}

# ==============================================================================
# Action: watch - Suivi en live des pipelines
# ==============================================================================
_pipeline_bulk_watch() {
    local repos=("$@")
    local poll_interval=10
    local max_polls=60  # 10 minutes max

    _ui_header "Pipeline Bulk Watch"
    _ui_section "Dossier" "$(dirname "${repos[1]}")"
    _ui_section "Repos" "${#repos[@]} GitLab"
    _ui_section "Refresh" "${poll_interval}s"
    echo ""
    echo -e "${_ui_dim}Ctrl+C pour arreter${_ui_nc}"
    echo ""

    local poll_count=0
    local all_done=false

    while [[ "$all_done" != "true" && $poll_count -lt $max_polls ]]; do
        # Effacer les lignes precedentes (sauf au premier passage)
        if [[ $poll_count -gt 0 ]]; then
            # Remonter de N+2 lignes (N repos + separateur + resume)
            local lines_up=$(( ${#repos[@]} + 2 ))
            printf "\033[%dA" "$lines_up"
        fi

        local passed=0 failed=0 running=0 pending=0

        for repo in "${repos[@]}"; do
            local name=$(_ui_truncate "$(basename "$repo")" 22)

            # Recuperer le dernier pipeline
            local pipeline_info
            pipeline_info=$(_pipeline_bulk_glab "$repo" ci list -F json 2>/dev/null | _pipeline_bulk_parse_first 2>/dev/null)

            local p_id p_status p_duration
            p_id=$(echo "$pipeline_info" | cut -d'|' -f1)
            p_status=$(echo "$pipeline_info" | cut -d'|' -f2)
            p_duration=$(echo "$pipeline_info" | cut -d'|' -f3)

            # Recuperer les jobs/stages pour le detail
            local stages_detail=""
            if [[ -n "$p_id" && "$p_id" != "none" ]]; then
                stages_detail=$(_pipeline_bulk_get_stages "$repo" "$p_id")
            fi

            # Construire la ligne (effacer toute la ligne avant)
            printf "\033[2K"
            printf "  %-24s " "$name"

            case "$p_status" in
                success)
                    local dur=$(_pipeline_bulk_format_duration "$p_duration")
                    printf "${_ui_green}${_ui_check} passed${_ui_nc}    ${_ui_dim}%s${_ui_nc}" "$dur"
                    [[ -n "$stages_detail" ]] && printf "  ${_ui_dim}(%s)${_ui_nc}" "$stages_detail"
                    ((passed++))
                    ;;
                failed)
                    local dur=$(_pipeline_bulk_format_duration "$p_duration")
                    printf "${_ui_red}${_ui_cross} failed${_ui_nc}    ${_ui_dim}%s${_ui_nc}" "$dur"
                    [[ -n "$stages_detail" ]] && printf "  ${_ui_dim}(%s)${_ui_nc}" "$stages_detail"
                    ((failed++))
                    ;;
                running)
                    local dur=$(_pipeline_bulk_format_duration "$p_duration")
                    printf "${_ui_yellow}${_ui_circle} running${_ui_nc}   ${_ui_dim}%s${_ui_nc}" "$dur"
                    [[ -n "$stages_detail" ]] && printf "  %s" "$stages_detail"
                    ((running++))
                    ;;
                pending|waiting_for_resource|created)
                    printf "${_ui_dim}${_ui_circle} pending${_ui_nc}   ${_ui_dim}--${_ui_nc}"
                    ((pending++))
                    ;;
                canceled)
                    printf "${_ui_dim}${_ui_cross} canceled${_ui_nc}"
                    ((passed++))
                    ;;
                *)
                    printf "${_ui_dim}${_ui_circle} %-9s${_ui_nc}" "${p_status:-unknown}"
                    ((pending++))
                    ;;
            esac
            echo ""
        done

        # Ligne de resume
        printf "\033[2K"
        _ui_separator 72
        printf "\033[2K"
        printf "${_ui_green}%d${_ui_nc} passed  ${_ui_red}%d${_ui_nc} failed  ${_ui_yellow}%d${_ui_nc} running  ${_ui_dim}%d${_ui_nc} pending" \
            "$passed" "$failed" "$running" "$pending"

        # Verifier si tout est termine
        if [[ $running -eq 0 && $pending -eq 0 ]]; then
            all_done=true
            echo ""
            echo ""
            if [[ $failed -eq 0 ]]; then
                _ui_msg_ok "Tous les pipelines sont termines"
            else
                _ui_msg_fail "${failed} pipeline(s) en echec"
            fi
        else
            printf "  ${_ui_dim}(refresh dans ${poll_interval}s)${_ui_nc}"
            echo ""
            ((poll_count++))
            sleep "$poll_interval"
        fi
    done

    if [[ $poll_count -ge $max_polls ]]; then
        echo ""
        _ui_msg_warn "Timeout atteint ($(( max_polls * poll_interval / 60 ))min)"
    fi
}

# ==============================================================================
# Helpers
# ==============================================================================

# Parse le premier pipeline du JSON retourne par glab ci list
_pipeline_bulk_parse_first() {
    local json
    json=$(cat)

    if [[ -z "$json" || "$json" == "[]" || "$json" == "null" ]]; then
        echo "none"
        return
    fi

    # Utiliser python si disponible, sinon fallback basique
    if command -v python3 &>/dev/null; then
        echo "$json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if not data:
        print('none')
    else:
        p = data[0]
        pid = p.get('id', '')
        status = p.get('status', 'unknown')
        duration = p.get('duration', 0)
        print(f'{pid}|{status}|{duration}')
except:
    print('none')
" 2>/dev/null
    else
        local id status duration
        id=$(echo "$json" | grep -oE '"id":\s*[0-9]+' | head -1 | grep -oE '[0-9]+')
        status=$(echo "$json" | grep -oE '"status":\s*"[^"]*"' | head -1 | grep -oE '"[^"]*"$' | tr -d '"')
        duration=$(echo "$json" | grep -oE '"duration":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
        if [[ -n "$id" ]]; then
            echo "${id}|${status}|${duration:-0}"
        else
            echo "none"
        fi
    fi
}

# Recuperer le detail des stages/jobs d'un pipeline
_pipeline_bulk_get_stages() {
    local repo="$1"
    local pipeline_id="$2"

    local jobs_output
    jobs_output=$(_pipeline_bulk_glab "$repo" ci view "$pipeline_id" 2>/dev/null)

    if [[ -z "$jobs_output" ]]; then
        return
    fi

    # Parser la sortie texte de glab ci view pour extraire les jobs et statuts
    local summary=""
    while IFS= read -r line; do
        if echo "$line" | grep -qE '(passed|failed|running|pending|created|skipped)'; then
            local status_icon
            if echo "$line" | grep -q 'failed'; then
                status_icon="${_ui_red}${_ui_cross}${_ui_nc}"
            elif echo "$line" | grep -q 'passed\|success'; then
                status_icon="${_ui_green}${_ui_check}${_ui_nc}"
            elif echo "$line" | grep -q 'running'; then
                status_icon="${_ui_yellow}${_ui_bullet}${_ui_nc}"
            else
                status_icon="${_ui_dim}${_ui_circle}${_ui_nc}"
            fi
            local job
            job=$(echo "$line" | sed -E 's/[[:space:]]*(.*)[[:space:]]*[-:].*/\1/' | xargs)
            if [[ -n "$job" ]]; then
                [[ -n "$summary" ]] && summary+=" ${_ui_arrow} "
                summary+="${job}${status_icon}"
            fi
        fi
    done <<< "$jobs_output"

    echo "$summary"
}

# Formater une duree en secondes vers un format lisible
_pipeline_bulk_format_duration() {
    local seconds="${1:-0}"
    seconds=${seconds%.*}
    [[ -z "$seconds" || "$seconds" == "null" ]] && return

    if [[ $seconds -lt 60 ]]; then
        printf "%ds" "$seconds"
    elif [[ $seconds -lt 3600 ]]; then
        printf "%dm%02ds" $((seconds / 60)) $((seconds % 60))
    else
        printf "%dh%02dm" $((seconds / 3600)) $(( (seconds % 3600) / 60 ))
    fi
}

# ==============================================================================
# Aide
# ==============================================================================
_pipeline_bulk_help() {
    _ui_header "Pipeline Bulk"

    printf "${_ui_bold}%-28s${_ui_nc} %s\n" "Action" "Description"
    _ui_separator 58

    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "status" "Dernier pipeline de chaque repo (defaut)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "trigger" "Declencher un pipeline sur chaque repo"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "watch" "Suivre les pipelines en live"

    echo ""
    printf "${_ui_bold}%-28s${_ui_nc} %s\n" "Option" "Description"
    _ui_separator 58

    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-b <branch>" "Branche cible (defaut: branche courante)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-d <dossier>" "Dossier a scanner (defaut: .)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-f <filtre>" "Filtre par nom de repo (glob)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-s <skip>" "Exclure des repos par nom (glob)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-w" "Watch apres trigger"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-h" "Cette aide"

    echo ""
    printf "${_ui_bold}Exemples:${_ui_nc}\n"
    _ui_separator 58
    echo ""
    echo -e "  ${_ui_dim}# Statut des pipelines dans ~/work${_ui_nc}"
    echo -e "  zsh-env-pipeline-bulk ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Trigger tous les repos sur develop${_ui_nc}"
    echo -e "  zsh-env-pipeline-bulk trigger -b develop ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Trigger + watch enchaine${_ui_nc}"
    echo -e "  zsh-env-pipeline-bulk trigger -w ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Watch les pipelines en cours${_ui_nc}"
    echo -e "  zsh-env-pipeline-bulk watch ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Filtrer par nom de repo${_ui_nc}"
    echo -e "  zsh-env-pipeline-bulk status -f 'front*' ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Exclure des repos${_ui_nc}"
    echo -e "  zsh-env-pipeline-bulk trigger -s 'runner*' ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Combiner filtre et skip${_ui_nc}"
    echo -e "  zsh-env-pipeline-bulk status -f 'api*' -s '*legacy*' ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Alias courts${_ui_nc}"
    echo -e "  gpbulk ~/work            ${_ui_dim}# = status${_ui_nc}"
    echo -e "  gpbulk trigger -w ~/work ${_ui_dim}# = trigger + watch${_ui_nc}"
}

# Alias courts
alias gpbulk='zsh-env-pipeline-bulk'
alias gpbs='zsh-env-pipeline-bulk status'
alias gpbt='zsh-env-pipeline-bulk trigger'
alias gpbw='zsh-env-pipeline-bulk watch'
