# Repos de configs — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter `work_config_repo` au module `work` : audit et mise aux normes des repos de configuration GitLab, création incluse.

**Architecture:** Tout en zsh dans `modules/work/config_repos.zsh`, dans le moule d'`elasticsearch.zsh`. Le cœur est un **planificateur pur** (`_work_cfg_build_plan`) qui reçoit l'état du repo sous forme de TSV et rend une liste d'actions, sans aucun appel réseau — c'est lui qui porte toute la logique de norme, et c'est lui qu'on teste. Autour, une couche de collecte (curl + jq) et une couche d'application, minces par construction.

**Tech Stack:** zsh, curl, jq, API GitLab v4 (forge en 18.11.7 **CE**). Tests en bash dans `scripts/tests/`, moule d'`assert_equals` repris de `zsh-special-vars.test.sh`.

**Spec:** `web/docs/superpowers/specs/2026-08-07-work-config-repos-design.md`

## Global Constraints

- **Aucune couleur en dur** (`\033[...`). Tout passe par les fonctions `_ui_*` de `core/ui.zsh`.
- **Pas de shellspec.** Les tests sont des scripts bash autonomes dans `scripts/tests/*.test.sh`, sur le moule de `zsh-special-vars.test.sh` (compteurs dans `$TEST_TMPDIR`, `assert_equals` lisant stdin).
- **Pas de `-k` sur curl.** `--cacert "$SSL_CERT_FILE"` si la variable est définie, sinon appel nu. Vérifié le 2026-08-07 : la forge répond 200 sans désactiver la vérification.
- **Aucune donnée réelle dans les fixtures.** zanvil est un dépôt public. Les cas de test sont synthétiques (`bu` fictive `blg`, app `demoapp`, repos `demo-*`), sans nom d'hôte ni identifiant de projet réel.
- **`technical-assets` est refusé entièrement**, audit compris, avant tout appel réseau.
- **Le sous-groupe `companion` est hors périmètre.**
- **Le groupe `configurations` n'est jamais créé.** Absent → échec net.
- Chemin canonique : `$WORK_DIR/<bu>/applications/<app>/configurations/<repo>` — `applications` au **pluriel**.
- Norme : branches `dev qlf pprd prd`, défaut `dev`, `dev`/`qlf` non protégées, `pprd`/`prd` protégées en `push_access_level=40`, `merge_access_level=40`, `allow_force_push=false`.
- Codes de sortie : `0` conforme ou corrigé, `1` erreur, `2` écarts détectés en audit.
- Messages et commentaires en français sans accents dans les fichiers `.zsh` (convention du module `work`).

---

### Task 1 : Chemin canonique et refus durs

**Files:**
- Create: `modules/work/config_repos.zsh`
- Create: `scripts/tests/work-config-repos.test.sh`
- Modify: `modules/work/init.zsh`
- Modify: `modules/work/.lazy`

**Interfaces:**
- Consomme : rien
- Produit :
  - `_work_cfg_parse_path <chemin>` → `bu<TAB>app<TAB>repo` sur stdout, `return 1` si non canonique
  - `_work_cfg_guard_target <bu> <app> <repo>` → `return 0|1`, message d'erreur via `_ui_msg_fail`
  - constantes `_WORK_CFG_ENVS_ALL`, `_WORK_CFG_ENVS_PROTECTED`, `_WORK_CFG_BU_ALL`, `_WORK_CFG_PUSH_LEVEL`, `_WORK_CFG_MERGE_LEVEL`

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `scripts/tests/work-config-repos.test.sh` :

```bash
#!/usr/bin/env bash
# Verifie work_config_repo : chemin canonique, refus durs, normalisation des envs,
# et le planificateur pur. Aucun appel reseau.
# Usage : scripts/tests/work-config-repos.test.sh
#
# Les cas sont synthetiques : zanvil est public, aucune nomenclature interne reelle
# n a sa place ici.
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
MOD="$ROOT/modules/work/config_repos.zsh"

TEST_TMPDIR=$(mktemp -d) || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
echo 0 > "$TEST_TMPDIR/pass"
echo 0 > "$TEST_TMPDIR/fail"

assert_equals() {
    local label="$1" needle="$2" out
    out=$(cat)
    if [[ "$out" == "$needle" ]]; then
        printf '  ok   %s\n' "$label"
        echo $(($(cat "$TEST_TMPDIR/pass") + 1)) > "$TEST_TMPDIR/pass"
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        echo $(($(cat "$TEST_TMPDIR/fail") + 1)) > "$TEST_TMPDIR/fail"
    fi
}

# Lance une expression zsh avec ui.zsh et le module charges, WORK_DIR maitrise.
zc() {
    zsh -f -c "
        WORK_DIR='$TEST_TMPDIR/work'
        source '$ROOT/core/ui.zsh' >/dev/null 2>&1
        source '$MOD'
        $1
    " 2>&1
}

echo "== chemin canonique =="

zc '_work_cfg_parse_path "$WORK_DIR/blg/applications/demoapp/configurations/demo-front"' \
    | assert_equals "chemin canonique decompose" "$(printf 'blg\tdemoapp\tdemo-front')"

zc '_work_cfg_parse_path "$WORK_DIR/blg/application/demoapp/configurations/demo-front" || print refuse' \
    | assert_equals "application au singulier refuse" "refuse"

zc '_work_cfg_parse_path "$WORK_DIR/xxx/applications/demoapp/configurations/demo-front" || print refuse' \
    | assert_equals "BU inconnue refusee" "refuse"

zc '_work_cfg_parse_path "$WORK_DIR/blg/applications/demoapp/components/demo-front" || print refuse' \
    | assert_equals "hors groupe configurations refuse" "refuse"

zc '_work_cfg_parse_path "$WORK_DIR/blg/applications/demoapp/configurations/companion/app" || print refuse' \
    | assert_equals "chemin companion refuse" "refuse"

zc '_work_cfg_parse_path "/ailleurs/blg/applications/demoapp/configurations/demo-front" || print refuse' \
    | assert_equals "hors WORK_DIR refuse" "refuse"

echo
echo "== refus durs, sans reseau =="

zc '_work_cfg_guard_target blg demoapp demo-front && print ok' \
    | assert_equals "cible legitime acceptee" "ok"

zc '_work_cfg_guard_target blg demoapp technical-assets >/dev/null 2>&1 || print refuse' \
    | assert_equals "technical-assets refuse" "refuse"

zc '_work_cfg_guard_target blg demoapp companion >/dev/null 2>&1 || print refuse' \
    | assert_equals "companion refuse" "refuse"

zc '_work_cfg_guard_target xxx demoapp demo-front >/dev/null 2>&1 || print refuse' \
    | assert_equals "BU inconnue refusee au garde" "refuse"

zc '_work_cfg_guard_target blg "" demo-front >/dev/null 2>&1 || print refuse' \
    | assert_equals "app vide refusee" "refuse"

zc '_work_cfg_guard_target blg demoapp "" >/dev/null 2>&1 || print refuse' \
    | assert_equals "repo vide refuse" "refuse"

# Le refus doit tomber AVANT tout appel reseau : on rend curl introuvable.
zc 'curl() { print "APPEL RESEAU" }
    _work_cfg_guard_target blg demoapp technical-assets 2>/dev/null
    print "rc=$?"' \
    | assert_equals "technical-assets refuse sans toucher au reseau" "rc=1"

echo
printf '== %s ok, %s echecs ==\n' "$(cat "$TEST_TMPDIR/pass")" "$(cat "$TEST_TMPDIR/fail")"
[[ "$(cat "$TEST_TMPDIR/fail")" == 0 ]]
```

Rendre exécutable : `chmod +x scripts/tests/work-config-repos.test.sh`

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: FAIL sur toutes les assertions — `_work_cfg_parse_path: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Créer `modules/work/config_repos.zsh` :

```zsh
# ==============================================================================
# Work Config Repos — creation et mise aux normes des repos de configuration
# ==============================================================================
# Spec : web/docs/superpowers/specs/2026-08-07-work-config-repos-design.md
#
# Le coeur de ce fichier est `_work_cfg_build_plan` : une fonction pure qui recoit
# l etat d un repo et rend une liste d actions. Tout le reste — collecte, rendu,
# application — est mince autour d elle, et c est deliberé : la norme est la seule
# chose qui merite d etre testee, et elle ne doit pas dependre du reseau pour l etre.

# --- Norme, en dur (surchargeable au runtime par --envs, jamais persistee) ---

typeset -ga _WORK_CFG_ENVS_ALL=(dev qlf pprd prd)
typeset -ga _WORK_CFG_ENVS_PROTECTED=(pprd prd)
typeset -ga _WORK_CFG_BU_ALL=(blg edt udb tsc shared)
typeset -g  _WORK_CFG_PUSH_LEVEL=40      # Maintainers
typeset -g  _WORK_CFG_MERGE_LEVEL=40     # Maintainers

# --- Chemin canonique ---

# Decompose un chemin absolu en bu/app/repo.
# Usage : _work_cfg_parse_path <chemin>
# Sortie : "<bu>\t<app>\t<repo>". Return 1 si le chemin ne suit pas la forme
#          $WORK_DIR/<bu>/applications/<app>/configurations/<repo>.
#
# L arite stricte a cinq segments ecarte d elle-meme les chemins sous companion/,
# qui en comptent six. Le message dedie est rendu par _work_cfg_guard_target.
_work_cfg_parse_path() {
    local p="${1:-}"
    local root="${WORK_DIR:-$HOME/work}"
    [[ -n "$p" && "$p" == "$root"/* ]] || return 1

    local rel="${p#$root/}"
    local -a parts
    parts=(${(s:/:)rel})

    (( ${#parts} == 5 )) || return 1
    [[ "$parts[2]" == applications ]] || return 1
    [[ "$parts[4]" == configurations ]] || return 1
    (( ${_WORK_CFG_BU_ALL[(I)$parts[1]]} )) || return 1

    print -r -- "$parts[1]	$parts[3]	$parts[5]"
    return 0
}

# --- Refus durs ---

# Refuse une cible hors perimetre. Aucun appel reseau, jamais.
# Usage : _work_cfg_guard_target <bu> <app> <repo>
_work_cfg_guard_target() {
    local bu="${1:-}" app="${2:-}" repo="${3:-}"

    if ! (( ${_WORK_CFG_BU_ALL[(I)$bu]} )); then
        _ui_msg_fail "BU inconnue : « ${bu:-<vide>} » (attendu : ${_WORK_CFG_BU_ALL})"
        return 1
    fi
    if [[ -z "$app" ]]; then
        _ui_msg_fail "application non determinee — passer --app, ou se placer dans le chemin canonique"
        return 1
    fi
    if [[ -z "$repo" ]]; then
        _ui_msg_fail "repo non determine — le passer en argument, ou se placer dans le chemin canonique"
        return 1
    fi
    # technical-assets appartient a une autre chaine de responsabilite et n a pas la
    # topologie de la norme : l auditer produirait des ecarts qu il ne faut pas corriger.
    if [[ "$repo" == technical-assets ]]; then
        _ui_msg_fail "technical-assets est hors perimetre — ni ecriture, ni audit"
        return 1
    fi
    if [[ "$repo" == companion || "$repo" == companion/* ]]; then
        _ui_msg_fail "le sous-groupe companion est hors perimetre"
        return 1
    fi
    return 0
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 13 ok, 0 echecs ==`, code de sortie 0

- [ ] **Step 5 : Brancher le module et vérifier la syntaxe**

Ajouter à `modules/work/init.zsh` :
```zsh
source "$ZANVIL_DIR/modules/work/config_repos.zsh"
```

Ajouter à `modules/work/.lazy` (une ligne, à la fin) :
```
work_config_repo
```

Run: `zsh -n modules/work/config_repos.zsh && echo SYNTAXE-OK`
Expected: `SYNTAXE-OK`

- [ ] **Step 6 : Commit**

```bash
git add modules/work/config_repos.zsh modules/work/init.zsh modules/work/.lazy scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): chemin canonique et refus durs des repos de configs"
```

---

### Task 2 : Normalisation des envs et norme dérivée

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : `_WORK_CFG_ENVS_ALL`, `_WORK_CFG_ENVS_PROTECTED` (Task 1)
- Produit :
  - `_work_cfg_normalize_envs <csv>` → csv trié dans l'ordre canonique et dédupliqué ; `return 1` si un env est inconnu ou la liste vide
  - `_work_cfg_expected_default <csv_normalise>` → nom de la branche par défaut attendue
  - `_work_cfg_env_is_protected <env>` → `return 0|1`
  - `_work_cfg_readme_content <repo> <branche>` → `# <repo> <branche>`

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter à `scripts/tests/work-config-repos.test.sh`, juste avant le bloc final `printf '== %s ok...` :

```bash
echo
echo "== normalisation des envs =="

zc '_work_cfg_normalize_envs "prd,dev"' \
    | assert_equals "ordre canonique retabli" "dev,prd"

zc '_work_cfg_normalize_envs "dev,dev,qlf"' \
    | assert_equals "doublons ecartes" "dev,qlf"

zc '_work_cfg_normalize_envs ""  >/dev/null 2>&1 || print refuse' \
    | assert_equals "liste vide refusee" "refuse"

zc '_work_cfg_normalize_envs "dev,uat" >/dev/null 2>&1 || print refuse' \
    | assert_equals "env inconnu refuse" "refuse"

zc '_work_cfg_normalize_envs "dev, qlf "' \
    | assert_equals "espaces autour des valeurs tolerees" "dev,qlf"

echo
echo "== norme derivee =="

zc '_work_cfg_expected_default "dev,qlf,pprd,prd"' \
    | assert_equals "defaut attendu sur la norme complete" "dev"

zc '_work_cfg_expected_default "qlf,prd"' \
    | assert_equals "defaut attendu sans dev" "qlf"

zc '_work_cfg_env_is_protected prd && print oui || print non' \
    | assert_equals "prd protegee" "oui"

zc '_work_cfg_env_is_protected pprd && print oui || print non' \
    | assert_equals "pprd protegee" "oui"

zc '_work_cfg_env_is_protected dev && print oui || print non' \
    | assert_equals "dev non protegee" "non"

zc '_work_cfg_env_is_protected qlf && print oui || print non' \
    | assert_equals "qlf non protegee" "non"

echo
echo "== contenu README =="

zc '_work_cfg_readme_content demo-front dev' \
    | assert_equals "README en H1, une ligne" "# demo-front dev"

zc '_work_cfg_readme_content demo-front prd | wc -l | tr -d " "' \
    | assert_equals "README fait exactement une ligne" "1"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 13 ok puis FAIL sur les 13 nouvelles — `_work_cfg_normalize_envs: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Ajouter à `modules/work/config_repos.zsh`, après le bloc « Refus durs » :

```zsh
# --- Envs et norme derivee ---

# Normalise une liste d envs : espaces retires, doublons ecartes, ordre canonique
# retabli (dev < qlf < pprd < prd). L ordre de frappe n a donc aucune importance.
# Usage : _work_cfg_normalize_envs "prd,dev"  ->  "dev,prd"
# Return 1 si la liste est vide ou contient un env hors norme.
_work_cfg_normalize_envs() {
    local csv="${1:-}"
    local -a wanted out e
    wanted=(${(s:,:)csv})
    wanted=(${wanted//[[:space:]]/})
    wanted=(${wanted:#})

    (( ${#wanted} )) || { _ui_msg_fail "liste d envs vide"; return 1 }

    for e in $wanted; do
        if ! (( ${_WORK_CFG_ENVS_ALL[(I)$e]} )); then
            _ui_msg_fail "env inconnu : « $e » (attendu : ${_WORK_CFG_ENVS_ALL})"
            return 1
        fi
    done

    # On itere sur la norme, pas sur la saisie : l ordre canonique en decoule.
    for e in $_WORK_CFG_ENVS_ALL; do
        (( ${wanted[(I)$e]} )) && out+=($e)
    done

    print -r -- "${(j:,:)out}"
    return 0
}

# La branche par defaut attendue est la premiere env de la liste normalisee.
# Sur la norme complete c est dev ; sur --envs qlf,prd c est qlf.
_work_cfg_expected_default() {
    local -a envs
    envs=(${(s:,:)${1:-}})
    print -r -- "${envs[1]:-}"
}

# La protection se decide par NOM de branche, pas par rang dans la liste.
_work_cfg_env_is_protected() {
    (( ${_WORK_CFG_ENVS_PROTECTED[(I)${1:-}]} ))
}

# Contenu attendu du README d une branche d env : un titre H1, une ligne, rien d autre.
_work_cfg_readme_content() {
    print -r -- "# ${1} ${2}"
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 26 ok, 0 echecs ==`

- [ ] **Step 5 : Commit**

```bash
git add modules/work/config_repos.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): normalisation des envs et norme derivee"
```

---

### Task 3 : Le planificateur pur

C'est le cœur. Il ne touche ni au réseau, ni à `jq` : il reçoit trois tableaux TSV et rend une liste d'actions. Toute la norme vit ici.

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : `_work_cfg_normalize_envs`, `_work_cfg_expected_default`, `_work_cfg_env_is_protected` (Task 2)
- Produit :
  - `_work_cfg_build_plan <repo> <envs_csv> <readme_optin> <default_branch> <branches> <rules> <readmes>`
    - `branches` : une branche par ligne
    - `rules` : `nom<TAB>push<TAB>merge<TAB>force` par ligne
    - `readmes` : `branche<TAB>ok|absent|divergent` par ligne
    - Sortie : une action par ligne, champs séparés par TAB, parmi
      `branch_create<TAB>env<TAB>source`, `default_set<TAB>env`,
      `protect_create<TAB>br`, `protect_replace<TAB>br`, `protect_patch<TAB>br`,
      `unprotect<TAB>br`, `rule_delete_orphan<TAB>br`, `readme_write<TAB>br`,
      `master_delete<TAB>br`, `warn<TAB>texte`

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter à `scripts/tests/work-config-repos.test.sh` avant le bloc final.

Les fixtures sont construites **dans l'expression zsh**, pas dans bash : les faire traverser
deux niveaux de guillemets avec des tabulations littérales est un piège gratuit.

```bash
echo
echo "== planificateur : repo conforme =="

# demo-front conforme : 4 branches, defaut dev, pprd et prd protegees 40/40/false.
zc 'br=$(print -l dev qlf pprd prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nqlf\tok\npprd\tok\nprd\tok")
    _work_cfg_build_plan demo-front dev,qlf,pprd,prd 0 dev "$br" "$rules" "$rm" | wc -l | tr -d " "' \
    | assert_equals "repo conforme : aucune action" "0"

echo
echo "== planificateur : deux branches d env absentes =="

# demo-docs : dev (defaut) et prd existent ; regles pprd et prd deja conformes.
zc 'br=$(print -l dev prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-docs dev,qlf,pprd,prd 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "norme complete : creations + README d office" \
"$(printf 'branch_create\tqlf\tdev\nbranch_create\tpprd\tdev\nreadme_write\tqlf\nreadme_write\tpprd')"

# La regle pprd n est PAS orpheline quand le plan cree la branche pprd.
zc 'br=$(print -l dev prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-docs dev,qlf,pprd,prd 0 dev "$br" "$rules" "$rm" \
      | grep -c rule_delete_orphan' \
    | assert_equals "regle dont la branche va etre creee : pas orpheline" "0"

# Restreindre a dev,qlf rend la regle pprd orpheline et sort prd du perimetre.
zc 'br=$(print -l dev prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-docs dev,qlf 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "envs restreints : orpheline detectee, prd conservee" \
"$(printf 'branch_create\tqlf\tdev\nrule_delete_orphan\tpprd\nreadme_write\tqlf\nwarn\tbranche hors norme conservee : prd')"

echo
echo "== planificateur : protections =="

zc 'br=$(print -l dev prd); rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-x dev,prd 0 dev "$br" "" "$rm"' \
    | assert_equals "regle absente sur prd : creation" "$(printf 'protect_create\tprd')"

zc 'br=$(print -l dev prd); rm=$(printf "dev\tok\nprd\tok")
    rules=$(printf "prd\t30\t40\tfalse")
    _work_cfg_build_plan demo-x dev,prd 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "niveau d acces divergent : remplacement" "$(printf 'protect_replace\tprd')"

zc 'br=$(print -l dev prd); rm=$(printf "dev\tok\nprd\tok")
    rules=$(printf "prd\t40\t40\ttrue")
    _work_cfg_build_plan demo-x dev,prd 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "seul allow_force_push divergent : patch" "$(printf 'protect_patch\tprd')"

zc 'br=$(print -l dev qlf); rm=$(printf "dev\tok\nqlf\tok")
    rules=$(printf "qlf\t40\t40\tfalse")
    _work_cfg_build_plan demo-x dev,qlf 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "qlf protegee a tort : deprotection" "$(printf 'unprotect\tqlf')"

echo
echo "== planificateur : README opt-in =="

zc 'rm=$(printf "dev\tdivergent")
    _work_cfg_build_plan demo-x dev 0 dev "dev" "" "$rm"' \
    | assert_equals "README preexistant divergent sans --readme : averti, pas ecrit" \
"$(printf 'warn\tREADME de dev divergent — relancer avec --readme')"

zc 'rm=$(printf "dev\tdivergent")
    _work_cfg_build_plan demo-x dev 1 dev "dev" "" "$rm"' \
    | assert_equals "README preexistant divergent avec --readme : ecrit" \
"$(printf 'readme_write\tdev')"

zc 'rm=$(printf "dev\tok")
    _work_cfg_build_plan demo-x dev,qlf 0 dev "dev" "" "$rm" | grep readme_write' \
    | assert_equals "branche creee dans le run : README ecrit sans --readme" \
"$(printf 'readme_write\tqlf')"

echo
echo "== planificateur : branches hors norme =="

zc 'br=$(print -l master dev qlf pprd prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nqlf\tok\npprd\tok\nprd\tok")
    _work_cfg_build_plan demo-x dev,qlf,pprd,prd 0 master "$br" "$rules" "$rm"' \
    | assert_equals "master : bascule du defaut puis suppression" \
"$(printf 'default_set\tdev\nmaster_delete\tmaster')"

zc 'br=$(print -l dev feature/x config/y unprotected); rm=$(printf "dev\tok")
    _work_cfg_build_plan demo-x dev 0 dev "$br" "" "$rm"' \
    | assert_equals "feature/config/unprotected : conservees, signalees" \
"$(printf 'warn\tbranche hors norme conservee : feature/x\nwarn\tbranche hors norme conservee : config/y\nwarn\tbranche hors norme conservee : unprotected')"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 26 ok puis FAIL — `_work_cfg_build_plan: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Ajouter à `modules/work/config_repos.zsh` :

```zsh
# --- Planificateur ---

# Construit la liste des actions a partir d un etat, sans aucun appel reseau.
#
# Usage : _work_cfg_build_plan <repo> <envs_csv> <readme_optin> <default_branch> \
#                              <branches> <rules> <readmes>
#   branches : une branche par ligne
#   rules    : nom<TAB>push<TAB>merge<TAB>force
#   readmes  : branche<TAB>ok|absent|divergent
#
# Sortie : une action par ligne, champs separes par TAB. L ordre d emission est
# stable — les tests comparent des sorties entieres, et l ordre d application en
# depend (cf. _work_cfg_apply).
_work_cfg_build_plan() {
    local repo="$1" envs_csv="$2" readme_optin="$3" default_branch="$4"
    local branches_raw="$5" rules_raw="$6" readmes_raw="$7"

    local -a envs branches created
    envs=(${(s:,:)envs_csv})
    branches=(${(f)branches_raw})
    branches=(${branches:#})

    local -A rule_push rule_merge rule_force has_rule readme_state
    local line nom f2 f3 f4
    for line in ${(f)rules_raw}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r nom f2 f3 f4 <<< "$line"
        has_rule[$nom]=1; rule_push[$nom]="$f2"; rule_merge[$nom]="$f3"; rule_force[$nom]="$f4"
    done
    for line in ${(f)readmes_raw}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r nom f2 <<< "$line"
        readme_state[$nom]="$f2"
    done

    local expected_default e b
    expected_default=$(_work_cfg_expected_default "$envs_csv")
    local source_branch="${default_branch:-$expected_default}"

    # 1. branches d env manquantes, derivees du defaut courant
    for e in $envs; do
        if ! (( ${branches[(I)$e]} )); then
            print -r -- "branch_create	$e	$source_branch"
            created+=($e)
        fi
    done

    # 2. branche par defaut
    [[ "$default_branch" != "$expected_default" ]] && print -r -- "default_set	$expected_default"

    # 3-4. protections, par nom de branche
    for e in $envs; do
        if _work_cfg_env_is_protected "$e"; then
            if (( ! ${+has_rule[$e]} )); then
                print -r -- "protect_create	$e"
            elif [[ "$rule_push[$e]" != "$_WORK_CFG_PUSH_LEVEL" || \
                    "$rule_merge[$e]" != "$_WORK_CFG_MERGE_LEVEL" ]]; then
                # GitLab CE ne sait pas modifier un niveau d acces par PATCH :
                # DELETE puis POST, donc une breve fenetre de non-protection.
                print -r -- "protect_replace	$e"
            elif [[ "$rule_force[$e]" != false ]]; then
                print -r -- "protect_patch	$e"
            fi
        else
            (( ${+has_rule[$e]} )) && print -r -- "unprotect	$e"
        fi
    done

    # 5. regles orphelines. Une regle dont la branche va etre creee par ce plan
    #    n est PAS orpheline : elle deviendra une protection legitime.
    for nom in ${(ok)has_rule}; do
        (( ${branches[(I)$nom]} )) && continue
        (( ${created[(I)$nom]} )) && continue
        print -r -- "rule_delete_orphan	$nom"
    done

    # 6. README. D office sur ce que ce run vient de creer — la branche derive de
    #    dev et porte donc le README de dev, il n y a rien a ecraser. Sur une
    #    branche preexistante, il faut --readme.
    for e in $envs; do
        if (( ${created[(I)$e]} )); then
            print -r -- "readme_write	$e"
        elif [[ "${readme_state[$e]:-ok}" != ok ]]; then
            if [[ "$readme_optin" == 1 ]]; then
                print -r -- "readme_write	$e"
            else
                print -r -- "warn	README de $e ${readme_state[$e]} — relancer avec --readme"
            fi
        fi
    done

    # 7. branches hors norme. master/main sont candidates a la suppression ;
    #    tout le reste est conserve. cls-borne porte des config/* vivantes et
    #    cls-bff une feature/* : une regle « supprimer le hors-norme » les tuerait.
    for b in $branches; do
        (( ${envs[(I)$b]} )) && continue
        if [[ "$b" == master || "$b" == main ]]; then
            print -r -- "master_delete	$b"
        else
            print -r -- "warn	branche hors norme conservee : $b"
        fi
    done
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 39 ok, 0 echecs ==`

- [ ] **Step 5 : Commit**

```bash
git add modules/work/config_repos.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): planificateur pur des ecarts a la norme"
```

---

### Task 4 : Point d'entrée, options, aide et completions

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `modules/work/completions.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : `_work_cfg_parse_path`, `_work_cfg_guard_target` (Task 1), `_work_cfg_normalize_envs` (Task 2)
- Produit :
  - `work_config_repo [<repo>] [--bu X] [--app Y] [--envs csv] [--readme] [--fix] [-h|--help]`
  - `_work_cfg_usage` → aide sur stdout
  - variables résolues passées aux tâches suivantes : `bu`, `app`, `repo`, `envs_csv`, `readme_optin`, `do_fix`

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter à `scripts/tests/work-config-repos.test.sh` avant le bloc final :

```bash
echo
echo "== parsing d options =="

zc 'work_config_repo --help | head -1' \
    | assert_equals "aide disponible" "Usage: work_config_repo [<repo>] [options]"

# Le piege zsh : un flag a valeur en dernier argument. Sous `set -u` en bash, shift 2
# echoue ; en zsh il boucle a l infini. Le timeout est la garde du test.
( zc 'work_config_repo --envs 2>/dev/null; print "rc=$?"' & sleep 5; kill %1 2>/dev/null ) \
    | head -1 | assert_equals "--envs en dernier argument ne boucle pas" "rc=1"

( zc 'work_config_repo --bu 2>/dev/null; print "rc=$?"' & sleep 5; kill %1 2>/dev/null ) \
    | head -1 | assert_equals "--bu en dernier argument ne boucle pas" "rc=1"

zc 'work_config_repo --bu blg --app demoapp technical-assets >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "technical-assets nomme explicitement : rc=1" "rc=1"

zc 'work_config_repo --zzz >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "option inconnue : rc=1" "rc=1"

zc 'work_config_repo --bu blg --app demoapp --envs uat demo-x >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "env inconnu : rc=1" "rc=1"

# Hors du chemin canonique et sans flags : refus, sans reseau.
zc 'cd "$TMPDIR" 2>/dev/null || cd /
    work_config_repo >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "cible indeterminable : rc=1" "rc=1"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 40 ok puis FAIL — `work_config_repo: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Ajouter à `modules/work/config_repos.zsh` :

```zsh
# --- Point d entree ---

_work_cfg_usage() {
    print -r -- "Usage: work_config_repo [<repo>] [options]"
    print -r -- ""
    print -r -- "  Audite un repo de configuration, ou le met aux normes avec --fix."
    print -r -- "  Sans argument, la cible est deduite du repertoire courant."
    print -r -- ""
    print -r -- "  --bu <${(j:|:)_WORK_CFG_BU_ALL}>"
    print -r -- "  --app <nom>              application"
    print -r -- "  --envs <csv>             sous-ensemble d envs (defaut: ${(j:,:)_WORK_CFG_ENVS_ALL})"
    print -r -- "  --readme                 autorise la reecriture des README preexistants"
    print -r -- "  --fix                    applique ; sans lui, audit en lecture seule"
    print -r -- "  -h, --help               cette aide"
    print -r -- ""
    print -r -- "  Codes de sortie : 0 conforme ou corrige, 1 erreur, 2 ecarts detectes."
}

work_config_repo() {
    local bu="" app="" repo="" envs_csv="" readme_optin=0 do_fix=0

    while (( $# )); do
        case "$1" in
            --bu)
                (( $# >= 2 )) || { _ui_msg_fail "--bu attend une valeur"; return 1 }
                bu="$2"; shift 2 ;;
            --app)
                (( $# >= 2 )) || { _ui_msg_fail "--app attend une valeur"; return 1 }
                app="$2"; shift 2 ;;
            --envs)
                (( $# >= 2 )) || { _ui_msg_fail "--envs attend une valeur"; return 1 }
                envs_csv="$2"; shift 2 ;;
            --readme) readme_optin=1; shift ;;
            --fix)    do_fix=1; shift ;;
            -h|--help) _work_cfg_usage; return 0 ;;
            -*) _ui_msg_fail "option inconnue : $1"; _work_cfg_usage; return 1 ;;
            *)  repo="$1"; shift ;;
        esac
    done

    # Deduction depuis le repertoire courant pour ce qui n a pas ete passe.
    if [[ -z "$bu" || -z "$app" || -z "$repo" ]]; then
        local parsed p_bu p_app p_repo
        if parsed=$(_work_cfg_parse_path "$PWD"); then
            IFS=$'\t' read -r p_bu p_app p_repo <<< "$parsed"
            [[ -z "$bu" ]]   && bu="$p_bu"
            [[ -z "$app" ]]  && app="$p_app"
            [[ -z "$repo" ]] && repo="$p_repo"
        fi
    fi

    _work_cfg_guard_target "$bu" "$app" "$repo" || return 1

    envs_csv=$(_work_cfg_normalize_envs "${envs_csv:-${(j:,:)_WORK_CFG_ENVS_ALL}}") || return 1

    _work_cfg_run "$bu" "$app" "$repo" "$envs_csv" "$readme_optin" "$do_fix"
}

# Provisoire — remplacee en Task 6. Permet de valider le parsing des le Task 4.
_work_cfg_run() {
    _ui_msg_info "cible : $1/applications/$2/configurations/$3 — envs $4 (readme=$5 fix=$6)"
    return 0
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 46 ok, 0 echecs ==`

- [ ] **Step 5 : Ajouter les completions**

Ajouter à la fin de `modules/work/completions.zsh` :

```zsh
_work_config_repo() {
    _arguments \
        '--bu[Business unit]:bu:(blg edt udb tsc shared)' \
        '--app[Application]:app:' \
        '--envs[Sous-ensemble d envs, separes par des virgules]:envs:(dev dev,qlf dev,qlf,pprd dev,qlf,pprd,prd)' \
        '--readme[Autorise la reecriture des README preexistants]' \
        '--fix[Applique les corrections au lieu d auditer]' \
        '(-h --help)'{-h,--help}'[Afficher l aide]' \
        '1:repo de configuration:'
}
compdef _work_config_repo work_config_repo
```

Run: `zsh -n modules/work/completions.zsh && zsh -n modules/work/config_repos.zsh && echo SYNTAXE-OK`
Expected: `SYNTAXE-OK`

- [ ] **Step 6 : Commit**

```bash
git add modules/work/config_repos.zsh modules/work/completions.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): point d entree work_config_repo, aide et completions"
```

---

### Task 5 : Couche réseau

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : rien
- Produit :
  - `_work_cfg_require` → `return 0|1`, source `~/.gitlab_secrets` si besoin
  - `_work_cfg_api` → `https://<domaine>/api/v4`
  - `_work_cfg_curl METHOD PATH [BODY]` → code HTTP en 1re ligne, corps ensuite ; `return` = code curl
  - `_work_cfg_json METHOD PATH [BODY]` → corps seul ; `return 1` et remplit `$_work_cfg_last_error`
  - `_work_cfg_enc <chemin>` → chemin URL-encodé pour l'API (`/` → `%2F`)

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter à `scripts/tests/work-config-repos.test.sh` avant le bloc final :

```bash
echo
echo "== couche reseau =="

zc '_work_cfg_enc "blg/applications/demoapp/configurations/demo-front"' \
    | assert_equals "chemin encode pour l API" "blg%2Fapplications%2Fdemoapp%2Fconfigurations%2Fdemo-front"

zc 'GITLAB_BASE_DOMAIN=forge.exemple.test; _work_cfg_api' \
    | assert_equals "URL de l API construite" "https://forge.exemple.test/api/v4"

zc 'unset GITLAB_BASE_DOMAIN GITLAB_TOKEN
    HOME=$TMPDIR
    _work_cfg_require >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "sans domaine ni token : refus" "rc=1"

# Le point qui compte : hors reseau, la commande echoue vite, elle ne pend pas.
zc 'GITLAB_BASE_DOMAIN=127.0.0.1:9 GITLAB_TOKEN=x
    SECONDS=0
    _work_cfg_json GET version >/dev/null 2>&1
    rc=$?
    print "rc=$rc borne=$(( SECONDS <= 10 ))"' \
    | assert_equals "hote injoignable : echec immediat, pas de pendaison" "rc=1 borne=1"

zc 'GITLAB_BASE_DOMAIN=127.0.0.1:9 GITLAB_TOKEN=x
    _work_cfg_json GET version >/dev/null 2>&1
    [[ -n "$_work_cfg_last_error" ]] && print renseigne || print vide' \
    | assert_equals "la cause de l echec est nommee" "renseigne"

# Pas de -k : la commande ne doit jamais desactiver la verification TLS.
grep -c -- '-k' "$MOD" | tr -d ' ' | assert_equals "aucun -k dans le module" "0"
grep -c -- '--insecure' "$MOD" | tr -d ' ' | assert_equals "aucun --insecure dans le module" "0"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 47 ok puis FAIL — `_work_cfg_enc: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Ajouter à `modules/work/config_repos.zsh`, avant le bloc « Point d entree » :

```zsh
# --- Couche reseau ---
#
# Calquee sur _work_es_curl / _work_es_json. Une difference assumee avec
# modules/gitlab/gitlab_logic.zsh : pas de -k. Verifie le 2026-08-07, la forge
# repond 200 sans desactiver la verification TLS — desactiver par precaution
# reviendrait a accepter n importe quel certificat pour rien.

_work_cfg_api() {
    print -r -- "https://${GITLAB_BASE_DOMAIN}/api/v4"
}

# Encode un chemin de projet ou de groupe pour l API (les / deviennent %2F).
_work_cfg_enc() {
    print -r -- "${1//\//%2F}"
}

_work_cfg_require() {
    if ! command -v curl &>/dev/null; then
        _ui_msg_fail "curl requis"; return 1
    fi
    if ! command -v jq &>/dev/null; then
        _ui_msg_fail "jq requis (brew install jq / apt install jq)"; return 1
    fi
    if [[ -z "${GITLAB_TOKEN:-}" && -f "$HOME/.gitlab_secrets" ]]; then
        source "$HOME/.gitlab_secrets"
    fi
    if [[ -z "${GITLAB_BASE_DOMAIN:-}" ]]; then
        _ui_msg_fail "GITLAB_BASE_DOMAIN non definie (voir ~/.gitlab_secrets)"; return 1
    fi
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        _ui_msg_fail "GITLAB_TOKEN non defini (voir ~/.gitlab_secrets)"; return 1
    fi
    return 0
}

# Usage : _work_cfg_curl METHOD PATH [BODY]
# Sortie : 1re ligne = code HTTP, reste = corps. Return = code de sortie curl.
_work_cfg_curl() {
    local method=$1 api_path=$2 body="${3:-}"
    local -a opts
    opts=(-s --connect-timeout 5 --max-time 30 -X "$method")
    [[ -n "${SSL_CERT_FILE:-}" ]] && opts+=(--cacert "$SSL_CERT_FILE")
    opts+=(-H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H 'Content-Type: application/json')
    [[ -n "$body" ]] && opts+=(-d "$body")

    local out ret
    out=$(command curl "${opts[@]}" -w $'\n%{http_code}' "$(_work_cfg_api)/$api_path" 2>/dev/null)
    ret=$?
    (( ret != 0 )) && return $ret
    print -r -- "${out##*$'\n'}"
    local resp="${out%$'\n'*}"
    [[ "$resp" != "$out" && -n "$resp" ]] && print -r -- "$resp"
    return 0
}

# Usage : _work_cfg_json METHOD PATH [BODY]
# Sortie : corps seul. Return 1 en cas d echec, avec la cause dans
# _work_cfg_last_error — un « echec » nu ne dit pas si c est le VPN, le token
# ou le chemin qui est en cause, et les trois envoient a des endroits opposes.
_work_cfg_json() {
    typeset -g _work_cfg_last_error=""
    local out code rc
    out=$(_work_cfg_curl "$@"); rc=$?
    if (( rc != 0 )); then
        case $rc in
            6)  _work_cfg_last_error="hote introuvable (DNS) — VPN actif ?" ;;
            7)  _work_cfg_last_error="connexion refusee" ;;
            28) _work_cfg_last_error="delai depasse" ;;
            35|60) _work_cfg_last_error="echec TLS — SSL_CERT_FILE pointe-t-il le bundle d entreprise ?" ;;
            *)  _work_cfg_last_error="curl a rendu $rc" ;;
        esac
        return 1
    fi
    code="${out%%$'\n'*}"
    if [[ "$code" != <-> ]]; then
        _work_cfg_last_error="reponse sans code HTTP — un proxy s est interpose ?"
        return 1
    fi
    if (( code >= 400 )); then
        case $code in
            401) _work_cfg_last_error="HTTP 401 — GITLAB_TOKEN refuse" ;;
            403) _work_cfg_last_error="HTTP 403 — droits insuffisants (Maintainer requis sur les branches protegees)" ;;
            404) _work_cfg_last_error="HTTP 404 — ressource introuvable" ;;
            *)   _work_cfg_last_error="HTTP $code" ;;
        esac
        [[ "$out" == *$'\n'* ]] && \
            _work_cfg_last_error+=" : $(print -r -- "${out#*$'\n'}" | head -c 300)"
        return 1
    fi
    [[ "$out" == *$'\n'* ]] && print -r -- "${out#*$'\n'}"
    return 0
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 53 ok, 0 echecs ==`

- [ ] **Step 5 : Commit**

```bash
git add modules/work/config_repos.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): couche reseau GitLab, sans desactivation TLS"
```

---

### Task 6 : Collecte de l'état distant et rapport d'audit

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : `_work_cfg_json`, `_work_cfg_enc` (Task 5), `_work_cfg_build_plan` (Task 3), `_work_cfg_readme_content` (Task 2)
- Produit :
  - `_work_cfg_collect <bu> <app> <repo> <envs_csv>` → remplit les globales `_work_cfg_pid`, `_work_cfg_default`, `_work_cfg_branches`, `_work_cfg_rules`, `_work_cfg_readmes` ; `return 0` si le projet existe, `2` s'il n'existe pas (404), `1` sur erreur
  - `_work_cfg_render <repo> <plan>` → rapport lisible sur stdout
  - `_work_cfg_run` (remplace le stub du Task 4)

- [ ] **Step 1 : Écrire le test qui échoue**

Le rendu est pur : il prend un plan et rend du texte. C'est lui qu'on teste. Ajouter avant le bloc final :

```bash
echo
echo "== rendu du rapport =="

zc "_work_cfg_render demo-x '' | tail -1" \
    | assert_equals "plan vide : conformite annoncee" "  Rien a faire — le repo est conforme."

zc "_work_cfg_render demo-docs \"\$(printf 'branch_create\tqlf\tdev\nreadme_write\tqlf')\" | grep -c '^  '" \
    | assert_equals "deux actions rendues sur deux lignes" "2"

zc "_work_cfg_render demo-docs \"\$(printf 'branch_create\tqlf\tdev')\" | grep -o 'creer branche qlf depuis dev'" \
    | assert_equals "creation de branche libellee" "creer branche qlf depuis dev"

zc "_work_cfg_render demo-x \"\$(printf 'protect_replace\tprd')\" | grep -o 'fenetre de non-protection'" \
    | assert_equals "le remplacement de protection annonce sa fenetre" "fenetre de non-protection"

zc "_work_cfg_render demo-x \"\$(printf 'master_delete\tmaster')\" | grep -o 'sous reserve du merge-base'" \
    | assert_equals "la suppression de master annonce sa garde" "sous reserve du merge-base"

zc "_work_cfg_count_actions \"\$(printf 'branch_create\tqlf\tdev\nwarn\tblabla\nreadme_write\tqlf')\"" \
    | assert_equals "les avertissements ne comptent pas comme des actions" "2"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 54 ok puis FAIL — `_work_cfg_render: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Ajouter à `modules/work/config_repos.zsh` :

```zsh
# --- Collecte de l etat distant ---

# Remplit les globales decrivant l etat du repo. Return 2 si le projet n existe pas.
_work_cfg_collect() {
    local bu="$1" app="$2" repo="$3" envs_csv="$4"
    typeset -g _work_cfg_pid="" _work_cfg_default="" \
               _work_cfg_branches="" _work_cfg_rules="" _work_cfg_readmes=""

    local full="$bu/applications/$app/configurations/$repo"
    local enc; enc=$(_work_cfg_enc "$full")

    local proj
    if ! proj=$(_work_cfg_json GET "projects/$enc"); then
        [[ "$_work_cfg_last_error" == HTTP\ 404* ]] && return 2
        _ui_msg_fail "lecture du projet : $_work_cfg_last_error"
        return 1
    fi
    _work_cfg_pid=$(print -r -- "$proj" | jq -r '.id')
    _work_cfg_default=$(print -r -- "$proj" | jq -r '.default_branch // ""')

    local br rules
    br=$(_work_cfg_json GET "projects/$_work_cfg_pid/repository/branches?per_page=100") || {
        _ui_msg_fail "lecture des branches : $_work_cfg_last_error"; return 1
    }
    _work_cfg_branches=$(print -r -- "$br" | jq -r '.[].name')

    rules=$(_work_cfg_json GET "projects/$_work_cfg_pid/protected_branches?per_page=100") || {
        _ui_msg_fail "lecture des protections : $_work_cfg_last_error"; return 1
    }
    _work_cfg_rules=$(print -r -- "$rules" | jq -r '
        .[] | [ .name,
                (.push_access_levels[0].access_level  // "0" | tostring),
                (.merge_access_levels[0].access_level // "0" | tostring),
                (.allow_force_push | tostring) ] | @tsv')

    # Etat des README, une lecture par branche d env existante.
    local -a envs; envs=(${(s:,:)envs_csv})
    local e want got code raw lines
    for e in $envs; do
        print -r -- "$_work_cfg_branches" | grep -qx -- "$e" || continue
        want=$(_work_cfg_readme_content "$repo" "$e")
        raw=$(_work_cfg_curl GET "projects/$_work_cfg_pid/repository/files/README%2Emd/raw?ref=$e")
        code="${raw%%$'\n'*}"
        if [[ "$code" == 404 ]]; then
            _work_cfg_readmes+="$e	absent"$'\n'
        elif [[ "$code" == 200 ]]; then
            got="${raw#*$'\n'}"
            if [[ "${got%$'\n'}" == "$want" ]]; then
                _work_cfg_readmes+="$e	ok"$'\n'
            else
                _work_cfg_readmes+="$e	divergent"$'\n'
            fi
        else
            _work_cfg_readmes+="$e	divergent"$'\n'
        fi
    done
    return 0
}

# --- Rendu ---

# Compte les actions reelles d un plan : les lignes `warn` n en sont pas.
_work_cfg_count_actions() {
    local line n=0
    for line in ${(f)${1:-}}; do
        [[ -z "$line" ]] && continue
        [[ "${line%%	*}" == warn ]] && continue
        (( n++ ))
    done
    print -r -- "$n"
}

# Rend un plan en texte lisible. Fonction pure : aucune lecture distante.
_work_cfg_render() {
    local repo="$1" plan="$2"
    local line kind a b n
    n=$(_work_cfg_count_actions "$plan")

    if (( n == 0 )); then
        for line in ${(f)plan}; do
            [[ -z "$line" ]] && continue
            IFS=$'\t' read -r kind a b <<< "$line"
            [[ "$kind" == warn ]] && print -r -- "  ${_ui_yellow}!${_ui_nc} $a"
        done
        print -r -- "  Rien a faire — le repo est conforme."
        return 0
    fi

    print -r -- "${_ui_bold}Plan ($n actions)${_ui_nc}"
    for line in ${(f)plan}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r kind a b <<< "$line"
        case "$kind" in
            branch_create) print -r -- "  + creer branche $a depuis $b" ;;
            default_set)   print -r -- "  ~ basculer la branche par defaut sur $a" ;;
            protect_create) print -r -- "  + proteger $a (Maintainers/Maintainers, force=off)" ;;
            protect_replace) print -r -- "  ~ remplacer la protection de $a — breve fenetre de non-protection (GitLab CE)" ;;
            protect_patch) print -r -- "  ~ desactiver allow_force_push sur $a" ;;
            unprotect)     print -r -- "  - deproteger $a" ;;
            rule_delete_orphan) print -r -- "  - supprimer la regle orpheline « $a »" ;;
            readme_write)  print -r -- "  ~ README de $a → « $(_work_cfg_readme_content "$repo" "$a") »" ;;
            master_delete) print -r -- "  - supprimer $a, sous reserve du merge-base" ;;
            warn)          print -r -- "  ${_ui_yellow}!${_ui_nc} $a" ;;
        esac
    done
    return 0
}

# --- Orchestration ---

_work_cfg_run() {
    local bu="$1" app="$2" repo="$3" envs_csv="$4" readme_optin="$5" do_fix="$6"

    _work_cfg_require || return 1

    _ui_header "Repo de configuration"
    _ui_section "Cible" "$bu/applications/$app/configurations/$repo"
    _ui_section "Envs" "$envs_csv"

    local rc; _work_cfg_collect "$bu" "$app" "$repo" "$envs_csv"; rc=$?
    (( rc == 1 )) && return 1
    if (( rc == 2 )); then
        _ui_msg_warn "le projet n existe pas encore sur la forge"
        (( do_fix )) || { _ui_msg_info "relancer avec --fix pour le creer"; return 2 }
        _work_cfg_create "$bu" "$app" "$repo" "$envs_csv"
        return $?
    fi

    local plan
    plan=$(_work_cfg_build_plan "$repo" "$envs_csv" "$readme_optin" "$_work_cfg_default" \
            "$_work_cfg_branches" "$_work_cfg_rules" "$_work_cfg_readmes")

    echo ""
    _work_cfg_render "$repo" "$plan"

    local n; n=$(_work_cfg_count_actions "$plan")
    (( n == 0 )) && return 0
    (( do_fix )) || return 2

    _work_cfg_confirm_and_apply "$repo" "$envs_csv" "$readme_optin" "$plan"
}
```

Ajouter aussi un stub temporaire, remplacé aux tâches 7 à 9 :

```zsh
# Provisoire — remplacees en Task 7 (confirmation), 8 (application), 9 (creation).
_work_cfg_confirm_and_apply() { _ui_msg_warn "application non encore implementee"; return 1 }
_work_cfg_create() { _ui_msg_warn "creation non encore implementee"; return 1 }
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 59 ok, 0 echecs ==`

- [ ] **Step 5 : Audit réel en lecture seule**

Run: `zsh -ic 'work_config_repo --bu blg --app frontlibreservice cls-bff; print "rc=$?"'`
Expected: rapport, `Rien a faire — le repo est conforme.`, `rc=0`

Run: `zsh -ic 'work_config_repo --bu blg --app frontlibreservice cls-docs; print "rc=$?"'`
Expected: plan listant `creer branche qlf depuis dev` et `creer branche pprd depuis dev`, `rc=2`. **Aucune écriture** : `--fix` n'est pas passé.

- [ ] **Step 6 : Commit**

```bash
git add modules/work/config_repos.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): collecte de l etat distant et rapport d audit"
```

---

### Task 7 : Dialogue [y/N/u]

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : `_work_cfg_build_plan` (Task 3), `_work_cfg_render`, `_work_cfg_count_actions` (Task 6)
- Produit :
  - `_work_cfg_read_answer` → `y|n|u` sur stdout ; lit une ligne sur stdin, défaut `n`
  - `_work_cfg_confirm_and_apply <repo> <envs_csv> <readme_optin> <plan>` (remplace le stub du Task 6)

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter avant le bloc final :

```bash
echo
echo "== dialogue y/N/u =="

zc 'print "" | _work_cfg_read_answer' \
    | assert_equals "entree vide : refus par defaut" "n"

zc 'print "y" | _work_cfg_read_answer' | assert_equals "y accepte" "y"
zc 'print "Y" | _work_cfg_read_answer' | assert_equals "Y accepte (casse ignoree)" "y"
zc 'print "u" | _work_cfg_read_answer' | assert_equals "u accepte" "u"
zc 'print "n" | _work_cfg_read_answer' | assert_equals "n accepte" "n"
zc 'print "zzz" | _work_cfg_read_answer' | assert_equals "reponse inconnue : refus" "n"

# stdin ferme (execution non interactive) : refus, jamais d application implicite.
zc '_work_cfg_read_answer < /dev/null' \
    | assert_equals "stdin ferme : refus" "n"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 60 ok puis FAIL — `_work_cfg_read_answer: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Remplacer le stub `_work_cfg_confirm_and_apply` dans `modules/work/config_repos.zsh` par :

```zsh
# Lit la reponse au prompt. Tout ce qui n est pas y ou u vaut non — y compris
# une entree vide et un stdin ferme. Une execution non interactive ne doit jamais
# appliquer quoi que ce soit par defaut.
_work_cfg_read_answer() {
    local ans
    if ! read -r ans; then
        print -r -- "n"; return 0
    fi
    case "${(L)ans}" in
        y|yes|o|oui) print -r -- "y" ;;
        u|update)    print -r -- "u" ;;
        *)           print -r -- "n" ;;
    esac
}

# Boucle de confirmation. `u` recalcule le plan avec une nouvelle liste d envs et
# repropose : le sous-ensemble n est jamais persiste nulle part.
_work_cfg_confirm_and_apply() {
    local repo="$1" envs_csv="$2" readme_optin="$3" plan="$4"

    while true; do
        echo ""
        print -n -- "Appliquer ? [y/N/u] "
        local ans; ans=$(_work_cfg_read_answer)

        case "$ans" in
            y) _work_cfg_apply "$repo" "$plan"; return $? ;;
            n) _ui_msg_info "rien n a ete ecrit"; return 2 ;;
            u)
                print -n -- "Quels envs ? (${(j:,:)_WORK_CFG_ENVS_ALL}) "
                local raw; read -r raw || raw=""
                local new_envs
                new_envs=$(_work_cfg_normalize_envs "$raw") || continue
                envs_csv="$new_envs"
                _ui_section "Envs" "$envs_csv"
                plan=$(_work_cfg_build_plan "$repo" "$envs_csv" "$readme_optin" \
                        "$_work_cfg_default" "$_work_cfg_branches" "$_work_cfg_rules" \
                        "$_work_cfg_readmes")
                echo ""
                _work_cfg_render "$repo" "$plan"
                (( $(_work_cfg_count_actions "$plan") == 0 )) && return 0
                ;;
        esac
    done
}
```

Ajouter le stub temporaire de l'application, remplacé au Task 8 :

```zsh
# Provisoire — remplacee en Task 8.
_work_cfg_apply() { _ui_msg_warn "application non encore implementee"; return 1 }
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 66 ok, 0 echecs ==`

- [ ] **Step 5 : Commit**

```bash
git add modules/work/config_repos.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): dialogue y/N/u avec recalcul du plan"
```

---

### Task 8 : Application du plan et garde merge-base

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : `_work_cfg_json` (Task 5), `_work_cfg_readme_content` (Task 2)
- Produit :
  - `_work_cfg_sha_contained <sha_branche> <sha_merge_base>` → `return 0|1` (pur)
  - `_work_cfg_is_merged <pid> <branche> <cible>` → `return 0|1`
  - `_work_cfg_sort_plan <plan>` → plan réordonné selon l'ordre d'application
  - `_work_cfg_apply <repo> <plan>` (remplace le stub du Task 7)

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter avant le bloc final :

```bash
echo
echo "== garde merge-base =="

zc '_work_cfg_sha_contained abc123 abc123 && print sur || print refuse' \
    | assert_equals "merge-base egal au SHA : suppression sure" "sur"

zc '_work_cfg_sha_contained abc123 def456 && print sur || print refuse' \
    | assert_equals "merge-base different : suppression refusee" "refuse"

zc '_work_cfg_sha_contained "" "" && print sur || print refuse' \
    | assert_equals "SHA vides : suppression refusee" "refuse"

zc '_work_cfg_sha_contained abc123 "" && print sur || print refuse' \
    | assert_equals "merge-base vide : suppression refusee" "refuse"

echo
echo "== ordre d application =="

# L API refuse de supprimer la branche par defaut, et de supprimer une branche
# protegee : l ordre n est donc pas libre.
zc "_work_cfg_sort_plan \"\$(printf 'master_delete\tmaster\nprotect_create\tprd\nbranch_create\tqlf\tdev\ndefault_set\tdev\nreadme_write\tqlf\nunprotect\tqlf\nrule_delete_orphan\tzzz')\" | cut -f1" \
    | assert_equals "sept etapes remises dans l ordre de la spec" \
"$(printf 'branch_create\ndefault_set\nunprotect\nreadme_write\nprotect_create\nrule_delete_orphan\nmaster_delete')"

zc "_work_cfg_sort_plan \"\$(printf 'warn\tblabla\nbranch_create\tqlf\tdev')\" | cut -f1" \
    | assert_equals "les avertissements sortent en fin de plan" \
"$(printf 'branch_create\nwarn')"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 68 ok puis FAIL — `_work_cfg_sha_contained: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Remplacer le stub `_work_cfg_apply` par :

```zsh
# --- Application ---

# Une branche n est supprimable que si son sommet est deja contenu dans la cible.
# Fonction pure, isolee pour etre testable : c est la seule garde entre un
# `master` reprenant des commits absents de `dev` et leur perte.
_work_cfg_sha_contained() {
    [[ -n "${1:-}" && -n "${2:-}" && "$1" == "$2" ]]
}

# Return 0 si <branche> est deja contenue dans <cible>.
_work_cfg_is_merged() {
    local pid="$1" src="$2" dst="$3" sha base
    sha=$(_work_cfg_json GET "projects/$pid/repository/branches/$src" | jq -r '.commit.id // ""') || return 1
    base=$(_work_cfg_json GET "projects/$pid/repository/merge_base?refs%5B%5D=$src&refs%5B%5D=$dst" \
            | jq -r '.id // ""') || return 1
    _work_cfg_sha_contained "$sha" "$base"
}

# Remet le plan dans l ordre d application. L API impose deux contraintes qui se
# croisent — on ne supprime pas la branche par defaut, on ne supprime pas une
# branche protegee — et les README doivent etre ecrits avant que les protections
# ne soient posees, sinon un repo neuf bute sur ses propres regles.
_work_cfg_sort_plan() {
    local -a order
    order=(branch_create default_set unprotect readme_write protect_create
           protect_replace protect_patch rule_delete_orphan master_delete warn)
    local kind line
    for kind in $order; do
        for line in ${(f)${1:-}}; do
            [[ -z "$line" ]] && continue
            [[ "${line%%	*}" == "$kind" ]] && print -r -- "$line"
        done
    done
}

# Execute le plan. S arrete a la premiere erreur : appliquer la suite d un plan
# dont une etape a echoue laisserait le repo dans un etat qu aucun des deux
# rapports ne decrit.
_work_cfg_apply() {
    local repo="$1" plan="$2"
    local pid="$_work_cfg_pid"
    local line kind a b body

    for line in ${(f)$(_work_cfg_sort_plan "$plan")}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r kind a b <<< "$line"
        case "$kind" in
            branch_create)
                _work_cfg_json POST "projects/$pid/repository/branches?branch=$a&ref=$b" >/dev/null \
                    || { _ui_msg_fail "creation de $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "branche $a creee depuis $b" ;;
            default_set)
                _work_cfg_json PUT "projects/$pid" "{\"default_branch\":\"$a\"}" >/dev/null \
                    || { _ui_msg_fail "bascule du defaut sur $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "branche par defaut : $a" ;;
            unprotect)
                _work_cfg_json DELETE "projects/$pid/protected_branches/$a" >/dev/null \
                    || { _ui_msg_fail "deprotection de $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "$a deprotegee" ;;
            readme_write)
                _work_cfg_write_readme "$pid" "$repo" "$a" || return 1 ;;
            protect_create)
                _work_cfg_protect "$pid" "$a" || return 1 ;;
            protect_replace)
                _ui_msg_warn "$a : fenetre de non-protection le temps du remplacement"
                _work_cfg_json DELETE "projects/$pid/protected_branches/$a" >/dev/null \
                    || { _ui_msg_fail "retrait de la protection de $a : $_work_cfg_last_error"; return 1 }
                _work_cfg_protect "$pid" "$a" || return 1 ;;
            protect_patch)
                _work_cfg_json PATCH "projects/$pid/protected_branches/$a" \
                    '{"allow_force_push":false}' >/dev/null \
                    || { _ui_msg_fail "allow_force_push sur $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "$a : allow_force_push desactive" ;;
            rule_delete_orphan)
                _work_cfg_json DELETE "projects/$pid/protected_branches/$a" >/dev/null \
                    || { _ui_msg_fail "suppression de la regle « $a » : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "regle orpheline « $a » supprimee" ;;
            master_delete)
                local target; target=$(_work_cfg_expected_default "$_work_cfg_envs_current")
                if ! _work_cfg_is_merged "$pid" "$a" "$target"; then
                    _ui_msg_warn "$a NON supprimee : elle porte des commits absents de $target"
                    continue
                fi
                _work_cfg_json DELETE "projects/$pid/protected_branches/$a" >/dev/null 2>&1
                _work_cfg_json DELETE "projects/$pid/repository/branches/$a" >/dev/null \
                    || { _ui_msg_fail "suppression de $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "$a supprimee (contenu repris dans $target)" ;;
            warn)
                _ui_msg_warn "$a" ;;
        esac
    done
    return 0
}

_work_cfg_protect() {
    local pid="$1" br="$2"
    _work_cfg_json POST "projects/$pid/protected_branches?name=$br&push_access_level=$_WORK_CFG_PUSH_LEVEL&merge_access_level=$_WORK_CFG_MERGE_LEVEL&allow_force_push=false" >/dev/null \
        || { _ui_msg_fail "protection de $br : $_work_cfg_last_error"; return 1 }
    _ui_msg_ok "$br protegee (Maintainers/Maintainers, force=off)"
    return 0
}

# Ecrit le README d une branche. Cree ou met a jour selon ce qui existe deja.
# Sur une branche protegee, le commit part sous l identite du token : Maintainer,
# il passe ; sinon GitLab rend 403 et on le dit. On ne deprotege jamais pour se
# faire de la place.
_work_cfg_write_readme() {
    local pid="$1" repo="$2" br="$3"
    local content; content=$(_work_cfg_readme_content "$repo" "$br")
    local encoded; encoded=$(print -r -- "$content" | jq -Rs .)
    local action=create
    local probe; probe=$(_work_cfg_curl GET "projects/$pid/repository/files/README%2Emd?ref=$br")
    [[ "${probe%%$'\n'*}" == 200 ]] && action=update

    _work_cfg_json POST "projects/$pid/repository/commits" \
        "{\"branch\":\"$br\",\"commit_message\":\"chore: normalise le README ($repo $br)\",\"actions\":[{\"action\":\"$action\",\"file_path\":\"README.md\",\"content\":$encoded}]}" >/dev/null \
        || { _ui_msg_fail "README de $br : $_work_cfg_last_error"; return 1 }
    _ui_msg_ok "README de $br normalise"
    return 0
}
```

Renseigner `_work_cfg_envs_current` dans `_work_cfg_run`, juste après le calcul de `envs_csv`, pour que `master_delete` sache quelle est la cible :

```zsh
typeset -g _work_cfg_envs_current="$envs_csv"
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 72 ok, 0 echecs ==`

- [ ] **Step 5 : Vérifier la syntaxe et l'absence de stubs résiduels**

Run: `zsh -n modules/work/config_repos.zsh && echo SYNTAXE-OK`
Expected: `SYNTAXE-OK`

Les stubs `_work_cfg_confirm_and_apply` (Task 6) et `_work_cfg_apply` (Task 7) doivent avoir
été remplacés, pas dupliqués — une seconde définition écraserait silencieusement la vraie.

Run: `grep -c 'non encore implementee' modules/work/config_repos.zsh`
Expected: `1` — il ne doit rester que celui de `_work_cfg_create`, remplacé au Task 9.

- [ ] **Step 6 : Commit**

```bash
git add modules/work/config_repos.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): application du plan, garde merge-base sur master"
```

---

### Task 9 : Création d'un repo absent

**Files:**
- Modify: `modules/work/config_repos.zsh`
- Modify: `scripts/tests/work-config-repos.test.sh`

**Interfaces:**
- Consomme : `_work_cfg_json`, `_work_cfg_enc` (Task 5), `_work_cfg_protect`, `_work_cfg_write_readme` (Task 8)
- Produit :
  - `_work_cfg_local_path <bu> <app> <repo>` → chemin canonique local (pur)
  - `_work_cfg_create <bu> <app> <repo> <envs_csv>` (remplace le stub du Task 6)

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter avant le bloc final :

```bash
echo
echo "== chemin local de destination =="

zc '_work_cfg_local_path blg demoapp demo-front' \
    | assert_equals "chemin canonique reconstruit" "$TEST_TMPDIR/work/blg/applications/demoapp/configurations/demo-front"

# Aller-retour : ce que _work_cfg_local_path produit, _work_cfg_parse_path le relit.
zc '_work_cfg_parse_path "$(_work_cfg_local_path blg demoapp demo-front)"' \
    | assert_equals "aller-retour chemin stable" "$(printf 'blg\tdemoapp\tdemo-front')"

zc 'p=$(_work_cfg_local_path tsc autreapp demo-api); _work_cfg_parse_path "$p"' \
    | assert_equals "aller-retour sur une autre BU" "$(printf 'tsc\tautreapp\tdemo-api')"
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: 74 ok puis FAIL — `_work_cfg_local_path: command not found`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Remplacer le stub `_work_cfg_create` par :

```zsh
# --- Creation ---

_work_cfg_local_path() {
    print -r -- "${WORK_DIR:-$HOME/work}/$1/applications/$2/configurations/$3"
}

# Cree le projet, ses branches, ses protections, puis le clone au chemin canonique.
# Le groupe `configurations` n est JAMAIS cree : une frappe fautive doit echouer,
# pas laisser un groupe orphelin sur la forge.
_work_cfg_create() {
    local bu="$1" app="$2" repo="$3" envs_csv="$4"
    local -a envs; envs=(${(s:,:)envs_csv})
    local grp="$bu/applications/$app/configurations"
    local enc; enc=$(_work_cfg_enc "$grp")

    local gid
    gid=$(_work_cfg_json GET "groups/$enc" | jq -r '.id // ""') || {
        _ui_msg_fail "groupe $grp introuvable : $_work_cfg_last_error"
        _ui_msg_info "ce groupe n est pas cree automatiquement — le creer sur la forge d abord"
        return 1
    }
    [[ -n "$gid" ]] || { _ui_msg_fail "groupe $grp introuvable"; return 1 }

    local default_env="${envs[1]}"
    local proj
    proj=$(_work_cfg_json POST projects \
        "{\"name\":\"$repo\",\"path\":\"$repo\",\"namespace_id\":$gid,\"visibility\":\"internal\",\"default_branch\":\"$default_env\",\"initialize_with_readme\":true}") \
        || { _ui_msg_fail "creation du projet : $_work_cfg_last_error"; return 1 }

    typeset -g _work_cfg_pid; _work_cfg_pid=$(print -r -- "$proj" | jq -r '.id')
    _ui_msg_ok "projet $grp/$repo cree"

    _work_cfg_write_readme "$_work_cfg_pid" "$repo" "$default_env" || return 1

    local e
    for e in ${envs[2,-1]}; do
        _work_cfg_json POST "projects/$_work_cfg_pid/repository/branches?branch=$e&ref=$default_env" >/dev/null \
            || { _ui_msg_fail "creation de $e : $_work_cfg_last_error"; return 1 }
        _ui_msg_ok "branche $e creee depuis $default_env"
        _work_cfg_write_readme "$_work_cfg_pid" "$repo" "$e" || return 1
    done

    # Les protections viennent apres les README : l inverse ferait buter les commits
    # sur les regles qu on vient d ecrire.
    for e in $envs; do
        _work_cfg_env_is_protected "$e" && { _work_cfg_protect "$_work_cfg_pid" "$e" || return 1 }
    done

    local url dest
    url=$(print -r -- "$proj" | jq -r '.http_url_to_repo')
    dest=$(_work_cfg_local_path "$bu" "$app" "$repo")
    mkdir -p "${dest:h}" || { _ui_msg_fail "creation de ${dest:h}"; return 1 }
    if git clone "$url" "$dest"; then
        _ui_msg_ok "clone : $dest"
        cd "$dest"
    else
        _ui_msg_fail "clone en echec — le projet existe, le cloner a la main : git clone $url $dest"
        return 1
    fi
    return 0
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `scripts/tests/work-config-repos.test.sh`
Expected: `== 75 ok, 0 echecs ==`

- [ ] **Step 5 : Vérification finale, chargement et non-régression**

Run: `zsh -n modules/work/config_repos.zsh && zsh -n modules/work/completions.zsh && echo SYNTAXE-OK`
Expected: `SYNTAXE-OK`

Run: `zsh -f -c 'ZANVIL_DIR=$PWD; source core/ui.zsh; source modules/work/config_repos.zsh; print "charge=$(( $+functions[work_config_repo] ))"'`
Expected: `charge=1`

Run: `scripts/tests/zsh-special-vars.test.sh`
Expected: aucune régression — le nouveau fichier ne doit déclarer aucun `local path=` / `local status=`

Run: `zsh -ic 'work_config_repo --bu blg --app frontlibreservice cls-bff; print "rc=$?"'`
Expected: `Rien a faire — le repo est conforme.`, `rc=0`

- [ ] **Step 6 : Commit**

```bash
git add modules/work/config_repos.zsh scripts/tests/work-config-repos.test.sh
git commit -m "feat(work): creation d un repo de configuration et clone local"
```

---

## Ce que le plan ne couvre pas

Repris de la spec, pour mémoire — aucune tâche ne les implémente :

- création de groupes sur la forge
- persistance du sous-ensemble d'envs
- balayage de tous les repos d'un groupe en une commande
- alignement des `merge_method`, `squash_option`, règles d'approbation
- toute opération sur `technical-assets`
- suppression de branches autres que `master`/`main`

## Point de vigilance à l'exécution

Les tâches 1 à 5 et 7 à 9 se vérifient hors réseau. La **tâche 6** est la seule dont l'étape 5 touche la forge, en **lecture seule** (`cls-bff` et `cls-docs`, sans `--fix`). La première écriture réelle n'a lieu qu'après la tâche 8, et seulement sur un repo que tu choisis explicitement — le plan ne prescrit aucun `--fix` sur un repo existant.
