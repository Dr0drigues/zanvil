# ==============================================================================
# ZSH Profile - Profiling du temps de demarrage du shell
# ==============================================================================
# Mesure le temps de chargement de chaque module pour identifier les lenteurs
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

# Profiling du startup complet
zsh-env-profile() {
    local verbose=false
    [[ "$1" == "-v" ]] && verbose=true

    _ui_header "ZSH_ENV Profiling"

    local total_start=$EPOCHREALTIME
    local results=()
    local total_time=0

    # Fonction pour mesurer le temps de source d'un fichier
    _profile_source() {
        local file="$1"
        local label="$2"

        if [[ -f "$file" ]]; then
            local start=$EPOCHREALTIME
            source "$file" 2>/dev/null
            local end=$EPOCHREALTIME
            local elapsed=$(( (end - start) * 1000 ))
            total_time=$(( total_time + elapsed ))
            results+=("$(printf "%6.1f ms  %s" "$elapsed" "$label")")
        fi
    }

    # Simuler le chargement dans l'ordre de rc.zsh
    local zsh_env_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}"

    # Config personnalisee
    _profile_source "$zsh_env_dir/config.zsh" "config.zsh"

    # Secrets
    _profile_source "$HOME/.secrets" "~/.secrets"

    # Variables
    _profile_source "$zsh_env_dir/variables.zsh" "variables.zsh"

    # Functions (le plus lourd generalement)
    if [[ -d "$zsh_env_dir/functions" ]]; then
        for func_file in "$zsh_env_dir/functions"/*.zsh(N); do
            local name=$(basename "$func_file")
            _profile_source "$func_file" "functions/$name"
        done
    fi

    # Aliases
    _profile_source "$zsh_env_dir/aliases.zsh" "aliases.zsh"

    # Plugins
    _profile_source "$zsh_env_dir/plugins.zsh" "plugins.zsh"

    # Completions
    _profile_source "$zsh_env_dir/completions.zsh" "completions.zsh"

    # Aliases locaux
    _profile_source "$zsh_env_dir/aliases.local.zsh" "aliases.local.zsh"

    local total_end=$EPOCHREALTIME
    local real_total=$(( (total_end - total_start) * 1000 ))

    # Trier par temps (decroissant)
    echo "Temps par fichier (trie par duree):"
    _ui_separator 44

    # Trier et afficher
    printf '%s\n' "${results[@]}" | sort -rn | while read -r line; do
        local time_val=${line%% *}
        # Colorer en rouge si > 50ms, jaune si > 20ms
        if (( time_val > 50 )); then
            echo -e "${_ui_red}$line${_ui_nc}"
        elif (( time_val > 20 )); then
            echo -e "${_ui_yellow}$line${_ui_nc}"
        else
            echo -e "${_ui_green}$line${_ui_nc}"
        fi
    done

    _ui_separator 44
    printf "Total mesure:  %6.1f ms\n" "$total_time"
    printf "Temps reel:    %6.1f ms\n" "$real_total"
    echo ""

    # Conseils
    if (( real_total > 500 )); then
        echo -e "${_ui_yellow}Conseil: Le demarrage est lent (>500ms).${_ui_nc}"
        echo "  - Desactivez les modules inutiles dans config.zsh"
    elif (( real_total > 200 )); then
        echo -e "${_ui_green}Le temps de demarrage est acceptable.${_ui_nc}"
    else
        echo -e "${_ui_green}Excellent! Demarrage rapide (<200ms).${_ui_nc}"
    fi
}

# Profiling rapide (juste le total)
zsh-env-profile-quick() {
    local start=$EPOCHREALTIME
    source "${ZSH_ENV_DIR:-$HOME/.zsh_env}/rc.zsh" 2>/dev/null
    local end=$EPOCHREALTIME
    local elapsed=$(( (end - start) * 1000 ))
    printf "Temps de chargement: %.1f ms\n" "$elapsed"
}

# Benchmark multiple runs
zsh-env-benchmark() {
    local runs=${1:-5}
    local times=()
    local sum=0

    _ui_header "ZSH_ENV Benchmark"

    echo "Benchmark sur $runs executions..."
    echo ""

    for ((i=1; i<=runs; i++)); do
        # Utiliser EPOCHREALTIME pour mesurer precisement
        local start=$EPOCHREALTIME
        zsh -i -c exit 2>/dev/null
        local end=$EPOCHREALTIME
        local time_ms=$(( (end - start) * 1000 ))
        times+=("$time_ms")
        sum=$(( sum + time_ms ))
        printf "  Run %d: %.0f ms\n" "$i" "$time_ms"
    done

    # Calculer moyenne
    local avg=$(( sum / runs ))

    echo ""
    _ui_separator 44
    printf "Moyenne: %.1f ms\n" "$avg"
}
