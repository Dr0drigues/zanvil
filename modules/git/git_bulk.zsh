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
#   checkout Switch tous les repos sur une branche
#   stash    Stash/restore les repos dirty
#   branch   Gestion de branches multi-repos
#   log      Historique condense multi-repos
#   merge    Merge une branche dans tous les repos
#   prune    Nettoie les branches stale (gone/merged)
#   clean    Supprime les fichiers untracked
#   reset    Reset sur upstream
#
# Options:
#   -m "msg"         Message de commit/stash
#   -d <dir>         Dossier a scanner (defaut: dossier courant)
#   -r               Recursif (cherche aussi dans les sous-sous-dossiers)
#   -b <br> [base]   Cree la branche (pour checkout)
#   -n|--dry-run     Simule l'action sans l'executer
#   --apply          Execute (pour prune/branch delete/clean/reset)
#   --abort          Abort les merges en cours
#   --since <date>   Filtrer par date (pour log)
#   --author <name>  Filtrer par auteur (pour log)
#   -h               Aide
# ==============================================================================
zsh-env-git-bulk() {
    local action="status"
    local target_dir="."
    local commit_msg=""
    local recursive=true
    local dry_run=false
    local apply=false
    local branch_name=""
    local create_branch=false
    local base_branch=""
    local sub_action=""
    local log_count=5
    local log_since=""
    local log_author=""

    # Parse des arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            status|pull|push|fetch|commit|prune|clean|reset)
                action="$1"
                shift
                ;;
            checkout|merge)
                action="$1"
                shift
                # Prochain arg non-flag = nom de branche
                if [[ $# -gt 0 && "$1" != -* ]]; then
                    branch_name="$1"
                    shift
                fi
                ;;
            stash|branch)
                action="$1"
                shift
                # Prochain arg non-flag = sous-action ou argument
                if [[ $# -gt 0 && "$1" != -* ]]; then
                    sub_action="$1"
                    shift
                    # Pour branch delete et stash, capturer un eventuel argument supplementaire
                    if [[ $# -gt 0 && "$1" != -* ]]; then
                        branch_name="$1"
                        shift
                    fi
                fi
                ;;
            log)
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
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            --apply)
                apply=true
                shift
                ;;
            -b)
                create_branch=true
                shift
                if [[ $# -gt 0 && "$1" != -* ]]; then
                    branch_name="$1"
                    shift
                    # Eventuelle base branch
                    if [[ $# -gt 0 && "$1" != -* ]]; then
                        base_branch="$1"
                        shift
                    fi
                fi
                ;;
            --since)
                shift
                log_since="$1"
                shift
                ;;
            --author)
                shift
                log_author="$1"
                shift
                ;;
            --abort)
                sub_action="abort"
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
    if [[ "$dry_run" == "true" ]]; then
        case "$action" in
            status)   _git_bulk_status "${repos[@]}" ;;
            pull)     _git_bulk_pull_dry "${repos[@]}" ;;
            push)     _git_bulk_push_dry "${repos[@]}" ;;
            fetch)    _ui_msg_info "[DRY-RUN] fetch: rien a simuler, utilisez 'fetch' directement" ;;
            commit)   _git_bulk_commit_dry "${repos[@]}" ;;
            prune)    _git_bulk_prune false "${repos[@]}" ;;
            checkout) _git_bulk_checkout_dry "$branch_name" "${repos[@]}" ;;
            stash)    _git_bulk_stash_dry "$sub_action" "${repos[@]}" ;;
            branch)   _git_bulk_branch "$sub_action" "$branch_name" false "${repos[@]}" ;;
            log)      _git_bulk_log "$log_count" "$log_since" "$log_author" "${repos[@]}" ;;
            merge)    _git_bulk_merge_dry "$branch_name" "${repos[@]}" ;;
            clean)    _git_bulk_clean false "${repos[@]}" ;;
            reset)    _git_bulk_reset false "${repos[@]}" ;;
        esac
    else
        case "$action" in
            status)   _git_bulk_status "${repos[@]}" ;;
            pull)     _git_bulk_pull "${repos[@]}" ;;
            push)     _git_bulk_push "${repos[@]}" ;;
            fetch)    _git_bulk_fetch "${repos[@]}" ;;
            commit)   _git_bulk_commit "$commit_msg" "${repos[@]}" ;;
            prune)    _git_bulk_prune "$apply" "${repos[@]}" ;;
            checkout) _git_bulk_checkout "$branch_name" "$create_branch" "$base_branch" "${repos[@]}" ;;
            stash)    _git_bulk_stash "$sub_action" "$commit_msg" "${repos[@]}" ;;
            branch)   _git_bulk_branch "$sub_action" "$branch_name" "$apply" "${repos[@]}" ;;
            log)      _git_bulk_log "$log_count" "$log_since" "$log_author" "${repos[@]}" ;;
            merge)    _git_bulk_merge "$branch_name" "$sub_action" "${repos[@]}" ;;
            clean)    _git_bulk_clean "$apply" "${repos[@]}" ;;
            reset)    _git_bulk_reset "$apply" "${repos[@]}" ;;
        esac
    fi
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
# Dry-run: pull (fetch + affiche combien de commits en retard)
# ==============================================================================
_git_bulk_pull_dry() {
    local repos=("$@")

    _ui_header "Git Bulk Pull [DRY-RUN]"
    echo ""

    local behind_total=0 up_to_date=0 errors=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        # Fetch pour mettre a jour les refs distantes
        git -C "$repo" fetch 2>/dev/null
        local rc=$?

        if [[ $rc -ne 0 ]]; then
            _ui_fail "" "fetch erreur"
            echo ""
            ((errors++))
            continue
        fi

        local behind_n
        behind_n=$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null || echo "0")

        if [[ $behind_n -gt 0 ]]; then
            _ui_msg_info "[DRY-RUN] ${behind_n} commit(s) a pull"
            ((behind_total += behind_n))
        else
            _ui_ok "" "a jour"
            echo ""
            ((up_to_date++))
        fi
    done

    echo ""
    _ui_separator 54
    printf "${_ui_cyan}%d${_ui_nc} a jour  ${_ui_yellow}%d${_ui_nc} commit(s) a pull  ${_ui_red}%d${_ui_nc} erreurs\n" "$up_to_date" "$behind_total" "$errors"
}

# ==============================================================================
# Dry-run: push (affiche combien de commits en avance)
# ==============================================================================
_git_bulk_push_dry() {
    local repos=("$@")

    _ui_header "Git Bulk Push [DRY-RUN]"
    echo ""

    local ahead_total=0 up_to_date=0 errors=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        local ahead_n
        ahead_n=$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null)
        local rc=$?

        if [[ $rc -ne 0 ]]; then
            _ui_skip "pas de remote"
            echo ""
            ((errors++))
            continue
        fi

        if [[ $ahead_n -gt 0 ]]; then
            _ui_msg_info "[DRY-RUN] ${ahead_n} commit(s) a push"
            ((ahead_total += ahead_n))
        else
            _ui_ok "" "rien a push"
            echo ""
            ((up_to_date++))
        fi
    done

    echo ""
    _ui_separator 54
    printf "${_ui_cyan}%d${_ui_nc} a jour  ${_ui_yellow}%d${_ui_nc} commit(s) a push  ${_ui_dim}%d${_ui_nc} sans remote\n" "$up_to_date" "$ahead_total" "$errors"
}

# ==============================================================================
# Dry-run: commit (affiche les fichiers modifies par repo)
# ==============================================================================
_git_bulk_commit_dry() {
    local repos=("$@")

    _ui_header "Git Bulk Commit [DRY-RUN]"
    echo ""

    local dirty=0 clean=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        local changes
        changes=$(git -C "$repo" status --porcelain 2>/dev/null)
        local file_count=$(echo "$changes" | grep -c '.' 2>/dev/null || echo "0")

        if [[ -z "$changes" ]]; then
            _ui_ok "" "clean"
            echo ""
            ((clean++))
        else
            _ui_msg_info "[DRY-RUN] ${file_count} fichier(s) modifie(s)"
            ((dirty++))
        fi
    done

    echo ""
    _ui_separator 54
    printf "${_ui_green}%d${_ui_nc} clean  ${_ui_yellow}%d${_ui_nc} avec changements\n" "$clean" "$dirty"
}

# ==============================================================================
# Action: checkout
# ==============================================================================
_git_bulk_checkout() {
    local branch="$1" create="$2" base="$3"
    shift 3
    local repos=("$@")

    if [[ -z "$branch" ]]; then
        _ui_msg_fail "Usage: zsh-env-git-bulk checkout <branche> [-b <branche> [base]]"
        return 1
    fi

    _ui_header "Git Bulk Checkout"
    _ui_section "Branche" "$branch"
    [[ "$create" == "true" ]] && _ui_section "Mode" "creation (-b)${base:+ depuis $base}"
    echo ""

    local ok=0 skip=0 fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null)
        printf "  %-24s " "$name"

        # Deja sur la bonne branche
        if [[ "$current" == "$branch" && "$create" != "true" ]]; then
            _ui_skip "deja sur $branch"
            echo ""
            ((skip++))
            continue
        fi

        # Verifier si dirty
        local dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
        if [[ -n "$dirty" ]]; then
            local dirty_count=$(echo "$dirty" | wc -l | tr -d ' ')
            _ui_warn "$name" "skip (dirty: ${dirty_count} fichiers)"
            echo ""
            ((skip++))
            continue
        fi

        local output rc
        if [[ "$create" == "true" ]]; then
            if [[ -n "$base" ]]; then
                output=$(git -C "$repo" checkout -b "$branch" "$base" 2>&1)
            else
                output=$(git -C "$repo" checkout -b "$branch" 2>&1)
            fi
            rc=$?
        else
            # Verifier si la branche existe localement
            if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
                output=$(git -C "$repo" checkout "$branch" 2>&1)
                rc=$?
            # Sinon, verifier en remote
            elif git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
                output=$(git -C "$repo" checkout -t "origin/$branch" 2>&1)
                rc=$?
            else
                _ui_fail "" "branche '$branch' introuvable"
                echo ""
                ((fail++))
                continue
            fi
        fi

        if [[ $rc -eq 0 ]]; then
            _ui_ok "" "$branch (was $current)"
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
    _ui_separator 54
    printf "${_ui_green}%d${_ui_nc} switched  ${_ui_dim}%d${_ui_nc} skipped  ${_ui_red}%d${_ui_nc} failed\n" "$ok" "$skip" "$fail"
}

# ==============================================================================
# Dry-run: checkout
# ==============================================================================
_git_bulk_checkout_dry() {
    local branch="$1"
    shift
    local repos=("$@")

    if [[ -z "$branch" ]]; then
        _ui_msg_fail "Usage: zsh-env-git-bulk checkout <branche> [--dry-run]"
        return 1
    fi

    _ui_header "Git Bulk Checkout [DRY-RUN]"
    _ui_section "Branche" "$branch"
    echo ""

    printf "${_ui_bold}%-24s %-14s %-12s %s${_ui_nc}\n" "Repo" "Actuelle" "Cible" "Statut"
    _ui_separator 64

    local ready=0 dirty=0 missing=0 already=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null)
        printf "  %-24s ${_ui_cyan}%-14s${_ui_nc} " "$name" "$current"

        if [[ "$current" == "$branch" ]]; then
            printf "%-12s ${_ui_dim}deja dessus${_ui_nc}\n" "$branch"
            ((already++))
            continue
        fi

        # Branche existe ?
        local has_local=$(git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null && echo "yes")
        local has_remote=$(git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null && echo "yes")

        if [[ -z "$has_local" && -z "$has_remote" ]]; then
            printf "%-12s ${_ui_red}introuvable${_ui_nc}\n" "—"
            ((missing++))
            continue
        fi

        # Dirty ?
        local is_dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
        if [[ -n "$is_dirty" ]]; then
            local src="local"
            [[ -z "$has_local" ]] && src="remote"
            printf "%-12s ${_ui_yellow}dirty (bloquerait)${_ui_nc}\n" "$branch ($src)"
            ((dirty++))
        else
            local src="local"
            [[ -z "$has_local" ]] && src="remote"
            printf "%-12s ${_ui_green}pret${_ui_nc}\n" "$branch ($src)"
            ((ready++))
        fi
    done

    echo ""
    _ui_separator 64
    printf "${_ui_green}%d${_ui_nc} pret  ${_ui_dim}%d${_ui_nc} deja  ${_ui_yellow}%d${_ui_nc} dirty  ${_ui_red}%d${_ui_nc} introuvable\n" \
        "$ready" "$already" "$dirty" "$missing"
}

# ==============================================================================
# Action: stash
# ==============================================================================
_git_bulk_stash() {
    local sub="$1" msg="$2"
    shift 2
    local repos=("$@")
    [[ -z "$sub" ]] && sub="push"

    case "$sub" in
        push) _git_bulk_stash_push "$msg" "${repos[@]}" ;;
        pop)  _git_bulk_stash_pop "${repos[@]}" ;;
        list) _git_bulk_stash_list "${repos[@]}" ;;
        *)
            _ui_msg_fail "Sous-action inconnue: $sub (push|pop|list)"
            return 1
            ;;
    esac
}

_git_bulk_stash_push() {
    local msg="$1"
    shift
    local repos=("$@")

    _ui_header "Git Bulk Stash"
    echo ""

    local ok=0 skip=0 fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        local dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
        if [[ -z "$dirty" ]]; then
            _ui_skip "clean"
            echo ""
            ((skip++))
            continue
        fi

        local output rc
        if [[ -n "$msg" ]]; then
            output=$(git -C "$repo" stash push -m "$msg" 2>&1)
        else
            output=$(git -C "$repo" stash push 2>&1)
        fi
        rc=$?

        if [[ $rc -eq 0 ]]; then
            local count=$(echo "$dirty" | wc -l | tr -d ' ')
            _ui_ok "" "stashed (${count} fichiers)"
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
    printf "${_ui_green}%d${_ui_nc} stashed  ${_ui_dim}%d${_ui_nc} clean  ${_ui_red}%d${_ui_nc} failed\n" "$ok" "$skip" "$fail"
}

_git_bulk_stash_pop() {
    local repos=("$@")

    _ui_header "Git Bulk Stash Pop"
    echo ""

    local ok=0 skip=0 fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        local has_stash=$(git -C "$repo" stash list 2>/dev/null | head -1)
        if [[ -z "$has_stash" ]]; then
            _ui_skip "pas de stash"
            echo ""
            ((skip++))
            continue
        fi

        local output
        output=$(git -C "$repo" stash pop 2>&1)
        local rc=$?

        if [[ $rc -eq 0 ]]; then
            _ui_ok "" "restored"
            echo ""
            ((ok++))
        else
            if [[ "$output" == *"CONFLICT"* ]]; then
                _ui_warn "$name" "conflits"
                echo ""
            else
                _ui_fail "" "erreur"
                echo ""
            fi
            ((fail++))
        fi
    done

    echo ""
    _ui_separator 44
    printf "${_ui_green}%d${_ui_nc} popped  ${_ui_dim}%d${_ui_nc} no stash  ${_ui_red}%d${_ui_nc} failed\n" "$ok" "$skip" "$fail"
}

_git_bulk_stash_list() {
    local repos=("$@")

    _ui_header "Git Bulk Stash List"
    echo ""

    local total=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local stashes=$(git -C "$repo" stash list 2>/dev/null)

        if [[ -z "$stashes" ]]; then
            continue
        fi

        local count=$(echo "$stashes" | wc -l | tr -d ' ')
        ((total += count))

        printf "  ${_ui_cyan}%-24s${_ui_nc} %d stash(s)\n" "$name" "$count"
        echo "$stashes" | while IFS= read -r line; do
            printf "    ${_ui_dim}%s${_ui_nc}\n" "$line"
        done
    done

    if [[ $total -eq 0 ]]; then
        _ui_msg_ok "Aucun stash trouve"
    else
        echo ""
        _ui_separator 44
        printf "${_ui_yellow}%d${_ui_nc} stash(s) au total\n" "$total"
    fi
}

# ==============================================================================
# Dry-run: stash
# ==============================================================================
_git_bulk_stash_dry() {
    local sub="$1"
    shift
    local repos=("$@")
    [[ -z "$sub" || "$sub" == "push" ]] && sub="push"

    _ui_header "Git Bulk Stash [DRY-RUN]"
    echo ""

    if [[ "$sub" == "push" ]]; then
        local dirty=0 clean=0
        for repo in "${repos[@]}"; do
            local name=$(basename "$repo")
            printf "  %-24s " "$name"
            local changes=$(git -C "$repo" status --porcelain 2>/dev/null)
            if [[ -n "$changes" ]]; then
                local count=$(echo "$changes" | wc -l | tr -d ' ')
                _ui_msg_info "[DRY-RUN] ${count} fichier(s) a stash"
                ((dirty++))
            else
                _ui_ok "" "clean"
                echo ""
                ((clean++))
            fi
        done
        echo ""
        _ui_separator 44
        printf "${_ui_yellow}%d${_ui_nc} a stash  ${_ui_green}%d${_ui_nc} clean\n" "$dirty" "$clean"
    elif [[ "$sub" == "pop" ]]; then
        local with=0 without=0
        for repo in "${repos[@]}"; do
            local name=$(basename "$repo")
            printf "  %-24s " "$name"
            local has=$(git -C "$repo" stash list 2>/dev/null | head -1)
            if [[ -n "$has" ]]; then
                _ui_msg_info "[DRY-RUN] stash disponible"
                ((with++))
            else
                _ui_skip "pas de stash"
                echo ""
                ((without++))
            fi
        done
        echo ""
        _ui_separator 44
        printf "${_ui_yellow}%d${_ui_nc} avec stash  ${_ui_dim}%d${_ui_nc} sans\n" "$with" "$without"
    else
        _git_bulk_stash_list "${repos[@]}"
    fi
}

# ==============================================================================
# Action: branch
# ==============================================================================
_git_bulk_branch() {
    local sub="$1" target="$2" do_apply="$3"
    shift 3
    local repos=("$@")
    [[ -z "$sub" ]] && sub="list"

    case "$sub" in
        list) _git_bulk_branch_list "${repos[@]}" ;;
        delete) _git_bulk_branch_delete "$target" "$do_apply" "${repos[@]}" ;;
        *)
            _ui_msg_fail "Sous-action inconnue: $sub (list|delete)"
            return 1
            ;;
    esac
}

_git_bulk_branch_list() {
    local repos=("$@")

    _ui_header "Git Bulk Branch"
    echo ""

    printf "${_ui_bold}%-24s %-14s %s${_ui_nc}\n" "Repo" "Courante" "Branches"
    _ui_separator 54

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null || echo "detached")
        local branch_count=$(git -C "$repo" branch --list 2>/dev/null | wc -l | tr -d ' ')

        printf "  %-24s ${_ui_cyan}%-14s${_ui_nc} %d locale(s)\n" "$name" "$current" "$branch_count"
    done
}

_git_bulk_branch_delete() {
    local target="$1" do_apply="$2"
    shift 2
    local repos=("$@")

    local protected=("main" "master" "develop" "dev")

    if [[ -z "$target" ]]; then
        _ui_msg_fail "Usage: zsh-env-git-bulk branch delete <branche> [--apply]"
        return 1
    fi

    # Verifier si branche protegee
    for p in "${protected[@]}"; do
        if [[ "$target" == "$p" ]]; then
            _ui_msg_fail "Impossible de supprimer la branche protegee '$target'"
            return 1
        fi
    done

    if [[ "$do_apply" == "true" ]]; then
        _ui_header "Git Bulk Branch Delete"
    else
        _ui_header "Git Bulk Branch Delete [DRY-RUN]"
    fi
    _ui_section "Branche" "$target"
    echo ""

    local ok=0 skip=0 fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null)
        printf "  %-24s " "$name"

        # Verifier si c'est la branche courante
        if [[ "$current" == "$target" ]]; then
            _ui_warn "$name" "branche courante, skip"
            echo ""
            ((skip++))
            continue
        fi

        # Verifier si la branche existe
        if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$target" 2>/dev/null; then
            _ui_skip "branche absente"
            echo ""
            ((skip++))
            continue
        fi

        if [[ "$do_apply" == "true" ]]; then
            local output
            output=$(git -C "$repo" branch -d "$target" 2>&1)
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                _ui_ok "" "supprimee"
                echo ""
                ((ok++))
            else
                _ui_fail "" "erreur: $output"
                echo ""
                ((fail++))
            fi
        else
            _ui_msg_info "[DRY-RUN] branche presente, supprimable"
            ((ok++))
        fi
    done

    echo ""
    _ui_separator 54
    if [[ "$do_apply" == "true" ]]; then
        printf "${_ui_green}%d${_ui_nc} supprimee(s)  ${_ui_dim}%d${_ui_nc} skip  ${_ui_red}%d${_ui_nc} failed\n" "$ok" "$skip" "$fail"
    else
        printf "${_ui_yellow}%d${_ui_nc} a supprimer  ${_ui_dim}%d${_ui_nc} skip  ${_ui_dim}(--apply pour executer)${_ui_nc}\n" "$ok" "$skip"
    fi
}

# ==============================================================================
# Action: log
# ==============================================================================
_git_bulk_log() {
    local count="$1" since="$2" author="$3"
    shift 3
    local repos=("$@")

    _ui_header "Git Bulk Log"
    local filters=""
    [[ -n "$since" ]] && filters+="depuis $since  "
    [[ -n "$author" ]] && filters+="auteur: $author  "
    [[ -n "$filters" ]] && _ui_section "Filtres" "$filters"
    echo ""

    local total_commits=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null || echo "detached")

        # Construire la commande log
        local -a log_args=("log" "--oneline" "--no-decorate" "-n" "$count")
        [[ -n "$since" ]] && log_args+=("--since=$since")
        [[ -n "$author" ]] && log_args+=("--author=$author")

        local output
        output=$(git -C "$repo" "${log_args[@]}" 2>/dev/null)

        if [[ -z "$output" ]]; then
            continue
        fi

        local commit_count=$(echo "$output" | wc -l | tr -d ' ')
        ((total_commits += commit_count))

        printf "  ${_ui_cyan}%-24s${_ui_nc} ${_ui_dim}(%s)${_ui_nc}\n" "$name" "$current"
        echo "$output" | while IFS= read -r line; do
            printf "    ${_ui_dim}%s${_ui_nc}\n" "$line"
        done
        echo ""
    done

    _ui_separator 44
    printf "${_ui_cyan}%d${_ui_nc} commit(s) sur ${_ui_cyan}%d${_ui_nc} repo(s)\n" "$total_commits" "${#repos[@]}"
}

# ==============================================================================
# Action: merge
# ==============================================================================
_git_bulk_merge() {
    local branch="$1" sub="$2"
    shift 2
    local repos=("$@")

    # Gerer --abort
    if [[ "$sub" == "abort" ]]; then
        _ui_header "Git Bulk Merge Abort"
        echo ""
        local ok=0 skip=0
        for repo in "${repos[@]}"; do
            local name=$(basename "$repo")
            printf "  %-24s " "$name"
            local output
            output=$(git -C "$repo" merge --abort 2>&1)
            if [[ $? -eq 0 ]]; then
                _ui_ok "" "abort"
                echo ""
                ((ok++))
            else
                _ui_skip "pas de merge en cours"
                echo ""
                ((skip++))
            fi
        done
        echo ""
        _ui_separator 44
        printf "${_ui_green}%d${_ui_nc} aborted  ${_ui_dim}%d${_ui_nc} skip\n" "$ok" "$skip"
        return 0
    fi

    if [[ -z "$branch" ]]; then
        _ui_msg_fail "Usage: zsh-env-git-bulk merge <branche>"
        return 1
    fi

    _ui_header "Git Bulk Merge"
    _ui_section "Source" "$branch"
    echo ""

    local ok=0 uptodate=0 conflicts=0 fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null)
        printf "  %-24s " "$name"

        # Verifier que la branche source existe
        if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null && \
           ! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
            _ui_skip "branche '$branch' absente"
            echo ""
            ((fail++))
            continue
        fi

        local output
        output=$(git -C "$repo" merge "$branch" 2>&1)
        local rc=$?

        if [[ $rc -eq 0 ]]; then
            if [[ "$output" == *"Already up to date"* ]] || [[ "$output" == *"Already up-to-date"* ]]; then
                _ui_ok "" "a jour"
                echo ""
                ((uptodate++))
            else
                _ui_ok "" "merged ($branch -> $current)"
                echo ""
                ((ok++))
            fi
        else
            if [[ "$output" == *"CONFLICT"* ]]; then
                local conflict_count=$(echo "$output" | grep -c "CONFLICT")
                _ui_warn "$name" "${conflict_count} conflit(s)"
                echo ""
                ((conflicts++))
            else
                _ui_fail "" "erreur"
                echo ""
                echo -e "    ${_ui_dim}${output}${_ui_nc}" | head -2
                ((fail++))
            fi
        fi
    done

    echo ""
    _ui_separator 54
    printf "${_ui_green}%d${_ui_nc} merged  ${_ui_dim}%d${_ui_nc} a jour  ${_ui_yellow}%d${_ui_nc} conflits  ${_ui_red}%d${_ui_nc} failed\n" \
        "$ok" "$uptodate" "$conflicts" "$fail"

    if [[ $conflicts -gt 0 ]]; then
        echo ""
        _ui_msg_warn "Resolvez les conflits puis committez, ou utilisez: gbulk merge --abort"
    fi
}

# ==============================================================================
# Dry-run: merge
# ==============================================================================
_git_bulk_merge_dry() {
    local branch="$1"
    shift
    local repos=("$@")

    if [[ -z "$branch" ]]; then
        _ui_msg_fail "Usage: zsh-env-git-bulk merge <branche> --dry-run"
        return 1
    fi

    _ui_header "Git Bulk Merge [DRY-RUN]"
    _ui_section "Source" "$branch"
    echo ""

    local clean=0 conflicts=0 missing=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        # Verifier que la branche source existe
        if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null && \
           ! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
            _ui_skip "branche absente"
            echo ""
            ((missing++))
            continue
        fi

        # Tenter le merge sans commit
        local output
        output=$(git -C "$repo" merge --no-commit --no-ff "$branch" 2>&1)
        local rc=$?

        # Toujours abort pour revenir a l'etat initial
        git -C "$repo" merge --abort 2>/dev/null

        if [[ $rc -eq 0 ]]; then
            if [[ "$output" == *"Already up to date"* ]] || [[ "$output" == *"Already up-to-date"* ]]; then
                _ui_ok "" "a jour"
            else
                _ui_ok "" "merge possible"
            fi
            echo ""
            ((clean++))
        else
            if [[ "$output" == *"CONFLICT"* ]]; then
                local conflict_count=$(echo "$output" | grep -c "CONFLICT")
                _ui_warn "$name" "${conflict_count} conflit(s) detecte(s)"
            else
                _ui_fail "" "erreur"
            fi
            echo ""
            ((conflicts++))
        fi
    done

    echo ""
    _ui_separator 54
    printf "${_ui_green}%d${_ui_nc} ok  ${_ui_yellow}%d${_ui_nc} conflits  ${_ui_dim}%d${_ui_nc} absente\n" "$clean" "$conflicts" "$missing"
}

# ==============================================================================
# Action: clean (dry-run par defaut)
# ==============================================================================
_git_bulk_clean() {
    local do_apply="$1"
    shift
    local repos=("$@")

    if [[ "$do_apply" == "true" ]]; then
        _ui_header "Git Bulk Clean"
    else
        _ui_header "Git Bulk Clean [DRY-RUN]"
    fi
    echo ""

    local total_files=0 total_repos=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        printf "  %-24s " "$name"

        local output
        if [[ "$do_apply" == "true" ]]; then
            output=$(git -C "$repo" clean -fd 2>&1)
        else
            output=$(git -C "$repo" clean -fdn 2>&1)
        fi

        if [[ -z "$output" ]]; then
            _ui_ok "" "rien a nettoyer"
            echo ""
            continue
        fi

        local file_count=$(echo "$output" | wc -l | tr -d ' ')
        ((total_files += file_count))
        ((total_repos++))

        if [[ "$do_apply" == "true" ]]; then
            _ui_ok "" "${file_count} fichier(s) supprime(s)"
        else
            _ui_msg_info "[DRY-RUN] ${file_count} fichier(s) a supprimer"
        fi
    done

    echo ""
    _ui_separator 54
    if [[ "$do_apply" == "true" ]]; then
        printf "${_ui_green}%d${_ui_nc} fichier(s) supprime(s) sur ${_ui_cyan}%d${_ui_nc} repo(s)\n" "$total_files" "$total_repos"
    else
        if [[ $total_files -gt 0 ]]; then
            printf "${_ui_yellow}%d${_ui_nc} fichier(s) a supprimer sur ${_ui_cyan}%d${_ui_nc} repo(s)  ${_ui_dim}(--apply pour executer)${_ui_nc}\n" \
                "$total_files" "$total_repos"
        else
            _ui_msg_ok "Rien a nettoyer"
        fi
    fi
}

# ==============================================================================
# Action: reset (dry-run par defaut, confirmation interactive)
# ==============================================================================
_git_bulk_reset() {
    local do_apply="$1"
    shift
    local repos=("$@")

    if [[ "$do_apply" == "true" ]]; then
        _ui_header "Git Bulk Reset"
    else
        _ui_header "Git Bulk Reset [DRY-RUN]"
    fi
    echo ""

    local total_dirty=0 total_reset=0 total_fail=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null)
        printf "  %-24s " "$name"

        # Verifier upstream
        local upstream
        upstream=$(git -C "$repo" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
        if [[ -z "$upstream" ]]; then
            _ui_skip "pas d'upstream"
            echo ""
            continue
        fi

        # Verifier s'il y a une divergence
        local local_sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
        local remote_sha=$(git -C "$repo" rev-parse "@{upstream}" 2>/dev/null)

        if [[ "$local_sha" == "$remote_sha" ]]; then
            local dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
            if [[ -z "$dirty" ]]; then
                _ui_ok "" "aligne sur $upstream"
                echo ""
                continue
            fi
        fi

        local changes=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        local ahead_n=$(git -C "$repo" rev-list --count "@{upstream}"..HEAD 2>/dev/null || echo "0")
        ((total_dirty++))

        if [[ "$do_apply" == "true" ]]; then
            local output
            output=$(git -C "$repo" reset --hard "@{upstream}" 2>&1)
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                _ui_ok "" "reset sur $upstream"
                echo ""
                ((total_reset++))
            else
                _ui_fail "" "erreur"
                echo ""
                ((total_fail++))
            fi
        else
            local details=""
            [[ $changes -gt 0 ]] && details+="${changes} fichiers modifies  "
            [[ $ahead_n -gt 0 ]] && details+="${ahead_n} commits ahead"
            _ui_msg_info "[DRY-RUN] $details"
        fi
    done

    echo ""
    _ui_separator 54
    if [[ "$do_apply" == "true" ]]; then
        printf "${_ui_green}%d${_ui_nc} reset  ${_ui_red}%d${_ui_nc} failed\n" "$total_reset" "$total_fail"
    else
        if [[ $total_dirty -gt 0 ]]; then
            printf "${_ui_yellow}%d${_ui_nc} repo(s) a reset  ${_ui_dim}(--apply pour executer)${_ui_nc}\n" "$total_dirty"
        else
            _ui_msg_ok "Tous les repos sont alignes sur upstream"
        fi
    fi
}

# ==============================================================================
# Action: prune (dry-run par defaut, --apply pour supprimer)
# ==============================================================================
_git_bulk_prune() {
    local do_apply="$1"
    shift
    local repos=("$@")

    local protected=("main" "master" "develop" "dev")

    if [[ "$do_apply" == "true" ]]; then
        _ui_header "Git Bulk Prune"
    else
        _ui_header "Git Bulk Prune [DRY-RUN]"
    fi
    echo ""

    local total_stale=0 total_deleted=0 total_failed=0 repos_affected=0

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        local current=$(git -C "$repo" branch --show-current 2>/dev/null)

        # Fetch + prune remote tracking refs
        git -C "$repo" fetch --prune 2>/dev/null

        # Detecter la branche par defaut
        local default_branch
        default_branch=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
        [[ -z "$default_branch" ]] && default_branch="main"

        # Collecter les branches gone
        local gone_branches=()
        local line
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local br=$(echo "$line" | awk '{print $1}')
            gone_branches+=("$br")
        done < <(git -C "$repo" branch -vv 2>/dev/null | grep ': gone\]' | sed 's/^[* ]*//')

        # Collecter les branches merged
        local merged_branches=()
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local br=$(echo "$line" | sed 's/^[* ]*//' | awk '{print $1}')
            merged_branches+=("$br")
        done < <(git -C "$repo" branch --merged "$default_branch" 2>/dev/null)

        # Union + dedup + filtrage des branches protegees
        local -A stale_map  # branch -> reason
        for br in "${gone_branches[@]}"; do
            # Verifier protection
            [[ "$br" == "$current" ]] && continue
            local is_protected=false
            for p in "${protected[@]}"; do
                [[ "$br" == "$p" ]] && { is_protected=true; break; }
            done
            [[ "$is_protected" == "true" ]] && continue
            stale_map[$br]="gone"
        done
        for br in "${merged_branches[@]}"; do
            [[ "$br" == "$current" ]] && continue
            local is_protected=false
            for p in "${protected[@]}"; do
                [[ "$br" == "$p" ]] && { is_protected=true; break; }
            done
            [[ "$is_protected" == "true" ]] && continue
            # Ne pas ecraser si deja marque gone
            [[ -z "${stale_map[$br]}" ]] && stale_map[$br]="merged"
        done

        local stale_count=${#stale_map}
        if [[ $stale_count -eq 0 ]]; then
            printf "  %-24s " "$name"
            _ui_ok "" "aucune branche stale"
            echo ""
            continue
        fi

        ((repos_affected++))
        ((total_stale += stale_count))

        printf "  ${_ui_yellow}${_ui_circle}${_ui_nc} %-22s ${_ui_yellow}%d branche(s) stale${_ui_nc}\n" "$name" "$stale_count"

        # Afficher les branches
        for br in ${(k)stale_map}; do
            local reason="${stale_map[$br]}"
            if [[ "$do_apply" == "true" ]]; then
                # Supprimer la branche
                local delete_flag="-d"
                [[ "$reason" == "gone" ]] && delete_flag="-D"

                local output
                output=$(git -C "$repo" branch "$delete_flag" "$br" 2>&1)
                local rc=$?

                if [[ $rc -eq 0 ]]; then
                    printf "    ${_ui_green}${_ui_check}${_ui_nc} %-8s %s\n" "$reason" "$br"
                    ((total_deleted++))
                else
                    printf "    ${_ui_red}${_ui_cross}${_ui_nc} %-8s %s ${_ui_dim}(%s)${_ui_nc}\n" "$reason" "$br" "$output"
                    ((total_failed++))
                fi
            else
                printf "    ${_ui_dim}%-10s${_ui_nc} %s\n" "$reason" "$br"
            fi
        done
    done

    echo ""
    _ui_separator 54

    if [[ "$do_apply" == "true" ]]; then
        printf "${_ui_green}%d${_ui_nc} supprimee(s)  ${_ui_red}%d${_ui_nc} echouee(s)  sur ${_ui_cyan}%d${_ui_nc} repo(s)\n" \
            "$total_deleted" "$total_failed" "$repos_affected"
    else
        if [[ $total_stale -gt 0 ]]; then
            printf "${_ui_yellow}%d${_ui_nc} branche(s) stale sur ${_ui_cyan}%d${_ui_nc} repo(s)  ${_ui_dim}(--apply pour supprimer)${_ui_nc}\n" \
                "$total_stale" "$repos_affected"
        else
            _ui_msg_ok "Aucune branche stale trouvee"
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
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "checkout <branche>" "Switch tous les repos sur une branche"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "stash [push|pop|list]" "Stash/restore les repos dirty"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "branch [list|delete]" "Gestion de branches multi-repos"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "log" "Historique condense multi-repos"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "merge <branche>" "Merge une branche dans tous les repos"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "prune" "Nettoie les branches stale (gone/merged)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "clean" "Supprime les fichiers untracked"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "reset" "Reset sur upstream"

    echo ""
    printf "${_ui_bold}%-28s${_ui_nc} %s\n" "Option" "Description"
    _ui_separator 50

    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-m \"message\"" "Message de commit/stash"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-d <dossier>" "Dossier a scanner (defaut: .)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-r" "Recherche recursive"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-b <branche> [base]" "Cree la branche (pour checkout)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "-n, --dry-run" "Simule l'action sans l'executer"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "--apply" "Execute la suppression (prune/branch/clean/reset)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "--abort" "Abort les merges en cours (pour merge)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "--since <date>" "Filtrer par date (pour log)"
    printf "${_ui_cyan}%-28s${_ui_nc} %s\n" "--author <name>" "Filtrer par auteur (pour log)"
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
    echo ""
    echo -e "  ${_ui_dim}# Dry-run: voir ce que pull ferait${_ui_nc}"
    echo -e "  zsh-env-git-bulk pull --dry-run -d ~/work"
    echo ""
    echo -e "  ${_ui_dim}# Lister les branches stale (dry-run par defaut)${_ui_nc}"
    echo -e "  zsh-env-git-bulk prune -d ~/projects"
    echo ""
    echo -e "  ${_ui_dim}# Supprimer les branches stale${_ui_nc}"
    echo -e "  zsh-env-git-bulk prune --apply -d ~/projects"
    echo ""
    echo -e "  ${_ui_dim}# Switcher tous les repos sur develop${_ui_nc}"
    echo -e "  zsh-env-git-bulk checkout develop"
    echo ""
    echo -e "  ${_ui_dim}# Creer une branche feature sur tous les repos${_ui_nc}"
    echo -e "  zsh-env-git-bulk checkout -b feature/new develop"
    echo ""
    echo -e "  ${_ui_dim}# Stash avant un checkout${_ui_nc}"
    echo -e "  zsh-env-git-bulk stash && zsh-env-git-bulk checkout main"
    echo ""
    echo -e "  ${_ui_dim}# Historique recent filtre par auteur${_ui_nc}"
    echo -e "  zsh-env-git-bulk log --since '1 week ago' --author dr0drigues"
    echo ""
    echo -e "  ${_ui_dim}# Merge develop avec detection de conflits${_ui_nc}"
    echo -e "  zsh-env-git-bulk merge develop --dry-run"
}

# Alias courts
alias gbulk='zsh-env-git-bulk'
alias gbs='zsh-env-git-bulk status'
alias gbp='zsh-env-git-bulk pull'
alias gbprune='zsh-env-git-bulk prune'
alias gbco='zsh-env-git-bulk checkout'
alias gbst='zsh-env-git-bulk stash'
alias gbbr='zsh-env-git-bulk branch'
alias gbl='zsh-env-git-bulk log'
alias gbm='zsh-env-git-bulk merge'
