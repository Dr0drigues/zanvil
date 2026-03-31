# ==============================================================================
# Core Completions - Completions pour les commandes zsh-env-*
# ==============================================================================

if ! (( $+functions[compdef] )); then return 0; fi

_zsh_env_theme() {
    local themes_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}/themes"
    local themes=()

    if [[ -d "$themes_dir" ]]; then
        themes=(${(f)"$(ls "$themes_dir" 2>/dev/null | sed 's/\.toml$//')"})
    fi

    _arguments \
        '1:theme:(list ${themes[@]})'
}
compdef _zsh_env_theme zsh-env-theme

_zsh_env_completion_add() {
    _arguments \
        '1:name:' \
        '2:command:'
}
compdef _zsh_env_completion_add zsh-env-completion-add

_zsh_env_completion_remove() {
    local completions_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}/completions.d"
    local completions=()

    if [[ -d "$completions_dir" ]]; then
        completions=(${(f)"$(ls "$completions_dir" 2>/dev/null | sed 's/^_//')"})
    fi

    _arguments \
        '1:completion:(${completions[@]})'
}
compdef _zsh_env_completion_remove zsh-env-completion-remove

_zsh_env_modules() {
    local modules=(GITLAB DOCKER MISE NUSHELL KUBE)

    _arguments \
        '1:action:(list enable disable)' \
        '2:module:(${modules[@]})'
}
compdef _zsh_env_modules zsh-env-modules

_zsh_env_gitlab_browse() {
    _arguments \
        '(-m --mrs -p --pipelines -i --issues)'{-m,--mrs}'[Merge Requests]' \
        '(-m --mrs -p --pipelines -i --issues)'{-p,--pipelines}'[Pipelines]' \
        '(-m --mrs -p --pipelines -i --issues)'{-i,--issues}'[Issues]'
}
compdef _zsh_env_gitlab_browse zsh-env-gitlab-browse
