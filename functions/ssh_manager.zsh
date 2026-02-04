# ==============================================================================
# SSH Manager - Gestion des connexions SSH
# ==============================================================================
# Utilitaires pour gerer les hosts SSH facilement
# ==============================================================================

SSH_CONFIG_FILE="$HOME/.ssh/config"

# Parse le fichier ssh config et extrait les hosts
_ssh_list_hosts() {
    if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
        return
    fi

    # Extraire les Host (ignorer les wildcards)
    grep -i "^Host " "$SSH_CONFIG_FILE" | awk '{print $2}' | grep -v '[*?]' | sort -u
}

# Obtient les details d'un host
_ssh_get_host_info() {
    local host="$1"

    if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
        return 1
    fi

    awk -v host="$host" '
        BEGIN { found=0; IGNORECASE=1 }
        /^Host / {
            if (found) exit
            if ($2 == host) found=1
            next
        }
        found && /^[[:space:]]/ {
            gsub(/^[[:space:]]+/, "")
            print
        }
        found && /^[^[:space:]]/ { exit }
    ' "$SSH_CONFIG_FILE"
}

# Selection interactive d'un host SSH
# Usage: ssh_select [pattern]
ssh_select() {
    local pattern="$1"
    local hosts=$(_ssh_list_hosts)

    if [[ -z "$hosts" ]]; then
        echo "Aucun host configure dans $SSH_CONFIG_FILE" >&2
        return 1
    fi

    # Filtrer si pattern fourni
    if [[ -n "$pattern" ]]; then
        hosts=$(echo "$hosts" | grep -i "$pattern")
        if [[ -z "$hosts" ]]; then
            echo "Aucun host correspondant a '$pattern'" >&2
            return 1
        fi
    fi

    local selected
    if command -v fzf &> /dev/null; then
        selected=$(echo "$hosts" | fzf \
            --header="Hosts SSH (ENTER: connect)" \
            --prompt="SSH > " \
            --preview="grep -A 10 -i '^Host {}$' $SSH_CONFIG_FILE | head -10" \
            --preview-window=right:40%)
    else
        echo "Hosts disponibles:"
        echo "$hosts" | nl
        echo -n "Numero ou nom: "
        read choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            selected=$(echo "$hosts" | sed -n "${choice}p")
        else
            selected="$choice"
        fi
    fi

    [[ -z "$selected" ]] && return 0

    echo "Connexion a $selected..."
    ssh "$selected"
}

# Liste les hosts configures
ssh_list() {
    local hosts=$(_ssh_list_hosts)

    if [[ -z "$hosts" ]]; then
        echo "Aucun host configure dans $SSH_CONFIG_FILE"
        return 0
    fi

    echo "Hosts SSH configures:"
    echo "──────────────────────────────────────────"

    while IFS= read -r host; do
        local hostname=$(grep -A 5 -i "^Host $host$" "$SSH_CONFIG_FILE" | grep -i "HostName" | head -1 | awk '{print $2}')
        local user=$(grep -A 5 -i "^Host $host$" "$SSH_CONFIG_FILE" | grep -i "User" | head -1 | awk '{print $2}')

        if [[ -n "$hostname" ]]; then
            printf "  %-20s  %s" "$host" "$hostname"
            [[ -n "$user" ]] && printf " (%s)" "$user"
            echo ""
        else
            echo "  $host"
        fi
    done <<< "$hosts"

    echo "──────────────────────────────────────────"
    echo "Total: $(echo "$hosts" | wc -l | tr -d ' ') hosts"
}

# Affiche les details d'un host
ssh_info() {
    local host="$1"

    if [[ -z "$host" ]]; then
        echo "Usage: ssh_info <host>" >&2
        return 1
    fi

    local info=$(_ssh_get_host_info "$host")

    if [[ -z "$info" ]]; then
        echo "Host '$host' non trouve dans $SSH_CONFIG_FILE" >&2
        return 1
    fi

    echo "Configuration de '$host':"
    echo "──────────────────────────────────────────"
    echo "$info" | while IFS= read -r line; do
        echo "  $line"
    done
    echo "──────────────────────────────────────────"
}

# Ajoute un nouveau host interactivement
ssh_add() {
    local alias="$1"

    if [[ -z "$alias" ]]; then
        echo -n "Alias du host: "
        read alias
    fi

    [[ -z "$alias" ]] && return 0

    # Verifier si existe deja
    if grep -qi "^Host $alias$" "$SSH_CONFIG_FILE" 2>/dev/null; then
        echo "Le host '$alias' existe deja." >&2
        return 1
    fi

    echo -n "Hostname (IP ou domaine): "
    read hostname
    [[ -z "$hostname" ]] && return 0

    echo -n "Utilisateur [$(whoami)]: "
    read user
    user="${user:-$(whoami)}"

    echo -n "Port [22]: "
    read port
    port="${port:-22}"

    echo -n "Fichier de cle [~/.ssh/id_rsa]: "
    read keyfile
    keyfile="${keyfile:-~/.ssh/id_rsa}"

    # Creer le fichier config si n'existe pas
    if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
        mkdir -p "$HOME/.ssh"
        touch "$SSH_CONFIG_FILE"
        chmod 600 "$SSH_CONFIG_FILE"
    fi

    # Ajouter l'entree
    cat >> "$SSH_CONFIG_FILE" << EOF

Host $alias
    HostName $hostname
    User $user
    Port $port
    IdentityFile $keyfile
EOF

    echo ""
    echo "Host '$alias' ajoute a $SSH_CONFIG_FILE"
    echo "Utilisez 'ssh $alias' pour vous connecter."
}

# Supprime un host
ssh_remove() {
    local host="$1"

    if [[ -z "$host" ]]; then
        # Selection interactive
        local hosts=$(_ssh_list_hosts)
        if [[ -z "$hosts" ]]; then
            echo "Aucun host configure." >&2
            return 1
        fi

        if command -v fzf &> /dev/null; then
            host=$(echo "$hosts" | fzf --header="Host a supprimer" --prompt="Remove > ")
        else
            echo "Hosts disponibles:"
            echo "$hosts" | nl
            echo -n "Numero ou nom: "
            read choice
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                host=$(echo "$hosts" | sed -n "${choice}p")
            else
                host="$choice"
            fi
        fi
    fi

    [[ -z "$host" ]] && return 0

    if ! grep -qi "^Host $host$" "$SSH_CONFIG_FILE" 2>/dev/null; then
        echo "Host '$host' non trouve." >&2
        return 1
    fi

    # Confirmation
    echo -n "Supprimer le host '$host'? [y/N] "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0

    # Backup
    cp "$SSH_CONFIG_FILE" "$SSH_CONFIG_FILE.bak"

    # Supprimer le bloc Host
    awk -v host="$host" '
        BEGIN { skip=0; IGNORECASE=1 }
        /^Host / {
            if ($2 == host) { skip=1; next }
            else { skip=0 }
        }
        skip && /^[[:space:]]/ { next }
        skip && /^$/ { next }
        skip && /^[^[:space:]]/ { skip=0 }
        !skip { print }
    ' "$SSH_CONFIG_FILE.bak" > "$SSH_CONFIG_FILE"

    echo "Host '$host' supprime."
    echo "Backup: $SSH_CONFIG_FILE.bak"
}

# Copie la cle publique vers un serveur
ssh_copy_key() {
    local host="$1"
    local keyfile="${2:-$HOME/.ssh/id_rsa.pub}"

    if [[ -z "$host" ]]; then
        echo "Usage: ssh_copy_key <host> [keyfile]" >&2
        return 1
    fi

    if [[ ! -f "$keyfile" ]]; then
        echo "Cle publique non trouvee: $keyfile" >&2
        echo "Generez une cle avec: ssh-keygen -t rsa -b 4096" >&2
        return 1
    fi

    echo "Copie de $keyfile vers $host..."
    ssh-copy-id -i "$keyfile" "$host"
}

# Teste la connexion a un host
ssh_test() {
    local host="$1"

    if [[ -z "$host" ]]; then
        echo "Usage: ssh_test <host>" >&2
        return 1
    fi

    echo "Test de connexion a $host..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo 'Connexion OK'" 2>/dev/null; then
        echo "Connexion reussie."
        return 0
    else
        echo "Echec de connexion." >&2
        return 1
    fi
}

# Aide
ssh_help() {
    cat << 'EOF'
SSH Manager - Commandes disponibles:

  ssh_select [pattern]   Selection interactive des hosts (fzf)
  ssh_list               Liste tous les hosts configures
  ssh_info <host>        Affiche les details d'un host
  ssh_add [alias]        Ajoute un nouveau host (interactif)
  ssh_remove [host]      Supprime un host
  ssh_copy_key <host>    Copie la cle publique vers un serveur
  ssh_test <host>        Teste la connexion a un host

Fichier de configuration: ~/.ssh/config
EOF
}
