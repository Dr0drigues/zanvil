# Completions atuin — générées dynamiquement
(( $+functions[compdef] )) || return 0

if command -v atuin &>/dev/null; then
    eval "$(atuin gen-completions --shell zsh 2>/dev/null)"
fi
