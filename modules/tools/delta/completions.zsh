# Completions delta — générées dynamiquement
(( $+functions[compdef] )) || return 0

if command -v delta &>/dev/null; then
    eval "$(delta --generate-completion zsh 2>/dev/null)"
fi
