# =======================================================
# ZSH CONFIG & SOURCE
# =======================================================

# Raccourci pour sourcer un fichier (ex: s .env)
# Pas besoin de $1, l'alias fait juste un remplacement de texte
alias s='source'

# Rechargement rapide de la configuration
# Avec un petit feedback visuel pour confirmer que ça a marché
alias ss='source $HOME/.zshrc && echo "Zsh config reloaded"'

# =======================================================
# NAVIGATION & LISTING
# =======================================================

# 1. Protection du remplacement de 'ls' par 'eza'
# On utilise 'command -v' qui est POSIX compliant et plus rapide que 'which'
if command -v eza &> /dev/null; then
    alias ls='eza --color=auto'
    alias l="ls -lah"
    alias ll='ls -la'
    alias l.='ls -d .* --color=auto'
else
    # Fallback si eza n'est pas là
    alias l='ls -lah'
    alias ll='ls -la'
fi

# 2. Protection des alias Git
# Vérifions que git est installé (rare qu'il ne le soit pas, mais sait-on jamais)
if command -v git &> /dev/null; then
    alias gst='git status'
    alias gl='git fetch --all; git pull'
    alias ga='git add'
    alias gp='git push'
    alias gc='git commit -v' # -v est une bonne pratique pour relire son code avant de commit
    alias gld='git log --oneline --decorate --graph --all'
    alias git-clean-branches="git branch --merged | grep -v '\*' | grep -v 'master' | grep -v 'main' | grep -v 'dev' | xargs -n 1 git branch -d"
fi

# =======================================================
# NUSHELL INTEGRATION
# =======================================================
if command -v nu &> /dev/null; then
    # Lancer nushell rapidement
    alias nush='nu'
    
    # Exécuter une commande Nu one-liner depuis Zsh
    # Ex: nuc "ls | where size > 10kb | sort-by size"
    alias nuc='nu -c'
    
    # Remplacer les outils classiques pour l'exploration de données ?
    # alias tojson='nu -c "from json"' 
fi

# =======================================================
# SYSTEM & UTILS
# =======================================================
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

alias ..='cd ..'
alias c='clear'
alias h='history'

# Protection 'sudo' (alias please)
alias please='sudo $(fc -ln -1)'

# Gestion intelligente de l'extraction (Tar)
# Utilise votre fonction extract si définie, sinon fallback
if type extract &> /dev/null; then
    alias x='extract'
fi

if command -v bat &> /dev/null; then
    alias cat='bat'
fi

# Sécurité suppression
if command -v trash &> /dev/null; then
    alias rm='trash'
    alias rmi='/bin/rm -i'
else
    # Si pas de trash, on force la confirmation pour éviter les accidents
    alias rm='rm -i'
fi

# =======================================================
# MISCELLANEOUS
# =======================================================
if command -v npm &> /dev/null; then
    alias npmi='npm install'
    alias npmu='npm update'
    alias npml='npm list --depth=0'
    # Si le node_modules existe, on le supprime. Dans tous les cas, on vide le cache de npm et on réinstalle
    alias nci='if [ -d node_modules ]; then rmi -rf node_modules; fi && npm cache clean --force && npm install' 
fi