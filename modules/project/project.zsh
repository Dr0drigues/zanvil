# ==============================================================================
# Module project : ouvre une MR GitLab dans un worktree sous $WORK_DIR
# ==============================================================================

# _project_parse_mr <url> : reply=(hote chemin-projet iid), code 1 si pas un lien de MR
_project_parse_mr() {
    reply=()
    [[ "$1" =~ '^https?://([^/]+)/(.+)/-/merge_requests/([0-9]+)' ]] || return 1
    reply=("${match[1]}" "${match[2]}" "${match[3]}")
}

_project_repo_dir() { print -r -- "$WORK_DIR/$1"; }

# _project_worktree_dir <chemin-projet> <branche>
_project_worktree_dir() {
    local parent="${1%/*}" repo="${1##*/}"
    print -r -- "$WORK_DIR/$parent/.worktrees/$repo/${2//\//-}"
}

_project_notify() {
    command -v osascript &>/dev/null \
        && osascript -e "display notification \"${1//\"/\\\"}\" with title \"zanvil project\"" &>/dev/null
    [[ -t 1 ]] && _ui_msg_warn "$1"
    return 0
}

_project_help() {
    _ui_header "project"
    print "  project open <lien-de-MR>   ouvre la MR dans un worktree sous \$WORK_DIR"
    print "  project clean               supprime les worktrees des MR terminees"
    print "  project help                cette aide"
}

project() {
    local sub="${1:-help}"
    (( $# )) && shift
    case "$sub" in
        open|clean)
            if (( $+functions[_project_$sub] )); then
                "_project_$sub" "$@"
            else
                _ui_msg_fail "project $sub : pas encore disponible"
                return 1
            fi ;;
        help|-h|--help) _project_help ;;
        *) _ui_msg_fail "sous-commande inconnue : $sub"; _project_help; return 1 ;;
    esac
}
