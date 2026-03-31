# ==============================================================================
# Tmux Completions - Completions pour les commandes tm*
# ==============================================================================

(( $+functions[compdef] )) || return 0

_tm() {
    local sessions=()
    if command -v tmux &> /dev/null; then
        sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
    fi
    _arguments \
        '1:session:(${sessions[@]})'
}
compdef _tm tm
compdef _tm tm-kill

_tm_project() {
    _arguments \
        '1:directory:_files -/' \
        '2:session name:'
}
compdef _tm_project tm-project
