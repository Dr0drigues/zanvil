# ==============================================================================
# Project Completions - Completions pour les commandes proj*
# ==============================================================================

(( $+functions[compdef] )) || return 0

_proj() {
    local projects=()
    local registry="$HOME/.config/zsh_env/projects.yml"

    if [[ -f "$registry" ]]; then
        projects=(${(f)"$(grep -E '^[a-zA-Z0-9_-]+:' "$registry" | sed 's/:.*//')"})
    fi

    _arguments \
        '1:project or option:(--add --list --remove --init --scan --auto --help ${projects[@]})'
}
compdef _proj proj

_proj_remove() {
    local projects=()
    local registry="$HOME/.config/zsh_env/projects.yml"

    if [[ -f "$registry" ]]; then
        projects=(${(f)"$(grep -E '^[a-zA-Z0-9_-]+:' "$registry" | sed 's/:.*//')"})
    fi

    _arguments \
        '1:project:(${projects[@]})'
}
compdef _proj_remove proj_remove
