# Completions lazygit — générées dynamiquement par lazygit
(( $+functions[compdef] )) || return 0

if command -v lazygit &>/dev/null; then
    eval "$(lazygit completion zsh 2>/dev/null)"
fi
