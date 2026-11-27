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
    # Theme genere par zanvil-theme ; expansion de parametres seulement, aucun binaire.
    if [[ -z "$STARSHIP_CONFIG" && -f "${XDG_CONFIG_HOME:-$HOME/.config}/zanvil/theme/starship.toml" ]]; then
        export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/zanvil/theme/starship.toml"
    fi
    _zanvil_cached starship starship init zsh && source "$REPLY"
else
    # Fallback minimaliste si starship absent
    PROMPT='%n@%m %1~ %# '
fi

# =======================================================
# MISE (Gestionnaire de versions: Node, Java, Maven, etc.)
# =======================================================
if [[ "$ZANVIL_MODULE_MISE" = "true" ]]; then
    if command -v mise &> /dev/null; then
        eval "$(mise activate zsh)"
    fi
fi

# =======================================================
# ZOXIDE (Navigation rapide)
# =======================================================
# Zoxide utilise un hook chpwd pour enregistrer les repertoires.
if command -v zoxide &> /dev/null; then
    export _ZO_DOCTOR=0  # Desactive l'avertissement (direnv charge apres)
    _zanvil_cached zoxide zoxide init zsh && source "$REPLY"
    alias cd="z"
fi

# =======================================================
# DIRENV (Charge/decharge les .envrc automatiquement)
# =======================================================
if command -v direnv &> /dev/null; then
    _zanvil_cached direnv direnv hook zsh && source "$REPLY"
fi

# =======================================================
# ZANVIL LOCAL (auto-chargement par projet, style direnv)
# =======================================================
# Fonctions dans core/zanvil_local.zsh ; ici seulement le hook et le chargement initial.

# Enregistrer le hook chpwd
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _zanvil_local_chpwd

# Charger si on est deja dans un dossier avec .zanvil.local
[[ -f "$PWD/.zanvil.local" ]] && _zanvil_local_load "$PWD/.zanvil.local"

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

# =======================================================
# ATUIN (Historique enrichi — remplace Ctrl+R de fzf)
# =======================================================
# Chargé en dernier pour que Ctrl+R override celui de fzf.
# --disable-up-arrow : les flèches ↑↓ restent en recherche par préfixe.
if [[ "${ZANVIL_MODULE_ATUIN:-}" == "true" ]] && command -v atuin &>/dev/null; then
    _zanvil_cached atuin-init atuin init zsh --disable-up-arrow && source "$REPLY"
fi

# =======================================================
# BANNIERE DE DEMARRAGE (zanvil)
# =======================================================
# Ligne compacte a chaque shell interactif. Opt-out : ZANVIL_STARTUP_BANNER=false
# ZANVIL_STARTUP_BANNER=fastfetch : zfetch banner, une fois par shell de premier niveau (pas a chaque ss)
if [[ -o interactive && "${ZANVIL_STARTUP_BANNER:-true}" != "false" ]]; then
    if [[ "$ZANVIL_STARTUP_BANNER" == fastfetch ]] && (( $+functions[zfetch] && SHLVL == 1 && ! ${+_ZANVIL_FETCH_SHOWN} )); then
        typeset -g _ZANVIL_FETCH_SHOWN=1
        zfetch banner
    else
        _zanvil_banner_compact
    fi
fi
