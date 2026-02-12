# ==============================================================================
# Hooks & Initialisations d'outils externes
# ==============================================================================
# Ce fichier centralise les initialisations d'outils qui utilisent des hooks zsh
# (eval "$(tool init zsh)", hooks chpwd, etc.)
# ==============================================================================

# =======================================================
# FZF (Keybindings & Completion)
# =======================================================
# Ctrl+R : recherche historique | Ctrl+T : fichiers | Alt+C : cd
if command -v fzf &> /dev/null; then
    # Chemins possibles pour les scripts fzf
    _fzf_paths=(
        "/opt/homebrew/opt/fzf/shell"    # MacOS Apple Silicon (Brew)
        "/usr/local/opt/fzf/shell"       # MacOS Intel (Brew)
        "/usr/share/fzf"                 # Linux (apt/dnf)
        "$HOME/.fzf"                     # Installation manuelle
    )

    for _fzf_path in "${_fzf_paths[@]}"; do
        if [[ -d "$_fzf_path" ]]; then
            [[ -f "$_fzf_path/key-bindings.zsh" ]] && source "$_fzf_path/key-bindings.zsh"
            [[ -f "$_fzf_path/completion.zsh" ]] && source "$_fzf_path/completion.zsh"
            break
        fi
    done
    unset _fzf_paths _fzf_path
fi

# =======================================================
# STARSHIP (Prompt)
# =======================================================
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
else
    # Fallback minimaliste si starship absent
    PROMPT='%n@%m %1~ %# '
fi

# =======================================================
# NVM (Node Version Manager)
# =======================================================
if [ "$ZSH_ENV_MODULE_NVM" = "true" ]; then
    export NVM_DIR="$HOME/.nvm"

    # Fonction interne pour charger NVM
    _zsh_env_load_nvm() {
        local nvm_candidates=(
            "$NVM_DIR/nvm.sh"                          # Linux / Install Manuelle
            "/opt/homebrew/opt/nvm/nvm.sh"             # MacOS Apple Silicon (Brew)
            "/usr/local/opt/nvm/nvm.sh"                # MacOS Intel (Brew)
            "/usr/share/nvm/init-nvm.sh"               # Arch Linux (AUR)
        )

        local nvm_path
        for nvm_path in "${nvm_candidates[@]}"; do
            if [ -s "$nvm_path" ]; then
                source "$nvm_path"

                # Chargement de l'autocompletion
                local nvm_root=$(dirname "$nvm_path")
                local completion_path="$nvm_root/etc/bash_completion.d/nvm"
                [ ! -f "$completion_path" ] && completion_path="$NVM_DIR/bash_completion"
                [ -s "$completion_path" ] && source "$completion_path"

                # Hook automatique pour .nvmrc
                if command -v nvm &> /dev/null; then
                    autoload -U add-zsh-hook
                    add-zsh-hook chpwd load-nvmrc
                fi

                return 0
            fi
        done
        return 1
    }

    if [ "$ZSH_ENV_NVM_LAZY" = "true" ]; then
        # Mode Lazy : wrappers qui chargent NVM au premier appel
        _zsh_env_lazy_nvm() {
            unfunction node npm npx yarn pnpm nvm 2>/dev/null
            if _zsh_env_load_nvm; then
                "$@"
            else
                echo "[zsh_env] NVM non trouve"
                return 1
            fi
        }

        node()  { _zsh_env_lazy_nvm node "$@" }
        npm()   { _zsh_env_lazy_nvm npm "$@" }
        npx()   { _zsh_env_lazy_nvm npx "$@" }
        yarn()  { _zsh_env_lazy_nvm yarn "$@" }
        pnpm()  { _zsh_env_lazy_nvm pnpm "$@" }
        nvm()   { _zsh_env_lazy_nvm nvm "$@" }
    else
        # Mode normal : charger NVM immediatement
        if _zsh_env_load_nvm; then
            load-nvmrc 2>/dev/null
        fi
    fi
fi

# =======================================================
# SDKMAN (Java, Gradle, Maven, etc.)
# =======================================================
export SDKMAN_DIR="$HOME/.sdkman"
if [ -d "$SDKMAN_DIR" ] && [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi

# =======================================================
# ZOXIDE (Navigation rapide)
# =======================================================
# Zoxide utilise un hook chpwd pour enregistrer les repertoires.
if command -v zoxide &> /dev/null; then
    export _ZO_DOCTOR=0  # Desactive l'avertissement (direnv charge apres)
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

# =======================================================
# DIRENV (Charge/decharge les .envrc automatiquement)
# =======================================================
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi

# =======================================================
# KEYBINDINGS
# =======================================================
# Fleches haut/bas : recherche historique par prefixe
# Tape "git" puis fleche haut -> affiche les commandes commencant par "git"
autoload -U history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end

bindkey '^[[A' history-beginning-search-backward-end  # Fleche haut
bindkey '^[[B' history-beginning-search-forward-end   # Fleche bas
bindkey '^[OA' history-beginning-search-backward-end  # Fleche haut (mode application)
bindkey '^[OB' history-beginning-search-forward-end   # Fleche bas (mode application)
