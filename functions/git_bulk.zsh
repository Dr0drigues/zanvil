# ==============================================================================
# Git Bulk - Operations Git en masse sur plusieurs repos
# ==============================================================================
# Parcourt un dossier, detecte les repos Git, et execute des actions en masse
# ==============================================================================

# ==============================================================================
# zsh-env-git-bulk : Point d'entree principal
# ==============================================================================
# Usage:
#   zsh-env-git-bulk [action] [options] [dossier]
#
# Actions:
#   status   (defaut) Affiche le statut de tous les repos
#   pull     Pull tous les repos
#   push     Push tous les repos
#   fetch    Fetch tous les repos
#   commit   Commit les repos avec des changements stages
#
# Options:
#   -m "msg"   Message de commit (pour commit)
#   -d <dir>   Dossier a scanner (defaut: dossier courant)
#   -r         Recursif (cherche aussi dans les sous-sous-dossiers)
#   -h         Aide
# ==============================================================================
zsh-env-git-bulk() {
    local action="status"
    local target_dir="."
    local commit_msg=""
    local recursive=true

    # Parse des arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            status|pull|push|fetch|commit)
                action="$1"
                shift
                ;;
            -m)
                shift
                commit_msg="$1"
                shift
                ;;
            -d)
                shift
                target_dir="$1"
                shift
                ;;
            -r)
                recursive=true
                shift
                ;;
            -h|--help)
                _git_bulk_help
                return 0
                ;;
            *)
                # Dernier argument sans flag = dossier
                if [[ -d "$1" ]]; then
                    target_dir="$1"
                else
                    _ui_msg_fail "Argument inconnu: $1"
                    _git_bulk_help
                    return 1
                fi
                shift
                ;;
        esac
    done

    # Resoudre le chemin absolu
    target_dir=$(cd "$target_dir" 2>/dev/null && pwd) || {
        _ui_msg_fail "Dossier introuvable: $target_dir"
        return 1
    }

    # Scanner les repos
    local repos=()
    repos=($(_git_bulk_scan "$target_dir" "$recursive"))

    if [[ ${#repos[@]} -eq 0 ]]; then
        _ui_header "Git Bulk"
        _ui_msg_warn "Aucun repo Git trouve dans ${target_dir}"
        return 0
    fi

    # Executer l'action
    case "$action" in
        status) _git_bulk_status "${repos[@]}" ;;
        pull)   _git_bulk_pull "${repos[@]}" ;;
        push)   _git_bulk_push "${repos[@]}" ;;
        fetch)  _git_bulk_fetch "${repos[@]}" ;;
        commit) _git_bulk_commit "$commit_msg" "${repos[@]}" ;;
    esac
}

# ==============================================================================
# Scanner les repos Git
# ==============================================================================
_git_bulk_scan() {
    local dir="$1"
    local recursive="$2"

    if [[ "$recursive" == "true" ]]; then
        find "$dir" -name ".git" -type d 2>/dev/null | sort | while IFS= read -r gitdir; do
            [[ -z "$gitdir" ]] && continue
            echo "$(dirname "$gitdir")"
        done
    else
        for sub in "$dir"/*/; do
            [[ -d "${sub}.git" ]] && echo "${sub%/}"
        done
    fi
}

# ==============================================================================
# Action: status
# ==============================================================================
_git_bulk_status() {
    local repos=("$@")

    _ui_header "Git Bulk Status"
    _ui_section "Dossier" "$(dirname "${repos[1]}")"
    _ui_section "Repos" "${#repos[@]} trouves"
    echo ""

    printf "${_ui_bold}%-24s %-14s %-10s %s${_ui_nc}\n" "Repo" "Branche" "Statut" "Details"
    _ui_separator 64

    local clean=0 dirty=0 ahead=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "detached")
        local short_name=$(_ui_truncate "$name" 22)

        # Statut du working tree
        local staged=$(git -C "$repo" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        local modified=$(git -C "$repo" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        local untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

        # Ahead/behind
        local ab=""
        ab=$(git -C "$repo" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || echo "")
        local ahead_n=0 behind_n=0
        if [[ -n "$ab" ]]; then
            ahead_n=$(echo "$ab" | awk '{print $1}')
            behind_n=$(echo "$ab" | awk '{print $2}')
        fi

        # Construire le statut
        local status_str="" details=""

        if [[ $staged -eq 0 && $modified -eq 0 && $untracked -eq 0 ]]; then
            status_str="${_ui_green}${_ui_check} clean${_ui_nc}"
            ((clean++))
        else
            status_str="${_ui_yellow}${_ui_circle} dirty${_ui_nc}"
            ((dirty++))
            local parts=()
            [[ $staged -gt 0 ]] && parts+=("${_ui_green}+${staged}staged${_ui_nc}")
            [[ $modified -gt 0 ]] && parts+=("${_ui_yellow}~${modified}mod${_ui_nc}")
            [[ $untracked -gt 0 ]] && parts+=("${_ui_dim}?${untracked}${_ui_nc}")
            details="${(j: :)parts}"
        fi

        # Ahead/behind info
        if [[ $ahead_n -gt 0 ]]; then
            details+=" ${_ui_cyan}${_ui_arrow}${ahead_n}${_ui_nc}"
            ((ahead++))
        fi
        [[ $behind_n -gt 0 ]] && details+=" ${_ui_red}${_ui_arrow}${behind_n}${_ui_nc}"

        printf "  %-24s ${_ui_cyan}%-14s${_ui_nc} %-18s %s\n" "$short_name" "$branch" "$status_str" "$details"
    done

    echo ""
    _ui_separator 64
    printf "${_ui_green}%d${_ui_nc} clean  ${_ui_yellow}%d${_ui_nc} dirty  ${_ui_cyan}%d${_ui_nc} ahead\n" "$clean" "$dirty" "$ahead"
}

# ==============================================================================
# Action: pull
# ==============================================================================
_git_bulk_pull() {
    local repos=("$@")

    _ui_header "Git Bulk Pull"
    echo ""

    local ok=0 fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        local output
        output=$(git -C "$repo" pull 2>&1)
        local rc=$?

        if [[ $rc -eq 0 ]]; then
            if [[ "$output" == *"Already up to date"* ]] || [[ "$output" == *"Already up-to-date"* ]]; then
                _ui_ok "" "a jour"
            else
                local changes=$(echo "$output" | grep -E "^\s+\d+ file" | head -1)
                _ui_ok "" "${changes:-pulled}"
            fi
            echo ""
            ((ok++))
        else
            _ui_fail "" "erreur"
            echo ""
            echo -e "    ${_ui_dim}${output}${_ui_nc}" | head -2
            ((fail++))
        fi
    done

    echo ""
    _ui_summary $fail 0
}

# ==============================================================================
# Action: push
# ==============================================================================
_git_bulk_push() {
    local repos=("$@")

    _ui_header "Git Bulk Push"
    echo ""

    local ok=0 fail=0 skip=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")

        # Verifier s'il y a quelque chose a push
        local ahead_n=0
        ahead_n=$(git -C "$repo" rev-list --count HEAD...@{upstream} --left-only 2>/dev/null || echo "0")

        if [[ $ahead_n -eq 0 ]]; then
            printf "  %-24s " "$name"
            _ui_skip "rien a push"
            echo ""
            ((skip++))
            continue
        fi

        local output
        output=$(git -C "$repo" push 2>/dev/null)
        local rc=$?

        printf "  %-24s " "$name"
        if [[ $rc -eq 0 ]]; then
            _ui_ok "" "${ahead_n} commit(s)"
            echo ""
            ((ok++))
        else
            _ui_fail "" "erreur"
            echo ""
            ((fail++))
        fi
    done

    echo ""
    _ui_separator 44
    printf "${_ui_green}%d${_ui_nc} pushed  ${_ui_dim}%d${_ui_nc} skipped  ${_ui_red}%d${_ui_nc} failed\n" "$ok" "$skip" "$fail"
}

# ==============================================================================
# Action: fetch
# ==============================================================================
_git_bulk_fetch() {
    local repos=("$@")

    _ui_header "Git Bulk Fetch"
    echo ""

    local ok=0 fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        local output
        output=$(git -C "$repo" fetch --all --prune 2>&1)
        local rc=$?

        if [[ $rc -eq 0 ]]; then
            _ui_ok ""
            echo ""
            ((ok++))
        else
            _ui_fail "" "erreur"
            echo ""
            ((fail++))
        fi
    done

    echo ""
    _ui_summary $fail 0
}

# ==============================================================================
# Action: commit
# ==============================================================================
_git_bulk_commit() {
    local commit_msg="$1"
    shift
    local repos=("$@")

    _ui_header "Git Bulk Commit"
    echo ""

    # Filtrer les repos qui ont des changements stages
    local dirty_repos=()
    for repo in "${repos[@]}"; do
        local staged=$(git -C "$repo" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        local modified=$(git -C "$repo" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        local untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

        if [[ $staged -gt 0 || $modified -gt 0 || $untracked -gt 0 ]]; then
            dirty_repos+=("$repo")
        fi
    done

    if [[ ${#dirty_repos[@]} -eq 0 ]]; then
        _ui_msg_ok "Tous les repos sont clean, rien a commit"
        return 0
    fi

    _ui_section "Repos" "${#dirty_repos[@]} avec des changements"
    echo ""

    # Lister les repos dirty
    for repo in "${dirty_repos[@]}"; do
        local name=$(basename "$repo")
        local staged=$(git -C "$repo" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        local modified=$(git -C "$repo" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        local untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

        printf "  ${_ui_yellow}${_ui_circle}${_ui_nc} %-22s" "$name"
        [[ $staged -gt 0 ]] && printf " ${_ui_green}+%d staged${_ui_nc}" "$staged"
        [[ $modified -gt 0 ]] && printf " ${_ui_yellow}~%d mod${_ui_nc}" "$modified"
        [[ $untracked -gt 0 ]] && printf " ${_ui_dim}?%d untracked${_ui_nc}" "$untracked"
        echo ""
    done
    echo ""

    # Demander si on stage tout (git add -A) avant de commit
    local do_stage
    printf "${_ui_bold}Stager tous les changements (git add -A) avant commit?${_ui_nc} [Y/n] "
    read -r do_stage
    [[ -z "$do_stage" ]] && do_stage="y"

    if [[ "$do_stage" != "n" && "$do_stage" != "N" ]]; then
        for repo in "${dirty_repos[@]}"; do
            git -C "$repo" add -A 2>/dev/null
        done
        _ui_msg_ok "Changements stages"
        echo ""
    fi

    # Gestion du message de commit
    if [[ -z "$commit_msg" ]]; then
        local msg_mode
        printf "${_ui_bold}Message commun pour tous les repos?${_ui_nc} [Y/n] "
        read -r msg_mode
        [[ -z "$msg_mode" ]] && msg_mode="y"

        if [[ "$msg_mode" != "n" && "$msg_mode" != "N" ]]; then
            # Message commun
            printf "${_ui_bold}Message de commit:${_ui_nc} "
            read -r commit_msg
            if [[ -z "$commit_msg" ]]; then
                _ui_msg_fail "Message vide, abandon"
                return 1
            fi
        fi
    fi

    echo ""
    local ok=0 fail=0

    for repo in "${dirty_repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        # Verifier qu'il y a des changements stages
        local staged_now=$(git -C "$repo" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        if [[ $staged_now -eq 0 ]]; then
            _ui_skip "rien de stage"
            echo ""
            continue
        fi

        local msg="$commit_msg"

        # Si pas de message commun, demander pour ce repo
        if [[ -z "$msg" ]]; then
            echo ""
            printf "    ${_ui_cyan}${_ui_arrow}${_ui_nc} Message pour ${_ui_bold}$name${_ui_nc}: "
            read -r msg
            if [[ -z "$msg" ]]; then
                printf "  %-24s " "$name"
                _ui_skip "skip (message vide)"
                echo ""
                continue
            fi
            printf "  %-24s " "$name"
        fi

        local output
        output=$(git -C "$repo" commit -m "$msg" 2>&1)
        local rc=$?

        if [[ $rc -eq 0 ]]; then
            local files_changed=$(echo "$output" | grep -oE '[0-9]+ file' | head -1)
            _ui_ok "" "${files_changed:-committed}"
            echo ""
            ((ok++))
        else
            _ui_fail "" "erreur"
            echo ""
            echo -e "    ${_ui_dim}${output}${_ui_nc}" | head -2
            ((fail++))
        fi
    done

    echo ""
    _ui_separator 44
    printf "${_ui_green}%d${_ui_nc} committed  ${_ui_red}%d${_ui_nc} failed\n" "$ok" "$fail"

    # Proposer le push apres commit
    if [[ $ok -gt 0 ]]; then
        echo ""
        local do_push
        printf "${_ui_bold}Push les commits?${_ui_nc} [y/N] "
        read -r do_push
        if [[ "$do_push" == "y" || "$do_push" == "Y" ]]; then
            echo ""
            _git_bulk_push "${dirty_repos[@]}"
        fi
    fi
}

# ==============================================================================
# Aide
# ==============================================================================
_git_bulk_help() {
    _ui_header "Git Bulk"

    printf "${_ui_bold}%-28s${_ui_nc} %s\n" "Action" "Description"
    _ui_separator 50

    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "status" "Statut de tous les repos (defaut)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "pull" "Pull tous les repos"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "push" "Push tous les repos"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "fetch" "Fetch tous les repos"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "commit" "Commit les repos modifies"

    echo ""
    printf "${_ui_bold}%-28s${_ui_nc} %s\n" "Option" "Description"
    _ui_separator 50

    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-m \"message\"" "Message de commit"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-d <dossier>" "Dossier a scanner (defaut: .)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-r" "Recherche recursive"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-h" "Cette aide"

    echo ""
    printf "${_ui_bold}Exemples:${_ui_nc}\n"
    _ui_separator 50
    echo -e "  ${_ui_dim}# Statut de tous les repos dans ~/projects${_ui_nc}"
    echo -e "  zsh-env-git-bulk ~/projects"
    echo ""
    echo -e "  ${_ui_dim}# Pull tous les repos du dossier courant${_ui_nc}"
    echo -e "  zsh-env-git-bulk pull"
    echo ""
    echo -e "  ${_ui_dim}# Commit avec message commun${_ui_nc}"
    echo -e "  zsh-env-git-bulk commit -m \"chore: update deps\""
    echo ""
    echo -e "  ${_ui_dim}# Commit interactif (message par repo)${_ui_nc}"
    echo -e "  zsh-env-git-bulk commit -d ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Scan recursif${_ui_nc}"
    echo -e "  zsh-env-git-bulk status -r -d ~/projects"
}

# Alias courts
alias gbulk='zsh-env-git-bulk'
alias gbs='zsh-env-git-bulk status'
alias gbp='zsh-env-git-bulk pull'
