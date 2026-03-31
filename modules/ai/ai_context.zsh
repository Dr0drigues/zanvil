# ==============================================================================
# AI Context Manager - Gestion des contextes pour assistants IA
# ==============================================================================
# Genere des fichiers de contexte (CLAUDE.md, .cursorrules, copilot-instructions)
# avec detection automatique et templates personnalisables
# ==============================================================================

# Repertoires de configuration
AI_CONTEXT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh_env/ai-contexts"
AI_CONTEXT_TEMPLATES_DIR="$AI_CONTEXT_CONFIG_DIR/templates"
AI_CONTEXT_LOCAL_FILE=".ai-context.yml"

# ==============================================================================
# DETECTION AUTOMATIQUE
# ==============================================================================

# Detecte la stack technique du projet
_ai_detect_stack() {
    local dir="${1:-$PWD}"
    local stack=()

    # Node.js / JavaScript / TypeScript
    if [[ -f "$dir/package.json" ]]; then
        stack+=("nodejs")
        [[ -f "$dir/tsconfig.json" ]] && stack+=("typescript")

        # Frameworks
        if grep -q '"react"' "$dir/package.json" 2>/dev/null; then
            stack+=("react")
        fi
        if grep -q '"vue"' "$dir/package.json" 2>/dev/null; then
            stack+=("vue")
        fi
        if grep -q '"angular"' "$dir/package.json" 2>/dev/null; then
            stack+=("angular")
        fi
        if grep -q '"next"' "$dir/package.json" 2>/dev/null; then
            stack+=("nextjs")
        fi
        if grep -q '"express"' "$dir/package.json" 2>/dev/null; then
            stack+=("express")
        fi
        if grep -q '"nestjs"' "$dir/package.json" 2>/dev/null; then
            stack+=("nestjs")
        fi
    fi

    # Python
    if [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" || -f "$dir/requirements.txt" ]]; then
        stack+=("python")
        [[ -f "$dir/pyproject.toml" ]] && grep -q "django" "$dir/pyproject.toml" 2>/dev/null && stack+=("django")
        [[ -f "$dir/pyproject.toml" ]] && grep -q "fastapi" "$dir/pyproject.toml" 2>/dev/null && stack+=("fastapi")
        [[ -f "$dir/pyproject.toml" ]] && grep -q "flask" "$dir/pyproject.toml" 2>/dev/null && stack+=("flask")
    fi

    # Rust
    [[ -f "$dir/Cargo.toml" ]] && stack+=("rust")

    # Go
    [[ -f "$dir/go.mod" ]] && stack+=("go")

    # Java / Kotlin
    if [[ -f "$dir/pom.xml" ]]; then
        stack+=("java" "maven")
    elif [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]]; then
        stack+=("java" "gradle")
        [[ -f "$dir/build.gradle.kts" ]] && stack+=("kotlin")
    fi

    # .NET
    [[ -f "$dir/*.csproj"(N) || -f "$dir/*.sln"(N) ]] && stack+=("dotnet" "csharp")

    # Docker
    [[ -f "$dir/Dockerfile" || -f "$dir/docker-compose.yml" || -f "$dir/docker-compose.yaml" ]] && stack+=("docker")

    # Kubernetes
    [[ -d "$dir/k8s" || -d "$dir/kubernetes" || -f "$dir/helmfile.yaml" ]] && stack+=("kubernetes")

    echo "${stack[@]}"
}

# Detecte la structure du projet
_ai_detect_structure() {
    local dir="${1:-$PWD}"
    local structure=""

    # Detecter les dossiers communs
    local dirs_found=()
    [[ -d "$dir/src" ]] && dirs_found+=("src/")
    [[ -d "$dir/lib" ]] && dirs_found+=("lib/")
    [[ -d "$dir/app" ]] && dirs_found+=("app/")
    [[ -d "$dir/tests" || -d "$dir/test" || -d "$dir/__tests__" ]] && dirs_found+=("tests/")
    [[ -d "$dir/docs" ]] && dirs_found+=("docs/")
    [[ -d "$dir/scripts" ]] && dirs_found+=("scripts/")
    [[ -d "$dir/config" || -d "$dir/configs" ]] && dirs_found+=("config/")
    [[ -d "$dir/public" || -d "$dir/static" ]] && dirs_found+=("public/")
    [[ -d "$dir/api" ]] && dirs_found+=("api/")
    [[ -d "$dir/components" ]] && dirs_found+=("components/")
    [[ -d "$dir/pages" ]] && dirs_found+=("pages/")
    [[ -d "$dir/services" ]] && dirs_found+=("services/")
    [[ -d "$dir/models" ]] && dirs_found+=("models/")
    [[ -d "$dir/utils" || -d "$dir/helpers" ]] && dirs_found+=("utils/")

    echo "${dirs_found[@]}"
}

# Detecte les informations Git
_ai_detect_git() {
    local dir="${1:-$PWD}"

    if ! git -C "$dir" rev-parse --git-dir &>/dev/null; then
        echo "not_a_git_repo"
        return 1
    fi

    local user_name=$(git -C "$dir" config user.name 2>/dev/null)
    local user_email=$(git -C "$dir" config user.email 2>/dev/null)
    local default_branch=$(git -C "$dir" config init.defaultBranch 2>/dev/null || echo "main")
    local has_hooks="false"

    [[ -d "$dir/.git/hooks" ]] && [[ -n "$(ls "$dir/.git/hooks" 2>/dev/null | grep -v '.sample$')" ]] && has_hooks="true"

    # Detecter conventional commits
    local uses_conventional="false"
    if git -C "$dir" log --oneline -10 2>/dev/null | grep -qE "^[a-f0-9]+ (feat|fix|docs|style|refactor|test|chore|ci|perf|build)(\(.+\))?:"; then
        uses_conventional="true"
    fi

    echo "user_name:$user_name"
    echo "user_email:$user_email"
    echo "default_branch:$default_branch"
    echo "has_hooks:$has_hooks"
    echo "conventional_commits:$uses_conventional"
}

# Detecte les strategies de tests
_ai_detect_tests() {
    local dir="${1:-$PWD}"
    local test_frameworks=()

    # JavaScript/TypeScript
    if [[ -f "$dir/package.json" ]]; then
        grep -q '"jest"' "$dir/package.json" 2>/dev/null && test_frameworks+=("jest")
        grep -q '"mocha"' "$dir/package.json" 2>/dev/null && test_frameworks+=("mocha")
        grep -q '"vitest"' "$dir/package.json" 2>/dev/null && test_frameworks+=("vitest")
        grep -q '"cypress"' "$dir/package.json" 2>/dev/null && test_frameworks+=("cypress")
        grep -q '"playwright"' "$dir/package.json" 2>/dev/null && test_frameworks+=("playwright")
    fi

    # Python
    [[ -f "$dir/pytest.ini" || -f "$dir/pyproject.toml" ]] && grep -q "pytest" "$dir/pyproject.toml" 2>/dev/null && test_frameworks+=("pytest")
    [[ -f "$dir/tox.ini" ]] && test_frameworks+=("tox")

    # Rust
    [[ -f "$dir/Cargo.toml" ]] && test_frameworks+=("cargo-test")

    # Go
    [[ -f "$dir/go.mod" ]] && test_frameworks+=("go-test")

    # Java
    [[ -f "$dir/pom.xml" ]] && test_frameworks+=("junit")

    echo "${test_frameworks[@]}"
}

# Detection complete
ai_context_detect() {
    local dir="${1:-$PWD}"

    echo "Detection du projet: $dir"
    echo "========================================"
    echo ""

    echo "Stack technique:"
    local stack=$(_ai_detect_stack "$dir")
    if [[ -n "$stack" ]]; then
        for s in ${=stack}; do
            echo "  - $s"
        done
    else
        echo "  (non detecte)"
    fi
    echo ""

    echo "Structure:"
    local structure=$(_ai_detect_structure "$dir")
    if [[ -n "$structure" ]]; then
        for s in ${=structure}; do
            echo "  - $s"
        done
    else
        echo "  (non detecte)"
    fi
    echo ""

    echo "Tests:"
    local tests=$(_ai_detect_tests "$dir")
    if [[ -n "$tests" ]]; then
        for t in ${=tests}; do
            echo "  - $t"
        done
    else
        echo "  (non detecte)"
    fi
    echo ""

    echo "Git:"
    local git_info=$(_ai_detect_git "$dir")
    if [[ "$git_info" != "not_a_git_repo" ]]; then
        echo "$git_info" | while IFS=: read -r key value; do
            [[ -n "$value" ]] && echo "  $key: $value"
        done
    else
        echo "  (pas un repo git)"
    fi
}

# ==============================================================================
# GENERATION DE CONTEXTE
# ==============================================================================

# Genere le contenu CLAUDE.md
_ai_generate_claude_md() {
    local project_name="${1:-$(basename "$PWD")}"
    local stack="${2:-}"
    local structure="${3:-}"
    local tests="${4:-}"
    local git_info="${5:-}"
    local custom_config="${6:-}"

    cat << CLAUDE_EOF
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Name:** $project_name
CLAUDE_EOF

    # Stack technique
    if [[ -n "$stack" ]]; then
        echo ""
        echo "## Technology Stack"
        echo ""
        for s in ${=stack}; do
            echo "- $s"
        done
    fi

    # Structure
    if [[ -n "$structure" ]]; then
        echo ""
        echo "## Project Structure"
        echo ""
        echo "\`\`\`"
        for s in ${=structure}; do
            echo "$s"
        done
        echo "\`\`\`"
    fi

    # Tests
    if [[ -n "$tests" ]]; then
        echo ""
        echo "## Testing Strategy"
        echo ""
        echo "### Test Frameworks"
        for t in ${=tests}; do
            echo "- $t"
        done
        echo ""
        echo "### Running Tests"
        echo "\`\`\`bash"
        # Commandes selon le framework
        if [[ "$tests" == *"jest"* || "$tests" == *"vitest"* ]]; then
            echo "npm test"
        elif [[ "$tests" == *"pytest"* ]]; then
            echo "pytest"
        elif [[ "$tests" == *"cargo-test"* ]]; then
            echo "cargo test"
        elif [[ "$tests" == *"go-test"* ]]; then
            echo "go test ./..."
        else
            echo "# Add test command"
        fi
        echo "\`\`\`"
    fi

    # Git
    echo ""
    echo "## Git Conventions"
    echo ""

    local conventional="false"
    if [[ -n "$git_info" ]]; then
        echo "$git_info" | while IFS=: read -r key value; do
            if [[ "$key" == "conventional_commits" && "$value" == "true" ]]; then
                conventional="true"
            fi
        done
    fi

    if [[ "$conventional" == "true" ]]; then
        cat << 'GIT_CONV'
This project uses **Conventional Commits**. Format:

```
<type>(<scope>): <description>

[optional body]
[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `perf`, `build`
GIT_CONV
    else
        echo "Use clear, descriptive commit messages."
    fi

    # Section ecriture
    echo ""
    echo "## Code Style & Writing"
    echo ""
    cat << 'STYLE_EOF'
- Follow existing code patterns and conventions
- Keep functions small and focused
- Use meaningful variable and function names
- Add comments only when the logic is not self-evident
- Prefer composition over inheritance
STYLE_EOF

    # Custom config si present
    if [[ -n "$custom_config" && -f "$custom_config" ]]; then
        echo ""
        echo "## Project-Specific Guidelines"
        echo ""
        cat "$custom_config"
    fi
}

# Genere le contenu .cursorrules
_ai_generate_cursorrules() {
    local project_name="${1:-$(basename "$PWD")}"
    local stack="${2:-}"

    cat << 'CURSOR_HEADER'
# Cursor Rules for this project

You are an expert developer. Follow these rules:

CURSOR_HEADER

    # Regles selon la stack
    if [[ "$stack" == *"typescript"* ]]; then
        cat << 'TS_RULES'
## TypeScript Guidelines
- Use strict TypeScript with explicit types
- Prefer interfaces over type aliases for object shapes
- Use enums for fixed sets of values
- Avoid `any` type - use `unknown` if type is truly unknown

TS_RULES
    fi

    if [[ "$stack" == *"react"* ]]; then
        cat << 'REACT_RULES'
## React Guidelines
- Use functional components with hooks
- Keep components small and focused
- Use TypeScript for props interfaces
- Prefer composition over prop drilling

REACT_RULES
    fi

    if [[ "$stack" == *"python"* ]]; then
        cat << 'PYTHON_RULES'
## Python Guidelines
- Follow PEP 8 style guide
- Use type hints for function signatures
- Prefer f-strings for string formatting
- Use dataclasses or Pydantic for data structures

PYTHON_RULES
    fi

    if [[ "$stack" == *"rust"* ]]; then
        cat << 'RUST_RULES'
## Rust Guidelines
- Follow Rust API guidelines
- Use Result for error handling
- Prefer references over ownership when possible
- Document public APIs with rustdoc

RUST_RULES
    fi

    if [[ "$stack" == *"go"* ]]; then
        cat << 'GO_RULES'
## Go Guidelines
- Follow effective Go guidelines
- Use short variable names in small scopes
- Return errors, don't panic
- Use interfaces for abstraction

GO_RULES
    fi

    # Regles generales
    cat << 'GENERAL_RULES'
## General Guidelines
- Write clean, maintainable code
- Follow DRY (Don't Repeat Yourself) principle
- Write tests for new functionality
- Keep commits atomic and well-described
GENERAL_RULES
}

# Genere le contenu copilot-instructions.md
_ai_generate_copilot() {
    local project_name="${1:-$(basename "$PWD")}"
    local stack="${2:-}"

    cat << COPILOT_EOF
# GitHub Copilot Instructions

## Project: $project_name

COPILOT_EOF

    if [[ -n "$stack" ]]; then
        echo "## Tech Stack: ${stack}"
        echo ""
    fi

    cat << 'COPILOT_RULES'
## Coding Preferences

- Follow existing code style and patterns
- Use descriptive names for variables and functions
- Add appropriate error handling
- Write unit tests for new functionality
- Keep functions focused and small

## Commit Messages

Use conventional commit format when suggesting commits:
- feat: new feature
- fix: bug fix
- docs: documentation
- refactor: code refactoring
- test: adding tests
COPILOT_RULES
}

# ==============================================================================
# COMMANDES PRINCIPALES
# ==============================================================================

# Initialise un contexte IA dans le projet courant
ai_context_init() {
    local dir="${1:-$PWD}"
    local config_file="$dir/$AI_CONTEXT_LOCAL_FILE"

    if [[ -f "$config_file" ]]; then
        echo "Fichier $AI_CONTEXT_LOCAL_FILE existe deja."
        echo -n "Ecraser? [y/N] "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    fi

    # Detection automatique
    local stack=$(_ai_detect_stack "$dir")
    local structure=$(_ai_detect_structure "$dir")
    local tests=$(_ai_detect_tests "$dir")

    cat > "$config_file" << EOF
# Configuration AI Context
# Utilisez 'ai-context generate' pour generer les fichiers

# Nom du projet (auto-detecte si vide)
name: $(basename "$dir")

# Stack technique (auto-detectee: $stack)
stack:
$(for s in ${=stack}; do echo "  - $s"; done)

# Structure du projet
structure:
$(for s in ${=structure}; do echo "  - $s"; done)

# Frameworks de test (auto-detectes: $tests)
tests:
$(for t in ${=tests}; do echo "  - $t"; done)

# Conventions Git
git:
  conventional_commits: true
  commit_types:
    - feat: Nouvelle fonctionnalite
    - fix: Correction de bug
    - docs: Documentation
    - style: Formatage
    - refactor: Refactoring
    - test: Tests
    - chore: Maintenance

# Style d'ecriture
style:
  language: french  # ou english
  comments: minimal
  documentation: jsdoc  # ou docstring, rustdoc, godoc

# Formats a generer
outputs:
  - CLAUDE.md
  - .cursorrules
  - .github/copilot-instructions.md

# Instructions personnalisees (ajoutees a la fin)
custom: |
  # Ajoutez vos instructions specifiques ici
EOF

    echo "Fichier $AI_CONTEXT_LOCAL_FILE cree."
    echo "Editez-le puis lancez 'ai-context generate' pour generer les fichiers."
}

# Genere les fichiers de contexte
ai_context_generate() {
    local dir="${1:-$PWD}"
    local force=false
    [[ "$1" == "-f" || "$1" == "--force" ]] && force=true && dir="${2:-$PWD}"

    # Detection
    local stack=$(_ai_detect_stack "$dir")
    local structure=$(_ai_detect_structure "$dir")
    local tests=$(_ai_detect_tests "$dir")
    local git_info=$(_ai_detect_git "$dir")
    local project_name=$(basename "$dir")

    # Charger config locale si presente
    local custom_file=""
    if [[ -f "$dir/$AI_CONTEXT_LOCAL_FILE" ]]; then
        echo "Configuration locale detectee: $AI_CONTEXT_LOCAL_FILE"
        # TODO: parser YAML pour overrides
    fi

    echo "Generation des fichiers de contexte IA..."
    echo ""

    # CLAUDE.md
    local claude_file="$dir/CLAUDE.md"
    if [[ -f "$claude_file" && "$force" != true ]]; then
        echo -n "CLAUDE.md existe. Ecraser? [y/N] "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "  Skip CLAUDE.md" || {
            _ai_generate_claude_md "$project_name" "$stack" "$structure" "$tests" "$git_info" > "$claude_file"
            echo "  Genere: CLAUDE.md"
        }
    else
        _ai_generate_claude_md "$project_name" "$stack" "$structure" "$tests" "$git_info" > "$claude_file"
        echo "  Genere: CLAUDE.md"
    fi

    # .cursorrules
    local cursor_file="$dir/.cursorrules"
    if [[ -f "$cursor_file" && "$force" != true ]]; then
        echo -n ".cursorrules existe. Ecraser? [y/N] "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "  Skip .cursorrules" || {
            _ai_generate_cursorrules "$project_name" "$stack" > "$cursor_file"
            echo "  Genere: .cursorrules"
        }
    else
        _ai_generate_cursorrules "$project_name" "$stack" > "$cursor_file"
        echo "  Genere: .cursorrules"
    fi

    # .github/copilot-instructions.md
    local github_dir="$dir/.github"
    local copilot_file="$github_dir/copilot-instructions.md"
    [[ ! -d "$github_dir" ]] && mkdir -p "$github_dir"

    if [[ -f "$copilot_file" && "$force" != true ]]; then
        echo -n "copilot-instructions.md existe. Ecraser? [y/N] "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "  Skip copilot-instructions.md" || {
            _ai_generate_copilot "$project_name" "$stack" > "$copilot_file"
            echo "  Genere: .github/copilot-instructions.md"
        }
    else
        _ai_generate_copilot "$project_name" "$stack" > "$copilot_file"
        echo "  Genere: .github/copilot-instructions.md"
    fi

    echo ""
    echo "Terminé ! Fichiers generes dans $dir"
}

# Liste les templates disponibles
ai_context_templates() {
    echo "Templates disponibles:"
    echo "======================"

    if [[ ! -d "$AI_CONTEXT_TEMPLATES_DIR" ]]; then
        echo "(aucun template - utilisez 'ai-context template add' pour en creer)"
        return 0
    fi

    for template in "$AI_CONTEXT_TEMPLATES_DIR"/*.yml(N); do
        local name="${template:t:r}"
        echo "  - $name"
    done
}

# Aide
ai_context_help() {
    cat << 'EOF'
AI Context Manager - Gestion des contextes pour assistants IA

Usage:
  ai-context detect           Affiche les informations detectees du projet
  ai-context init             Cree un fichier .ai-context.yml
  ai-context generate [-f]    Genere les fichiers de contexte (-f pour forcer)
  ai-context templates        Liste les templates disponibles
  ai-context help             Affiche cette aide

Fichiers generes:
  - CLAUDE.md                     Pour Claude Code
  - .cursorrules                  Pour Cursor AI
  - .github/copilot-instructions.md  Pour GitHub Copilot

Detection automatique:
  - Stack technique (Node, Python, Rust, Go, Java, etc.)
  - Structure du projet (src/, tests/, etc.)
  - Frameworks de test (Jest, Pytest, etc.)
  - Configuration Git (conventional commits, etc.)

Configuration locale: .ai-context.yml
Templates globaux: ~/.config/zsh_env/ai-contexts/templates/
EOF
}

# Fonction principale
ai-context() {
    local cmd="${1:-help}"
    shift 2>/dev/null

    case "$cmd" in
        detect|d)
            ai_context_detect "$@"
            ;;
        init|i)
            ai_context_init "$@"
            ;;
        generate|gen|g)
            ai_context_generate "$@"
            ;;
        templates|template|t)
            ai_context_templates "$@"
            ;;
        help|h|--help|-h)
            ai_context_help
            ;;
        *)
            echo "Commande inconnue: $cmd" >&2
            ai_context_help
            return 1
            ;;
    esac
}
