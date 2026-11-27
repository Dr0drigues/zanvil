# ==============================================================================
# Core Completions - Completions pour les commandes zanvil-*
# ==============================================================================

if ! (( $+functions[compdef] )); then return 0; fi

_zanvil_theme() {
    local themes_dir="${ZANVIL_DIR:-$HOME/.zanvil}/config/themes"
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
compdef _zanvil_theme zanvil-theme

_zanvil_completion_add() {
    _arguments \
        '1:name:' \
        '2:command:'
}
compdef _zanvil_completion_add zanvil-completion-add

_zanvil_completion_remove() {
    # Meme lecture que zanvil-completion-remove : les entrees "nom:commande" de completions.zsh.
    local -a completions
    completions=(${(f)"$(sed -n 's/^[[:space:]]*"\([^:"]*\):.*/\1/p' "${ZANVIL_DIR:-$HOME/.zanvil}/completions.zsh" 2>/dev/null)"})

    _arguments \
        '1:completion:(${completions[@]})'
}
compdef _zanvil_completion_remove zanvil-completion-remove

_zanvil_modules() {
    local modules=(GITLAB DOCKER MISE NUSHELL KUBE)

    _arguments \
        '1:action:(list enable disable)' \
        '2:module:(${modules[@]})'
}
compdef _zanvil_modules zanvil-modules

_zanvil_dotfiles() {
    _arguments \
        '1:action:(status pull install cleanup link adopt apply migrate)' \
        '2:fichier:_files' \
        '3:couche:(common pro perso)'
}
compdef _zanvil_dotfiles zanvil-dotfiles

_zanvil_gitlab_browse() {
    _arguments \
        '(-m --mrs -p --pipelines -i --issues)'{-m,--mrs}'[Merge Requests]' \
        '(-m --mrs -p --pipelines -i --issues)'{-p,--pipelines}'[Pipelines]' \
        '(-m --mrs -p --pipelines -i --issues)'{-i,--issues}'[Issues]'
}
compdef _zanvil_gitlab_browse zanvil-gitlab-browse

_zanvil_switch() {
    local profiles_dir="${ZANVIL_DIR:-$HOME/.zanvil}/profiles"
    local -a profiles=()
    for f in "$profiles_dir"/*.zsh(N); do
        profiles+=($(basename "$f" .zsh))
    done
    _arguments '1:profile:(list ${profiles[@]})'
}
compdef _zanvil_switch zanvil-switch

_zanvil_sync() {
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
compdef _zanvil_sync zanvil-sync

_zanvil_bench() {
    _arguments \
        '--quick[Temps total uniquement]' \
        '--runs[Benchmark multi-runs]:runs:' \
        '-q[Temps total uniquement]' \
        '-r[Benchmark multi-runs]:runs:'
}
compdef _zanvil_bench zanvil-bench

_zanvil_secrets_scan() {
    _arguments \
        '--current[Scan le working tree]' \
        '--history[Scan historique git]' \
        '--bulk[Mode multi-repos]' \
        '--include[Filtrer par glob]:glob:' \
        '--exclude[Exclure par glob]:glob:' \
        '-d[Dossier]:directory:_directories'
}
compdef _zanvil_secrets_scan zanvil-secrets-scan

_zanvil_docker_clean() {
    _arguments \
        '--apply[Executer le nettoyage]' \
        '--all[Inclure images non-dangling et build cache]'
}
compdef _zanvil_docker_clean zanvil-docker-clean dclean

_zanvil_ghostty() {
    local -a themes=(${${(f)"$(command ls "${ZANVIL_DIR:-$HOME/.zanvil}/config/ghostty/themes" 2>/dev/null)"}})
    _alternative \
        'actions:action:((list\:"Lister les themes" sync\:"Suivre le theme zanvil" auto\:"Clair/sombre selon le systeme"))' \
        "themes:theme:(${themes[*]})"
}
compdef _zanvil_ghostty zanvil-ghostty

_zanvil_restore() {
    local -a backups=(${(f)"$(command ls "${ZANVIL_DIR:-$HOME/.zanvil}/backups" 2>/dev/null)"})
    _arguments "1:backup:(${backups[*]})"
}
compdef _zanvil_restore zanvil-restore

_zanvil_migrate() {
    _arguments '1:action:((run\:"Appliquer les migrations" --list\:"Lister" --status\:"Etat" --help\:"Aide"))'
}
compdef _zanvil_migrate zanvil-migrate

_zanvil_trust() { _arguments '1:fichier .zanvil.local:_files' }
compdef _zanvil_trust zanvil-trust

# Commandes sans argument : rien a proposer (et pas des noms de fichiers).
compdef _nothing zanvil-backup zanvil-config-reset zanvil-doctor-conflicts zanvil-audit zanvil-audit-fix zanvil-update
