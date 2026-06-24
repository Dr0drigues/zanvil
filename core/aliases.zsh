# =======================================================
# ZSH CONFIG & SOURCE
# =======================================================

# Raccourci pour sourcer un fichier (ex: s .env)
# Pas besoin de $1, l'alias fait juste un remplacement de texte
alias s='source'

# Rechargement rapide de la configuration
# Avec un petit feedback visuel pour confirmer que ça a marché
alias ss='source $HOME/.zshrc && _zsh_env_banner'

# =======================================================
# NAVIGATION & LISTING
# =======================================================

# Copier le chemin courant dans le presse-papiers
cpwd() {
    local _path="$PWD"
    if command -v pbcopy &>/dev/null; then
        printf '%s' "$_path" | pbcopy
    elif command -v xclip &>/dev/null; then
        printf '%s' "$_path" | xclip -selection clipboard
    elif command -v xsel &>/dev/null; then
        printf '%s' "$_path" | xsel --clipboard --input
    else
        echo "$_path"
        return 1
    fi
    echo "$_path"
}

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
    alias gl='git pull'
    alias ga='git add'
    alias gp='git push'
    alias gc='git commit -v' # -v est une bonne pratique pour relire son code avant de commit
    alias gld='git log --oneline --decorate --graph --all'
    # Nettoyage des branches mergees (avec confirmation)
    function git-clean-branches {
        local branches
        branches=$(git branch --merged | grep -vE '(\*|master|main|dev|develop|release/)')
        if [[ -z "$branches" ]]; then
            echo "Aucune branche mergee a supprimer."
            return 0
        fi
        echo "Branches mergees qui seront supprimees :"
        echo "$branches" | sed 's/^/  /'
        echo ""
        local response
        read -q "response?Supprimer ces branches ? [y/N] "
        echo ""
        if [[ "$response" == "y" ]]; then
            echo "$branches" | xargs -n 1 git branch -d
        else
            echo "Annule."
        fi
    }
fi

# =======================================================
# NUSHELL INTEGRATION
# =======================================================
if [[ "$ZSH_ENV_MODULE_NUSHELL" == "true" ]] && command -v nu &> /dev/null; then
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
# Note: zoxide est initialise a la fin de rc.zsh pour optimisation

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

# =======================================================
# MODERN CLI REPLACEMENTS
# =======================================================
# Remplacements drop-in en usage interactif. Chaque alias est garde par
# 'command -v' : si l'outil est absent, l'alias ne s'active pas.
# Echappatoire pour les usages avances : 'command du', '\ps', etc.
# grep/find/sed NE sont PAS aliases : rg et fd s'utilisent sous leurs vrais noms.

command -v dust  &>/dev/null && alias du='dust'
command -v duf   &>/dev/null && alias df='duf'
command -v btop  &>/dev/null && alias top='btop'
command -v gping &>/dev/null && alias ping='gping'
# Attention: 'procs aux' n'est pas equivalent a 'ps aux'. Usage interactif simple.
command -v procs &>/dev/null && alias ps='procs'

# Sécurité suppression
# Nettoyage préalable pour éviter les conflits au reload
unalias rm 2>/dev/null
unfunction rm 2>/dev/null

if command -v trash &> /dev/null; then
    # Fonction intelligente : trash en interactif direct, rm natif sinon (ex: sdkman)
    rm() {
        if [[ ${#funcstack[@]} -le 1 && $- == *i* ]]; then
            command trash "$@"
        else
            command rm "$@"
        fi
    }
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
    # Reinstallation propre des node_modules
    alias nci='if [[ -d node_modules ]]; then command rm -rf node_modules; fi && npm cache clean --force && npm install'
fi

if command -v brew &> /dev/null; then
    alias bubu='brew update && brew upgrade && brew cleanup'
fi

# ArmadAI DEV
if command -v armadai &> /dev/null; then
    alias armadai-dev='$WORK_DIR/misc/armadai/target/release/armadai'
fi