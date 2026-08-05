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

    # env.d/*.zsh, qui manquait — et c'est le repertoire que la convention designe pour
    # les variables d'environnement, donc celui ou les anciens noms sont les plus
    # probables. Sur la machine de developpement, quatre reglages y etaient poses sous la
    # forme ZSH_ENV_* et donc ignores : l'URL Elasticsearch, celle du Nexus, un timeout et
    # un TTL de cache. Aucun message ne le disait.
    #
    # Les fichiers *.sops.zsh sont exclus : ils sont chiffres, et un sed dessus les
    # rendrait indechiffrables. Leur contenu se remigre en clair, puis se rechiffre.
    local envd="$new/env.d" f
    if [[ -d "$envd" ]]; then
        for f in "$envd"/*.zsh(N); do
            [[ "$f" == *.sops.zsh ]] && continue
            grep -q 'ZSH_ENV_' "$f" 2>/dev/null || continue
            cp "$f" "${f}.bak-${ts}"
            sed 's/ZSH_ENV_/ZANVIL_/g' "$f" > "${f}.tmp" \
                && mv "${f}.tmp" "$f" \
                && echo "zanvil: env.d/${f:t} migre" \
                || echo "zanvil: avertissement: reecriture ${f:t} echouee"
        done
        # Un fichier chiffre qui porte l'ancien nom ne peut pas etre migre ici, mais se
        # taire reviendrait a laisser un reglage mort sans le dire — ce que ce volet
        # existe pour empecher.
        for f in "$envd"/*.sops.zsh(N); do
            echo "zanvil: ${f:t} est chiffre — verifiez ses ZSH_ENV_* a la main"
        done
    fi

    echo "zanvil: migration terminee (backup: ${bak}). Rechargement..."
    export ZANVIL_DIR="$new"
    [[ -n "$ZANVIL_MIGRATE_NO_EXEC" ]] && return 0
    exec zsh
}
_zanvil_migrate_from_zsh_env
