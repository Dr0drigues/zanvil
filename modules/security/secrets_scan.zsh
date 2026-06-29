[[ "${ZANVIL_MODULE_SECURITY:-true}" != "true" ]] && return 0

# ==============================================================================
# Secrets Scan - Detection de secrets dans les repos Git
# ==============================================================================
# Scanne le working tree ou l'historique git pour detecter des secrets leakes
# Respecte .gitignore par defaut dans les repos Git (via git grep)
# ==============================================================================

# Globs globaux (modifies par --include / --exclude)
typeset -ga _secrets_include_globs
typeset -ga _secrets_exclude_globs

zanvil-secrets-scan() {
    local target_dir="."
    local mode="current"
    local bulk=false
    _secrets_include_globs=()
    _secrets_exclude_globs=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --history)  mode="history"; shift ;;
            --current)  mode="current"; shift ;;
            --bulk)     bulk=true; shift ;;
            --include)  shift; _secrets_include_globs+=("$1"); shift ;;
            --exclude)  shift; _secrets_exclude_globs+=("$1"); shift ;;
            -d)         shift; target_dir="$1"; shift ;;
            -h|--help)  _secrets_scan_help; return 0 ;;
            *)
                if [[ -d "$1" ]]; then
                    target_dir="$1"
                fi
                shift
                ;;
        esac
    done

    target_dir=$(cd "$target_dir" 2>/dev/null && pwd) || {
        _ui_msg_fail "Dossier introuvable: $target_dir"
        return 1
    }

    if [[ "$bulk" == "true" ]]; then
        _secrets_scan_bulk "$target_dir" "$mode"
    else
        _secrets_scan_repo "$target_dir" "$mode"
    fi
}

# ==============================================================================
# Patterns de detection
# ==============================================================================
_secrets_patterns() {
    cat <<'PATTERNS'
AWS Access Key|AKIA[0-9A-Z]{16}
AWS Secret Key|aws_secret_access_key\s*[:=]\s*[A-Za-z0-9/+=]{40}
Private Key|-----BEGIN (RSA|EC|OPENSSH|DSA|PGP) PRIVATE KEY-----
GitHub Token|gh[ps]_[A-Za-z0-9_]{36,}
GitHub PAT|github_pat_[A-Za-z0-9_]{82,}
GitLab Token|glpat-[A-Za-z0-9_\-]{20,}
Generic Token|(token|api_key|apikey|secret_key|secretkey)\s*[:=]\s*['"][^'"]{8,}['"]
Generic Password|(password|passwd|pwd)\s*[:=]\s*['"][^'"]{8,}['"]
Azure Key|(AccountKey|SharedAccessKey|SharedAccessKeyName)\s*=\s*[A-Za-z0-9+/=]{20,}
Slack Token|xox[bporas]-[0-9A-Za-z\-]{10,}
JWT|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
Connection String|(mongodb|postgres|mysql|redis)://[^\s'"]{10,}
PATTERNS
}

# ==============================================================================
# Moteur de grep : rg (ripgrep) > git grep > grep
# rg respecte .gitignore nativement et est le plus rapide
# ==============================================================================
_secrets_grep() {
    local pattern="$1" dir="$2"

    if command -v rg &>/dev/null; then
        # ripgrep : respecte .gitignore, rapide, globs natifs
        local -a args=(-n --no-heading --color=never -e "$pattern")

        # Includes
        for g in "${_secrets_include_globs[@]}"; do
            args+=("--glob" "$g")
        done

        # Exclusions par defaut (binaires, generes)
        local -a default_excludes=('*.min.js' '*.min.css' '*.map' '*.lock'
            'package-lock.json' 'yarn.lock' '*.wasm' '*.svg' '*.zip' '*.tar.gz')

        for ex in "${default_excludes[@]}"; do
            args+=("--glob" "!$ex")
        done

        # Exclusions custom
        for g in "${_secrets_exclude_globs[@]}"; do
            args+=("--glob" "!$g")
        done

        rg "${args[@]}" "$dir" 2>/dev/null

    elif git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        # Fallback git grep : respecte .gitignore
        local -a args=(-rnE "$pattern")
        local -a pathspecs=()

        for g in "${_secrets_include_globs[@]}"; do
            pathspecs+=("$g")
        done

        local -a default_excludes=('*.min.js' '*.min.css' '*.map' '*.lock'
            'package-lock.json' 'yarn.lock' '*.wasm' '*.svg' '*.zip' '*.tar.gz')

        for ex in "${default_excludes[@]}"; do
            pathspecs+=(":!$ex")
        done
        for g in "${_secrets_exclude_globs[@]}"; do
            pathspecs+=(":!$g")
        done

        if [[ ${#pathspecs[@]} -gt 0 ]]; then
            args+=("--" "${pathspecs[@]}")
        fi

        git -C "$dir" grep "${args[@]}" 2>/dev/null
    else
        # Fallback grep
        local -a args=(-rnE "$pattern"
            --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git
            --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__
            --exclude-dir=target
            --exclude='*.min.js' --exclude='*.min.css' --exclude='*.map'
            --exclude='*.lock' --exclude='*.wasm')

        for g in "${_secrets_include_globs[@]}"; do
            args+=("--include=$g")
        done
        for g in "${_secrets_exclude_globs[@]}"; do
            args+=("--exclude=$g")
        done

        grep "${args[@]}" "$dir" 2>/dev/null
    fi
}

# Compteur de matches (pour le mode bulk)
_secrets_grep_count() {
    local pattern="$1" dir="$2"
    _secrets_grep "$pattern" "$dir" | wc -l | tr -d ' '
}

# ==============================================================================
# Masquer la valeur du secret
# ==============================================================================
_secrets_mask() {
    local value="$1"
    local len=${#value}
    if (( len <= 8 )); then
        echo "****"
    else
        echo "${value:0:4}...${value: -4}"
    fi
}

# ==============================================================================
# Scan d'un repo unique
# ==============================================================================
_secrets_scan_repo() {
    local dir="$1" mode="$2"
    local findings=0

    _ui_header "Secrets Scan"
    _ui_section "Dossier" "$dir"
    _ui_section "Mode" "$mode"
    # Afficher les filtres actifs
    if [[ ${#_secrets_include_globs[@]} -gt 0 ]]; then
        _ui_section "Include" "${(j:, :)_secrets_include_globs}"
    fi
    if [[ ${#_secrets_exclude_globs[@]} -gt 0 ]]; then
        _ui_section "Exclude" "${(j:, :)_secrets_exclude_globs}"
    fi
    # Indiquer le moteur et le respect de .gitignore
    if command -v rg &>/dev/null; then
        _ui_section "Moteur" "ripgrep (.gitignore respecte)"
    elif git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        _ui_section "Moteur" "git grep (.gitignore respecte)"
    else
        _ui_section "Moteur" "grep (exclusions par defaut)"
    fi
    echo ""

    if [[ "$mode" == "current" ]]; then
        _secrets_scan_working_tree "$dir"
        findings=$?
    else
        _secrets_scan_history "$dir"
        findings=$?
    fi

    echo ""
    _ui_separator 64

    if [[ $findings -gt 0 ]]; then
        printf "${_ui_red}%d${_ui_nc} secret(s) detecte(s)\n" "$findings"
        echo ""
        _ui_msg_warn "Verifiez ces resultats — certains peuvent etre des faux positifs"
        _ui_msg_info "Utilisez 'git filter-repo' pour supprimer les secrets de l'historique"
    else
        _ui_msg_ok "Aucun secret detecte"
    fi

    return $findings
}

# ==============================================================================
# Scan du working tree
# ==============================================================================
_secrets_scan_working_tree() {
    local dir="$1"
    local tmpfile=$(mktemp)

    printf "${_ui_bold}%-40s %-16s %s${_ui_nc}\n" "Fichier" "Type" "Valeur"
    _ui_separator 64

    # Phase 1 : collecter tous les matches annotes dans un fichier temp
    while IFS='|' read -r label pattern; do
        [[ -z "$label" || "$label" == \#* ]] && continue
        _secrets_grep "$pattern" "$dir" | while IFS= read -r line; do
            local val=$(echo "${line#*:*:}" | grep -oE "$pattern" 2>/dev/null | head -1)
            printf '%s\t%s\t%s\n' "$label" "$line" "$val"
        done >> "$tmpfile"
    done < <(_secrets_patterns)

    # Phase 2 : afficher les resultats (dedup par fichier:ligne)
    local findings=0
    typeset -A seen

    while IFS=$'\t' read -r label match_line matched_val; do
        [[ -z "$match_line" ]] && continue

        local file="${match_line%%:*}"
        local rest="${match_line#*:}"
        local lineno="${rest%%:*}"
        local key="${file}:${lineno}"

        [[ -n "${seen[$key]}" ]] && continue
        seen[$key]=1

        local relpath="${file#$dir/}"
        local masked=$(_secrets_mask "$matched_val")

        printf "  ${_ui_yellow}%-38s${_ui_nc} ${_ui_red}%-16s${_ui_nc} ${_ui_dim}%s${_ui_nc}\n" \
            "${relpath}:${lineno}" "$label" "$masked"
        ((findings++))
    done < "$tmpfile"

    rm -f "$tmpfile"
    return $findings
}

# ==============================================================================
# Scan de l'historique git
# ==============================================================================
_secrets_scan_history() {
    local dir="$1"

    if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        _ui_msg_fail "Pas un repo Git: $dir"
        return 0
    fi

    _ui_msg_info "Scan de l'historique git (peut prendre du temps)..."
    echo ""

    printf "${_ui_bold}%-20s %-16s %s${_ui_nc}\n" "Commit" "Type" "Valeur"
    _ui_separator 54

    local tmpfile=$(mktemp)
    local findings=0

    # Construire les pathspecs d'exclusion pour git log
    local -a pathspecs=(':!*.min.js' ':!*.lock' ':!package-lock.json' ':!yarn.lock')
    for g in "${_secrets_exclude_globs[@]}"; do
        pathspecs+=(":!$g")
    done
    # Includes : si definis, limiter a ces globs
    local -a include_specs=()
    for g in "${_secrets_include_globs[@]}"; do
        include_specs+=("$g")
    done

    while IFS='|' read -r label pattern; do
        [[ -z "$label" || "$label" == \#* ]] && continue

        local -a log_args=(log --all -p -G "$pattern" --format="COMMIT:%h" --)
        if [[ ${#include_specs[@]} -gt 0 ]]; then
            log_args+=("${include_specs[@]}" "${pathspecs[@]}")
        else
            log_args+=("${pathspecs[@]}")
        fi

        git -C "$dir" "${log_args[@]}" 2>/dev/null | head -500 | while IFS= read -r line; do
            if [[ "$line" == COMMIT:* ]]; then
                echo "${line#COMMIT:}" > "$tmpfile.commit"
            elif [[ "$line" == +* ]] && echo "$line" | grep -qE "$pattern" 2>/dev/null; then
                local commit=$(cat "$tmpfile.commit" 2>/dev/null)
                local val=$(echo "$line" | grep -oE "$pattern" 2>/dev/null | head -1)
                printf '%s\t%s\t%s\n' "$label" "${commit:-unknown}" "$val" >> "$tmpfile"
            fi
        done
    done < <(_secrets_patterns)

    rm -f "$tmpfile.commit"

    if [[ -f "$tmpfile" ]]; then
        while IFS=$'\t' read -r label commit matched_val; do
            [[ -z "$commit" ]] && continue
            local masked=$(_secrets_mask "$matched_val")
            printf "  ${_ui_cyan}%-20s${_ui_nc} ${_ui_red}%-16s${_ui_nc} ${_ui_dim}%s${_ui_nc}\n" \
                "$commit" "$label" "$masked"
            ((findings++))
        done < "$tmpfile"
    fi

    rm -f "$tmpfile"
    return $findings
}

# ==============================================================================
# Scan bulk (multi-repos)
# ==============================================================================
_secrets_scan_bulk() {
    local dir="$1" mode="$2"

    _ui_header "Secrets Scan [BULK]"
    _ui_section "Dossier" "$dir"
    _ui_section "Mode" "$mode"
    if [[ ${#_secrets_include_globs[@]} -gt 0 ]]; then
        _ui_section "Include" "${(j:, :)_secrets_include_globs}"
    fi
    if [[ ${#_secrets_exclude_globs[@]} -gt 0 ]]; then
        _ui_section "Exclude" "${(j:, :)_secrets_exclude_globs}"
    fi
    echo ""

    local total_findings=0 repos_scanned=0 repos_with_secrets=0

    local repos=()
    for sub in "$dir"/*/; do
        [[ -d "${sub}.git" ]] && repos+=("${sub%/}")
    done

    if [[ ${#repos[@]} -eq 0 ]]; then
        _ui_msg_warn "Aucun repo Git trouve dans $dir"
        return 0
    fi

    _ui_section "Repos" "${#repos[@]} trouves"
    echo ""

    for repo in "${repos[@]}"; do
        local name=$(basename "$repo")
        ((repos_scanned++))
        printf "  %-24s " "$name"

        local findings=0

        while IFS='|' read -r label pattern; do
            [[ -z "$label" || "$label" == \#* ]] && continue
            local count=$(_secrets_grep_count "$pattern" "$repo")
            ((findings += count))
        done < <(_secrets_patterns)

        if [[ $findings -gt 0 ]]; then
            _ui_warn "$name" "${findings} secret(s)"
            echo ""
            ((repos_with_secrets++))
            ((total_findings += findings))
        else
            _ui_ok "" "clean"
            echo ""
        fi
    done

    echo ""
    _ui_separator 54
    if [[ $total_findings -gt 0 ]]; then
        printf "${_ui_red}%d${_ui_nc} secret(s) dans ${_ui_yellow}%d${_ui_nc} repo(s) sur ${_ui_cyan}%d${_ui_nc} scannes\n" \
            "$total_findings" "$repos_with_secrets" "$repos_scanned"
        echo ""
        _ui_msg_info "Lancez sans --bulk sur un repo specifique pour le detail"
    else
        printf "${_ui_green}%d${_ui_nc} repo(s) scannes — aucun secret detecte\n" "$repos_scanned"
    fi
}

# ==============================================================================
# Aide
# ==============================================================================
_secrets_scan_help() {
    _ui_header "Secrets Scan"
    echo ""
    printf "${_ui_bold}Usage:${_ui_nc}\n"
    echo "  zanvil-secrets-scan [dir]               Scan le working tree (defaut)"
    echo "  zanvil-secrets-scan --history [dir]      Scan l'historique git"
    echo "  zanvil-secrets-scan --bulk [dir]         Scan tous les repos d'un dossier"
    echo ""
    printf "${_ui_bold}Filtres:${_ui_nc}\n"
    echo "  --include \"*.ts\"          Scanner uniquement ces fichiers"
    echo "  --include \"src/**/*.js\"   Plusieurs --include possibles"
    echo "  --exclude \"*.spec.ts\"     Exclure ces fichiers"
    echo "  --exclude \"test/**\"       Plusieurs --exclude possibles"
    echo ""
    printf "${_ui_bold}Note:${_ui_nc} .gitignore est respecte par defaut dans les repos Git\n"
    echo ""
    printf "${_ui_bold}Patterns detectes:${_ui_nc}\n"
    echo "  AWS keys, cles privees, GitHub/GitLab tokens, passwords,"
    echo "  Azure keys, Slack tokens, JWT, connection strings"
    echo ""
    printf "${_ui_bold}Options:${_ui_nc}\n"
    echo "  --current     Scan le working tree uniquement (defaut)"
    echo "  --history     Scan l'historique git"
    echo "  --bulk        Mode multi-repos"
    echo "  -d <dir>      Dossier a scanner"
    echo ""
    printf "${_ui_bold}Exemples:${_ui_nc}\n"
    echo "  zanvil-secrets-scan --include '*.ts' --exclude '*.spec.ts'"
    echo "  zanvil-secrets-scan --bulk -d ~/projects"
    echo "  zanvil-secrets-scan --history --include 'src/**'"
}
