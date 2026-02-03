# =======================================================
# TEST RUNNER - Lanceur de tests unitaires
# =======================================================
# Usage: trun [options] [pattern]
#   -c, --coverage    Inclure la couverture de code
#   -o, --output      Fichier de sortie (défaut: stdout)
#   -r, --runner      Runner à utiliser (défaut: jest)
#   -v, --verbose     Mode verbeux (affiche tout)
#   -h, --help        Affiche l'aide
#
# Exemples:
#   trun                      # Lance tous les tests
#   trun -c                   # Avec couverture
#   trun -o report.txt        # Sortie dans un fichier
#   trun src/utils            # Tests matchant le pattern

trun() {
    local coverage=false
    local output_file=""
    local runner="jest"
    local verbose=false
    local pattern=""
    local tmp_file=$(mktemp)

    # Parse des arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--coverage) coverage=true; shift ;;
            -o|--output) output_file="$2"; shift 2 ;;
            -r|--runner) runner="$2"; shift 2 ;;
            -v|--verbose) verbose=true; shift ;;
            -h|--help) _trun_help; return 0 ;;
            -*) echo "Option inconnue: $1"; _trun_help; return 1 ;;
            *) pattern="$1"; shift ;;
        esac
    done

    # Vérification du runner
    if ! _trun_check_runner "$runner"; then
        return 1
    fi

    # Construction et exécution de la commande
    local cmd=$(_trun_build_cmd "$runner" "$coverage" "$pattern")

    if $verbose; then
        eval "$cmd" 2>&1 | tee "$tmp_file"
    else
        # Lancement avec spinner
        _trun_spinner "$runner" "$cmd" "$tmp_file"
    fi

    local exit_code=$?

    # Formatage de la sortie
    local result=$(_trun_format_output "$tmp_file" "$runner" "$coverage" "$exit_code")

    # Sortie
    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        echo "Rapport sauvegardé: $output_file"
    else
        echo "$result"
    fi

    rm -f "$tmp_file"
    return $exit_code
}

# Affiche l'aide
_trun_help() {
    cat << 'EOF'
trun - Lanceur de tests unitaires

Usage: trun [options] [pattern]

Options:
  -c, --coverage    Inclure la couverture de code
  -o, --output      Fichier de sortie (défaut: stdout)
  -r, --runner      Runner (jest|vitest|mocha) - défaut: jest
  -v, --verbose     Mode verbeux
  -h, --help        Affiche cette aide

Exemples:
  trun                      Tous les tests
  trun -c -o report.txt     Avec couverture, sortie fichier
  trun "auth"               Tests matchant "auth"
EOF
}

# Vérifie si le runner est disponible (local ou via npx)
_trun_check_runner() {
    local runner=$1

    # Vérifie qu'on est dans un projet npm
    if [[ ! -f "package.json" ]]; then
        echo "ERR: Aucun package.json trouvé dans $(pwd)"
        return 1
    fi

    case $runner in
        jest|vitest|mocha) ;;
        *)
            echo "ERR: Runner '$runner' non supporté (jest|vitest|mocha)"
            return 1
            ;;
    esac

    # Vérifie si le runner est dans les devDependencies ou dependencies
    if ! grep -qE "\"$runner\"" package.json 2>/dev/null; then
        echo "ERR: $runner non trouvé dans package.json"
        echo "     Installer avec: npm i -D $runner"
        return 1
    fi
    return 0
}

# Spinner pendant l'exécution des tests
_trun_spinner() {
    local runner=$1
    local cmd=$2
    local tmp_file=$3
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local pid

    # Lance la commande en arrière-plan
    eval "$cmd" > "$tmp_file" 2>&1 &
    pid=$!

    # Affiche le spinner
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r\033[K%s Tests en cours... (%s)" "${spinner:$i:1}" "$runner"
        i=$(( (i + 1) % ${#spinner} ))
        sleep 0.1
    done

    # Récupère le code de sortie
    wait $pid
    local exit_code=$?

    # Efface la ligne du spinner
    printf "\r\033[K"

    return $exit_code
}

# Vérifie si un script npm existe
_trun_has_npm_script() {
    local script=$1
    grep -q "\"$script\":" package.json 2>/dev/null
}

# Construit la commande de test
_trun_build_cmd() {
    local runner=$1
    local coverage=$2
    local pattern=$3
    local cmd=""
    local extra_args=""

    # Construit les arguments supplémentaires
    [[ -n "$pattern" ]] && extra_args="$extra_args '$pattern'"

    case $runner in
        jest)
            # Préfère npm run test si disponible
            if _trun_has_npm_script "test"; then
                cmd="npm run test --silent --"
                cmd="$cmd --no-colors"
                # Coverage souvent déjà dans le script, on force text-summary pour la sortie
                $coverage && cmd="$cmd --coverageReporters text-summary"
                ! $coverage && cmd="$cmd --coverage=false"
            else
                cmd="./node_modules/.bin/jest --no-colors"
                $coverage && cmd="$cmd --coverage --coverageReporters text-summary"
            fi
            [[ -n "$pattern" ]] && cmd="$cmd $extra_args"
            ;;
        vitest)
            if _trun_has_npm_script "test"; then
                cmd="npm run test --silent -- run --no-color"
                $coverage && cmd="$cmd --coverage"
            else
                cmd="./node_modules/.bin/vitest run --no-color"
                $coverage && cmd="$cmd --coverage"
            fi
            [[ -n "$pattern" ]] && cmd="$cmd $extra_args"
            ;;
        mocha)
            if _trun_has_npm_script "test"; then
                cmd="npm run test --silent -- --no-colors"
            else
                cmd="./node_modules/.bin/mocha --no-colors"
            fi
            $coverage && cmd="npx nyc --reporter=text-summary $cmd"
            [[ -n "$pattern" ]] && cmd="$cmd --grep $extra_args"
            ;;
    esac

    echo "$cmd"
}

# Formate la sortie pour être compacte et lisible
_trun_format_output() {
    local tmp_file=$1
    local runner=$2
    local coverage=$3
    local exit_code=$4

    # Filtre les messages parasites (reporters tiers, etc.)
    sed -i.bak -E '/Un-recognized argument|^\[.+\] +(exit|done)/d' "$tmp_file" 2>/dev/null
    rm -f "${tmp_file}.bak"

    local output=""
    local timestamp=$(date +%Y-%m-%d_%H:%M:%S)

    # En-tête compact
    if [[ $exit_code -eq 0 ]]; then
        output="[OK] $timestamp\n"
    else
        output="[FAIL] $timestamp\n"
    fi

    # Extraction des stats de tests
    case $runner in
        jest)
            # Stats: Tests: X passed, Y failed, Z total
            local stats=$(grep -E "^Tests:" "$tmp_file" | tail -1)
            [[ -n "$stats" ]] && output="$output$stats\n"

            # Erreurs uniquement
            if [[ $exit_code -ne 0 ]]; then
                output="$output\n--- ERREURS ---\n"
                # Capture les blocs d'erreur Jest
                output="$output$(sed -n '/● /,/^$/p' "$tmp_file" | head -100)\n"
            fi

            # Couverture si demandée
            if $coverage; then
                output="$output\n--- COUVERTURE ---\n"
                output="$output$(grep -A5 "Coverage summary" "$tmp_file" 2>/dev/null || echo "N/A")\n"
            fi
            ;;
        vitest)
            local stats=$(grep -E "Tests" "$tmp_file" | head -1)
            [[ -n "$stats" ]] && output="$output$stats\n"

            if [[ $exit_code -ne 0 ]]; then
                output="$output\n--- ERREURS ---\n"
                output="$output$(sed -n '/FAIL/,/^$/p' "$tmp_file" | head -100)\n"
            fi

            if $coverage; then
                output="$output\n--- COUVERTURE ---\n"
                output="$output$(grep -A5 "Coverage" "$tmp_file" 2>/dev/null || echo "N/A")\n"
            fi
            ;;
        mocha)
            local stats=$(grep -E "passing|failing" "$tmp_file")
            [[ -n "$stats" ]] && output="$output$stats\n"

            if [[ $exit_code -ne 0 ]]; then
                output="$output\n--- ERREURS ---\n"
                output="$output$(grep -A10 "failing" "$tmp_file" | head -100)\n"
            fi

            if $coverage; then
                output="$output\n--- COUVERTURE ---\n"
                output="$output$(grep -A5 "Coverage" "$tmp_file" 2>/dev/null || echo "N/A")\n"
            fi
            ;;
    esac

    echo -e "$output"
}
