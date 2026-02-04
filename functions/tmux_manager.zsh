# ==============================================================================
# Tmux Manager - Gestion des sessions tmux
# ==============================================================================
# Utilitaires pour gerer les sessions tmux facilement
# ==============================================================================

# Verification de tmux
_tmux_check() {
    if ! command -v tmux &> /dev/null; then
        echo "tmux n'est pas installe." >&2
        return 1
    fi
    return 0
}

# Attach ou cree une session tmux
# Usage: tm [session_name]
tm() {
    _tmux_check || return 1

    local session_name="$1"

    # Sans argument: selection interactive ou attach
    if [[ -z "$session_name" ]]; then
        local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)

        if [[ -z "$sessions" ]]; then
            # Pas de sessions, en creer une
            session_name="main"
            echo "Aucune session existante. Creation de '$session_name'..."
            tmux new-session -s "$session_name"
            return
        fi

        # Selection interactive si fzf disponible
        if command -v fzf &> /dev/null; then
            local selected=$(echo "$sessions" | fzf --header="Sessions tmux (ENTER: attach, Ctrl-N: nouvelle)" \
                --bind="ctrl-n:abort" \
                --expect="ctrl-n")

            local key=$(echo "$selected" | head -1)
            local choice=$(echo "$selected" | tail -1)

            if [[ "$key" == "ctrl-n" ]]; then
                echo -n "Nom de la nouvelle session: "
                read session_name
                [[ -z "$session_name" ]] && session_name="session-$(date +%H%M)"
                tmux new-session -s "$session_name"
                return
            fi

            [[ -z "$choice" ]] && return 0
            session_name="$choice"
        else
            echo "Sessions disponibles:"
            echo "$sessions" | nl
            echo -n "Numero ou nom (vide = nouvelle): "
            read choice
            if [[ -z "$choice" ]]; then
                session_name="session-$(date +%H%M)"
            elif [[ "$choice" =~ ^[0-9]+$ ]]; then
                session_name=$(echo "$sessions" | sed -n "${choice}p")
            else
                session_name="$choice"
            fi
        fi
    fi

    # Verifier si la session existe
    if tmux has-session -t "$session_name" 2>/dev/null; then
        # Attach (detach des autres clients si deja attache)
        if [[ -n "$TMUX" ]]; then
            tmux switch-client -t "$session_name"
        else
            tmux attach-session -t "$session_name"
        fi
    else
        # Creer la session
        echo "Creation de la session '$session_name'..."
        if [[ -n "$TMUX" ]]; then
            tmux new-session -d -s "$session_name"
            tmux switch-client -t "$session_name"
        else
            tmux new-session -s "$session_name"
        fi
    fi
}

# Liste les sessions tmux
tm-list() {
    _tmux_check || return 1

    local sessions=$(tmux list-sessions 2>/dev/null)

    if [[ -z "$sessions" ]]; then
        echo "Aucune session tmux active."
        return 0
    fi

    echo "Sessions tmux:"
    echo "──────────────────────────────────────────"
    tmux list-sessions -F "#{?session_attached,*  ,   }#{session_name} (#{session_windows} fenetres, cree #{t:session_created})"
    echo "──────────────────────────────────────────"
    echo "* = session attachee"
}

# Tue une session tmux
# Usage: tm-kill [session_name]
tm-kill() {
    _tmux_check || return 1

    local session_name="$1"

    # Selection interactive si pas d'argument
    if [[ -z "$session_name" ]]; then
        local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)

        if [[ -z "$sessions" ]]; then
            echo "Aucune session tmux active."
            return 0
        fi

        if command -v fzf &> /dev/null; then
            session_name=$(echo "$sessions" | fzf --header="Session a tuer" --prompt="Kill > ")
            [[ -z "$session_name" ]] && return 0
        else
            echo "Sessions disponibles:"
            echo "$sessions" | nl
            echo -n "Numero ou nom: "
            read choice
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                session_name=$(echo "$sessions" | sed -n "${choice}p")
            else
                session_name="$choice"
            fi
        fi
    fi

    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux kill-session -t "$session_name"
        echo "Session '$session_name' terminee."
    else
        echo "Session '$session_name' non trouvee." >&2
        return 1
    fi
}

# Tue toutes les sessions sauf celle en cours
tm-kill-others() {
    _tmux_check || return 1

    local current=""
    [[ -n "$TMUX" ]] && current=$(tmux display-message -p '#{session_name}')

    local killed=0
    for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null); do
        if [[ "$session" != "$current" ]]; then
            tmux kill-session -t "$session"
            ((killed++))
        fi
    done

    if [[ $killed -gt 0 ]]; then
        echo "$killed session(s) terminee(s)."
    else
        echo "Aucune autre session a terminer."
    fi
}

# Renomme la session courante
tm-rename() {
    _tmux_check || return 1

    if [[ -z "$TMUX" ]]; then
        echo "Pas dans une session tmux." >&2
        return 1
    fi

    local new_name="$1"
    if [[ -z "$new_name" ]]; then
        echo -n "Nouveau nom: "
        read new_name
    fi

    [[ -z "$new_name" ]] && return 0

    tmux rename-session "$new_name"
    echo "Session renommee en '$new_name'."
}

# Cree une session pour un projet (avec layout predetermine)
tm-project() {
    _tmux_check || return 1

    local project_dir="${1:-$PWD}"
    local session_name="${2:-$(basename "$project_dir")}"

    # Aller au dossier projet
    if [[ ! -d "$project_dir" ]]; then
        echo "Dossier non trouve: $project_dir" >&2
        return 1
    fi

    # Creer ou attacher
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "Session '$session_name' existe deja. Attachment..."
        tm "$session_name"
        return
    fi

    echo "Creation de la session projet '$session_name'..."

    # Creer session avec layout projet
    tmux new-session -d -s "$session_name" -c "$project_dir"

    # Fenetre 1: Editeur
    tmux rename-window -t "$session_name:1" "edit"

    # Fenetre 2: Terminal
    tmux new-window -t "$session_name" -n "term" -c "$project_dir"

    # Fenetre 3: Git/Logs
    tmux new-window -t "$session_name" -n "git" -c "$project_dir"

    # Revenir a la premiere fenetre
    tmux select-window -t "$session_name:1"

    # Attacher
    tm "$session_name"
}

# Aide
tm-help() {
    cat << 'EOF'
Tmux Manager - Commandes disponibles:

  tm [session]       Attach ou cree une session (interactif sans arg)
  tm-list            Liste les sessions actives
  tm-kill [session]  Tue une session (interactif sans arg)
  tm-kill-others     Tue toutes les sessions sauf celle en cours
  tm-rename [name]   Renomme la session courante
  tm-project [dir]   Cree une session avec layout projet

Raccourcis fzf (dans tm):
  ENTER     Attach a la session
  Ctrl-N    Creer une nouvelle session
EOF
}
