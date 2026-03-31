# ==============================================================================
# GitLab Completions - Completions pour les alias gc-*
# ==============================================================================

(( $+functions[compdef] )) || return 0

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
