# ==============================================================================
# AI Tokens Optimizer - Estimation et optimisation des tokens pour LLMs
# ==============================================================================
# Estime les tokens, compresse le contexte, selectionne les fichiers pertinents
# ==============================================================================

# Configuration
AI_TOKENS_CHARS_PER_TOKEN=4  # Approximation moyenne (ajustable)

# Patterns a ignorer par defaut
AI_TOKENS_IGNORE_DIRS=(
    "node_modules" ".git" ".svn" ".hg"
    "dist" "build" "out" "target"
    ".next" ".nuxt" ".output"
    "__pycache__" ".pytest_cache" ".mypy_cache"
    "vendor" "deps" "_build"
    ".idea" ".vscode" ".vs"
    "coverage" ".nyc_output"
    "tmp" "temp" "cache"
)

AI_TOKENS_IGNORE_FILES=(
    "*.min.js" "*.min.css" "*.map"
    "*.lock" "package-lock.json" "yarn.lock" "pnpm-lock.yaml"
    "*.log" "*.pid"
    "*.pyc" "*.pyo" "*.class"
    "*.so" "*.dylib" "*.dll" "*.exe"
    "*.jpg" "*.jpeg" "*.png" "*.gif" "*.ico" "*.svg" "*.webp"
    "*.mp3" "*.mp4" "*.wav" "*.avi"
    "*.zip" "*.tar" "*.gz" "*.rar" "*.7z"
    "*.woff" "*.woff2" "*.ttf" "*.eot"
    "*.pdf" "*.doc" "*.docx"
)

# Extensions prioritaires (poids pour le scoring)
typeset -A AI_TOKENS_PRIORITY
AI_TOKENS_PRIORITY=(
    [md]=10 [txt]=5
    [ts]=9 [tsx]=9 [js]=8 [jsx]=8
    [py]=9 [rs]=9 [go]=9
    [java]=8 [kt]=8 [scala]=8
    [c]=7 [cpp]=7 [h]=7 [hpp]=7
    [rb]=8 [php]=7
    [sh]=6 [zsh]=6 [bash]=6
    [yml]=7 [yaml]=7 [json]=6 [toml]=7
    [sql]=6 [graphql]=7
    [html]=5 [css]=5 [scss]=5
    [vue]=8 [svelte]=8
)

# Prix par million de tokens (input) - Janvier 2024
typeset -A AI_TOKENS_PRICES
AI_TOKENS_PRICES=(
    [gpt-4-turbo]=10.00
    [gpt-4]=30.00
    [gpt-3.5-turbo]=0.50
    [claude-3-opus]=15.00
    [claude-3-sonnet]=3.00
    [claude-3-haiku]=0.25
    [claude-3.5-sonnet]=3.00
)

# ==============================================================================
# ESTIMATION DE TOKENS
# ==============================================================================

# Estime le nombre de tokens pour une chaine
_ai_estimate_tokens_string() {
    local text="$1"
    local char_count=${#text}

    # Approximation: ~4 caracteres = 1 token (ajuste pour le code)
    # Le code a tendance a avoir plus de tokens par caractere
    local tokens=$(( (char_count + AI_TOKENS_CHARS_PER_TOKEN - 1) / AI_TOKENS_CHARS_PER_TOKEN ))

    # Ajustement pour les tokens speciaux (newlines, etc.)
    local newlines=$(echo "$text" | wc -l)
    tokens=$(( tokens + newlines / 2 ))

    echo "$tokens"
}

# Estime les tokens d'un fichier
_ai_estimate_tokens_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi

    local content=$(cat "$file" 2>/dev/null)
    _ai_estimate_tokens_string "$content"
}

# Estime les tokens avec details
ai_tokens_estimate() {
    local target="${1:--}"
    local total_tokens=0
    local total_chars=0
    local file_count=0

    # Mode pipe/stdin
    if [[ "$target" == "-" ]]; then
        local content=$(cat)
        local tokens=$(_ai_estimate_tokens_string "$content")
        local chars=${#content}

        echo "Estimation (stdin):"
        echo "==================="
        echo "  Caracteres: $chars"
        echo "  Tokens:     ~$tokens"
        echo ""
        _ai_print_cost_estimates "$tokens"
        return 0
    fi

    # Mode fichier unique
    if [[ -f "$target" ]]; then
        local tokens=$(_ai_estimate_tokens_file "$target")
        local chars=$(wc -c < "$target" | tr -d ' ')

        echo "Estimation: $target"
        echo "==================="
        echo "  Caracteres: $chars"
        echo "  Tokens:     ~$tokens"
        echo ""
        _ai_print_cost_estimates "$tokens"
        return 0
    fi

    # Mode dossier
    if [[ -d "$target" ]]; then
        ai_tokens_analyze "$target"
        return 0
    fi

    echo "Cible non trouvee: $target" >&2
    return 1
}

# Affiche les estimations de cout
_ai_print_cost_estimates() {
    local tokens="$1"
    local millions=$(echo "scale=6; $tokens / 1000000" | bc)

    echo "Cout estime (input):"
    echo "--------------------"

    for model in "claude-3.5-sonnet" "claude-3-haiku" "gpt-4-turbo" "gpt-3.5-turbo"; do
        local price=${AI_TOKENS_PRICES[$model]}
        local cost=$(echo "scale=4; $millions * $price" | bc)
        printf "  %-20s \$%.4f\n" "$model:" "$cost"
    done
}

# ==============================================================================
# ANALYSE DE PROJET
# ==============================================================================

# Analyse un projet et donne des stats detaillees
ai_tokens_analyze() {
    local dir="${1:-$PWD}"
    local show_files="${2:-true}"

    echo "Analyse: $dir"
    echo "=========================================="
    echo ""

    # Construire la commande find avec exclusions
    local find_excludes=""
    for d in "${AI_TOKENS_IGNORE_DIRS[@]}"; do
        find_excludes="$find_excludes -path '*/$d' -prune -o"
    done

    # Collecter les fichiers
    local files=()
    local file_tokens=()
    local file_chars=()
    local total_tokens=0
    local total_chars=0
    local large_count=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Verifier si le fichier doit etre ignore
        local skip=false
        for pattern in "${AI_TOKENS_IGNORE_FILES[@]}"; do
            if [[ "${file:t}" == $~pattern ]]; then
                skip=true
                break
            fi
        done
        $skip && continue

        # Estimer les tokens
        local tokens=$(_ai_estimate_tokens_file "$file")
        local chars=$(wc -c < "$file" 2>/dev/null | tr -d ' ')

        files+=("$file")
        file_tokens+=("$tokens")
        file_chars+=("$chars")

        total_tokens=$((total_tokens + tokens))
        total_chars=$((total_chars + chars))

        # Compter les fichiers volumineux
        [[ $tokens -gt 5000 ]] && ((large_count++))

    done < <(eval "find \"$dir\" $find_excludes -type f -print 2>/dev/null")

    local file_count=${#files[@]}

    # Afficher le resume
    echo "Resume:"
    echo "-------"
    printf "  Fichiers analyses: %d\n" "$file_count"
    printf "  Caracteres total:  %'d\n" "$total_chars"
    printf "  Tokens estimes:    ~%'d\n" "$total_tokens"
    echo ""

    # Top 10 fichiers les plus gros
    if [[ "$show_files" == "true" && $file_count -gt 0 ]]; then
        echo "Top 10 fichiers (par tokens):"
        echo "-----------------------------"

        # Trier par tokens (simulation avec paste)
        local i=1
        local sorted_indices=()

        # Creer un tableau associatif pour trier
        for ((i=1; i<=${#files[@]}; i++)); do
            echo "${file_tokens[$i]}|$i|${files[$i]}"
        done | sort -t'|' -k1 -rn | head -10 | while IFS='|' read -r tokens idx filepath; do
            local relpath="${filepath#$dir/}"
            printf "  %'8d tokens  %s\n" "$tokens" "$relpath"
        done

        echo ""
    fi

    # Cout estime
    _ai_print_cost_estimates "$total_tokens"
    echo ""

    # Suggestions
    _ai_print_suggestions "$dir" "$total_tokens" "${large_count:-0}"
}

# Affiche des suggestions d'optimisation
_ai_print_suggestions() {
    local dir="$1"
    local total_tokens="$2"
    local large_files="${3:-0}"

    echo "Suggestions d'optimisation:"
    echo "---------------------------"

    local suggestions=()

    # Fichiers volumineux
    if [[ $large_files -gt 0 ]]; then
        suggestions+=("  - $large_files fichier(s) > 5000 tokens: envisagez de les resumer ou exclure")
    fi

    # Lock files
    if [[ -f "$dir/package-lock.json" || -f "$dir/yarn.lock" || -f "$dir/pnpm-lock.yaml" ]]; then
        suggestions+=("  - Excluez les fichiers lock (package-lock.json, yarn.lock)")
    fi

    # Fichiers de config volumineux
    if [[ -f "$dir/tsconfig.json" ]] && [[ $(_ai_estimate_tokens_file "$dir/tsconfig.json") -gt 500 ]]; then
        suggestions+=("  - tsconfig.json est volumineux: incluez seulement si pertinent")
    fi

    # Seuil general
    if [[ $total_tokens -gt 50000 ]]; then
        suggestions+=("  - Contexte volumineux (>50k tokens): utilisez 'ai-tokens select' pour filtrer")
    fi

    if [[ $total_tokens -gt 100000 ]]; then
        suggestions+=("  - >100k tokens: utilisez 'ai-tokens export --max-tokens=50000' pour limiter")
    fi

    if [[ ${#suggestions[@]} -eq 0 ]]; then
        echo "  Aucune suggestion - le contexte semble optimise."
    else
        printf '%s\n' "${suggestions[@]}"
    fi
}

# ==============================================================================
# COMPRESSION DE CONTEXTE
# ==============================================================================

# Compresse le contenu (supprime commentaires, espaces excessifs)
_ai_compress_content() {
    local content="$1"
    local lang="${2:-auto}"

    # Detecter le langage si auto
    if [[ "$lang" == "auto" ]]; then
        # Sera detecte par l'extension dans la fonction appelante
        lang="generic"
    fi

    local compressed="$content"

    case "$lang" in
        js|ts|jsx|tsx|java|c|cpp|go|rust|php)
            # Supprimer commentaires single-line //
            compressed=$(echo "$compressed" | sed 's|//.*$||g')
            # Supprimer commentaires multi-line /* */
            compressed=$(echo "$compressed" | perl -0pe 's|/\*.*?\*/||gs' 2>/dev/null || echo "$compressed")
            ;;
        py|python)
            # Supprimer commentaires #
            compressed=$(echo "$compressed" | sed 's|#.*$||g')
            # Supprimer docstrings (basique)
            compressed=$(echo "$compressed" | perl -0pe 's|""".*?"""|""|gs' 2>/dev/null || echo "$compressed")
            ;;
        sh|bash|zsh)
            # Supprimer commentaires #
            compressed=$(echo "$compressed" | sed 's|#.*$||g')
            ;;
        html|xml)
            # Supprimer commentaires <!-- -->
            compressed=$(echo "$compressed" | perl -0pe 's|<!--.*?-->||gs' 2>/dev/null || echo "$compressed")
            ;;
    esac

    # Reductions generales
    # Supprimer lignes vides multiples
    compressed=$(echo "$compressed" | cat -s)
    # Supprimer espaces en fin de ligne
    compressed=$(echo "$compressed" | sed 's/[[:space:]]*$//')
    # Reduire indentation excessive (>8 espaces -> 2)
    compressed=$(echo "$compressed" | sed 's/^[[:space:]]\{8,\}/  /')

    echo "$compressed"
}

# Compresse un fichier ou stdin
ai_tokens_compress() {
    local target="${1:--}"
    local lang="${2:-auto}"

    local content
    local original_tokens
    local compressed_tokens

    if [[ "$target" == "-" ]]; then
        content=$(cat)
    elif [[ -f "$target" ]]; then
        content=$(cat "$target")
        # Detecter le langage par extension
        local ext="${target:e}"
        [[ "$lang" == "auto" ]] && lang="$ext"
    else
        echo "Fichier non trouve: $target" >&2
        return 1
    fi

    original_tokens=$(_ai_estimate_tokens_string "$content")

    local compressed=$(_ai_compress_content "$content" "$lang")
    compressed_tokens=$(_ai_estimate_tokens_string "$compressed")

    local saved=$((original_tokens - compressed_tokens))
    local percent=0
    [[ $original_tokens -gt 0 ]] && percent=$((saved * 100 / original_tokens))

    # Afficher stats sur stderr, contenu sur stdout
    echo "# Compression: $original_tokens -> $compressed_tokens tokens (-$saved, -${percent}%)" >&2
    echo "$compressed"
}

# ==============================================================================
# SELECTION INTELLIGENTE
# ==============================================================================

# Selectionne les fichiers pertinents pour une tache
ai_tokens_select() {
    local dir="${1:-$PWD}"
    local query="${2:-}"
    local max_tokens="${3:-100000}"

    echo "Selection intelligente: $dir"
    echo "Query: ${query:-<aucune>}"
    echo "Max tokens: $max_tokens"
    echo "=========================================="
    echo ""

    # Construire la liste des fichiers avec scoring
    local -A file_scores
    local -A file_tokens

    # Fichiers a ignorer
    local find_excludes=""
    for d in "${AI_TOKENS_IGNORE_DIRS[@]}"; do
        find_excludes="$find_excludes -path '*/$d' -prune -o"
    done

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Verifier patterns ignores
        local skip=false
        for pattern in "${AI_TOKENS_IGNORE_FILES[@]}"; do
            [[ "${file:t}" == $~pattern ]] && skip=true && break
        done
        $skip && continue

        # Calculer le score
        local ext="${file:e}"
        local base_score=${AI_TOKENS_PRIORITY[$ext]:-3}
        local score=$base_score

        # Bonus pour fichiers racine
        [[ "${file:h}" == "$dir" ]] && score=$((score + 2))

        # Bonus pour fichiers de config importants
        local filename="${file:t}"
        case "$filename" in
            README*|CLAUDE.md|package.json|Cargo.toml|go.mod|pyproject.toml)
                score=$((score + 5))
                ;;
            *.config.*|*.conf|config.*)
                score=$((score + 2))
                ;;
        esac

        # Bonus si match avec la query
        if [[ -n "$query" ]]; then
            if grep -qi "$query" "$file" 2>/dev/null; then
                score=$((score + 10))
            fi
            if [[ "$file" == *"$query"* ]]; then
                score=$((score + 5))
            fi
        fi

        # Malus pour tests si pas dans la query
        if [[ "$file" == *test* || "$file" == *spec* ]] && [[ "$query" != *test* ]]; then
            score=$((score - 3))
        fi

        file_scores[$file]=$score
        file_tokens[$file]=$(_ai_estimate_tokens_file "$file")

    done < <(eval "find \"$dir\" $find_excludes -type f -print 2>/dev/null")

    # Trier par score et selectionner
    local selected_files=()
    local selected_tokens=0

    # Afficher et selectionner
    echo "Fichiers selectionnes (par pertinence):"
    echo "----------------------------------------"

    for file in ${(Ok)file_scores}; do
        local tokens=${file_tokens[$file]}
        local score=${file_scores[$file]}

        if [[ $((selected_tokens + tokens)) -le $max_tokens ]]; then
            selected_files+=("$file")
            selected_tokens=$((selected_tokens + tokens))

            local relpath="${file#$dir/}"
            printf "  [%2d] %'6d tokens  %s\n" "$score" "$tokens" "$relpath"
        fi
    done | sort -t'[' -k2 -rn | head -50

    echo ""
    echo "----------------------------------------"
    printf "Total selectionne: %'d tokens (%d fichiers)\n" "$selected_tokens" "${#selected_files[@]}"
    echo ""

    # Proposer d'exporter
    echo "Commandes utiles:"
    echo "  ai-tokens export $dir > context.txt   # Exporter le contexte"
    echo "  ai-tokens export $dir --compress      # Exporter compresse"
}

# Exporte le contexte selectionne
ai_tokens_export() {
    local dir="${1:-$PWD}"
    local compress=false
    local max_tokens=100000

    # Parser les arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --compress|-c) compress=true ;;
            --max-tokens=*) max_tokens="${1#*=}" ;;
            --max-tokens) max_tokens="$2"; shift ;;
        esac
        shift
    done

    # Header
    echo "# Context Export: $(basename "$dir")"
    echo "# Generated: $(date -Iseconds)"
    echo "# Directory: $dir"
    echo ""

    # Construire la liste des fichiers avec scoring (meme logique que select)
    local find_excludes=""
    for d in "${AI_TOKENS_IGNORE_DIRS[@]}"; do
        find_excludes="$find_excludes -path '*/$d' -prune -o"
    done

    local current_tokens=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local skip=false
        for pattern in "${AI_TOKENS_IGNORE_FILES[@]}"; do
            [[ "${file:t}" == $~pattern ]] && skip=true && break
        done
        $skip && continue

        local tokens=$(_ai_estimate_tokens_file "$file")

        if [[ $((current_tokens + tokens)) -gt $max_tokens ]]; then
            echo "# ... (truncated at $max_tokens tokens)" >&2
            break
        fi

        local relpath="${file#$dir/}"
        echo "## File: $relpath"
        echo '```'"${file:e}"

        if $compress; then
            _ai_compress_content "$(cat "$file")" "${file:e}"
        else
            cat "$file"
        fi

        echo '```'
        echo ""

        current_tokens=$((current_tokens + tokens))

    done < <(eval "find \"$dir\" $find_excludes -type f -print 2>/dev/null" | head -100)

    echo "# Total: ~$current_tokens tokens" >&2
}

# ==============================================================================
# COMMANDES PRINCIPALES
# ==============================================================================

ai_tokens_help() {
    cat << 'EOF'
AI Tokens Optimizer - Estimation et optimisation des tokens

Usage:
  ai-tokens estimate [file|dir|-]  Estime les tokens (- pour stdin)
  ai-tokens analyze [dir]          Analyse detaillee d'un projet
  ai-tokens compress [file|-]      Compresse le contenu (supprime commentaires)
  ai-tokens select [dir] [query]   Selectionne les fichiers pertinents
  ai-tokens export [dir] [opts]    Exporte le contexte optimise
  ai-tokens help                   Affiche cette aide

Options d'export:
  --compress, -c          Compresse le contenu
  --max-tokens=N          Limite a N tokens (defaut: 100000)

Exemples:
  ai-tokens estimate src/           # Estime tokens du dossier src
  cat file.ts | ai-tokens estimate  # Estime depuis stdin
  ai-tokens analyze .               # Analyse le projet courant
  ai-tokens compress src/index.ts   # Compresse un fichier
  ai-tokens select . "auth"         # Fichiers lies a "auth"
  ai-tokens export . --compress     # Exporte contexte compresse

Modeles supportes (estimation cout):
  - Claude 3.5 Sonnet, Claude 3 Opus/Haiku
  - GPT-4 Turbo, GPT-3.5 Turbo
EOF
}

# Fonction principale
ai-tokens() {
    local cmd="${1:-help}"
    shift 2>/dev/null

    case "$cmd" in
        estimate|est|e)
            ai_tokens_estimate "$@"
            ;;
        analyze|analyse|a)
            ai_tokens_analyze "$@"
            ;;
        compress|comp|c)
            ai_tokens_compress "$@"
            ;;
        select|sel|s)
            ai_tokens_select "$@"
            ;;
        export|exp|x)
            ai_tokens_export "$@"
            ;;
        help|h|--help|-h)
            ai_tokens_help
            ;;
        *)
            echo "Commande inconnue: $cmd" >&2
            ai_tokens_help
            return 1
            ;;
    esac
}

# Alias court
alias ait='ai-tokens'
