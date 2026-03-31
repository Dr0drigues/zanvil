# ==============================================================================
# Docker Completions - Completions pour les commandes docker utils
# ==============================================================================

(( $+functions[compdef] )) || return 0

_dex() {
    local containers=()
    if command -v docker &> /dev/null; then
        containers=(${(f)"$(docker ps --format '{{.Names}}' 2>/dev/null)"})
    fi
    _arguments \
        '1:container:(${containers[@]})' \
        '2:shell:(bash sh zsh ash)'
}
compdef _dex dex
