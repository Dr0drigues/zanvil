# ==============================================================================
# GitLab Completions - Completions pour gclone et les alias gc-*
# ==============================================================================

(( $+functions[compdef] )) || return 0

# gclone : cles GITLAB_PROJECTS en premier argument, options du script ensuite
_gclone() {
    local -a keys opts
    local key id

    if (( CURRENT == 2 )); then
        for key id in "${(@kv)GITLAB_PROJECTS}"; do
            keys+=("$key:groupe $id")
        done
        _describe 'groupe GitLab' keys
        return
    fi

    opts=(
        'ssh:clone via SSH'
        'https:clone via HTTPS (defaut)'
        'full:clone complet (defaut)'
        'shallow:clone --depth 1'
        '--parallel:N projets en parallele'
        '--dry-run:liste sans cloner'
        '--help:affiche l'"'"'aide'
    )
    _describe 'option' opts
}
compdef _gclone gclone

_gc_gitlab_alias() {
    local -a gc_cmds
    for alias_name desc in "${(@kv)GC_ALIAS_DESCRIPTIONS}"; do
        gc_cmds+=("$alias_name:$desc")
    done
    _describe 'gc alias' gc_cmds
}

# Enregistre la complétion pour chaque alias gc-* existant
if (( ${#GC_ALIAS_DESCRIPTIONS} )); then
    for _gc_name in "${(@k)GC_ALIAS_DESCRIPTIONS}"; do
        compdef _gc_gitlab_alias "$_gc_name"
    done
    unset _gc_name
fi

_zanvil_pipeline_bulk() {
    _arguments \
        '1:action:((status\:"Etat des pipelines" trigger\:"Lancer un pipeline par depot" watch\:"Suivre les pipelines"))' \
        '-b[Branche]:branche:' \
        '-d[Dossier a scanner]:dossier:_directories' \
        '-f[Filtre sur le nom des depots]:filtre:' \
        '-s[Depots a ignorer (motif)]:motif:' \
        '-w[Suivre apres trigger]' \
        '(-h --help)'{-h,--help}'[Aide]' \
        '*:dossier:_directories'
}
compdef _zanvil_pipeline_bulk zanvil-pipeline-bulk
