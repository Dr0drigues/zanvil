# Suite de tests gaveldrop — lot 2a : ce qui est migrable aujourd'hui

> **Exécuté, puis largement dépassé le même jour.** Ce plan a été écrit sous trois murs — pas de
> `setup.stdin`, pas de normalisation ANSI, pas d'égalité exacte — que `v0.1.2` a tous levés en réponse au
> finding nº 8. Ce qui en subsiste et ce qui a changé :
>
> - **Le wrapper `tests/bin/k9s-fmt-plain` a été supprimé.** Il a vécu une heure. `setup.stdin` fournit
>   l'entrée, `ignore_ansi` retire les codes.
> - **Les assertions sont des `equals`, pas des `contains`.** Donc la sortie entière, pas un fragment.
> - **36 cas au lieu de 12**, les comptages étant devenus des égalités sur la sortie entière.
> - **La tâche 1 a rempli son office** : c'est elle qui a produit `equals`.
>
> Le plan reste tel qu'il a été écrit, pour que la trace des contraintes du moment et de leur levée soit
> lisible. Le spec porte l'état final.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** migrer en cas gaveldrop les 29 assertions de `scripts/tests/k9s-log-fmt.test.sh` qui sont
traduisibles sans convention artificielle, et remonter à gaveldrop le manque qui bloque les 30 autres.

**Architecture:** un exécutable de plomberie, `tests/bin/k9s-fmt-plain`, comble les deux manques du
format — pas de `setup.stdin`, pas de normalisation ANSI — en recevant l'entrée par argument et en
retirant les codes avant d'écrire sur sa sortie. Les cas restent des faits : une entrée, un attendu.
Le test bash conserve les assertions d'égalité et les comptages, qu'aucun `contains` ne peut exprimer
sans mentir.

**Tech Stack:** gaveldrop v0.1.1 (binaires de release), bash, jq (via le formatteur), zsh.

## Global Constraints

- **Aucune modification de `~/work/misc/gaveldrop`.** Ce qui manque est décrit, jamais corrigé sur place.
- **Version minimale de gaveldrop : v0.1.1** — c'est celle qu'épingle le job CI, et la première où
  `setup.hide` accepte un outil que `fake.bins` déclare.
- **Un cas ne contient aucune logique.** L'entrée et l'attendu sont des faits ; ce qui calcule vit dans
  le wrapper, qui est un vrai programme.
- **Aucune assertion ne doit pouvoir passer pour un mauvais résultat.** `contains: ["2"]` passe sur une
  sortie `12` — vérifié. Toute mesure numérique reste donc hors de gaveldrop pour ce lot.
- **Le wrapper ne compare jamais rien.** Il prépare et normalise. L'attendu appartient au cas.
- Les documents sous `web/docs/superpowers/` sont gitignored : les commits les ajoutent avec `git add -f`.
- Chaque cas est écrit avec un attendu **faux**, lancé pour constater le `FAIL`, puis corrigé.

---

### Task 1: Remonter le mur nº 4 à gaveldrop

**Files:**
- Modify: `web/docs/superpowers/reports/2026-08-03-gaveldrop-shell-adapter.md`

**Interfaces:**
- Consumes: rien.
- Produces: la section « 8. Aucune égalité exacte » du rapport, que la tâche 3 citera pour justifier ce
  qui reste en bash.

- [ ] **Step 1: Vérifier le manque, et le noter tel qu'on le mesure**

```bash
cd /tmp && mkdir -p eqprobe/tests/cases && cd eqprobe
printf 'cases: tests/cases/**/*.yaml\n' > gaveldrop.yaml
cat > tests/cases/does-contains-2-match-12.yaml <<'EOF'
name: does-contains-2-match-12
weight: 1
setup:
  run: ["printf", "12"]
expect:
  exit_code: 0
  stdout:
    contains: ["2"]
EOF
gaveldrop
```

Attendu : `ok does-contains-2-match-12 1/1`. Un `contains` de comptage est donc satisfait par une
valeur fausse.

- [ ] **Step 2: Écrire la section dans le rapport**

À ajouter après la section 7, avec le numéro 8 :

```markdown
## 8. Aucune égalité exacte, ni sur un flux ni sur un fichier

`TextExpectation` n'accepte que `contains` et `absent`, et c'est le seul schéma utilisé par
`expect.stdout`, `expect.stderr` et `expect.files`. Il n'existe donc aucun moyen d'asserter qu'une
sortie **est** une valeur.

Pour un texte, `contains` est souvent assez proche. Pour une mesure, il est faux :

    name: does-contains-2-match-12
    setup:
      run: ["printf", "12"]
    expect:
      stdout:
        contains: ["2"]
    → ok does-contains-2-match-12 1/1

Un test qui compte des lignes et asserte `contains: ["2"]` passe donc sur un résultat de `12`. Ce n'est
pas une assertion faible, c'est une assertion qui affirme le contraire de ce qu'elle vérifie.

Conséquence concrète sur le lot 2 : des 59 assertions de `scripts/tests/k9s-log-fmt.test.sh`, 30 sont
des égalités, dont 12 des comptages (`wc -l`, `awk -F'\t' '{print NF}'`, `grep -c`). Elles restent en
bash — les migrer en `contains` produirait une suite qui ment, et les migrer avec des délimiteurs
maison (`[lines=2]`) reviendrait à inventer une convention pour compenser l'absence de la clé.

**Ce qui manque :** `equals` dans `TextExpectation`. Le nom du champ dit déjà ce qu'il fait, et le
diff serait plus utile que celui d'un `contains` puisque les deux côtés sont connus.

À noter, sans lien avec le format : le `got` complet arrivé en v0.1.1 rend ce manque plus visible, pas
moins — on voit exactement ce qu'on aurait voulu comparer.
```

- [ ] **Step 3: Vérifier qu'aucun fichier de gaveldrop n'a été touché**

```bash
git -C ~/work/misc/gaveldrop status --porcelain
```

Attendu : vide.

- [ ] **Step 4: Commit**

```bash
git add -f web/docs/superpowers/reports/2026-08-03-gaveldrop-shell-adapter.md
git commit -m "docs(gaveldrop): mur nº 4 — aucune egalite exacte dans le format

TextExpectation n'accepte que contains et absent, pour stdout, stderr et
files. Un comptage asserte en contains passe donc sur un mauvais resultat :
contains [\"2\"] est satisfait par une sortie 12, verifie.

Bloque 30 des 59 assertions du lot 2, dont 12 comptages. Elles restent en
bash plutot que de produire une suite qui mente."
```

---

### Task 2: Le wrapper et les cas de rendu

**Files:**
- Create: `tests/bin/k9s-fmt-plain`
- Create: `tests/cases/k9s/*.yaml` (12 cas, listés à l'étape 4)

**Interfaces:**
- Consumes: `gaveldrop.yaml` et son `fake.bins` (lot 1) — aucun des cas k9s ne fake quoi que ce soit,
  mais ils héritent de la configuration.
- Produces: `tests/bin/k9s-fmt-plain`, dont le contrat est :
  - `--line '<texte>'` — une ligne d'entrée, passée telle quelle au formatteur ;
  - `--fixture <chemin>` — un fichier lu depuis `$ZANVIL_DIR` ;
  - `--pairs` — transmis au formatteur ;
  - `--field 1|2` — n'émet que le premier champ (`cut -f1`) ou le second et au-delà (`cut -f2-`) ;
  - `--raw` — n'enlève pas les codes ANSI ;
  - sortie : le rendu du formatteur, codes ANSI retirés sauf `--raw` ;
  - code de sortie : celui du formatteur, sauf `2` pour une option inconnue du wrapper.

- [ ] **Step 1: Écrire le wrapper**

```bash
#!/usr/bin/env bash
# Plomberie pour les cas gaveldrop de k9s-log-fmt.sh.
#
# Existe pour deux manques du format, tous deux dans le rapport :
#   - `setup` n'a pas de `stdin:`, donc un filtre stdin -> stdout n'est pas invocable ;
#   - aucune assertion ne normalise les codes ANSI, et le formatteur entoure chaque
#     champ des siens, donc un `contains` sur une ligne rendue casserait dessus.
#
# Il prepare et normalise. Il ne compare jamais rien : l attendu appartient au cas.
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
FMT="$ROOT/scripts/k9s-log-fmt.sh"

pairs=false raw=false field="" input="" have_input=false

while (( $# )); do
    case "$1" in
        --pairs) pairs=true ;;
        --raw)   raw=true ;;
        --line)
            if (( $# < 2 )); then printf 'k9s-fmt-plain: --line attend une valeur\n' >&2; exit 2; fi
            input="$2"; have_input=true; shift
            ;;
        --fixture)
            if (( $# < 2 )); then printf 'k9s-fmt-plain: --fixture attend un chemin\n' >&2; exit 2; fi
            if [[ ! -f "$ROOT/$2" ]]; then printf 'k9s-fmt-plain: fixture absente: %s\n' "$2" >&2; exit 2; fi
            input="$(cat "$ROOT/$2")"; have_input=true; shift
            ;;
        --field)
            if (( $# < 2 )); then printf 'k9s-fmt-plain: --field attend 1 ou 2\n' >&2; exit 2; fi
            field="$2"; shift
            ;;
        *) printf 'k9s-fmt-plain: option inconnue: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [[ "$have_input" != true ]]; then
    printf 'k9s-fmt-plain: --line ou --fixture est requis\n' >&2
    exit 2
fi

args=()
[[ "$pairs" == true ]] && args+=(--pairs)

out="$(printf '%s\n' "$input" | "$FMT" "${args[@]}")"
ret=$?

case "$field" in
    1) out="$(printf '%s\n' "$out" | cut -f1)" ;;
    2) out="$(printf '%s\n' "$out" | cut -f2-)" ;;
    "") : ;;
    *) printf 'k9s-fmt-plain: --field attend 1 ou 2, recu %s\n' "$field" >&2; exit 2 ;;
esac

if [[ "$raw" == true ]]; then
    printf '%s\n' "$out"
else
    printf '%s\n' "$out" | sed $'s/\033\\[[0-9;]*m//g'
fi

exit "$ret"
```

```bash
chmod +x tests/bin/k9s-fmt-plain
```

- [ ] **Step 2: Vérifier le wrapper à la main, hors gaveldrop**

```bash
cd ~/.zanvil
ZANVIL_DIR="$PWD" tests/bin/k9s-fmt-plain --line '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","message":"Demarrage termine"}'
```

Attendu, sans aucun code ANSI : `08:00:00.123 INFO  Demarrage termine`

```bash
ZANVIL_DIR="$PWD" tests/bin/k9s-fmt-plain --oops ; echo "code=$?"
```

Attendu : `k9s-fmt-plain: option inconnue: --oops` sur stderr et `code=2`.

- [ ] **Step 3: Écrire les douze cas avec un attendu faux**

Chacun sous `tests/cases/k9s/`, avec `weight: 3`. Le patron, à décliner :

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Dr0drigues/gaveldrop/main/docs/case.schema.json
name: k9s-renders-the-logback-pattern
weight: 3
setup:
  env:
    ZANVIL_DIR: "$GAVELDROP_PROJECT"
  run:
    - "$GAVELDROP_PROJECT/tests/bin/k9s-fmt-plain"
    - "--line"
    - '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.FooService","message":"Demarrage termine"}'
expect:
  exit_code: 0
  stdout:
    contains: ["un-attendu-volontairement-faux"]
```

Les douze, avec leur entrée et l'attendu **définitif** — l'attendu faux de cette étape est
`"un-attendu-volontairement-faux"` partout, remplacé à l'étape 5 :

| Fichier | `--line` | Attendu final (`contains`) |
|---|---|---|
| `k9s-renders-the-logback-pattern.yaml` | `{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.FooService","message":"Demarrage termine"}` | `08:00:00.123 INFO  [main] com.boulanger.foo.FooService - Demarrage termine` |
| `k9s-uppercases-the-level.yaml` | `{"@timestamp":"2026-07-28T08:00:01.456Z","level":"error","message":"Boom"}` | `08:00:01.456 ERROR Boom` |
| `k9s-reads-severity-and-msg.yaml` | `{"@timestamp":"2026-07-28T08:00:02.000Z","severity":"WARN","msg":"Alerte"}` | `08:00:02.000 WARN  Alerte` |
| `k9s-pads-the-hour-column-when-absent.yaml` | `{"message":"Sans horodatage"}` | `             INFO  Sans horodatage` |
| `k9s-maps-numeric-levels.yaml` | `{"level":50,"message":"hello"}` | `             ERROR hello` |
| `k9s-abbreviates-a-long-logger.yaml` | `{"level":"DEBUG","logger_name":"com.boulanger.foo.bar.baz.qux.EnormousServiceImplementation","message":"x"}` | `…b.b.q.EnormousServiceImplementation - x` |
| `k9s-truncates-a-long-thread.yaml` | `{"level":"TRACE","thread_name":"http-nio-8080-exec-with-a-very-long-name","logger_name":"com.Pool","message":"x"}` | `[http-nio-8080-exec-…] com.Pool - x` |
| `k9s-omits-empty-brackets-without-a-thread.yaml` | `{"level":"INFO","logger_name":"com.boulanger.foo.FooService","message":"Sans thread"}` | `INFO  com.boulanger.foo.FooService - Sans thread` |
| `k9s-indents-a-stack-trace.yaml` | `{"level":"ERROR","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)\n\t... 24 more"}` | `      at com.Foo.bar(Foo.java:17)` |
| `k9s-renders-mdc-as-key-value.yaml` | `{"level":"WARN","thread_name":"main","logger_name":"com.Cleanup","message":"3 orphelins","http.status":503,"retry":2}` | `http.status=503  retry=2` |
| `k9s-serialises-a-structured-mdc-value.yaml` | `{"level":"INFO","message":"x","nested":{"a":1}}` | `nested={"a":1}` |
| `k9s-shortens-the-exception-in-pairs-mode.yaml` | `{"@timestamp":"2026-07-28T08:00:01.456Z","level":"ERROR","thread_name":"main","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)","retry":2}` | `⤷ IllegalStateException` |

Le dernier prend `--pairs` et `--field 1` en plus de `--line`.

- [ ] **Step 4: Lancer et constater douze échecs**

```bash
cd ~/.zanvil && gaveldrop --only k9s/
```

Attendu : `12 cases · 0 passed · 12 failed`, chacun affichant sous `got` le rendu réel — sans codes
ANSI, ce qui confirme que le wrapper les retire.

- [ ] **Step 5: Remplacer chaque attendu par celui du tableau, puis vérifier**

```bash
cd ~/.zanvil && gaveldrop --only k9s/
```

Attendu : `12 cases · 12 passed · 0 failed`, score `36/36`.

- [ ] **Step 6: Vérifier que la suite entière reste verte**

```bash
gaveldrop
```

Attendu : `26 cases · 26 passed · 0 failed · score 104/104` — les 14 du lot 1 plus les 12 nouveaux.

- [ ] **Step 7: Commit**

```bash
git add tests/bin/k9s-fmt-plain tests/cases/k9s/
git commit -m "test(gaveldrop): douze cas de rendu k9s, via un wrapper de plomberie

Le wrapper existe pour deux manques du format : setup n'a pas de stdin:, donc
un filtre stdin -> stdout n'est pas invocable, et aucune assertion ne
normalise les codes ANSI que le formatteur met autour de chaque champ.

Il prepare et normalise, il ne compare jamais : l'attendu appartient au cas.
L'entree est passee en argument plutot que par une fixture, ce qui garde
chaque cas lisible et autonome."
```

---

### Task 3: Réduire le test bash à ce qu'il seul peut faire

**Files:**
- Modify: `scripts/tests/k9s-log-fmt.test.sh`

**Interfaces:**
- Consumes: les douze cas de la tâche 2, qui couvrent désormais ces assertions.
- Produces: rien.

- [ ] **Step 1: Retirer les douze assertions désormais couvertes**

Supprimer de `scripts/tests/k9s-log-fmt.test.sh` les douze `assert_contains` migrées à la tâche 2 —
celles dont le libellé correspond, une par ligne du tableau. Garder **toutes** les autres : les 30
égalités, les comptages, et les trois sections du viewer.

- [ ] **Step 2: Expliquer en tête du fichier ce qui reste et pourquoi**

À insérer après la ligne `set -uo pipefail` :

```bash
# Ce fichier ne couvre plus que ce que gaveldrop ne peut pas exprimer :
#   - les egalites exactes : TextExpectation n'accepte que contains et absent, donc
#     un comptage asserte en contains passe sur un mauvais resultat — contains ["2"]
#     est satisfait par une sortie 12 ;
#   - les mesures indirectes qui en decoulent (wc -l, awk NF, grep -c) ;
#   - les trois sections du viewer, qui pilotent un faux fzf et son code de sortie.
# Le rendu, lui, est couvert par tests/cases/k9s/ — voir le mur nº 4 du rapport
# web/docs/superpowers/reports/2026-08-03-gaveldrop-shell-adapter.md.
```

- [ ] **Step 3: Vérifier le compte et le vert**

```bash
cd ~/.zanvil && ZANVIL_DIR="$PWD" bash scripts/tests/k9s-log-fmt.test.sh | tail -2
```

Attendu : `43 ok, 0 echec(s)` — les 55 précédentes moins les douze migrées.

- [ ] **Step 4: Vérifier que rien d'autre n'a bougé**

```bash
gaveldrop && ZANVIL_DIR="$PWD" bash scripts/tests/zsh-special-vars.test.sh | tail -1
```

Attendu : `26 cases · 26 passed` et `7 ok, 0 echec(s)`.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/k9s-log-fmt.test.sh
git commit -m "test(k9s): reduire le test bash a ce que gaveldrop ne peut pas exprimer

Douze assertions de rendu partent dans tests/cases/k9s/. Restent les egalites
exactes, les comptages qui en dependent et les trois sections du viewer.

L'en-tete du fichier dit desormais pourquoi elles restent, pour qu'un
relecteur ne les prenne pas pour un oubli de migration."
```

---

## Auto-review de ce plan

**Couverture.** Le lot 2 tel que le spec le décrit visait les 53 assertions et un découpage en
fixtures. Ce plan couvre les 29 traduisibles — dont douze écrites ici, les dix-sept autres étant des
variantes des mêmes patrons, à ajouter au fil de l'eau — et documente pourquoi le reste attend. Deux
écarts assumés par rapport au spec, tous deux justifiés par une mesure :

- **Pas de fixtures découpées.** Les entrées sont passées en `--line`, ce qui garde chaque cas
  autonome et lisible. Le spec prévoyait `tests/fixtures/k9s/*.jsonl` ; il n'y a pas de raison de
  créer trente fichiers pour des entrées d'une ligne. `--fixture` reste disponible pour
  `config/k9s/fixtures/logs-sample.jsonl`, que deux assertions utilisent.
- **Migration partielle, pas intégrale.** Le mur nº 4 l'impose : `contains` sur un comptage passerait
  sur un mauvais résultat.

**Cohérence.** Le wrapper s'appelle `tests/bin/k9s-fmt-plain` dans les trois tâches. Le contrat des
options de la tâche 2 est celui utilisé par les cas du tableau. Les comptes annoncés s'enchaînent :
55 assertions bash aujourd'hui → 43 après la tâche 3, et 14 cas gaveldrop → 26.

**Ce que ce plan ne fait pas.** Les 30 égalités migreront dans un lot 2b, dès que `TextExpectation`
aura une clé `equals`. Rien d'autre ne les bloque : le wrapper les sert déjà.
