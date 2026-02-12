# ==============================================================================
# Project Switcher - Changement de contexte projet complet
# ==============================================================================
# Change tout le contexte: dossier, kube context, node version, tmux session
# ==============================================================================

# Fichier de config projet: .proj ou .project.yml
PROJ_CONFIG_NAMES=(".proj" ".project.yml" ".project.yaml")

# Registre des projets connus
PROJ_REGISTRY_FILE="$HOME/.config/zsh_env/projects.yml"

# Cherche un fichier de config projet
_proj_find_config() {
    local dir="${1:-$PWD}"

    for name in "${PROJ_CONFIG_NAMES[@]}"; do
        if [[ -f "$dir/$name" ]]; then
            echo "$dir/$name"
            return 0
        fi
    done

    return 1
}

# Parse une valeur du fichier projet (YAML simple)
_proj_get_value() {
    local file="$1"
    local key="$2"
    local line value

    while IFS= read -r line; do
        if [[ "$line" == ${key}:* ]]; then
            value="${line#*: }"
            value="${value//\"/}"
            value="${value//\'/}"
            echo "$value"
            return 0
        fi
    done < "$file" 2>/dev/null
}

# Charge un projet par son chemin
_proj_load_by_path() {
    local proj_dir="$1"
    local config_file

    if [[ ! -d "$proj_dir" ]]; then
        echo "Dossier non trouve: $proj_dir" >&2
        return 1
    fi

    config_file=$(_proj_find_config "$proj_dir")

    # CD au projet
    cd "$proj_dir" || return 1
    echo "Projet: $proj_dir"

    # Si pas de config, juste cd
    if [[ -z "$config_file" ]]; then
        echo "  (pas de fichier .proj)"
        return 0
    fi

    # Lire la config
    local kube_context=$(_proj_get_value "$config_file" "kube_context")
    local node_version=$(_proj_get_value "$config_file" "node_version")
    local tmux_session=$(_proj_get_value "$config_file" "tmux_session")
    local env_file=$(_proj_get_value "$config_file" "env_file")
    local post_cmd=$(_proj_get_value "$config_file" "post_cmd")

    # Appliquer le contexte kube
    if [[ -n "$kube_context" ]]; then
        if command -v kubectl &> /dev/null; then
            if kubectl config use-context "$kube_context" &> /dev/null; then
                echo "  Kube context: $kube_context"
            else
                echo "  Kube context '$kube_context' non trouve" >&2
            fi
        fi
    fi

    # Appliquer la version Node
    if [[ -n "$node_version" ]]; then
        if command -v nvm &> /dev/null || [[ -f "$NVM_DIR/nvm.sh" ]]; then
            [[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"
            [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
            nvm use "$node_version" 2>/dev/null || nvm install "$node_version"
            echo "  Node: $(node -v)"
        fi
    elif [[ -f "$proj_dir/.nvmrc" ]]; then
        # Fallback sur .nvmrc
        if command -v nvm &> /dev/null || [[ -s "$NVM_DIR/nvm.sh" ]]; then
            [[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"
            [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
            nvm use 2>/dev/null
            echo "  Node: $(node -v) (via .nvmrc)"
        fi
    fi

    # Charger un fichier env
    if [[ -n "$env_file" && -f "$proj_dir/$env_file" ]]; then
        # Securite: verifier que le fichier env appartient a l'utilisateur
        local env_owner
        if [[ "$OSTYPE" == darwin* ]]; then
            env_owner=$(stat -f '%u' "$proj_dir/$env_file" 2>/dev/null)
        else
            env_owner=$(stat -c '%u' "$proj_dir/$env_file" 2>/dev/null)
        fi
        if [[ "$env_owner" != "$UID" ]]; then
            echo "  Env: $env_file ignore (proprietaire different)" >&2
        else
            set -a
            source "$proj_dir/$env_file"
            set +a
            echo "  Env: $env_file charge"
        fi
    fi

    # Session tmux
    if [[ -n "$tmux_session" ]] && command -v tmux &> /dev/null; then
        if [[ -z "$TMUX" ]]; then
            echo "  Tmux: utilisez 'tm $tmux_session' pour la session dediee"
        fi
    fi

    # Commande post (confirmation obligatoire)
    if [[ -n "$post_cmd" ]]; then
        echo "  Post-cmd: $post_cmd"
        if [[ -t 0 ]]; then
            local response
            read -q "response?  Executer cette commande ? [y/N] "
            echo ""
            if [[ "$response" == "y" ]]; then
                eval "$post_cmd"
            else
                echo "  Post-cmd ignoree."
            fi
        else
            echo "  Post-cmd ignoree (mode non-interactif)." >&2
        fi
    fi

    return 0
}

# Fonction principale
# Usage: proj [name|path]
proj() {
    local target="$1"

    # Sans argument: projet courant ou selection
    if [[ -z "$target" ]]; then
        local config=$(_proj_find_config)
        if [[ -n "$config" ]]; then
            _proj_load_by_path "$PWD"
            return
        fi

        # Selection interactive
        if [[ -f "$PROJ_REGISTRY_FILE" ]] && command -v fzf &> /dev/null; then
            local projects=""
            local pline
            while IFS= read -r pline; do
                [[ -z "$pline" || "$pline" =~ ^# ]] && continue
                projects+="${pline%%:*}"$'\n'
            done < "$PROJ_REGISTRY_FILE"
            if [[ -n "$projects" ]]; then
                target=$(echo "$projects" | fzf --header="Projets enregistres" --prompt="Projet > ")
                [[ -z "$target" ]] && return 0
            fi
        fi

        if [[ -z "$target" ]]; then
            echo "Usage: proj <name|path>" >&2
            echo "       proj --add [name]    Enregistrer un projet" >&2
            echo "       proj --list          Lister les projets" >&2
            echo "       proj --scan [dir]    Scanner et proposer des projets" >&2
            return 1
        fi
    fi

    # Options
    case "$target" in
        --add|-a)
            proj_add "$2" "$3"
            return
            ;;
        --list|-l)
            proj_list
            return
            ;;
        --remove|-r)
            proj_remove "$2"
            return
            ;;
        --init|-i)
            proj_init
            return
            ;;
        --scan|-s)
            proj_scan "$2" "$3"
            return
            ;;
        --auto)
            proj_auto_register "$2" "$3"
            return
            ;;
        --help|-h)
            proj_help
            return
            ;;
    esac

    # Chemin absolu ou relatif
    if [[ -d "$target" ]]; then
        _proj_load_by_path "$target"
        return
    fi

    # Chemin avec ~
    if [[ -d "${target/#\~/$HOME}" ]]; then
        _proj_load_by_path "${target/#\~/$HOME}"
        return
    fi

    # Chercher dans le registre
    if [[ -f "$PROJ_REGISTRY_FILE" ]]; then
        local regpath="" regline
        while IFS= read -r regline; do
            if [[ "$regline" == ${target}:* ]]; then
                regpath="${regline#*: }"
                regpath="${regpath//\"/}"
                break
            fi
        done < "$PROJ_REGISTRY_FILE"
        regpath="${regpath/#\~/$HOME}"
        if [[ -n "$regpath" && -d "$regpath" ]]; then
            _proj_load_by_path "$regpath"
            return
        fi
    fi

    # Chercher dans WORK_DIR
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR/$target" ]]; then
        _proj_load_by_path "$WORK_DIR/$target"
        return
    fi

    echo "Projet '$target' non trouve." >&2
    return 1
}

# Verifie si un nom existe dans le registre
_proj_name_exists() {
    local check_name="$1"
    [[ ! -f "$PROJ_REGISTRY_FILE" ]] && return 1
    local line
    while IFS= read -r line; do
        [[ "${line%%:*}" == "$check_name" ]] && return 0
    done < "$PROJ_REGISTRY_FILE"
    return 1
}

# Verifie si un path existe dans le registre, retourne le nom associe
_proj_path_exists() {
    local check_path="$1"
    [[ ! -f "$PROJ_REGISTRY_FILE" ]] && return 1
    local line lpath
    while IFS= read -r line; do
        lpath="${line#*: }"
        lpath="${lpath//\"/}"
        [[ "$lpath" == "$check_path" ]] && { echo "${line%%:*}"; return 0; }
    done < "$PROJ_REGISTRY_FILE"
    return 1
}

# Enregistre un projet
# Usage: proj_add [-n|--name NAME] [-p|--path PATH] [NAME] [PATH]
proj_add() {
    local name="" path="" force=false

    # Parser les arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                name="$2"
                shift 2
                ;;
            -p|--path)
                path="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -*)
                echo "Option inconnue: $1" >&2
                return 1
                ;;
            *)
                # Arguments positionnels
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$path" ]]; then
                    path="$1"
                fi
                shift
                ;;
        esac
    done

    # Valeurs par defaut
    path="${path:-$PWD}"

    # Resoudre le chemin absolu
    path=$(cd "$path" 2>/dev/null && pwd)
    if [[ -z "$path" ]]; then
        echo "Chemin invalide." >&2
        return 1
    fi

    # Verifier si le path existe deja
    local existing_name
    existing_name=$(_proj_path_exists "$path")
    if [[ $? -eq 0 ]]; then
        echo "Ce chemin est deja enregistre sous le nom '$existing_name'."
        if [[ "$force" != true ]]; then
            echo -n "Mettre a jour le nom? [y/N] "
            read -r confirm
            [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
            # Supprimer l'ancienne entree
            _proj_remove_entry "$existing_name"
        else
            return 0
        fi
    fi

    # Demander le nom si non fourni
    if [[ -z "$name" ]]; then
        local default_name="${path:t}"
        echo -n "Nom du projet [$default_name]: "
        read -r input
        name="${input:-$default_name}"
    fi

    # Verifier si le nom existe deja
    if _proj_name_exists "$name"; then
        echo "Un projet nomme '$name' existe deja."
        if [[ "$force" != true ]]; then
            echo -n "Ecraser? [y/N] "
            read -r confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo -n "Nouveau nom: "
                read -r name
                [[ -z "$name" ]] && return 0
            fi
        fi
        # Supprimer l'ancienne entree
        _proj_remove_entry "$name"
    fi

    # Creer le dossier config
    local registry_dir="${PROJ_REGISTRY_FILE:h}"
    [[ ! -d "$registry_dir" ]] && /bin/mkdir -p "$registry_dir"

    # Ajouter
    echo "${name}: \"$path\"" >> "$PROJ_REGISTRY_FILE"
    echo "Projet '$name' enregistre."
    echo "  Chemin: $path"
}

# Supprime une entree du registre (fonction interne)
_proj_remove_entry() {
    local entry_name="$1"
    [[ ! -f "$PROJ_REGISTRY_FILE" ]] && return
    local tmpfile="${PROJ_REGISTRY_FILE}.tmp"
    local line
    while IFS= read -r line; do
        [[ "${line%%:*}" != "$entry_name" ]] && echo "$line"
    done < "$PROJ_REGISTRY_FILE" > "$tmpfile"
    /bin/mv "$tmpfile" "$PROJ_REGISTRY_FILE"
}

# Liste les projets enregistres
proj_list() {
    if [[ ! -f "$PROJ_REGISTRY_FILE" ]]; then
        echo "Aucun projet enregistre."
        echo "Utilisez 'proj --add [name] [path]' pour en ajouter."
        return 0
    fi

    echo "Projets enregistres:"
    echo "──────────────────────────────────────────"

    local proj_name proj_path
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Parse avec expansions zsh: "name: /path" ou "name: \"/path\""
        proj_name="${line%%:*}"
        proj_path="${line#*: }"
        proj_path="${proj_path//\"/}"  # Retire les guillemets
        proj_path="${proj_path/#\~/$HOME}"

        if [[ -d "$proj_path" ]]; then
            printf "  %-15s %s\n" "$proj_name" "$proj_path"
        else
            printf "  %-15s %s (manquant)\n" "$proj_name" "$proj_path"
        fi
    done < "$PROJ_REGISTRY_FILE"

    echo "──────────────────────────────────────────"
}

# Supprime un projet du registre
proj_remove() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "Usage: proj --remove <name>" >&2
        return 1
    fi

    if [[ ! -f "$PROJ_REGISTRY_FILE" ]]; then
        echo "Aucun projet enregistre." >&2
        return 1
    fi

    if ! grep -qE "^${name}:" "$PROJ_REGISTRY_FILE"; then
        echo "Projet '$name' non trouve." >&2
        return 1
    fi

    sed -i.bak "/^${name}:/d" "$PROJ_REGISTRY_FILE"
    echo "Projet '$name' supprime."
}

# Initialise un fichier .proj dans le dossier courant
proj_init() {
    local config_file="$PWD/.proj"

    if [[ -f "$config_file" ]]; then
        echo "Fichier .proj existe deja."
        return 1
    fi

    local default_name=$(basename "$PWD")
    cat > "$config_file" << EOF
# Configuration projet zsh_env
# Utilisez 'proj' pour charger ce contexte

# Nom du projet (utilise pour l'enregistrement auto)
name: $default_name

# Contexte Kubernetes (optionnel)
# kube_context: my-cluster-context

# Version Node (optionnel, sinon utilise .nvmrc)
# node_version: 18

# Session tmux (optionnel)
# tmux_session: $default_name

# Fichier d'environnement a charger (optionnel)
# env_file: .env.local

# Commande a executer apres chargement (optionnel)
# post_cmd: echo "Projet charge!"
EOF

    echo "Fichier .proj cree."
    echo "Editez-le pour configurer votre contexte projet."
}

# Scanne un dossier pour trouver des projets potentiels
proj_scan() {
    local scan_dir="${1:-${WORK_DIR:-$HOME/projects}}"
    local depth="${2:-2}"

    if [[ ! -d "$scan_dir" ]]; then
        echo "Dossier non trouve: $scan_dir" >&2
        return 1
    fi

    echo "Scan de $scan_dir (profondeur: $depth)..."
    echo ""

    local found=()
    local already_registered=()
    local name has_config markers is_registered

    # Chercher les dossiers avec .proj, .git, package.json, etc.
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        name="${dir:t}"
        has_config=false
        markers=""

        # Detecter les marqueurs de projet
        [[ -f "$dir/.proj" ]] && markers="$markers .proj" && has_config=true
        [[ -f "$dir/.project.yml" ]] && markers="$markers .project.yml" && has_config=true
        [[ -d "$dir/.git" ]] && markers="$markers git"
        [[ -f "$dir/package.json" ]] && markers="$markers node"
        [[ -f "$dir/Cargo.toml" ]] && markers="$markers rust"
        [[ -f "$dir/go.mod" ]] && markers="$markers go"
        [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" ]] && markers="$markers python"
        [[ -f "$dir/pom.xml" || -f "$dir/build.gradle" ]] && markers="$markers java"

        # Retirer l'espace initial et ignorer si pas de marqueur
        markers="${markers# }"
        [[ -z "$markers" ]] && continue

        # Verifier si deja enregistre
        is_registered=false
        if [[ -f "$PROJ_REGISTRY_FILE" ]]; then
            if grep -q "\"$dir\"" "$PROJ_REGISTRY_FILE" 2>/dev/null; then
                is_registered=true
            fi
        fi

        if $is_registered; then
            already_registered+=("$dir")
        else
            found+=("$dir|$name|$markers")
        fi
    done < <(find "$scan_dir" -maxdepth "$depth" -type d 2>/dev/null)

    # Afficher les resultats
    if [[ ${#found[@]} -eq 0 ]]; then
        echo "Aucun nouveau projet detecte."
        [[ ${#already_registered[@]} -gt 0 ]] && echo "${#already_registered[@]} projet(s) deja enregistre(s)."
        return 0
    fi

    echo "Projets detectes:"
    echo "──────────────────────────────────────────"

    local i=1
    local entry_dir entry_name entry_markers
    local parts
    for entry in "${found[@]}"; do
        # Split par | avec zsh
        parts=("${(@s:|:)entry}")
        entry_dir="${parts[1]}"
        entry_name="${parts[2]}"
        entry_markers="${parts[3]}"
        printf "  %2d) %-20s [%s]\n" "$i" "$entry_name" "$entry_markers"
        printf "      %s\n" "$entry_dir"
        ((i++))
    done

    echo "──────────────────────────────────────────"
    echo ""

    # Proposer d'enregistrer
    if command -v fzf &> /dev/null; then
        echo "Selection des projets a enregistrer (TAB: toggle, ENTER: valider):"
        # Formater pour fzf
        local fzf_lines=""
        for entry in "${found[@]}"; do
            parts=("${(@s:|:)entry}")
            fzf_lines+="$(printf "%-20s [%s] %s" "${parts[2]}" "${parts[3]}" "${parts[1]}")"$'\n'
        done
        local selected=$(echo "$fzf_lines" | fzf --multi --header="Projets a enregistrer" --prompt="Select > ")

        [[ -z "$selected" ]] && echo "Aucun projet selectionne." && return 0

        echo ""
        local sel_name sel_path
        while IFS= read -r line; do
            # Format: "name                 [markers] path"
            sel_name="${line%% *}"
            sel_path="${line##* }"
            proj_add -n "$sel_name" -p "$sel_path" -f
        done <<< "$selected"
    else
        echo -n "Enregistrer tous ces projets? [y/N] "
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            for entry in "${found[@]}"; do
                parts=("${(@s:|:)entry}")
                proj_add "${parts[2]}" "${parts[1]}"
            done
        fi
    fi
}

# Auto-enregistre les projets avec fichier .proj
proj_auto_register() {
    local scan_dir="${1:-${WORK_DIR:-$HOME/projects}}"
    local depth="${2:-3}"

    echo "Recherche des fichiers .proj dans $scan_dir..."

    # Creer le dossier config si necessaire
    local registry_dir="${PROJ_REGISTRY_FILE:h}"
    [[ ! -d "$registry_dir" ]] && /bin/mkdir -p "$registry_dir"

    local count=0 skipped=0
    local proj_dir proj_name existing_name custom_name
    while IFS= read -r proj_file; do
        proj_dir="${proj_file:h}"
        proj_name="${proj_dir:t}"

        # Verifier si le chemin est deja enregistre
        existing_name=$(_proj_path_exists "$proj_dir")
        if [[ $? -eq 0 ]]; then
            ((skipped++))
            continue
        fi

        # Lire le nom depuis le fichier .proj si defini
        custom_name=$(_proj_get_value "$proj_file" "name")
        [[ -n "$custom_name" ]] && proj_name="$custom_name"

        # Verifier si le nom existe deja, ajouter un suffixe si necessaire
        if _proj_name_exists "$proj_name"; then
            local base_name="$proj_name"
            local suffix=2
            while _proj_name_exists "${base_name}-${suffix}"; do
                ((suffix++))
            done
            proj_name="${base_name}-${suffix}"
            echo "  + $proj_name ($proj_dir) [renomme depuis $base_name]"
        else
            echo "  + $proj_name ($proj_dir)"
        fi

        echo "${proj_name}: \"$proj_dir\"" >> "$PROJ_REGISTRY_FILE"
        ((count++))
    done < <(find "$scan_dir" -maxdepth "$depth" -name ".proj" -o -name ".project.yml" 2>/dev/null)

    echo ""
    echo "$count projet(s) enregistre(s)."
    [[ $skipped -gt 0 ]] && echo "$skipped projet(s) deja enregistre(s) (ignores)."
}

# Aide
proj_help() {
    cat << 'EOF'
Project Switcher - Changement de contexte complet

Usage:
  proj [name|path]       Charge un projet (interactif sans arg)
  proj --add [OPTIONS]   Enregistre un projet
  proj --list            Liste les projets enregistres
  proj --remove <name>   Supprime un projet du registre
  proj --init            Cree un fichier .proj dans le dossier courant
  proj --scan [dir]      Scanne et propose des projets a enregistrer
  proj --auto [dir]      Auto-enregistre les projets avec .proj

Options de --add:
  -n, --name NAME        Nom du projet (sinon demande interactif)
  -p, --path PATH        Chemin du projet (defaut: dossier courant)
  -f, --force            Pas de confirmation pour ecraser les doublons

Exemples:
  proj --add                      # Enregistre le dossier courant (demande le nom)
  proj --add mon-projet           # Enregistre avec le nom 'mon-projet'
  proj --add -n api -p ~/work/api # Enregistre ~/work/api sous le nom 'api'
  proj --scan ~/projects          # Scanne et propose des projets

Fichier .proj:
  name: my-project       Nom du projet (optionnel)
  kube_context: ctx      Change le contexte kubectl
  node_version: 18       Change la version Node (nvm)
  tmux_session: name     Suggere une session tmux
  env_file: .env.local   Charge un fichier d'environnement
  post_cmd: "cmd"        Execute une commande apres chargement

Registre: ~/.config/zsh_env/projects.yml
EOF
}
