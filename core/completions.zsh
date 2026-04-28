# ==============================================================================
# Core Completions - Completions pour les commandes zsh-env-*
# ==============================================================================

if ! (( $+functions[compdef] )); then return 0; fi

_zsh_env_theme() {
    local themes_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}/themes"
    local -a themes=()
    # Directory themes
    for d in "$themes_dir"/*/prompt.toml(N); do
        themes+=($(basename $(dirname "$d")))
    done
    # Flat themes (skip duplicates)
    for f in "$themes_dir"/*.toml(N); do
        local name=$(basename "$f" .toml)
        (( ${themes[(Ie)$name]} )) || themes+=($name)
    done

    local -a actions=(
        'list:Lister les themes disponibles'
        'current:Afficher le theme actuel'
        'apply:Appliquer un theme'
        'preview:Apercu sans appliquer'
        'auto:Auto dark/light'
    )

    _arguments \
        '1:action:->actions' \
        '2:theme:(${themes[@]})'

    case "$state" in
        actions)
            _describe 'action' actions
            # Also complete theme names directly
            compadd -a themes
            ;;
    esac
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

_zsh_env_switch() {
    local profiles_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}/profiles"
    local -a profiles=()
    for f in "$profiles_dir"/*.zsh(N); do
        profiles+=($(basename "$f" .zsh))
    done
    _arguments '1:profile:(list ${profiles[@]})'
}
compdef _zsh_env_switch zsh-env-switch

_zsh_env_sync() {
    local -a actions=(
        'export:Exporter la config'
        'import:Importer une config'
        'diff:Comparer avec la config locale'
    )

    _arguments \
        '1:action:->actions' \
        '2:file:_files -g "*.json"'

    case "$state" in
        actions) _describe 'action' actions ;;
    esac
}
compdef _zsh_env_sync zsh-env-sync

_zsh_env_bench() {
    _arguments \
        '--quick[Temps total uniquement]' \
        '--runs[Benchmark multi-runs]:runs:' \
        '-q[Temps total uniquement]' \
        '-r[Benchmark multi-runs]:runs:'
}
compdef _zsh_env_bench zsh-env-bench

_zsh_env_secrets_scan() {
    _arguments \
        '--current[Scan le working tree]' \
        '--history[Scan historique git]' \
        '--bulk[Mode multi-repos]' \
        '--include[Filtrer par glob]:glob:' \
        '--exclude[Exclure par glob]:glob:' \
        '-d[Dossier]:directory:_directories'
}
compdef _zsh_env_secrets_scan zsh-env-secrets-scan

_zsh_env_docker_clean() {
    _arguments \
        '--apply[Executer le nettoyage]' \
        '--all[Inclure images non-dangling et build cache]'
}
compdef _zsh_env_docker_clean zsh-env-docker-clean dclean
