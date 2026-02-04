# AI Context Manager

Generateur de fichiers de contexte pour assistants IA (Claude Code, Cursor, GitHub Copilot).

## Presentation

Le module `ai-context` permet de generer automatiquement des fichiers de contexte pour differents assistants IA:

| Fichier | Assistant |
|---------|-----------|
| `CLAUDE.md` | Claude Code |
| `.cursorrules` | Cursor AI |
| `.github/copilot-instructions.md` | GitHub Copilot |

## Commandes

### Detection automatique

```bash
# Affiche les informations detectees du projet
ai-context detect

# Detecter un projet specifique
ai-context detect ~/projects/mon-app
```

La detection analyse automatiquement:
- **Stack technique**: Node.js, TypeScript, React, Vue, Angular, Python, Django, FastAPI, Rust, Go, Java, .NET, Docker, Kubernetes
- **Structure**: src/, tests/, docs/, components/, services/, etc.
- **Tests**: Jest, Vitest, Pytest, Cargo test, Go test, JUnit
- **Git**: conventional commits, user info, hooks existants

### Initialisation

```bash
# Cree un fichier .ai-context.yml dans le dossier courant
ai-context init
```

Ceci cree un fichier de configuration local que vous pouvez personnaliser.

### Generation

```bash
# Genere les fichiers de contexte
ai-context generate

# Forcer l'ecrasement des fichiers existants
ai-context generate -f
```

### Templates

```bash
# Liste les templates disponibles
ai-context templates
```

Les templates sont stockes dans `~/.config/zsh_env/ai-contexts/templates/`.

## Configuration locale

Le fichier `.ai-context.yml` permet de personnaliser le contexte genere:

```yaml
# Configuration AI Context
name: mon-projet

# Stack technique (override la detection)
stack:
  - nodejs
  - typescript
  - react

# Structure du projet
structure:
  - src/
  - tests/
  - docs/

# Frameworks de test
tests:
  - jest
  - cypress

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
  documentation: jsdoc

# Formats a generer
outputs:
  - CLAUDE.md
  - .cursorrules
  - .github/copilot-instructions.md

# Instructions personnalisees
custom: |
  ## Regles specifiques au projet
  - Utiliser des composants fonctionnels React
  - Preferer les named exports
```

## Exemple de sortie

### CLAUDE.md

```markdown
# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview
**Name:** mon-projet

## Technology Stack
- nodejs
- typescript
- react

## Project Structure
src/
tests/
docs/

## Testing Strategy
### Test Frameworks
- jest

### Running Tests
npm test

## Git Conventions
This project uses **Conventional Commits**.

## Code Style & Writing
- Follow existing code patterns
- Keep functions small and focused
- Use meaningful names
```

## Creer un template

Creez un fichier YAML dans `~/.config/zsh_env/ai-contexts/templates/`:

```bash
# Exemple: template pour API REST Node.js
cat > ~/.config/zsh_env/ai-contexts/templates/nodejs-api.yml << 'EOF'
name: ""
stack:
  - nodejs
  - typescript
  - express

structure:
  - src/
  - src/controllers/
  - src/services/
  - src/models/
  - src/middleware/
  - tests/

tests:
  - jest
  - supertest

git:
  conventional_commits: true

custom: |
  ## API Guidelines
  - Use async/await for all async operations
  - Validate all inputs with Joi or Zod
  - Return consistent error responses
  - Document endpoints with OpenAPI/Swagger
EOF
```

## Bonnes pratiques

1. **Commitez vos fichiers de contexte** - Ils aident toute l'equipe
2. **Mettez a jour regulierement** - Quand l'architecture evolue
3. **Soyez specifique** - Plus le contexte est precis, meilleures sont les suggestions
4. **Incluez les conventions** - Style de code, patterns utilises, etc.

## Voir aussi

- [AI Tokens](AI-Tokens) - Optimisation des tokens envoyes aux LLMs
- [Project Switcher](Project-Switcher) - Gestion des contextes projet
