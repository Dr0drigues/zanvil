#!/usr/bin/env zsh
# Completions pour zproject / zpr

_zproject_projects() {
    local -a projects
    local pdir="$HOME/.zsh-env/projects"
    [[ -d "$pdir" ]] || return 0
    projects=(${(f)"$(command ls -1 "$pdir" 2>/dev/null | grep -v '^_' | grep -v '^stacks$' | grep -v '^local$' | grep -v '\.')"})
    _describe 'project' projects
}

_zproject_envs_for() {
    local project="${1:-${words[2]}}"
    local edir="$HOME/.zsh-env/projects/${project}/envs"
    [[ -d "$edir" ]] || return 0
    local -a envs
    envs=(${(f)"$(command ls -1 "$edir" 2>/dev/null | sed 's/\.toml$//')"})
    _describe 'env' envs
}

_zproject_stacks() {
    local -a stacks
    local sdir="$HOME/.zsh-env/projects/stacks"
    [[ -d "$sdir" ]] || return 0
    stacks=(${(f)"$(command ls -1 "$sdir" 2>/dev/null | sed 's/\.toml$//')"})
    _describe 'stack' stacks
}

_zproject_commands_for() {
    local project="${1:-${ZPROJECT_NAME:-}}"
    [[ -z "$project" ]] && return 0
    local manifest="$HOME/.zsh-env/projects/${project}/project.toml"
    [[ -f "$manifest" ]] || return 0
    local -a cmds
    cmds=(${(f)"$(grep '^\[commands\]' -A 999 "$manifest" 2>/dev/null | grep '^[a-z]' | cut -d= -f1 | tr -d ' ')"})
    _describe 'command' cmds
}

_zproject() {
    local -a subcmds
    subcmds=(
        'list:lister tous les projets'
        'config:afficher la config resolue'
        'doctor:valider le manifeste'
        'diff:comparer deux projets ou envs'
        'scan:auto-fill depuis un path'
        'envs:lister les envs disponibles'
        'edit:ouvrir le manifeste dans $EDITOR'
        'status:afficher le projet actif'
        'run:executer une commande du projet'
        'exit:desactiver le projet courant'
    )

    case $CURRENT in
        2)
            _describe 'zproject command' subcmds
            _zproject_projects
            ;;
        3)
            case "${words[2]}" in
                config|doctor|envs|edit) _zproject_projects ;;
                diff)                   _zproject_projects ;;
                stack)                  _zproject_stacks ;;
                run)                    _zproject_commands_for ;;
                scan)                   _files -/ ;;
                *)
                    # Activation : second arg = env pour le projet donne
                    _zproject_envs_for "${words[2]}"
                    ;;
            esac
            ;;
        4)
            case "${words[2]}" in
                stack) _zproject_envs_for ;;
                diff)  _zproject_projects ;;
            esac
            ;;
    esac
}

compdef _zproject zproject
compdef _zproject zpr
