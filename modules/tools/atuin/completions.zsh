# Completions atuin — générées dynamiquement
(( $+functions[compdef] )) || return 0

if command -v atuin &>/dev/null; then
    _zanvil_cached atuin-completions atuin gen-completions --shell zsh && source "$REPLY"
fi
