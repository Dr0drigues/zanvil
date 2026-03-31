# ==============================================================================
# Git Completions - Completions pour les commandes hooks_*
# ==============================================================================

(( $+functions[compdef] )) || return 0

_hooks_cmd() {
    local hooks_dir
    hooks_dir=$(git rev-parse --git-dir 2>/dev/null)/hooks

    local hooks=()
    if [[ -d "$hooks_dir" ]]; then
        hooks=(${(f)"$(ls "$hooks_dir" 2>/dev/null | grep -v '\.sample$')"})
    fi

    _arguments \
        '1:hook:(${hooks[@]})'
}
compdef _hooks_cmd hooks_remove
compdef _hooks_cmd hooks_disable
compdef _hooks_cmd hooks_enable
compdef _hooks_cmd hooks_edit
