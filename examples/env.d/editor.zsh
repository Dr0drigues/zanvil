# Editeur par defaut
if command -v code &>/dev/null; then
    export EDITOR="code --wait"
    export VISUAL="code --wait"
elif command -v nvim &>/dev/null; then
    export EDITOR="nvim"
    export VISUAL="nvim"
else
    export EDITOR="vim"
    export VISUAL="vim"
fi
