# Init prompt (Starship)
# Vérification stricte avant le eval
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
else
    # Fallback minimaliste si starship absent
    # Affiche: [user@host dir]$ 
    PROMPT='%n@%m %1~ %# '
fi

# OPTIONAL: Activate AUTO_CD if wanted
# Uncomment the following line to enable AUTO_CD
setopt AUTO_CD

# Init Environment
if [[ -z "$ZSH_ENV_DIR" ]]; then
    echo "WARNING: ZSH_ENV_DIR is not set. Assuming default location." >&2
    export ZSH_ENV_DIR="$HOME/.zsh_env"
fi

# Load Configuration (modules actifs/inactifs)
# Valeurs par defaut (tout actif)
ZSH_ENV_MODULE_GITLAB=${ZSH_ENV_MODULE_GITLAB:-true}
ZSH_ENV_MODULE_DOCKER=${ZSH_ENV_MODULE_DOCKER:-true}
ZSH_ENV_MODULE_NVM=${ZSH_ENV_MODULE_NVM:-true}
ZSH_ENV_MODULE_NUSHELL=${ZSH_ENV_MODULE_NUSHELL:-true}

# Auto-update (valeurs par defaut)
ZSH_ENV_AUTO_UPDATE=${ZSH_ENV_AUTO_UPDATE:-true}
ZSH_ENV_UPDATE_FREQUENCY=${ZSH_ENV_UPDATE_FREQUENCY:-7}
ZSH_ENV_UPDATE_MODE=${ZSH_ENV_UPDATE_MODE:-prompt}

# NVM Lazy loading (true = charge NVM au premier appel node/npm)
ZSH_ENV_NVM_LAZY=${ZSH_ENV_NVM_LAZY:-true}

# Charger config personnalisee si presente
if [[ -f "$ZSH_ENV_DIR/config.zsh" ]]; then
    source "$ZSH_ENV_DIR/config.zsh"
fi

# Load Secrets (Ignored by git)
if [[ -f "$HOME/.secrets" ]]; then
    source "$HOME/.secrets"
fi

# Load variables (Critique : Doit etre charge en premier)
if [[ -f "$ZSH_ENV_DIR/variables.zsh" ]]; then
    source "$ZSH_ENV_DIR/variables.zsh" || echo "[zsh-env] Erreur au chargement de variables.zsh" >&2
else
    echo "[zsh-env] ERREUR: variables.zsh introuvable dans $ZSH_ENV_DIR" >&2
fi

export PATH="$SCRIPTS_DIR:$PATH"

# =======================================================
# COMPLETION SYSTEM (doit etre avant functions.zsh)
# =======================================================
# Initialiser compinit avec cache pour performance
autoload -Uz compinit
# Cache quotidien pour eviter la lenteur au demarrage
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

# Load functions
if [[ -f "$ZSH_ENV_DIR/functions.zsh" ]]; then
    source "$ZSH_ENV_DIR/functions.zsh" || echo "[zsh-env] Erreur au chargement de functions.zsh" >&2
fi

# Load aliases
if [[ -f "$ZSH_ENV_DIR/aliases.zsh" ]]; then
    source "$ZSH_ENV_DIR/aliases.zsh" || echo "[zsh-env] Erreur au chargement de aliases.zsh" >&2
fi

# Load plugins
if [[ -f "$ZSH_ENV_DIR/plugins.zsh" ]]; then
    source "$ZSH_ENV_DIR/plugins.zsh" || echo "[zsh-env] Erreur au chargement de plugins.zsh" >&2
fi

# Load local aliases (non versionnes)
if [[ -f "$ZSH_ENV_DIR/aliases.local.zsh" ]]; then
    source "$ZSH_ENV_DIR/aliases.local.zsh"
fi

# =======================================================
# NVM INIT (Cross-Platform avec Lazy Loading optionnel)
# =======================================================

if [[ "$ZSH_ENV_MODULE_NVM" == "true" ]]; then
    export NVM_DIR="$HOME/.nvm"

    # Fonction interne pour charger NVM
    _zsh_env_load_nvm() {
        # Liste priorisée des chemins (définie localement pour robustesse)
        local nvm_candidates=(
            "$NVM_DIR/nvm.sh"                          # Linux / Install Manuelle
            "/opt/homebrew/opt/nvm/nvm.sh"             # MacOS Apple Silicon (Brew)
            "/usr/local/opt/nvm/nvm.sh"                # MacOS Intel (Brew)
            "/usr/share/nvm/init-nvm.sh"               # Arch Linux (AUR)
        )

        local nvm_path
        for nvm_path in "${nvm_candidates[@]}"; do
            if [[ -s "$nvm_path" ]]; then
                source "$nvm_path"

                # Chargement de l'autocomplétion
                local nvm_root=$(dirname "$nvm_path")
                local completion_path="$nvm_root/etc/bash_completion.d/nvm"
                [[ ! -f "$completion_path" ]] && completion_path="$NVM_DIR/bash_completion"
                [[ -s "$completion_path" ]] && source "$completion_path"

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

    if [[ "$ZSH_ENV_NVM_LAZY" == "true" ]]; then
        # Mode Lazy : créer des wrappers qui chargent NVM au premier appel
        _zsh_env_lazy_nvm() {
            # Supprimer les wrappers
            unfunction node npm npx yarn pnpm nvm 2>/dev/null

            # Charger NVM
            if _zsh_env_load_nvm; then
                # Exécuter la commande originale
                "$@"
            else
                echo "[zsh_env] NVM non trouvé"
                return 1
            fi
        }

        # Créer les wrappers
        node()  { _zsh_env_lazy_nvm node "$@" }
        npm()   { _zsh_env_lazy_nvm npm "$@" }
        npx()   { _zsh_env_lazy_nvm npx "$@" }
        yarn()  { _zsh_env_lazy_nvm yarn "$@" }
        pnpm()  { _zsh_env_lazy_nvm pnpm "$@" }
        nvm()   { _zsh_env_lazy_nvm nvm "$@" }
    else
        # Mode normal : charger NVM immédiatement
        if _zsh_env_load_nvm; then
            load-nvmrc # Exécution au démarrage
        fi
    fi
fi

# SDKMAN (Optimisé et Silencieux)
# On vérifie d'abord que le dossier existe avant de tester le fichier
export SDKMAN_DIR="$HOME/.sdkman"
if [[ -d "$SDKMAN_DIR" ]] && [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi

# PATH Final (Déduplication)
# Empêche d'avoir le PATH qui grandit à l'infini si on reload le .zshrc
typeset -U PATH

# =======================================================
# ZOXIDE (doit etre charge en dernier)
# =======================================================
# Zoxide utilise un hook chpwd pour enregistrer les repertoires.
# Le charger en dernier garantit que son hook s'execute apres
# tous les autres (nvm, proj, etc.) et capture le repertoire final.
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
    alias cd="z"
fi