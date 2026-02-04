# Git Hooks Manager

Gestionnaire de hooks Git avec templates standards.

## Commandes

| Commande | Description |
|----------|-------------|
| `hooks_list` | Liste les hooks installés |
| `hooks_install` | Installe tous les hooks standards |
| `hooks_install_precommit` | Installe le hook pre-commit |
| `hooks_install_commitmsg` | Installe le hook commit-msg |
| `hooks_install_prepush` | Installe le hook pre-push |
| `hooks_remove [hook]` | Supprime un hook |
| `hooks_disable <hook>` | Désactive un hook |
| `hooks_enable <hook>` | Active un hook |
| `hooks_edit <hook>` | Édite un hook |
| `hooks_help` | Affiche l'aide |

## Installation rapide

```bash
# Dans un repo git
cd mon-projet

# Installer tous les hooks standards
hooks_install
```

## Hooks standards

### pre-commit

Exécuté avant chaque commit :

- **Node.js** : `npm run lint`, `npm run format:check`, `npm run typecheck`
- **Python** : `black --check`

```bash
hooks_install_precommit
```

### commit-msg

Valide le format Conventional Commits :

```
type(scope): description

Types: feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert
```

Exemples valides :
```
feat(auth): add login page
fix: resolve memory leak
docs(readme): update installation guide
```

```bash
hooks_install_commitmsg
```

### pre-push

Exécuté avant chaque push :

- **Node.js** : `npm test`
- **Python** : `pytest`

```bash
hooks_install_prepush
```

## Gestion des hooks

```bash
# Lister les hooks
hooks_list

# Désactiver temporairement
hooks_disable pre-commit

# Réactiver
hooks_enable pre-commit

# Éditer un hook
hooks_edit pre-commit

# Supprimer
hooks_remove pre-commit
```

## Personnalisation

Les hooks sont des scripts shell dans `.git/hooks/`. Éditez-les avec `hooks_edit` pour les personnaliser.

## Bypass

Pour bypasser un hook ponctuellement :

```bash
git commit --no-verify -m "WIP: travail en cours"
git push --no-verify
```
