(( $+functions[compdef] )) || return 0

if command -v posting &>/dev/null; then
    # posting s appuie sur click : les completions passent par une variable, pas une option
    _POSTING_COMPLETE=zsh_source _zanvil_cached posting-completions posting && source "$REPLY"
fi
