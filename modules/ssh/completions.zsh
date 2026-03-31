# ==============================================================================
# SSH Completions - Completions pour les commandes ssh_*
# ==============================================================================

(( $+functions[compdef] )) || return 0

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
