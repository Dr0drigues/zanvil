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
    local bak="${old}.bak-${ts}"
    echo "zanvil: migration depuis ~/.zsh_env vers ~/.zanvil ..."
    # Backup leger : exclut les dossiers lourds regenerables (node_modules, build
    # Rust, sorties/cache de build, .git) et NE preserve PAS les ACL/xattr. cp -a
    # echouait sur site/node_modules sous macOS (failed to copy ACLs) et dupliquait
    # plusieurs Go inutiles. rsync sinon repli sur cp -R.
    if command -v rsync &>/dev/null; then
        rsync -a \
            --exclude='.git' --exclude='node_modules' --exclude='target' \
            --exclude='dist' --exclude='.astro' \
            "$old/" "$bak/" || { echo "zanvil: backup echoue, abandon"; return 1; }
    else
        cp -R "$old" "$bak" || { echo "zanvil: backup echoue, abandon"; return 1; }
    fi
    mv "$old" "$new"                || { echo "zanvil: deplacement echoue, abandon"; return 1; }

    # Reecriture in-place portable (BSD/macOS + GNU/Linux) : pas de sed -i (la
    # syntaxe du suffixe differe entre les deux). On passe par un fichier temporaire.
    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]]; then
        cp "$zshrc" "${zshrc}.bak-${ts}" || { echo "zanvil: backup .zshrc echoue, abandon"; return 1; }
        sed -e 's/ZSH_ENV_DIR/ZANVIL_DIR/g' -e 's#\.zsh_env#.zanvil#g' "$zshrc" > "${zshrc}.tmp" \
            && mv "${zshrc}.tmp" "$zshrc" \
            || echo "zanvil: avertissement: reecriture .zshrc echouee"
    fi

    local cfg="$new/config.zsh"
    if [[ -f "$cfg" ]]; then
        cp "$cfg" "${cfg}.bak-${ts}"
        sed 's/ZSH_ENV_/ZANVIL_/g' "$cfg" > "${cfg}.tmp" \
            && mv "${cfg}.tmp" "$cfg" \
            || echo "zanvil: avertissement: reecriture config.zsh echouee"
    fi

    echo "zanvil: migration terminee (backup: ${bak}). Rechargement..."
    export ZANVIL_DIR="$new"
    [[ -n "$ZANVIL_MIGRATE_NO_EXEC" ]] && return 0
    exec zsh
}
_zanvil_migrate_from_zsh_env
