# ==============================================================================
# Chargement dynamique des fonctions
# ==============================================================================

# Charger ui.zsh en premier (fonctions utilitaires d'affichage)
if [[ -f "$ZSH_ENV_DIR/functions/ui.zsh" ]]; then
    source "$ZSH_ENV_DIR/functions/ui.zsh"
fi

# Fichiers charges en lazy loading (au premier appel)
_ZSH_ENV_LAZY_FILES=(ai_context.zsh ai_tokens.zsh)

# Charger tous les autres fichiers de fonctions (sauf lazy)
for file in "$ZSH_ENV_DIR/functions"/*; do
    if [[ -f "$file" && "$(basename "$file")" != "ui.zsh" ]]; then
        local name="$(basename "$file")"
        if (( ${_ZSH_ENV_LAZY_FILES[(Ie)$name]} )); then
            continue
        fi
        source "$file"
    fi
done

# --- Lazy loading : stubs pour les fichiers AI volumineux ---
# Les vrais fichiers sont charges au premier appel d'une fonction publique
_zsh_env_lazy_load() {
    local file="$1"
    shift
    local func="$1"
    source "$ZSH_ENV_DIR/functions/$file"
    "$func" "$@"
}

# ai_context.zsh (~670 lignes)
for _fn in ai_context_detect ai_context_init ai_context_generate ai_context_templates ai_context_help; do
    eval "${_fn}() { _zsh_env_lazy_load ai_context.zsh ${_fn} \"\$@\"; }"
done

# ai_tokens.zsh (~620 lignes)
for _fn in ai_tokens_estimate ai_tokens_analyze ai_tokens_compress ai_tokens_select ai_tokens_export ai_tokens_help; do
    eval "${_fn}() { _zsh_env_lazy_load ai_tokens.zsh ${_fn} \"\$@\"; }"
done
unset _fn
