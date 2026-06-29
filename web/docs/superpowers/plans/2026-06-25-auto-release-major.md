# auto-release major bump (#3b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un chemin de bump *major* (`breaking/*` → major) à `auto-release.yml`, prérequis de la v4.0.0.

**Architecture:** Modification additive d'un seul fichier workflow : une condition de branche + un cas dans le `case` de calcul de version. Le reste du pipeline (bump, push via RELEASE_TOKEN, tag, release) est inchangé.

**Tech Stack:** GitHub Actions (bash dans le workflow), pas de framework de test — vérification par simulation bash + validation YAML.

## Global Constraints

- Déclencheur major = préfixe de branche `breaking/*`.
- Additif uniquement : ne PAS modifier les chemins `minor`/`patch`/`skip` existants.
- Un major incrémente MAJOR, remet MINOR et PATCH à 0.
- **Doc avant PR** (règle standing) : mettre à jour `docs/ROADMAP.md` (#3b livré) avant de créer la PR.
- `$SCRATCHPAD` = `/private/tmp/claude-502/-Users-bl209054--zsh-env/518614f2-a551-4e43-9135-dfc256ae2d6e/scratchpad`

---

### Task 1: Ajouter le chemin major dans auto-release.yml

**Files:**
- Modify: `.github/workflows/auto-release.yml` (étapes « Determine bump type from branch name » et « Calculate new version »)
- Test: `$SCRATCHPAD/test_major.sh`

**Interfaces:**
- Produces: le workflow déduit `type=major` pour une branche `breaking/*` et calcule `MAJOR+1`, `MINOR=0`, `PATCH=0`.

- [ ] **Step 1: Écrire le test de simulation (doit échouer)**

Créer `$SCRATCHPAD/test_major.sh` :
```bash
#!/usr/bin/env bash
set -euo pipefail
F="$HOME/.zsh_env/.github/workflows/auto-release.yml"

# 1. Le workflow doit contenir le chemin breaking/* -> major et le cas major)
grep -q 'BRANCH" == breaking/\*' "$F" || { echo "FAIL: pas de condition breaking/*"; exit 1; }
grep -qE 'major\).*MAJOR=\$\(\(MAJOR \+ 1\)\)' "$F" || { echo "FAIL: pas de cas major) dans le calcul de version"; exit 1; }

# 2. Simulation de la logique de bump (réplique des conditions)
bump() {
  local BRANCH="$1"
  if [[ "$BRANCH" == breaking/* ]]; then echo major
  elif [[ "$BRANCH" == hotfix/* ]]; then echo patch
  elif [[ "$BRANCH" == feature/* || "$BRANCH" == feat/* ]]; then echo minor
  else echo skip; fi
}
[[ "$(bump breaking/rename-zanvil)" == major ]] || { echo "FAIL: breaking/ != major"; exit 1; }
[[ "$(bump hotfix/x)" == patch ]] || { echo "FAIL: hotfix/ != patch"; exit 1; }
[[ "$(bump feature/x)" == minor ]] || { echo "FAIL: feature/ != minor"; exit 1; }
[[ "$(bump feat/x)" == minor ]] || { echo "FAIL: feat/ != minor"; exit 1; }
[[ "$(bump chore/x)" == skip ]] || { echo "FAIL: chore/ != skip"; exit 1; }

# 3. Simulation du calcul de version : major sur v3.12.0 -> v4.0.0
calc() {
  local type="$1" CURRENT="$2"
  local VERSION=${CURRENT#v}; local MAJOR MINOR PATCH
  IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
  case "$type" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac
  echo "v${MAJOR}.${MINOR}.${PATCH}"
}
[[ "$(calc major v3.12.0)" == v4.0.0 ]] || { echo "FAIL: major v3.12.0 != v4.0.0"; exit 1; }
[[ "$(calc minor v3.12.0)" == v3.13.0 ]] || { echo "FAIL: minor v3.12.0 != v3.13.0"; exit 1; }
[[ "$(calc patch v3.12.0)" == v3.12.1 ]] || { echo "FAIL: patch v3.12.0 != v3.12.1"; exit 1; }

# 4. YAML valide
ruby -ryaml -e "YAML.load_file('$F')" >/dev/null || { echo "FAIL: YAML invalide"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bash "$SCRATCHPAD/test_major.sh"`
Expected: `FAIL: pas de condition breaking/*` (le workflow n'a pas encore le chemin major).

- [ ] **Step 3: Ajouter la condition `breaking/*` → major**

Dans `.github/workflows/auto-release.yml`, étape « Determine bump type from branch name », remplacer le bloc `if/elif/else` par :
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

- [ ] **Step 4: Ajouter le cas `major` au calcul de version**

Dans l'étape « Calculate new version », remplacer le `case` par :
```bash
          case "${{ steps.bump.outputs.type }}" in
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            patch) PATCH=$((PATCH + 1)) ;;
          esac
```

- [ ] **Step 5: Lancer le test pour vérifier qu'il passe**

Run: `bash "$SCRATCHPAD/test_major.sh"`
Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/auto-release.yml
git commit -m "ci: ajouter le chemin de bump major (breaking/*) à auto-release"
```

---

### Task 2: Documentation (OBLIGATOIRE avant la PR)

**Files:**
- Modify: `docs/ROADMAP.md` (#3b livré + mention du déclencheur `breaking/*`)

**Interfaces:**
- Consumes: le chemin major livré (Task 1).

- [ ] **Step 1: Mettre à jour la ROADMAP**

Dans `docs/ROADMAP.md` :
- Déplacer la ligne **#3b** du tableau Backlog vers le tableau **Livré** (version v3.13.0), libellé : « Chemin de bump major (`breaking/*`) dans `auto-release.yml` ».
- Dans la section « 🔴 Passage en v4.0.0 », mettre à jour le paragraphe « Prérequis CI (#3b) » pour indiquer qu'il est **livré** : une PR sur branche `breaking/*` déclenche désormais un bump major automatique.
- Dans le bloc d'intro en tête de fichier, ajouter `breaking/*` → major à la liste des préfixes.

- [ ] **Step 2: Vérifier**

```bash
cd /Users/bl209054/.zsh_env
grep -q "breaking/\*" docs/ROADMAP.md && echo "ROADMAP OK"
```
Expected: `ROADMAP OK`.

- [ ] **Step 3: Commit**

```bash
git add docs/ROADMAP.md
git commit -m "docs(roadmap): #3b livré — chemin de bump major breaking/*"
```

---

## Notes d'exécution

- Branche : `feature/auto-release-major` (préfixe `feature/*` → la modif elle-même se publie en **v3.13.0**). Elle portera aussi le commit local du spec (`c2fb8e1`).
- ⚠️ NE PAS nommer la branche `breaking/*` (sinon cette PR déclencherait elle-même un major v4.0.0 prématuré).
- Le major ne s'activera réellement qu'au futur merge d'une PR `breaking/rename-zanvil` (v4.0.0).
