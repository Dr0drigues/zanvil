(( $+functions[compdef] )) || return 0

if command -v posting &>/dev/null; then
    source <(posting --completion-script-zsh 2>/dev/null) 2>/dev/null || true
fi
