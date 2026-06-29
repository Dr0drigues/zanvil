# ==============================================================================
# core/migrate_zanvil.zsh — migration unique zsh_env -> zanvil (one-shot)
# ==============================================================================
# ATTENTION : contient VOLONTAIREMENT les anciens noms (.zsh_env, ZSH_ENV_*)
# pour detecter et migrer une install heritee. NE PAS renommer ce fichier.
# Idempotent : ne fait rien si ~/.zanvil existe deja ou ~/.zsh_env absent.
# ==============================================================================
_zanvil_migrate_from_zsh_env() {
    local old="$HOME/.zsh_env" new="$HOME/.zanvil"
    [[ -d "$old" && ! -d "$new" ]] || return 0

    local ts; ts=$(date +%Y%m%d-%H%M%S)
    echo "zanvil: migration depuis ~/.zsh_env vers ~/.zanvil ..."
    cp -a "$old" "${old}.bak-${ts}" || { echo "zanvil: backup echoue, abandon"; return 1; }
    mv "$old" "$new"                || { echo "zanvil: deplacement echoue, abandon"; return 1; }

    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]]; then
        cp "$zshrc" "${zshrc}.bak-${ts}"
        sed -i '' -e 's/ZSH_ENV_DIR/ZANVIL_DIR/g' -e 's#\.zsh_env#.zanvil#g' "$zshrc"
    fi

    local cfg="$new/config.zsh"
    [[ -f "$cfg" ]] && sed -i '' 's/ZSH_ENV_/ZANVIL_/g' "$cfg"

    echo "zanvil: migration terminee (backup: ${old}.bak-${ts}). Rechargement..."
    export ZANVIL_DIR="$new"
    [[ -n "$ZANVIL_MIGRATE_NO_EXEC" ]] && return 0
    exec zsh
}
_zanvil_migrate_from_zsh_env
