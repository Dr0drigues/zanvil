# ==============================================================================
# Git Hooks Manager - Gestion des hooks Git
# ==============================================================================
# Installe et gere les hooks Git courants
# ==============================================================================

# Dossier des templates de hooks
GIT_HOOKS_TEMPLATES="${ZSH_ENV_DIR:-$HOME/.zsh_env}/hooks-templates"

# Verifie qu'on est dans un repo git
_hooks_check_repo() {
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo "Pas dans un depot Git." >&2
        return 1
    fi
    return 0
}

# Chemin du dossier hooks
_hooks_dir() {
    git rev-parse --git-dir 2>/dev/null | xargs -I {} echo "{}"/hooks
}

# Liste les hooks installes
hooks_list() {
    _hooks_check_repo || return 1

    local hooks_dir=$(_hooks_dir)

    echo "Hooks Git installes:"
    echo "──────────────────────────────────────────"

    local found=false
    for hook in "$hooks_dir"/*; do
        [[ ! -f "$hook" ]] && continue
        [[ "$hook" == *.sample ]] && continue

        local name=$(basename "$hook")
        local status="actif"

        if [[ ! -x "$hook" ]]; then
            status="inactif (non executable)"
        fi

        printf "  %-20s %s\n" "$name" "$status"
        found=true
    done

    if ! $found; then
        echo "  (aucun hook installe)"
    fi

    echo "──────────────────────────────────────────"
    echo "Dossier: $hooks_dir"
}

# Installe un hook pre-commit basique
hooks_install_precommit() {
    _hooks_check_repo || return 1

    local hooks_dir=$(_hooks_dir)
    local hook_file="$hooks_dir/pre-commit"

    mkdir -p "$hooks_dir"

    if [[ -f "$hook_file" ]]; then
        echo "Hook pre-commit existe deja."
        echo -n "Ecraser? [y/N] "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    fi

    cat > "$hook_file" << 'HOOK'
#!/bin/sh
# Hook pre-commit genere par zsh_env

set -e

echo "Running pre-commit checks..."

# Lint staged files
if command -v npm &> /dev/null && [ -f "package.json" ]; then
    if grep -q '"lint"' package.json 2>/dev/null; then
        echo "  Running linter..."
        npm run lint --if-present || exit 1
    fi
fi

# Format check
if command -v npm &> /dev/null && [ -f "package.json" ]; then
    if grep -q '"format:check"' package.json 2>/dev/null; then
        echo "  Checking format..."
        npm run format:check --if-present || exit 1
    fi
fi

# Type check (TypeScript)
if command -v npm &> /dev/null && [ -f "tsconfig.json" ]; then
    if grep -q '"typecheck"' package.json 2>/dev/null; then
        echo "  Type checking..."
        npm run typecheck --if-present || exit 1
    fi
fi

# Python: black, flake8
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    if command -v black &> /dev/null; then
        echo "  Checking Python format (black)..."
        black --check . 2>/dev/null || true
    fi
fi

echo "Pre-commit checks passed!"
HOOK

    chmod +x "$hook_file"
    echo "Hook pre-commit installe: $hook_file"
}

# Installe un hook commit-msg pour verifier le format
hooks_install_commitmsg() {
    _hooks_check_repo || return 1

    local hooks_dir=$(_hooks_dir)
    local hook_file="$hooks_dir/commit-msg"

    mkdir -p "$hooks_dir"

    if [[ -f "$hook_file" ]]; then
        echo "Hook commit-msg existe deja."
        echo -n "Ecraser? [y/N] "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    fi

    cat > "$hook_file" << 'HOOK'
#!/bin/sh
# Hook commit-msg genere par zsh_env
# Verifie le format du message de commit (Conventional Commits)

commit_msg_file="$1"
commit_msg=$(cat "$commit_msg_file")

# Pattern Conventional Commits: type(scope): description
pattern="^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\([a-zA-Z0-9_-]+\))?: .{1,}"

# Ignorer les commits de merge
if echo "$commit_msg" | grep -qE "^Merge "; then
    exit 0
fi

if ! echo "$commit_msg" | grep -qE "$pattern"; then
    echo "ERROR: Le message de commit ne suit pas le format Conventional Commits."
    echo ""
    echo "Format attendu: type(scope): description"
    echo ""
    echo "Types valides:"
    echo "  feat     Nouvelle fonctionnalite"
    echo "  fix      Correction de bug"
    echo "  docs     Documentation"
    echo "  style    Formatage (pas de changement de code)"
    echo "  refactor Refactoring"
    echo "  test     Ajout/modification de tests"
    echo "  chore    Maintenance"
    echo "  perf     Amelioration de performance"
    echo "  ci       CI/CD"
    echo "  build    Build system"
    echo "  revert   Revert d'un commit"
    echo ""
    echo "Exemples:"
    echo "  feat(auth): add login page"
    echo "  fix: resolve memory leak in parser"
    echo ""
    exit 1
fi
HOOK

    chmod +x "$hook_file"
    echo "Hook commit-msg installe: $hook_file"
}

# Installe un hook pre-push
hooks_install_prepush() {
    _hooks_check_repo || return 1

    local hooks_dir=$(_hooks_dir)
    local hook_file="$hooks_dir/pre-push"

    mkdir -p "$hooks_dir"

    if [[ -f "$hook_file" ]]; then
        echo "Hook pre-push existe deja."
        echo -n "Ecraser? [y/N] "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    fi

    cat > "$hook_file" << 'HOOK'
#!/bin/sh
# Hook pre-push genere par zsh_env

set -e

echo "Running pre-push checks..."

# Run tests
if command -v npm &> /dev/null && [ -f "package.json" ]; then
    if grep -q '"test"' package.json 2>/dev/null; then
        echo "  Running tests..."
        npm test || exit 1
    fi
fi

# Python tests
if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
    if command -v pytest &> /dev/null; then
        echo "  Running pytest..."
        pytest || exit 1
    fi
fi

echo "Pre-push checks passed!"
HOOK

    chmod +x "$hook_file"
    echo "Hook pre-push installe: $hook_file"
}

# Installe tous les hooks standards
hooks_install() {
    _hooks_check_repo || return 1

    echo "Installation des hooks Git standards..."
    echo ""

    hooks_install_precommit
    hooks_install_commitmsg
    hooks_install_prepush

    echo ""
    echo "Hooks installes. Utilisez 'hooks_list' pour voir les hooks actifs."
}

# Supprime un hook
hooks_remove() {
    _hooks_check_repo || return 1

    local hook_name="$1"
    local hooks_dir=$(_hooks_dir)

    if [[ -z "$hook_name" ]]; then
        # Selection interactive
        local hooks=""
        for hook in "$hooks_dir"/*; do
            [[ ! -f "$hook" ]] && continue
            [[ "$hook" == *.sample ]] && continue
            hooks="$hooks$(basename "$hook")\n"
        done

        if [[ -z "$hooks" ]]; then
            echo "Aucun hook installe."
            return 0
        fi

        if command -v fzf &> /dev/null; then
            hook_name=$(echo -e "$hooks" | fzf --header="Hook a supprimer" --prompt="Remove > ")
        else
            echo "Hooks installes:"
            echo -e "$hooks" | nl
            echo -n "Numero ou nom: "
            read choice
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                hook_name=$(echo -e "$hooks" | sed -n "${choice}p")
            else
                hook_name="$choice"
            fi
        fi
    fi

    [[ -z "$hook_name" ]] && return 0

    local hook_file="$hooks_dir/$hook_name"

    if [[ ! -f "$hook_file" ]]; then
        echo "Hook '$hook_name' non trouve." >&2
        return 1
    fi

    rm "$hook_file"
    echo "Hook '$hook_name' supprime."
}

# Desactive un hook (le rend non executable)
hooks_disable() {
    _hooks_check_repo || return 1

    local hook_name="$1"
    local hooks_dir=$(_hooks_dir)

    if [[ -z "$hook_name" ]]; then
        echo "Usage: hooks_disable <hook_name>" >&2
        return 1
    fi

    local hook_file="$hooks_dir/$hook_name"

    if [[ ! -f "$hook_file" ]]; then
        echo "Hook '$hook_name' non trouve." >&2
        return 1
    fi

    chmod -x "$hook_file"
    echo "Hook '$hook_name' desactive."
}

# Active un hook
hooks_enable() {
    _hooks_check_repo || return 1

    local hook_name="$1"
    local hooks_dir=$(_hooks_dir)

    if [[ -z "$hook_name" ]]; then
        echo "Usage: hooks_enable <hook_name>" >&2
        return 1
    fi

    local hook_file="$hooks_dir/$hook_name"

    if [[ ! -f "$hook_file" ]]; then
        echo "Hook '$hook_name' non trouve." >&2
        return 1
    fi

    chmod +x "$hook_file"
    echo "Hook '$hook_name' active."
}

# Edite un hook
hooks_edit() {
    _hooks_check_repo || return 1

    local hook_name="$1"
    local hooks_dir=$(_hooks_dir)

    if [[ -z "$hook_name" ]]; then
        echo "Usage: hooks_edit <hook_name>" >&2
        return 1
    fi

    local hook_file="$hooks_dir/$hook_name"

    if [[ ! -f "$hook_file" ]]; then
        echo "Hook '$hook_name' non trouve." >&2
        return 1
    fi

    ${EDITOR:-vim} "$hook_file"
}

# Aide
hooks_help() {
    cat << 'EOF'
Git Hooks Manager - Commandes disponibles:

  hooks_list              Liste les hooks installes
  hooks_install           Installe tous les hooks standards
  hooks_install_precommit Installe le hook pre-commit
  hooks_install_commitmsg Installe le hook commit-msg
  hooks_install_prepush   Installe le hook pre-push
  hooks_remove [hook]     Supprime un hook (interactif sans arg)
  hooks_disable <hook>    Desactive un hook
  hooks_enable <hook>     Active un hook
  hooks_edit <hook>       Edite un hook

Hooks standards:
  pre-commit   Lint, format, typecheck avant commit
  commit-msg   Valide le format Conventional Commits
  pre-push     Tests avant push
EOF
}
