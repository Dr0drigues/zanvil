# ==============================================================================
# zanvil Bench - Profiling du temps de demarrage par module
# ==============================================================================
# Mesure le temps de chargement de chaque core/*.zsh et modules/*/init.zsh
# ==============================================================================

# Profiling detaille par composant
zanvil-bench() {
    local mode="detailed"
    local runs=5

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick|-q) mode="quick"; shift ;;
            --runs|-r) shift; runs="$1"; shift ;;
            -h|--help) _bench_help; return 0 ;;
            *) shift ;;
        esac
    done

    case "$mode" in
        quick)    _bench_quick ;;
        detailed) _bench_detailed ;;
    esac
}

# Benchmark multi-runs
zanvil-benchmark() {
    local runs=${1:-5}
    _bench_runs "$runs"
}

# ==============================================================================
# Profiling detaille
# ==============================================================================
_bench_detailed() {
    _ui_header "Zanvil Bench"

    local zanvil_dir="${ZANVIL_DIR:-$HOME/.zanvil}"
    local results=()
    local total_time=0

    # Fonction de mesure
    _bench_source() {
        local file="$1" label="$2"
        if [[ -f "$file" ]]; then
            local start=$EPOCHREALTIME
            source "$file" 2>/dev/null
            local end=$EPOCHREALTIME
            local elapsed=$(( (end - start) * 1000 ))
            total_time=$(( total_time + elapsed ))
            results+=("$(printf "%07.1f|%s" "$elapsed" "$label")")
        fi
    }

    local total_start=$EPOCHREALTIME

    # --- Phase 1 : Config & variables ---
    _ui_section "Phase" "config & variables"
    _bench_source "$zanvil_dir/config.zsh" "config.zsh"
    _bench_source "$HOME/.secrets" "~/.secrets"
    _bench_source "$zanvil_dir/core/variables.zsh" "core/variables.zsh"

    # --- Phase 2 : env.d ---
    for envfile in "$zanvil_dir/env.d"/*.zsh(N); do
        _bench_source "$envfile" "env.d/$(basename "$envfile")"
    done

    # --- Phase 3 : Core (ui.zsh first, then others) ---
    _bench_source "$zanvil_dir/core/ui.zsh" "core/ui.zsh"

    local skip_core=(rc.zsh loader.zsh ui.zsh variables.zsh aliases.zsh hooks.zsh)
    for core_file in "$zanvil_dir/core"/*.zsh(N); do
        local core_name=$(basename "$core_file")
        (( ${skip_core[(Ie)$core_name]} )) && continue
        _bench_source "$core_file" "core/$core_name"
    done

    # --- Phase 4 : Modules ---
    for module_dir in "$zanvil_dir/modules"/*/; do
        [[ ! -d "$module_dir" ]] && continue
        local module_name=$(basename "$module_dir")
        local init_file="$module_dir/init.zsh"

        # Skip lazy modules (stub only)
        if [[ -f "$module_dir/.lazy" ]]; then
            results+=("$(printf "%07.1f|%s" "0.0" "modules/$module_name (lazy)")")
            continue
        fi

        # Skip disabled modules
        local guard_var="ZANVIL_MODULE_${(U)module_name}"
        if [[ -n "${(P)guard_var}" && "${(P)guard_var}" != "true" ]]; then
            continue
        fi

        [[ -f "$init_file" ]] && _bench_source "$init_file" "modules/$module_name"
    done

    # --- Phase 5 : Aliases, plugins, hooks ---
    _bench_source "$zanvil_dir/core/aliases.zsh" "core/aliases.zsh"
    _bench_source "$zanvil_dir/plugins.zsh" "plugins.zsh"
    _bench_source "$zanvil_dir/core/hooks.zsh" "core/hooks.zsh"

    local total_end=$EPOCHREALTIME
    local real_total=$(( (total_end - total_start) * 1000 ))

    # --- Affichage ---
    echo ""
    printf "${_ui_bold}%-40s %8s  %s${_ui_nc}\n" "Composant" "Temps" ""
    _ui_separator 58

    # Trier par temps decroissant
    local sorted=($(printf '%s\n' "${results[@]}" | sort -rn))

    for entry in "${sorted[@]}"; do
        local time_val="${entry%%|*}"
        local label="${entry#*|}"
        local ms=$(printf "%.1f" "$time_val")

        # Barre horizontale proportionnelle
        local bar_len=0
        if (( real_total > 0 )); then
            bar_len=$(( (time_val * 20) / real_total ))
        fi
        (( bar_len < 0 )) && bar_len=0
        (( bar_len > 20 )) && bar_len=20
        local bar=$(printf '%*s' "$bar_len" '' | tr ' ' '█')
        local bar_empty=$(printf '%*s' "$(( 20 - bar_len ))" '' | tr ' ' '░')

        # Couleur selon le seuil
        local color="$_ui_green"
        if (( time_val > 50 )); then
            color="$_ui_red"
        elif (( time_val > 20 )); then
            color="$_ui_yellow"
        fi

        printf "  %-38s ${color}%6.1f ms${_ui_nc}  ${color}%s${_ui_nc}${_ui_dim}%s${_ui_nc}\n" \
            "$label" "$ms" "$bar" "$bar_empty"
    done

    echo ""
    _ui_separator 58
    printf "${_ui_bold}Total mesure:${_ui_nc}  %6.1f ms\n" "$total_time"
    printf "${_ui_bold}Temps reel:${_ui_nc}    %6.1f ms\n" "$real_total"
    echo ""

    # Conseils
    if (( real_total > 500 )); then
        _ui_msg_warn "Demarrage lent (>500ms). Desactivez les modules inutiles dans config.zsh"
    elif (( real_total > 200 )); then
        _ui_msg_info "Temps acceptable ($(printf '%.0f' "$real_total")ms)"
    else
        _ui_msg_ok "Excellent! Demarrage rapide (<200ms)"
    fi
}

# ==============================================================================
# Quick : juste le total
# ==============================================================================
_bench_quick() {
    local start=$EPOCHREALTIME
    zsh -i -c exit 2>/dev/null
    local end=$EPOCHREALTIME
    local elapsed=$(( (end - start) * 1000 ))
    printf "${_ui_bold}Temps de chargement:${_ui_nc} %.0f ms\n" "$elapsed"
}

# ==============================================================================
# Multi-runs benchmark
# ==============================================================================
_bench_runs() {
    local runs=${1:-5}

    _ui_header "Zanvil Benchmark"
    _ui_section "Runs" "$runs"
    echo ""

    local times=()
    local sum=0
    local min=999999 max=0

    for ((i=1; i<=runs; i++)); do
        local start=$EPOCHREALTIME
        zsh -i -c exit 2>/dev/null
        local end=$EPOCHREALTIME
        local ms=$(( (end - start) * 1000 ))
        times+=("$ms")
        sum=$(( sum + ms ))
        (( ms < min )) && min=$ms
        (( ms > max )) && max=$ms

        # Barre de progression
        local pct=$(( (i * 100) / runs ))
        local bar_len=$(( (i * 20) / runs ))
        local bar=$(printf '%*s' "$bar_len" '' | tr ' ' '█')
        local bar_empty=$(printf '%*s' "$(( 20 - bar_len ))" '' | tr ' ' '░')
        printf "\r  ${_ui_dim}[%s%s]${_ui_nc} Run %d/%d: %6.0f ms" "$bar" "$bar_empty" "$i" "$runs" "$ms"
    done

    echo ""
    echo ""

    # Stats
    local avg=$(( sum / runs ))

    # Trier pour p95
    local sorted_times=($(printf '%s\n' "${times[@]}" | sort -n))
    local p95_idx=$(( (runs * 95 + 99) / 100 ))
    (( p95_idx > runs )) && p95_idx=$runs
    local p95=${sorted_times[$p95_idx]}

    _ui_separator 44
    printf "  ${_ui_dim}%-12s${_ui_nc} ${_ui_green}%6.0f ms${_ui_nc}\n" "Min" "$min"
    printf "  ${_ui_dim}%-12s${_ui_nc} ${_ui_bold}%6.0f ms${_ui_nc}\n" "Moyenne" "$avg"
    printf "  ${_ui_dim}%-12s${_ui_nc} ${_ui_yellow}%6.0f ms${_ui_nc}\n" "P95" "$p95"
    printf "  ${_ui_dim}%-12s${_ui_nc} ${_ui_red}%6.0f ms${_ui_nc}\n" "Max" "$max"
}

# ==============================================================================
# Aide
# ==============================================================================
_bench_help() {
    _ui_header "Zanvil Bench"
    echo ""
    printf "${_ui_bold}Usage:${_ui_nc}\n"
    echo "  zanvil-bench                 Profiling detaille par module"
    echo "  zanvil-bench --quick         Temps total uniquement"
    echo "  zanvil-bench --runs N        Benchmark sur N executions (defaut: 5)"
    echo "  zanvil-benchmark [N]         Alias pour --runs N"
}
