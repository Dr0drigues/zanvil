# Completions lazygit — générées dynamiquement par lazygit
(( $+functions[compdef] )) || return 0

if command -v lazygit &>/dev/null; then
    _zanvil_cached lazygit-completions lazygit completion zsh && source "$REPLY"
fi
