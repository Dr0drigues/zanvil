# =======================================================
# ZANVIL PLUGINS MANAGER
# Gestionnaire de plugins léger et flexible
# =======================================================

ZANVIL_PLUGINS_DIR="$ZANVIL_DIR/plugins"

# Organisation par défaut (optionnel)
# Si défini, les plugins sans "/" seront préfixés par cette org
# Exemple: ZANVIL_PLUGINS_ORG="zsh-users"
ZANVIL_PLUGINS_ORG=${ZANVIL_PLUGINS_ORG:-""}

# Plugins à charger (définir dans config.zsh)
# Format: "repo" (utilise ZANVIL_PLUGINS_ORG), "owner/repo", ou URL complète
# Exemple:
#   ZANVIL_PLUGINS_ORG=zsh-users
#   ZANVIL_PLUGINS=(
#       zsh-autosuggestions        # -> zsh-users/zsh-autosuggestions
#       zsh-syntax-highlighting    # -> zsh-users/zsh-syntax-highlighting
#       Aloxaf/fzf-tab             # -> Aloxaf/fzf-tab (org explicite)
#   )
# Initialiser comme tableau vide si non défini
(( ${+ZANVIL_PLUGINS} )) || ZANVIL_PLUGINS=()

# =======================================================
# FONCTIONS INTERNES
# =======================================================

# Extraire le nom du plugin depuis une URL ou un shorthand
_zanvil_plugin_name() {
    local input="$1"
    # Retirer .git si présent
    input="${input%.git}"
    # Extraire le dernier segment (nom du repo)
    echo "${input##*/}"
}

# Construire l'URL de clonage
_zanvil_plugin_url() {
    local input="$1"

    # URL complète : utiliser telle quelle
    if [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ ^git@ ]]; then
        echo "$input"
        return
    fi

    # Si pas de "/" et org par défaut définie, préfixer
    if [[ ! "$input" =~ / ]] && [[ -n "$ZANVIL_PLUGINS_ORG" ]]; then
        input="${ZANVIL_PLUGINS_ORG}/${input}"
    fi

    # GitHub shorthand: owner/repo
    echo "https://github.com/${input}.git"
}

# Détecter automatiquement le fichier à sourcer
_zanvil_find_plugin_file() {
    local plugin_dir="$1"
    local name=$(basename "$plugin_dir")

    # Ordre de priorité pour la détection
    # 1. *.plugin.zsh (convention oh-my-zsh)
    for f in "$plugin_dir"/*.plugin.zsh(N); do
        [[ -f "$f" ]] && { echo "$f"; return 0; }
    done

    # 2. init.zsh (convention prezto)
    [[ -f "$plugin_dir/init.zsh" ]] && { echo "$plugin_dir/init.zsh"; return 0; }

    # 3. <nom>.zsh (convention zsh-users)
    [[ -f "$plugin_dir/$name.zsh" ]] && { echo "$plugin_dir/$name.zsh"; return 0; }

    # 4. Premier fichier .zsh trouvé
    for f in "$plugin_dir"/*.zsh(N); do
        [[ -f "$f" ]] && { echo "$f"; return 0; }
    done

    # 5. Pas de fichier à sourcer (peut-être des completions)
    return 1
}

# Charger un plugin
_zanvil_load_plugin() {
    local input="$1"
    local name=$(_zanvil_plugin_name "$input")
    local plugin_dir="$ZANVIL_PLUGINS_DIR/$name"

    if [[ ! -d "$plugin_dir" ]]; then
        return 1
    fi

    # Ajouter au fpath si le plugin contient des completions
    [[ -d "$plugin_dir/src" ]] && fpath=("$plugin_dir/src" $fpath)
    [[ -d "$plugin_dir/functions" ]] && fpath=("$plugin_dir/functions" $fpath)
    [[ -d "$plugin_dir/_*" ]] && fpath=("$plugin_dir" $fpath)

    # Trouver et sourcer le fichier principal
    local source_file
    source_file=$(_zanvil_find_plugin_file "$plugin_dir")
    if [[ -n "$source_file" && -f "$source_file" ]]; then
        source "$source_file"
    fi

    return 0
}

# =======================================================
# COMMANDES UTILISATEUR
# =======================================================

# Installer un plugin
zsh-plugin-install() {
    local input="$1"

    if [[ -z "$input" ]]; then
        echo "Usage: zsh-plugin-install <owner/repo> ou <url>"
        echo ""
        echo "Exemples:"
        echo "  zsh-plugin-install zsh-users/zsh-autosuggestions"
        echo "  zsh-plugin-install https://github.com/Aloxaf/fzf-tab.git"
        return 1
    fi

    local name=$(_zanvil_plugin_name "$input")
    local url=$(_zanvil_plugin_url "$input")
    local target="$ZANVIL_PLUGINS_DIR/$name"

    mkdir -p "$ZANVIL_PLUGINS_DIR"

    if [[ -d "$target" ]]; then
        echo "[plugins] $name déjà installé, mise à jour..."
        git -C "$target" pull --quiet
    else
        echo "[plugins] Installation de $name..."
        if git clone --depth 1 --quiet "$url" "$target" 2>/dev/null; then
            echo "[plugins] $name installé avec succès"
        else
            echo "[plugins] Erreur: impossible de cloner $url"
            return 1
        fi
    fi
}

# Désinstaller un plugin
zsh-plugin-remove() {
    local input="$1"

    if [[ -z "$input" ]]; then
        echo "Usage: zsh-plugin-remove <nom>"
        return 1
    fi

    local name=$(_zanvil_plugin_name "$input")
    local target="$ZANVIL_PLUGINS_DIR/$name"

    if [[ -d "$target" ]]; then
        rm -rf "$target"
        echo "[plugins] $name supprimé"
        echo "[plugins] Pensez à le retirer de ZANVIL_PLUGINS dans config.zsh"
    else
        echo "[plugins] Plugin non trouvé: $name"
        return 1
    fi
}

# Mettre à jour tous les plugins
zsh-plugin-update() {
    if [[ ! -d "$ZANVIL_PLUGINS_DIR" ]] || [[ -z "$(ls -A "$ZANVIL_PLUGINS_DIR" 2>/dev/null)" ]]; then
        echo "[plugins] Aucun plugin installé"
        return 0
    fi

    echo "[plugins] Mise à jour des plugins..."
    for dir in "$ZANVIL_PLUGINS_DIR"/*/; do
        if [[ -d "$dir/.git" ]]; then
            local name=$(basename "$dir")
            printf "  → %-30s " "$name"
            if git -C "$dir" pull --quiet 2>/dev/null; then
                echo "✓"
            else
                echo "✗ (erreur)"
            fi
        fi
    done
    echo "[plugins] Terminé. Rechargez le shell (ss)"
}

# Lister les plugins
zsh-plugin-list() {
    echo "Plugins installés:"
    echo ""

    if [[ ! -d "$ZANVIL_PLUGINS_DIR" ]] || [[ -z "$(ls -A "$ZANVIL_PLUGINS_DIR" 2>/dev/null)" ]]; then
        echo "  (aucun)"
        echo ""
    else
        for dir in "$ZANVIL_PLUGINS_DIR"/*/; do
            if [[ -d "$dir" ]]; then
                local name=$(basename "$dir")
                local active="○"
                # Vérifier si le plugin est dans ZANVIL_PLUGINS
                for p in "${ZANVIL_PLUGINS[@]}"; do
                    [[ "$(_zanvil_plugin_name "$p")" == "$name" ]] && { active="●"; break; }
                done
                echo "  $active $name"
            fi
        done
        echo ""
        echo "Légende: ○ installé (inactif) | ● actif"
        echo ""
    fi

    echo "Plugins populaires:"
    echo "  zsh-users/zsh-autosuggestions    Suggestions basées sur l'historique"
    echo "  zsh-users/zsh-syntax-highlighting Coloration syntaxique"
    echo "  zsh-users/zsh-completions        Completions additionnelles"
    echo "  Aloxaf/fzf-tab                   Completions avec fzf"
    echo "  agkozak/zsh-z                    Navigation rapide (alternative à zoxide)"
    echo "  hlissner/zsh-autopair            Auto-fermeture des parenthèses/quotes"
    echo "  MichaelAqworte/fast-syntax-highlighting  Highlighting performant"
}

# =======================================================
# CHARGEMENT DES PLUGINS
# =======================================================

# Charger tous les plugins définis dans ZANVIL_PLUGINS
for _plugin in "${ZANVIL_PLUGINS[@]}"; do
    if ! _zanvil_load_plugin "$_plugin"; then
        # Plugin non installé, proposer l'installation automatique
        zsh-plugin-install "$_plugin" && _zanvil_load_plugin "$_plugin"
    fi
done
unset _plugin

# Recharger les completions si des plugins en ont ajouté
(( $+functions[compinit] )) || autoload -Uz compinit

# =======================================================
# KEYBINDINGS POUR PLUGINS
# =======================================================

# zsh-history-substring-search : fleches haut/bas pour chercher dans l'historique
if (( $+functions[history-substring-search-up] )); then
    bindkey '^[[A' history-substring-search-up      # Fleche haut
    bindkey '^[[B' history-substring-search-down    # Fleche bas
    bindkey '^[OA' history-substring-search-up      # Fleche haut (mode application)
    bindkey '^[OB' history-substring-search-down    # Fleche bas (mode application)
fi
