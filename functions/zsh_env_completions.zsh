# ==============================================================================
# ZSH Env Completions - Completions pour les commandes zsh_env
# ==============================================================================
# Auto-completion pour toutes les fonctions du projet
# ==============================================================================

# Ne charger que si compdef est disponible (compinit doit etre execute avant)
if ! (( $+functions[compdef] )); then
    return 0
fi

# --- Completions zsh-env-* ---

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

# --- Completions kube_* ---

_kube_add() {
    _arguments \
        '1:config file:_files -g "*.yml *.yaml"'
}
compdef _kube_add kube_add

_kube_azure() {
    local clusters=(blg-dev blg-qlf blg-pprd blg-prd edt-dev edt-qlf edt-pprd edt-prd)
    _arguments \
        '1:cluster:(${clusters[@]})'
}
compdef _kube_azure kube_azure

_kube_encrypt() {
    _arguments \
        '1:config file:_files -g "*.yml *.yaml"'
}
compdef _kube_encrypt kube_encrypt

# --- Completions ssh_* ---

_ssh_select() {
    local hosts=()
    if [[ -f "$HOME/.ssh/config" ]]; then
        hosts=(${(f)"$(grep -i '^Host ' "$HOME/.ssh/config" | awk '{print $2}' | grep -v '[*?]')"})
    fi
    _arguments \
        '1:host pattern:(${hosts[@]})'
}
compdef _ssh_select ssh_select

_ssh_info() {
    local hosts=()
    if [[ -f "$HOME/.ssh/config" ]]; then
        hosts=(${(f)"$(grep -i '^Host ' "$HOME/.ssh/config" | awk '{print $2}' | grep -v '[*?]')"})
    fi
    _arguments \
        '1:host:(${hosts[@]})'
}
compdef _ssh_info ssh_info
compdef _ssh_info ssh_remove
compdef _ssh_info ssh_test
compdef _ssh_info ssh_copy_key

# --- Completions tm* (tmux) ---

_tm() {
    local sessions=()
    if command -v tmux &> /dev/null; then
        sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
    fi
    _arguments \
        '1:session:(${sessions[@]})'
}
compdef _tm tm
compdef _tm tm-kill

_tm_project() {
    _arguments \
        '1:directory:_files -/' \
        '2:session name:'
}
compdef _tm_project tm-project

# --- Completions proj* ---

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

# --- Completions hooks_* ---

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

# --- Completions docker utils ---

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

# --- Completions extract ---

_extract() {
    _arguments \
        '1:archive:_files -g "*.tar.gz *.tgz *.tar.bz2 *.tbz2 *.tar.xz *.txz *.zip *.rar *.7z *.gz *.bz2 *.xz"'
}
compdef _extract extract

# --- Completions misc ---

_mkcd() {
    _arguments \
        '1:directory:_files -/'
}
compdef _mkcd mkcd

_bak() {
    _arguments \
        '1:file:_files'
}
compdef _bak bak

_cx() {
    _arguments \
        '1:file:_files'
}
compdef _cx cx

_trash() {
    _arguments \
        '*:files:_files'
}
compdef _trash trash

# --- Completions ai-context ---

_ai_context() {
    local commands=(
        'detect:Affiche les informations detectees du projet'
        'init:Cree un fichier .ai-context.yml'
        'generate:Genere les fichiers de contexte'
        'templates:Liste les templates disponibles'
        'help:Affiche aide'
    )

    _arguments \
        '1:command:->command' \
        '*:args:->args'

    case $state in
        command)
            _describe 'command' commands
            ;;
        args)
            case $words[2] in
                generate|gen|g)
                    _arguments \
                        '-f[Force overwrite]' \
                        '--force[Force overwrite]' \
                        '1:directory:_files -/'
                    ;;
                detect|d|init|i)
                    _arguments '1:directory:_files -/'
                    ;;
            esac
            ;;
    esac
}
compdef _ai_context ai-context

# --- Completions ai-tokens ---

_ai_tokens() {
    local commands=(
        'estimate:Estime les tokens (fichier, dossier ou stdin)'
        'analyze:Analyse detaillee avec suggestions'
        'compress:Compresse le contenu (supprime commentaires)'
        'select:Selectionne les fichiers pertinents'
        'export:Exporte le contexte optimise'
        'help:Affiche aide'
    )

    _arguments \
        '1:command:->command' \
        '*:args:->args'

    case $state in
        command)
            _describe 'command' commands
            ;;
        args)
            case $words[2] in
                estimate|est|e|analyze|analyse|a|select|sel|s)
                    _arguments '1:target:_files'
                    ;;
                compress|comp|c)
                    _arguments \
                        '1:file:_files' \
                        '2:language:(js ts py python go rust java c cpp sh bash zsh html)'
                    ;;
                export|exp|x)
                    _arguments \
                        '1:directory:_files -/' \
                        '--compress[Compresse le contenu]' \
                        '-c[Compresse le contenu]' \
                        '--max-tokens=[Limite de tokens]:tokens:'
                    ;;
            esac
            ;;
    esac
}
compdef _ai_tokens ai-tokens
compdef _ai_tokens ait
