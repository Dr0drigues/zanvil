# Contributing

Guide pour contribuer au projet zsh_env.

## Structure du projet

```
~/.zsh_env/
├── functions/          # Fonctions modulaires
├── scripts/            # Scripts autonomes
├── themes/             # Thèmes Starship
├── wiki/               # Documentation (ce wiki)
├── install.sh          # Script d'installation
├── README.md           # Introduction rapide
└── CLAUDE.md           # Instructions pour Claude Code
```

## Conventions de code

### Fichiers de fonctions

- Un fichier par module dans `functions/`
- Nommage : `nom_module.zsh`
- Header avec description :

```zsh
# ==============================================================================
# Nom du Module - Description courte
# ==============================================================================
# Description détaillée
# ==============================================================================
```

### Fonctions

- Préfixer les fonctions internes avec `_` : `_ma_fonction_interne()`
- Fonctions publiques sans préfixe : `ma_commande()`
- Vérifier les dépendances avec `command -v`
- Utiliser `echo ... >&2` pour les erreurs

### Globs zsh

Toujours utiliser le modificateur `(N)` pour éviter les erreurs :

```zsh
for f in "$dir"/*.yml(N); do
    ...
done
```

## Convention de commits

Format Conventional Commits :

```
type(scope): description

Types:
- feat: Nouvelle fonctionnalité
- fix: Correction de bug
- docs: Documentation
- refactor: Refactoring
- test: Tests
- chore: Maintenance
```

Exemples :
```
feat(proj): add project scanning
fix(kube): fix glob pattern error
docs(wiki): add SSH manager documentation
```

## Documentation

### Quand mettre à jour

À chaque modification, mettre à jour :

1. **Nouvelle fonctionnalité** → Créer/mettre à jour la page wiki correspondante
2. **Nouvelle commande** → Ajouter dans [[Commandes]]
3. **Changement majeur** → Mettre à jour [[Home]] si nécessaire

### README vs Wiki

| README.md | Wiki |
|-----------|------|
| Introduction rapide | Documentation complète |
| Installation | Guides détaillés |
| Liens vers le wiki | Référence des commandes |
| < 100 lignes | Illimité |

### Format des pages wiki

```markdown
# Titre

Description courte.

## Commandes

| Commande | Description |
|----------|-------------|
| `cmd` | Description |

## Utilisation

...

## Exemples

```bash
exemple de code
```
```

## Workflow de contribution

1. Créer une branche : `git checkout -b feat/ma-feature`
2. Implémenter + documenter
3. Commit avec message conventionnel
4. Push et créer une PR
5. Mettre à jour le wiki si nécessaire

## Pousser le wiki

Le wiki GitHub est un repo git séparé :

```bash
# Cloner le wiki
git clone https://github.com/Dr0drigues/zsh_env.wiki.git

# Copier les fichiers
cp ~/.zsh_env/wiki/*.md zsh_env.wiki/

# Commit et push
cd zsh_env.wiki
git add . && git commit -m "docs: update wiki" && git push
```
