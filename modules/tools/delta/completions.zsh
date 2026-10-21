# Completions delta — générées dynamiquement
(( $+functions[compdef] )) || return 0

if command -v delta &>/dev/null; then
    _zanvil_cached delta-completions delta --generate-completion zsh && source "$REPLY"
fi
