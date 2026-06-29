# ==============================================================================
# Git Completions - Completions pour les commandes git bulk et hooks_*
# ==============================================================================

(( $+functions[compdef] )) || return 0

# Completion pour zanvil-git-bulk
_git_bulk_cmd() {
    local -a actions
    actions=(
        'status:Statut de tous les repos'
        'pull:Pull tous les repos'
        'push:Push tous les repos'
        'fetch:Fetch tous les repos'
        'commit:Commit les repos modifies'
        'checkout:Switch tous les repos sur une branche'
        'stash:Stash/restore les repos dirty'
        'branch:Gestion de branches multi-repos'
        'log:Historique condense multi-repos'
        'merge:Merge une branche dans tous les repos'
        'prune:Nettoie les branches stale (gone/merged)'
        'clean:Supprime les fichiers untracked'
        'reset:Reset sur upstream'
    )

    _arguments \
        '1:action:->actions' \
        '-d[Dossier a scanner]:directory:_directories' \
        '-m[Message de commit]:message:' \
        '-r[Recherche recursive]' \
        '-b[Cree la branche (checkout)]' \
        '-n[Dry-run]' \
        '--dry-run[Dry-run]' \
        '--apply[Execute (prune/branch/clean/reset)]' \
        '--abort[Abort les merges en cours]' \
        '--since[Filtrer par date (log)]:date:' \
        '--author[Filtrer par auteur (log)]:author:' \
        '-h[Aide]'

    case "$state" in
        actions)
            _describe 'action' actions
            ;;
    esac
}
compdef _git_bulk_cmd zanvil-git-bulk gbulk gbco gbst gbbr gbl gbm gbprune

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
