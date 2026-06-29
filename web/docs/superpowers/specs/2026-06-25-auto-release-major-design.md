# auto-release.yml — chemin de bump major (#3b) — Design

**Date** : 2026-06-25
**Statut** : Validé (en attente d'implémentation)
**Release cible** : minor (v3.13.0)

## Contexte

Prérequis de la v4.0.0 (rename technique). `.github/workflows/auto-release.yml` déduit le type de bump du nom de branche de la PR mergée : `hotfix/*`→patch, `feature/*`/`feat/*`→minor, sinon skip. **Il n'existe aucun chemin major** → le passage en v4.0.0 ne pourrait pas se publier automatiquement. Ce sous-projet ajoute le déclencheur major.

## Décision

Déclencheur major = **préfixe de branche `breaking/*`** (cohérent avec le pattern branche-nom existant).

## Modification (un seul fichier : `.github/workflows/auto-release.yml`)

### Étape « Determine bump type from branch name »
Ajouter `breaking/*` → `major` en **première** condition :
```bash
if [[ "$BRANCH" == breaking/* ]]; then
  echo "type=major" >> $GITHUB_OUTPUT
elif [[ "$BRANCH" == hotfix/* ]]; then
  echo "type=patch" >> $GITHUB_OUTPUT
elif [[ "$BRANCH" == feature/* || "$BRANCH" == feat/* ]]; then
  echo "type=minor" >> $GITHUB_OUTPUT
else
  echo "Branch '$BRANCH' does not match breaking/*, feature/*, feat/* or hotfix/* — skipping release."
  echo "type=skip" >> $GITHUB_OUTPUT
fi
```

### Étape « Calculate new version »
Ajouter le cas `major` au `case` existant :
```bash
case "${{ steps.bump.outputs.type }}" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
```

Le reste du workflow (bump `core/ui.zsh`, push via `RELEASE_TOKEN`, tag, release) est inchangé et fonctionne identiquement pour un major.

## Périmètre / sûreté

- Un seul fichier modifié. **Additif** : ne modifie pas les chemins minor/patch/skip existants.
- N'exécute rien de lui-même : un major ne se déclenche que sur le merge d'une PR dont la branche est `breaking/*`.
- Hors périmètre : le rename v4.0.0 lui-même (#4), tout autre mécanisme (label PR, conventional commits).

## Migration

Aucune (modification de workflow CI, aucun état utilisateur).

## Tests

- Simulation de la logique de bump (bash) : `breaking/x`→major, `hotfix/x`→patch, `feature/x`/`feat/x`→minor, `chore/x`→skip.
- Simulation du calcul de version : type `major` sur `CURRENT=v3.12.0` → `v4.0.0` (MAJOR+1, MINOR/PATCH=0).
- `ruby -ryaml -e "YAML.load_file('.github/workflows/auto-release.yml')"` → YAML valide.
