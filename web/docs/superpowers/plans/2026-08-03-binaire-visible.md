# Chantier 1 — rendre le binaire installable, à jour, et son absence visible

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** faire que le CLI Rust soit effectivement installé sous le nom `zanvil`, qu'il suive les mises
à jour du dépôt, et qu'une délégation ne puisse plus retomber silencieusement sur son repli zsh.

**Architecture:** trois défauts indépendants concourent au même symptôme, et chacun se corrige à
l'endroit où il se produit — `install.sh` pour le nettoyage de l'ancien nom, `_zanvil_do_update` pour la
reconstruction, `doctor` pour la visibilité. Un cas gaveldrop vérifie le seul de ces trois points qui
soit testable sans dépendre de la machine : que `doctor` signale un binaire manquant.

**Tech Stack:** bash (`install.sh`), zsh (`core/lifecycle/auto_update.zsh`), Rust
(`cli/src/cmd/doctor.rs`), gaveldrop v0.1.3.

## Global Constraints

- **Le repli zsh reste**, c'est une garantie documentée dans `CLAUDE.md`. Ce chantier ne le supprime
  pas : il le rend visible. Un repli acceptable est un repli qu'on sait avoir pris.
- **`core/lifecycle/migrate_zanvil.zsh` n'est pas le bon endroit** et ne doit pas être touché : la
  migration est one-shot et idempotente (« ne fait rien si `~/.zanvil` existe »), donc déjà passée
  partout où le problème se pose.
- **Aucune assertion ne doit dépendre de ce que la machine a installé.** Le binaire est présent sur un
  poste de développement et absent d'un runner : un cas qui teste `command -v zanvil` rendrait un
  verdict différent selon l'endroit.
- **Version minimale de gaveldrop : v0.1.3** — celle qu'épingle le job CI.
- Chaque cas est écrit avec un attendu **faux**, lancé pour constater le `FAIL`, puis corrigé.
- Les documents sous `web/docs/superpowers/` sont gitignored : les commits les ajoutent avec
  `git add -f`.

## Les trois défauts, et où chacun se corrige

| Défaut | Constat | Fichier |
|---|---|---|
| L'ancien binaire n'est jamais retiré | `~/.local/bin/zsh-env-cli` v3.0.0 d'avril cohabite avec un `zanvil` jamais installé | `install.sh:767-777` |
| Une mise à jour ne reconstruit pas le binaire | `_zanvil_do_update` fait `git pull` et rien d'autre : du code Rust neuf arrive, le binaire reste celui du dernier `install.sh` | `core/lifecycle/auto_update.zsh:44-56` |
| Rien ne signale l'absence | `doctor` vérifie git, curl, jq, starship, kubectl — mais pas son propre binaire | `cli/src/cmd/doctor.rs` |

---

### Task 1: `doctor` signale son propre binaire

Ce chantier commence par la visibilité, et non par la réparation : c'est elle qui manquait pendant
quatre mois, et c'est le seul des trois points qu'un cas peut vérifier sans dépendre de la machine.

**Files:**
- Modify: `cli/src/cmd/doctor.rs`
- Create: `tests/cases/cli/cli-doctor-reports-its-own-binary.yaml`

**Interfaces:**
- Consumes: `tests/hooks/prepare-zanvil-dir.sh` (lot 1), qui fournit un `ZANVIL_DIR` isolé.
- Produces: une section `Binaire` dans la sortie de `doctor`, que la tâche 3 ne réutilise pas mais que
  le cas de cette tâche asserte.

- [ ] **Step 1: Écrire le cas avec un attendu faux**

```yaml
# tests/cases/cli/cli-doctor-reports-its-own-binary.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Dr0drigues/gaveldrop/main/docs/case.schema.json
#
# Ce cas existe parce qu'un repli silencieux a masque une panne pendant quatre mois :
# ~/.local/bin portait zsh-env-cli v3.0.0 au lieu de zanvil, donc zproject etait casse
# et trois commandes tournaient degradees sans le dire.
#
# Il n asserte PAS que le binaire est installe — ce serait vrai sur un poste et faux sur
# un runner. Il asserte que doctor en PARLE, ce qui est vrai partout.
name: cli-doctor-reports-its-own-binary
weight: 7
setup:
  exec: ./tests/hooks/prepare-zanvil-dir.sh
  env:
    ZANVIL_DIR: "$HOME/zanvil"
  run: ["$GAVELDROP_PROJECT/cli/target/release/zanvil", "doctor"]
expect:
  exit_code: 0
  stdout:
    contains: ["une-section-qui-nexiste-pas"]
```

- [ ] **Step 2: Lancer et constater l'échec**

```bash
cd ~/.zanvil && gaveldrop --only cli-doctor-reports-its-own
```

Attendu : `FAIL cli-doctor-reports-its-own-binary 0/7`, avec sous `got` la sortie actuelle de `doctor` —
qui ne contient aucune ligne sur son binaire.

- [ ] **Step 3: Ajouter la section dans `doctor.rs`**

À insérer après la section `Integration` et avant `Requis`, en suivant le style des sections existantes
(`print_section` avec les symboles de `super::`) :

```rust
    // ── Binaire ───────────────────────────────────────────────────────────────
    // Une delegation zsh retombe sur son repli quand ce binaire manque, et le fait
    // silencieusement. Doctor est le seul endroit qui puisse le dire.
    let own = which_zanvil();
    let own_line = match &own {
        Some(path) => {
            let running = std::env::current_exe()
                .ok()
                .map(|p| p.display().to_string())
                .unwrap_or_default();
            if running.starts_with(path) || path == &running {
                format!("{} {}", "✓".green(), path)
            } else {
                // Un autre zanvil est premier dans le PATH : les delegations zsh
                // appelleront celui-la, pas celui qu'on vient de lancer.
                format!("{} {} (celui qui repond aux delegations)", "⚠".yellow(), path)
            }
        }
        None => {
            issues += 1;
            format!(
                "{} absent du PATH — les commandes zsh tombent sur leur repli. \
                 Installez-le : cd {}/cli && cargo build --release && \
                 cp target/release/zanvil ~/.local/bin/",
                "✗".red(),
                zanvil_dir.display()
            )
        }
    };
    print_section("Binaire", &own_line);
```

Et la fonction de recherche, à ajouter à côté de `command_exists` :

```rust
/// Cherche `zanvil` dans le PATH, et rend le premier chemin trouve.
///
/// On ne se contente pas de `current_exe()` : la question n'est pas « ou suis-je »
/// mais « qui repondra a une delegation zsh », et c'est le PATH qui en decide.
fn which_zanvil() -> Option<String> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join("zanvil"))
        .find(|candidate| candidate.is_file())
        .map(|p| p.display().to_string())
}
```

- [ ] **Step 4: Compiler et vérifier la sortie à la main**

```bash
cd ~/.zanvil/cli && cargo build --release && cd .. && \
  ZANVIL_DIR="$PWD" ./cli/target/release/zanvil doctor | grep -A1 Binaire
```

Attendu : une ligne `Binaire` suivie soit d'un `✓` avec le chemin, soit d'un `✗ absent du PATH` avec la
commande d'installation. Sur une machine où le binaire n'est pas installé, c'est le second cas — et
c'est le comportement qui manquait.

- [ ] **Step 5: Corriger l'attendu du cas**

```yaml
  stdout:
    # « Binaire » seul : la valeur qui suit depend de la machine — un poste equipe
    # affiche un chemin, un runner affiche l'absence — mais la SECTION existe partout.
    contains: ["Binaire"]
```

- [ ] **Step 6: Vérifier le vert, puis la faillibilité**

```bash
gaveldrop --only cli-doctor-reports-its-own
```

Attendu : `ok cli-doctor-reports-its-own-binary 7/7`.

Puis prouver que le cas mord, en retirant la section :

```bash
cd ~/.zanvil && cp cli/src/cmd/doctor.rs /tmp/doctor.bak
sed -i '' '/print_section("Binaire"/d' cli/src/cmd/doctor.rs
(cd cli && cargo build --release) && gaveldrop --only cli-doctor-reports-its-own
```

Attendu : `FAIL`. Puis restaurer :

```bash
cp /tmp/doctor.bak cli/src/cmd/doctor.rs && (cd cli && cargo build --release)
gaveldrop --only cli-doctor-reports-its-own
```

- [ ] **Step 7: Commit**

```bash
git add cli/src/cmd/doctor.rs tests/cases/cli/cli-doctor-reports-its-own-binary.yaml
git commit -m "feat(doctor): signaler l'absence du binaire, que le repli masquait

Une delegation zsh retombe sur son repli quand zanvil manque du PATH, et le
fait sans rien dire : ~/.local/bin portait zsh-env-cli v3.0.0 depuis avril,
donc zproject etait casse et trois commandes tournaient degradees pendant
quatre mois.

Doctor cherche desormais zanvil dans le PATH — pas current_exe(), parce que la
question n'est pas « ou suis-je » mais « qui repondra a une delegation » — et
compte son absence comme une erreur, avec la commande d'installation.

Le cas asserte que la section existe, pas qu'elle est verte : la valeur depend
de la machine, la section non."
```

---

### Task 2: `install.sh` retire l'ancien binaire

**Files:**
- Modify: `install.sh:767-777`

**Interfaces:**
- Consumes: rien.
- Produces: rien que les tâches suivantes consomment.

- [ ] **Step 1: Reproduire le défaut**

```bash
ls -l ~/.local/bin/zsh-env-cli ~/.local/bin/zanvil 2>&1
```

Attendu sur une machine installée avant la v4.0.0 : l'ancien existe, le nouveau non. C'est l'état qui a
produit la panne.

- [ ] **Step 2: Ajouter le nettoyage**

Remplacer le bloc `install.sh:767-777` par :

```bash
# Build du CLI Rust (optionnel, necessite cargo)
if command -v cargo &>/dev/null; then
    log_info "Build de zanvil..."
    if (cd "$TARGET_DIR/cli" && cargo build --release 2>/dev/null); then
        mkdir -p "$HOME/.local/bin"
        cp "$TARGET_DIR/cli/target/release/zanvil" "$HOME/.local/bin/"
        log_success "zanvil installe dans ~/.local/bin/"

        # Le binaire s'appelait zsh-env-cli avant la v4.0.0. Le laisser en place n'est
        # pas anodin : il porte une version anterieure au renommage, il repond a
        # --version, et sa presence donne l'illusion d'une installation valide.
        if [[ -e "$HOME/.local/bin/zsh-env-cli" ]]; then
            rm -f "$HOME/.local/bin/zsh-env-cli"
            log_success "ancien binaire zsh-env-cli retire"
        fi
    else
        log_warn "Build de zanvil echoue (optionnel, les commandes zsh fonctionnent sans)"
    fi
else
    log_info "cargo non trouve — zanvil non installe (optionnel)"
fi
```

- [ ] **Step 3: Vérifier la syntaxe**

```bash
cd ~/.zanvil && bash -n install.sh && echo "syntaxe ok"
```

- [ ] **Step 4: Vérifier le nettoyage sur un faux ancien binaire**

Sans lancer `install.sh` en entier — il modifierait la machine — on éprouve le seul bloc ajouté :

```bash
mkdir -p /tmp/binprobe && : > /tmp/binprobe/zsh-env-cli
HOME=/tmp/binprobe bash -c '
  if [[ -e "$HOME/.local/bin/zsh-env-cli" ]]; then rm -f "$HOME/.local/bin/zsh-env-cli"; fi
  mkdir -p "$HOME/.local/bin"; : > "$HOME/.local/bin/zsh-env-cli"
  if [[ -e "$HOME/.local/bin/zsh-env-cli" ]]; then rm -f "$HOME/.local/bin/zsh-env-cli"; echo retire; fi
  test -e "$HOME/.local/bin/zsh-env-cli" && echo "ENCORE LA" || echo "absent, correct"
'
```

Attendu : `retire` puis `absent, correct`.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "fix(install): retirer le binaire d'avant le renommage

zsh-env-cli survivait a l'installation de zanvil, avec une version anterieure
au renommage de la v4.0.0. Le laisser en place donne l'illusion d'une
installation valide : il repond a --version et il est dans le PATH."
```

---

### Task 3: une mise à jour reconstruit le binaire

**Files:**
- Modify: `core/lifecycle/auto_update.zsh:44-56`

**Interfaces:**
- Consumes: rien.
- Produces: rien.

- [ ] **Step 1: Constater que `git pull` ne suffit pas**

```bash
cd ~/.zanvil && grep -A12 '_zanvil_do_update()' core/lifecycle/auto_update.zsh | grep -cE 'cargo|local/bin'
```

Attendu : `0`. Un `git pull` amène du code Rust nouveau et laisse le binaire installé tel quel, qui
devient donc silencieusement périmé.

- [ ] **Step 2: Reconstruire après un `git pull` réussi**

À insérer dans `_zanvil_do_update`, juste après la ligne
`echo -e "${_ui_green}[zanvil]${_ui_nc} Mise a jour terminee. Rechargez avec: ${_ui_bold}ss${_ui_nc}"` :

```zsh
        # Le git pull amene du code Rust neuf ; sans cette reconstruction, le binaire
        # installe reste celui du dernier install.sh et devient silencieusement
        # perime. On ne reconstruit que si un binaire est deja installe : quelqu un
        # qui n'en veut pas ne doit pas en heriter par une mise a jour.
        if command -v cargo &>/dev/null && [[ -x "$HOME/.local/bin/zanvil" ]]; then
            echo -e "${_ui_blue}[zanvil]${_ui_nc} Reconstruction du binaire..."
            if (cd "$ZANVIL_DIR/cli" && cargo build --release 2>/dev/null); then
                cp "$ZANVIL_DIR/cli/target/release/zanvil" "$HOME/.local/bin/" \
                    && _ui_msg_ok "binaire mis a jour"
            else
                _ui_msg_warn "reconstruction echouee — le binaire reste a sa version precedente"
            fi
        fi
```

- [ ] **Step 3: Vérifier la syntaxe**

```bash
cd ~/.zanvil && zsh -n core/lifecycle/auto_update.zsh && echo "syntaxe ok"
```

- [ ] **Step 4: Vérifier que la garde tient**

Le bloc ne doit rien faire quand aucun binaire n'est installé :

```bash
zsh -fc '
  HOME=/tmp/noborn
  if command -v cargo &>/dev/null && [[ -x "$HOME/.local/bin/zanvil" ]]; then
    print "aurait reconstruit — INCORRECT"
  else
    print "ne reconstruit pas, correct"
  fi
'
```

Attendu : `ne reconstruit pas, correct`.

- [ ] **Step 5: Commit**

```bash
git add core/lifecycle/auto_update.zsh
git commit -m "fix(update): reconstruire le binaire apres un git pull

_zanvil_do_update ne faisait qu'un git pull : le code Rust arrivait, le binaire
installe restait celui du dernier install.sh. Il devenait donc perime sans que
rien ne le dise — le troisieme volet de la panne des quatre mois.

Garde volontaire : on ne reconstruit que si un binaire est deja installe.
Quelqu'un qui n'en veut pas ne doit pas en heriter par une mise a jour."
```

---

### Task 4: le garde-fou contre le retour de l'ancien nom

**Files:**
- Create: `tests/bin/stale-binary-references`
- Create: `tests/cases/docs/no-reference-to-the-old-binary-name.yaml`

**Interfaces:**
- Consumes: rien.
- Produces: rien.

Le nom `zsh-env-cli` ne doit plus apparaître dans le code. Deux exceptions, vérifiées avant d'écrire le
contrôle : `migrate_zanvil.zsh`, qui porte volontairement les anciens noms et le dit dans son en-tête,
et la documentation — `web/docs/ROADMAP.md:70` raconte le renommage, donc le scan ne couvre pas les
`.md`.

- [ ] **Step 1: Écrire le script de contrôle**

```bash
#!/usr/bin/env bash
# Imprime les references a l'ancien nom du binaire, hors migration.
#
# Le renommage zsh_env -> zanvil de la v4.0.0 a laisse un binaire zsh-env-cli en
# place pendant quatre mois. Ce controle empeche qu'une reference y revienne par
# inadvertance — dans install.sh, une delegation, ou une page de documentation.
#
# Deux exclusions, toutes deux legitimes :
#   - migrate_zanvil.zsh, dont l en-tete dit qu il porte VOLONTAIREMENT les anciens
#     noms pour detecter une installation heritee ;
#   - la documentation. web/docs/ROADMAP.md raconte le renommage et doit pouvoir
#     nommer l ancien binaire ; interdire le mot dans un historique n aurait aucun
#     sens. Le controle porte sur le CODE, qui lui ne doit plus le connaitre.
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"

grep -rn 'zsh-env-cli' "$ROOT" \
    --include='*.zsh' --include='*.sh' --include='*.rs' --include='*.yaml' \
    2>/dev/null \
    | grep -v 'migrate_zanvil.zsh' \
    | grep -v '/tests/bin/stale-binary-references' \
    | sed "s|^$ROOT/||" || true
```

```bash
chmod +x tests/bin/stale-binary-references
```

- [ ] **Step 2: Vérifier qu'il ne signale rien aujourd'hui**

```bash
cd ~/.zanvil && ZANVIL_DIR="$PWD" tests/bin/stale-binary-references
```

Attendu : aucune sortie. Si une ligne apparaît, c'est une référence à traiter avant de continuer.

- [ ] **Step 3: Écrire le cas**

```yaml
# tests/cases/docs/no-reference-to-the-old-binary-name.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Dr0drigues/gaveldrop/main/docs/case.schema.json
name: no-reference-to-the-old-binary-name
weight: 3
setup:
  env:
    ZANVIL_DIR: "$GAVELDROP_PROJECT"
  run: ["$GAVELDROP_PROJECT/tests/bin/stale-binary-references"]
expect:
  exit_code: 0
  stdout:
    # Vide, sinon le `got` nomme le fichier et la ligne a corriger.
    equals: ""
```

- [ ] **Step 4: Vérifier le vert, puis la faillibilité**

```bash
cd ~/.zanvil && gaveldrop --only no-reference-to-the-old
```

Attendu : `ok no-reference-to-the-old-binary-name 3/3`.

Puis prouver qu'il mord, en introduisant une référence là où elle serait une régression :

```bash
printf '\n# zsh-env-cli\n' >> install.sh
gaveldrop --only no-reference-to-the-old
git checkout install.sh
gaveldrop --only no-reference-to-the-old
```

Attendu : `FAIL` avec `got install.sh:…`, puis `ok` après restauration.

- [ ] **Step 5: Lancer la suite entière**

```bash
gaveldrop && ZANVIL_DIR="$PWD" bash scripts/tests/k9s-log-fmt.test.sh | tail -1 \
  && ZANVIL_DIR="$PWD" bash scripts/tests/zsh-special-vars.test.sh | tail -1
```

Attendu : `59 cases · 59 passed`, puis `13 ok` et `7 ok`.

- [ ] **Step 6: Commit**

```bash
git add tests/bin/stale-binary-references tests/cases/docs/no-reference-to-the-old-binary-name.yaml
git commit -m "test(install): un garde-fou contre le retour de l'ancien nom du binaire

zsh-env-cli a survecu quatre mois au renommage de la v4.0.0. Ce cas refuse
qu'une reference y revienne — dans install.sh, une delegation, un
module — et nomme le fichier fautif.

Deux exclusions : migrate_zanvil.zsh, qui porte volontairement les anciens noms
et le dit, et la documentation — ROADMAP.md raconte le renommage et doit pouvoir
nommer l'ancien binaire."
```

---

### Task 5: réparer la machine, et vérifier que la panne a disparu

**Files:** aucun — cette tâche exécute, elle ne modifie pas le dépôt.

**Interfaces:**
- Consumes: `install.sh` (tâche 2) et `doctor` (tâche 1).
- Produces: rien.

- [ ] **Step 1: Installer le binaire au bon nom**

```bash
cd ~/.zanvil/cli && cargo build --release && mkdir -p ~/.local/bin \
  && cp target/release/zanvil ~/.local/bin/ && rm -f ~/.local/bin/zsh-env-cli
```

- [ ] **Step 2: Vérifier que le PATH le trouve**

```bash
zsh -ic 'command -v zanvil && zanvil --version'
```

Attendu : `/Users/…/.local/bin/zanvil` puis la version courante — et non `zsh-env 3.0.0`.

- [ ] **Step 3: Vérifier que les trois commandes cassées fonctionnent**

```bash
zsh -ic 'zproject list' 2>&1 | tail -3
zsh -ic 'zanvil-doctor' 2>&1 | grep -A1 Binaire
```

Attendu : `zproject list` ne dit plus `command not found: zanvil`, et `doctor` affiche `Binaire ✓` avec
le chemin.

- [ ] **Step 4: Vérifier que le repli n'est plus emprunté**

```bash
zsh -ic 'zanvil-doctor' 2>&1 | head -3
```

Attendu : l'en-tête produit par le binaire Rust (`Zanvil Doctor vX.Y.Z` dans un cadre), et non celui du
repli zsh. C'est la preuve que la délégation aboutit enfin.

- [ ] **Step 5: Consigner le résultat dans le spec**

Ajouter à la fin de la section « Un principe, tiré d'une panne » de
`web/docs/superpowers/specs/2026-08-03-zsh-ou-rust-design.md` :

```markdown
**Réparé le 3 août 2026.** Le binaire est installé sous son nom, `install.sh` retire l'ancien, une mise
à jour reconstruit, et `doctor` signale une absence. Deux cas gaveldrop tiennent la position : l'un
vérifie que `doctor` parle de son binaire, l'autre qu'aucune référence à `zsh-env-cli` ne revient.
```

```bash
git add -f web/docs/superpowers/specs/2026-08-03-zsh-ou-rust-design.md
git commit -m "docs(specs): la panne du binaire est reparee, et tenue par deux cas"
```

---

## Auto-review de ce plan

**Couverture du chantier.** Le spec demandait de « réparer le binaire *et* ajouter le cas qui rendra ce
silence impossible ». Les trois volets du défaut sont couverts par une tâche chacun — visibilité
(tâche 1), nettoyage (tâche 2), reconstruction (tâche 3) — le garde-fou par la tâche 4, et la machine
elle-même par la tâche 5.

**L'ordre est délibéré.** La visibilité vient avant la réparation, parce que c'est elle qui manquait :
un `doctor` qui parle de son binaire aurait fait tomber la panne en quatre secondes au lieu de quatre
mois. Réparer d'abord aurait masqué le symptôme sans installer le témoin.

**Contrainte respectée.** Aucun cas n'asserte que le binaire est installé — les deux vérifient une
propriété vraie sur un poste comme sur un runner : que `doctor` mentionne la section, et qu'aucune
référence à l'ancien nom ne subsiste. Le mur nº 1 du spec précédent est évité.

**Cohérence des noms.** `which_zanvil()` est défini à la tâche 1 et n'est utilisé que là.
`tests/bin/stale-binary-references` porte le même nom dans le script, le cas et le commit. Les comptes
annoncés s'enchaînent : 57 cas aujourd'hui, plus un à la tâche 1 et un à la tâche 4, soit les 59 de la
tâche 4 étape 5.

**Ce que ce plan ne fait pas.** Il ne touche pas `migrate_zanvil.zsh`, et la contrainte dit pourquoi. Il
ne supprime aucun repli zsh : c'est un autre arbitrage, et le spec le garde comme garantie.
