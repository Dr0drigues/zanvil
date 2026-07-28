# k9s — rendu logback et explorateur de logs interactif : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner aux plugins de logs k9s un rendu calqué sur une console logback (thread, logger, stack trace lisible) et un second mode interactif permettant de filtrer, rechercher et copier les événements.

**Architecture:** Deux scripts aux responsabilités disjointes. `scripts/k9s-log-fmt.sh` reste un filtre pur `stdin → stdout` piloté par un unique filtre `jq` ; son flag `--pairs` garantit une ligne de sortie par ligne d'entrée, suivie d'un TAB et du JSON source. `scripts/k9s-log-view.sh` consomme ce format et pilote `fzf`, sans rien connaître du format des logs. Deux plugins k9s exposent les deux modes : `Shift-L` (statique, `less`) et `Ctrl-L` (interactif, `fzf`).

**Tech Stack:** bash, jq (filtre unique, codes ANSI embarqués), fzf, less, pbcopy/wl-copy/xclip, zsh (module kube), YAML (plugins k9s).

## Global Constraints

- **Spec de référence :** `web/docs/superpowers/specs/2026-07-28-k9s-log-viewer-design.md`. Toute divergence doit être remontée, pas décidée en silence.
- **Aucun caractère ESC littéral dans les sources.** Les couleurs sont produites par `jq` via l'échappement `\u001b` (validé sur jq 1.7). Le fichier actuel contient des ESC bruts invisibles : ils disparaissent en Task 1.
- **Le rendu ne dépend jamais de la détection d'un TTY.** k9s exécute le plugin derrière deux pipes ; toute logique `[[ -t 1 ]]` casserait les couleurs.
- **`k9s-log-fmt.sh` reste un filtre pur** : pas de fichier temporaire, pas de lecture de `/dev/tty`, pas d'appel réseau. C'est ce qui le rend testable et réutilisable par `klog`.
- **Contrat `--pairs` :** le nombre de lignes en sortie est **strictement égal** au nombre de lignes en entrée. Tout le mode interactif en dépend (`fzf` indexe par ligne).
- **Largeurs :** niveau complété à 5 caractères ; thread tronqué à 20 avec `…` ; logger abrégé à 36 selon la règle `%logger{36}`. **Ni le thread ni le logger ne sont complétés** à largeur fixe.
- **Une ligne d'entrée non-JSON est réémise à l'identique**, sans préfixe ni couleur (comportement actuel, à préserver).
- **Champs masqués :** `trace_id`, `span_id`, `trace_flags` ne sont jamais affichés dans la ligne rendue.
- **Style projet :** commentaire d'en-tête en français dans chaque script, `set -uo pipefail`, pas de `_ui_*` dans les scripts de `scripts/` (ils tournent hors zsh, donc hors système UI).
- **Écart assumé par rapport à la spec :** ce plan ajoute `scripts/tests/k9s-log-fmt.test.sh`, un vérificateur autonome d'une soixantaine de lignes sans dépendance. La spec ne prévoyait qu'une vérification manuelle par fixtures ; le cycle rouge/vert de ce plan a besoin d'un moyen répétable de constater l'échec. Ce n'est pas un framework de test, et cela ne préempte pas le backlog #9 (harnais e2e piloté par YAML).

---

## File Structure

| Fichier | Responsabilité |
|---------|----------------|
| `scripts/k9s-log-fmt.sh` *(modifié)* | Filtre pur. Parse les arguments, porte le filtre `jq` unique. Seul endroit qui connaît le format des logs. |
| `scripts/k9s-log-view.sh` *(créé)* | Viewer interactif. Résout le presse-papier, construit les options `fzf`, exécute. Ignore tout du format des logs. |
| `scripts/tests/k9s-log-fmt.test.sh` *(créé)* | Vérificateur autonome : cas inline, assertions sur la sortie débarrassée des ANSI, code de sortie non nul en cas d'échec. |
| `config/k9s/fixtures/logs-sample.jsonl` *(créé)* | Fixtures rejouables sans cluster : inspection visuelle et contrôle du contrat `--pairs`. |
| `config/k9s/plugins.yaml` *(modifié)* | Ajoute `log-view-pod` et `log-view-container` sur `Ctrl-L`. Corrige la mention obsolète de `humanlog`. |
| `modules/kube/kube_config.zsh` *(modifié)* | Une ligne d'aide dans `kube_help`. |

`k9s-log-fmt.sh` grossit d'environ 40 à 110 lignes : il reste sous le seuil où un découpage se justifierait, et son filtre `jq` forme un tout indissociable.

---

## Task 1 : Socle de test et rendu de base

Remplace le filtre `jq` actuel par une structure à fonctions nommées, avec horodatage court et niveau complété. Le thread et le logger arrivent en Task 2.

**Files:**
- Create: `scripts/tests/k9s-log-fmt.test.sh`
- Create: `config/k9s/fixtures/logs-sample.jsonl`
- Modify: `scripts/k9s-log-fmt.sh` (réécriture du filtre, lignes 1-39)

**Interfaces:**
- Produces: `scripts/k9s-log-fmt.sh` lit stdin, écrit stdout, code de sortie 0. `scripts/tests/k9s-log-fmt.test.sh` sort 0 si tous les cas passent, 1 sinon. Fonctions `jq` disponibles pour les tâches suivantes : `c($code; $s)`, `pad($n)`, `trunc($n)`, `hhmmss`.

- [ ] **Step 1 : Écrire le vérificateur qui échoue**

Créer `scripts/tests/k9s-log-fmt.test.sh` :

```bash
#!/usr/bin/env bash
# Verifie le rendu de k9s-log-fmt.sh. Autonome, sans dependance.
# Usage : scripts/tests/k9s-log-fmt.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
FMT="$ROOT/scripts/k9s-log-fmt.sh"
FIXTURES="$ROOT/config/k9s/fixtures/logs-sample.jsonl"

# Temp directory pour les compteurs (escape subshell issue)
TEST_TMPDIR=$(mktemp -d) || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
echo 0 > "$TEST_TMPDIR/pass"
echo 0 > "$TEST_TMPDIR/fail"

# Retire les codes ANSI : les assertions portent sur le texte, pas les couleurs.
strip_ansi() { sed $'s/\033\\[[0-9;]*m//g'; }

# assert_contains <libelle> <attendu>, entree sur stdin
assert_contains() {
    local label="$1" needle="$2" out
    out=$(strip_ansi)
    if [[ "$out" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        echo $(($(cat "$TEST_TMPDIR/pass") + 1)) > "$TEST_TMPDIR/pass"
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        echo $(($(cat "$TEST_TMPDIR/fail") + 1)) > "$TEST_TMPDIR/fail"
    fi
}

# assert_equals <libelle> <attendu>, entree sur stdin
assert_equals() {
    local label="$1" needle="$2" out
    out=$(strip_ansi)
    if [[ "$out" == "$needle" ]]; then
        printf '  ok   %s\n' "$label"
        echo $(($(cat "$TEST_TMPDIR/pass") + 1)) > "$TEST_TMPDIR/pass"
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        echo $(($(cat "$TEST_TMPDIR/fail") + 1)) > "$TEST_TMPDIR/fail"
    fi
}

echo "== rendu de base =="

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","message":"Demarrage termine"}' \
    | "$FMT" | assert_contains "horodatage court + niveau complete" "08:00:00.123 INFO  Demarrage termine"

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:01.456Z","level":"error","message":"Boom"}' \
    | "$FMT" | assert_contains "niveau en majuscules" "08:00:01.456 ERROR Boom"

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:02.000Z","severity":"WARN","msg":"Alerte"}' \
    | "$FMT" | assert_contains "champs severity et msg reconnus" "08:00:02.000 WARN  Alerte"

printf '%s\n' '{"message":"Sans horodatage"}' \
    | "$FMT" | assert_contains "niveau par defaut INFO, colonne heure vide" "             INFO  Sans horodatage"

printf '%s\n' 'ligne de texte brut' \
    | "$FMT" | assert_equals "texte brut reemis a l identique" "ligne de texte brut"

printf '%s\n' '{"level":"INFO","message":"accolade manquante"' \
    | "$FMT" | assert_equals "JSON malforme traite comme du texte brut" '{"level":"INFO","message":"accolade manquante"'

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:03+02:00","level":"INFO","message":"Offset"}' \
    | "$FMT" | assert_contains "horodatage sans millisecondes" "08:00:03.000 INFO  Offset"

echo
pass=$(cat "$TEST_TMPDIR/pass")
fail=$(cat "$TEST_TMPDIR/fail")
printf '%d ok, %d echec(s)\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
```

Rendre exécutable : `chmod +x scripts/tests/k9s-log-fmt.test.sh`

- [ ] **Step 2 : Lancer le vérificateur pour constater l'échec**

Run: `scripts/tests/k9s-log-fmt.test.sh`

Expected: FAIL sur 5 des 7 cas. Le format actuel produit `2026-07-28T08:00:00.123Z |INFO| Demarrage termine` — horodatage complet, niveau encadré de barres. Deux cas passent déjà et servent de garde-fous de non-régression : « texte brut réémis à l'identique » et « JSON malformé traité comme du texte brut » — le `catch` du filtre actuel les couvre.

- [ ] **Step 3 : Réécrire le filtre**

Remplacer intégralement le contenu de `scripts/k9s-log-fmt.sh` :

```bash
#!/usr/bin/env bash
# k9s-log-fmt.sh — rend des logs JSON au format d'une console logback.
# Filtre pur stdin -> stdout : pas d'etat, pas de fichier temporaire.
# Les codes ANSI sont embarques par jq (\u001b) : le rendu ne depend pas d'un TTY,
# ce qui est necessaire puisque k9s execute le plugin derriere deux pipes.
#
# Usage : kubectl logs ... | k9s-log-fmt.sh [--pairs]
#   (defaut)  rendu multi-ligne : stack trace indentee, champs extra sur 2e ligne
#   --pairs   une ligne par entree : texte, TAB, JSON source (pour k9s-log-view.sh)
set -uo pipefail

pairs=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pairs) pairs=true; shift ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            printf 'k9s-log-fmt.sh: option inconnue : %s\n' "$1" >&2
            exit 2 ;;
    esac
done

JQ_FILTER='
# --- helpers -----------------------------------------------------------------
def c($code; $s): "\u001b[" + $code + "m" + $s + "\u001b[0m";
def pad($n): if length >= $n then . else . + (" " * ($n - length)) end;
def trunc($n): if length > $n then .[0:$n-1] + "…" else . end;

# "2026-07-28T08:00:00.123456Z" -> "08:00:00.123". Chaine vide -> 12 espaces,
# pour que la colonne du niveau reste alignee.
def hhmmss:
  if . == "" then "            "
  else (if test("T") then split("T")[1] else . end) as $t
    | ($t | sub("(Z|[+-][0-9:]+)$"; "")) as $u
    | (if ($u | test("\\."))
       then (($u | split("."))[0] + "." + (($u | split("."))[1][0:3]))
       else $u + ".000" end)
  end;

def level_color:
  if . == "ERROR" or . == "FATAL" or . == "CRITICAL" then "1;31"
  elif . == "WARN" or . == "WARNING" then "1;33"
  elif . == "DEBUG" or . == "TRACE" then "36"
  else "1;32" end;

# --- rendu -------------------------------------------------------------------
. as $line |
try (
  $line | fromjson |

  (.level // .severity // .lvl // "INFO" | ascii_upcase) as $lvl |
  (.["@timestamp"] // .timestamp // .time // "" | tostring | hhmmss) as $hh |
  (.message // .msg // "" | tostring) as $msg |

  c("2"; $hh) + " " + c($lvl | level_color; $lvl | pad(5)) + " " + $msg

) catch $line
'

jq -Rr --argjson pairs "$pairs" "$JQ_FILTER"
```

Note : `--argjson pairs` est déjà passé mais pas encore consommé par le filtre — Task 5 s'en sert. `jq` accepte un argument non utilisé sans broncher.

- [ ] **Step 4 : Lancer le vérificateur pour constater le succès**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: `7 ok, 0 echec(s)`, code de sortie 0.

- [ ] **Step 5 : Créer les fixtures**

Créer `config/k9s/fixtures/logs-sample.jsonl`. **Une entrée par ligne, pas de ligne vide, le fichier se termine par un saut de ligne** (le contrôle de comptage de Task 5 en dépend) :

```
{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.FooService","message":"Demarrage termine"}
{"@timestamp":"2026-07-28T08:00:01.456Z","level":"ERROR","thread_name":"http-nio-8080-exec-2","logger_name":"com.boulanger.foo.BarClient","message":"Timeout amont","stack_trace":"java.lang.IllegalStateException: Timeout amont\n\tat com.boulanger.foo.BarClient.send(BarClient.java:17)\n\tat com.boulanger.foo.FooService.call(FooService.java:42)\n\t... 24 more"}
{"@timestamp":"2026-07-28T08:00:02.001Z","level":"WARN","thread_name":"scheduling-1","logger_name":"com.boulanger.foo.Cleanup","message":"3 orphelins ignores","http.status":503,"retry":2}
{"@timestamp":"2026-07-28T08:00:03.100Z","level":"DEBUG","thread_name":"main","logger_name":"com.boulanger.foo.bar.baz.qux.EnormousServiceImplementation","message":"Logger de plus de 36 caracteres"}
{"@timestamp":"2026-07-28T08:00:04.200Z","level":"TRACE","thread_name":"http-nio-8080-exec-with-a-very-long-thread-name","logger_name":"com.boulanger.foo.Pool","message":"Thread de plus de 20 caracteres"}
{"@timestamp":"2026-07-28T08:00:05.300Z","message":"Sans niveau ni thread ni logger"}
{"@timestamp":"2026-07-28T08:00:06.400Z","severity":"WARN","msg":"Champs severity et msg","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7"}
{"@timestamp":"2026-07-28T08:00:07.500Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.Report","message":"Ligne 1\nLigne 2\nLigne 3"}
Log applicatif en texte brut, emis par un conteneur sidecar
{"@timestamp":"2026-07-28T08:00:08.600Z","level":"INFO","message":"accolade manquante"
```

- [ ] **Step 6 : Vérifier les fixtures à l'œil**

Run: `scripts/k9s-log-fmt.sh < config/k9s/fixtures/logs-sample.jsonl`

Expected: 10 lignes, horodatages courts, niveaux colorés et alignés sur 5 caractères. Le thread, le logger, la stack trace et les champs extra ne sont **pas encore rendus** — c'est normal, Tasks 2 à 4 les ajoutent. La ligne de texte brut et la ligne malformée ressortent à l'identique.

- [ ] **Step 7 : Commit**

```bash
git add scripts/k9s-log-fmt.sh scripts/tests/k9s-log-fmt.test.sh config/k9s/fixtures/logs-sample.jsonl
git commit -m "test(k9s): verificateur de rendu + fixtures de logs

feat(k9s): rendu logback — horodatage court et niveau complete

Les codes ANSI passent d'ESC litteraux (invisibles a la lecture) a
l'echappement \\u001b de jq."
```

---

## Task 2 : Thread et logger

**Files:**
- Modify: `scripts/k9s-log-fmt.sh` (filtre `jq` : ajout de `abbrev_logger`, construction du préfixe)
- Modify: `scripts/tests/k9s-log-fmt.test.sh` (nouvelle section de cas)

**Interfaces:**
- Consumes: `c`, `pad`, `trunc`, `hhmmss`, `level_color` (Task 1).
- Produces: fonction `jq` `abbrev_logger($max)`. Variables du filtre disponibles pour les tâches suivantes : `$pre_plain` (préfixe sans ANSI, sert à calculer l'indentation en Task 4) et `$head` (première ligne colorée, complète).

- [ ] **Step 1 : Écrire les cas qui échouent**

Ajouter à la fin de `scripts/tests/k9s-log-fmt.test.sh`, **avant** le bloc `echo` / `printf '%d ok` final :

```bash
echo
echo "== thread et logger =="

printf '%s\n' '{"@timestamp":"2026-07-28T08:00:00.123Z","level":"INFO","thread_name":"main","logger_name":"com.boulanger.foo.FooService","message":"Demarrage termine"}' \
    | "$FMT" | assert_contains "thread entre crochets, logger, separateur" \
    "08:00:00.123 INFO  [main] com.boulanger.foo.FooService - Demarrage termine"

printf '%s\n' '{"level":"DEBUG","logger_name":"com.boulanger.foo.bar.baz.qux.EnormousServiceImplementation","message":"x"}' \
    | "$FMT" | assert_contains "logger de plus de 36 caracteres abrege" \
    "…b.b.q.EnormousServiceImplementation - x"

printf '%s\n' '{"level":"DEBUG","logger_name":"UneClasseSansAucunPointDontLeNomDepasseTrenteSixCaracteres","message":"x"}' \
    | "$FMT" | assert_contains "logger sans point de plus de 36 caracteres tronque" \
    "…DontLeNomDepasseTrenteSixCaracteres - x"

printf '%s\n' '{"level":"TRACE","thread_name":"http-nio-8080-exec-with-a-very-long-name","logger_name":"com.Pool","message":"x"}' \
    | "$FMT" | assert_contains "thread de plus de 20 caracteres tronque" \
    "[http-nio-8080-exec-…] com.Pool - x"

printf '%s\n' '{"level":"INFO","logger_name":"com.boulanger.foo.FooService","message":"Sans thread"}' \
    | "$FMT" | assert_contains "thread absent : pas de crochets vides" \
    "INFO  com.boulanger.foo.FooService - Sans thread"

printf '%s\n' '{"level":"INFO","thread_name":"main","message":"Sans logger"}' \
    | "$FMT" | assert_contains "logger absent : thread conserve" \
    "INFO  [main] - Sans logger"

printf '%s\n' '{"level":"INFO","message":"Ni thread ni logger"}' \
    | "$FMT" | assert_contains "thread et logger absents : pas de tiret orphelin" \
    "INFO  Ni thread ni logger"
```

- [ ] **Step 2 : Lancer le vérificateur pour constater l'échec**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: les 7 cas de Task 1 passent, les 5 premiers nouveaux cas échouent (thread et logger absents du rendu). Le dernier — « pas de tiret orphelin » — passe déjà, puisque rien n'est encore rendu : c'est un cas de non-régression pour la suite.

- [ ] **Step 3 : Ajouter l'abréviation et le préfixe**

Dans `JQ_FILTER`, ajouter la fonction après `def trunc` :

```jq
# Regle logback %logger{36} : au-dela de $max caracteres, chaque segment de
# package est reduit a son initiale, la classe finale etant preservee.
# "com.boulanger.foo.FooService" -> "c.b.f.FooService"
def abbrev_logger($max):
  if length <= $max then .
  else (split(".")) as $p
    | (if ($p | length) > 1
       then (($p[0:-1] | map(.[0:1])) + [$p[-1]]) | join(".")
       else . end) as $s
    | if ($s | length) <= $max then $s else "…" + $s[-($max-1):] end
  end;
```

Puis remplacer le bloc `# --- rendu` par :

```jq
. as $line |
try (
  $line | fromjson |

  (.level // .severity // .lvl // "INFO" | ascii_upcase) as $lvl |
  (.["@timestamp"] // .timestamp // .time // "" | tostring | hhmmss) as $hh |
  (.message // .msg // "" | tostring) as $msg |
  (.thread_name // "" | tostring) as $thr |
  (.logger_name // "" | tostring) as $log |

  (if $thr == "" then "" else "[" + ($thr | trunc(20)) + "] " end) as $thr_plain |
  (if $log == "" then "" else ($log | abbrev_logger(36)) + " " end) as $log_plain |
  (if $thr == "" and $log == "" then "" else "- " end) as $sep |

  # Prefixe sans ANSI : sert a calculer l indentation de la 2e ligne (Task 4).
  ($hh + " " + ($lvl | pad(5)) + " " + $thr_plain + $log_plain + $sep) as $pre_plain |

  (c("2"; $hh) + " " + c($lvl | level_color; $lvl | pad(5)) + " "
   + (if $thr == "" then "" else c("2"; "[" + ($thr | trunc(20)) + "]") + " " end)
   + (if $log == "" then "" else c("36"; ($log | abbrev_logger(36))) + " " end)
   + $sep + $msg) as $head |

  $head

) catch $line
```

- [ ] **Step 4 : Lancer le vérificateur pour constater le succès**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: `14 ok, 0 echec(s)`.

- [ ] **Step 5 : Commit**

```bash
git add scripts/k9s-log-fmt.sh scripts/tests/k9s-log-fmt.test.sh
git commit -m "feat(k9s): rendu logback — thread et logger abrege (%logger{36})"
```

---

## Task 3 : Stack trace

**Files:**
- Modify: `scripts/k9s-log-fmt.sh` (filtre `jq` : champ stack, rendu multi-ligne)
- Modify: `scripts/tests/k9s-log-fmt.test.sh` (nouvelle section de cas)

**Interfaces:**
- Consumes: `$head`, `$pre_plain` (Task 2).
- Produces: variable `$st` (stack trace brute, `""` si absente) et fonction `jq` `short_exception`, consommées par Task 5.

- [ ] **Step 1 : Écrire les cas qui échouent**

Ajouter à `scripts/tests/k9s-log-fmt.test.sh`, avant le bloc final :

```bash
echo
echo "== stack trace =="

STACK_JSON='{"level":"ERROR","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)\n\t... 24 more"}'

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "premiere ligne de la stack indentee de 2 espaces" \
    "  java.lang.IllegalStateException: Boom"

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "cadres indentes, tabulations converties" \
    "      at com.Foo.bar(Foo.java:17)"

printf '%s\n' "$STACK_JSON" \
    | "$FMT" | assert_contains "dernier cadre" "      ... 24 more"

printf '%s\n' "$STACK_JSON" | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "un evenement avec stack occupe 4 lignes" "4"

printf '%s\n' '{"level":"ERROR","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)\n"}' \
    | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "stack avec newline final : pas de ligne parasite" "3"

printf '%s\n' '{"level":"ERROR","message":"Boom","exception":"java.lang.NullPointerException: null"}' \
    | "$FMT" | assert_contains "champ exception reconnu" "  java.lang.NullPointerException: null"

printf '%s\n' '{"level":"ERROR","message":"Boom","throwable":"java.io.IOException: broken pipe"}' \
    | "$FMT" | assert_contains "champ throwable reconnu" "  java.io.IOException: broken pipe"

printf '%s\n' '{"level":"INFO","message":"Rien a signaler"}' \
    | "$FMT" | assert_equals "sans stack : une seule ligne" \
    "             INFO  Rien a signaler"
```

Note : `assert_equals` reçoit ici la sortie de `wc -l`, pas celle du formatteur — `strip_ansi` s'y applique sans effet, ce qui est inoffensif.

- [ ] **Step 2 : Lancer le vérificateur pour constater l'échec**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: les 6 premiers nouveaux cas échouent (la stack n'est pas rendue, le comptage donne `1` au lieu de `4`). Le dernier passe déjà.

- [ ] **Step 3 : Rendre la stack trace**

Dans `JQ_FILTER`, ajouter après `def abbrev_logger` :

```jq
# Nom court de l exception, extrait de la premiere ligne de la stack.
# "java.lang.IllegalStateException: Boom\n\tat ..." -> "IllegalStateException"
def short_exception:
  split("\n")[0] | split(":")[0] | split(".") | last;
```

Puis, dans le bloc `try`, ajouter la capture du champ après `$log` :

```jq
  (.stack_trace // .exception // .stacktrace // .throwable // "" | tostring) as $st |
```

Et remplacer la dernière expression `$head` par :

```jq
  $head
  + (if $st == "" then ""
     else "\n" + c("2";
       ($st | gsub("\t"; "    ") | sub("\n+$"; "") | split("\n") | map("  " + .) | join("\n")))
     end)
```

- [ ] **Step 4 : Lancer le vérificateur pour constater le succès**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: `22 ok, 0 echec(s)`.

- [ ] **Step 5 : Vérifier le rendu sur les fixtures**

Run: `scripts/k9s-log-fmt.sh < config/k9s/fixtures/logs-sample.jsonl`
Expected: l'entrée `ERROR` de la ligne 2 est suivie de 4 lignes indentées en gris.

- [ ] **Step 6 : Commit**

```bash
git add scripts/k9s-log-fmt.sh scripts/tests/k9s-log-fmt.test.sh
git commit -m "feat(k9s): rendu logback — stack trace restituee et indentee"
```

---

## Task 4 : Champs extra (MDC)

**Files:**
- Modify: `scripts/k9s-log-fmt.sh` (filtre `jq` : extraction et rendu des champs restants)
- Modify: `scripts/tests/k9s-log-fmt.test.sh` (nouvelle section de cas)

**Interfaces:**
- Consumes: `$head`, `$pre_plain`, `$st` (Tasks 2-3).
- Produces: variable `$extra` (`"cle=valeur  cle=valeur"`, `""` si aucun), consommée par Task 5.

- [ ] **Step 1 : Écrire les cas qui échouent**

Ajouter à `scripts/tests/k9s-log-fmt.test.sh`, avant le bloc final :

```bash
echo
echo "== champs extra (MDC) =="

printf '%s\n' '{"level":"WARN","thread_name":"main","logger_name":"com.Cleanup","message":"3 orphelins","http.status":503,"retry":2}' \
    | "$FMT" | assert_contains "champs extra en cle=valeur" "http.status=503  retry=2"

printf '%s\n' '{"level":"WARN","thread_name":"main","logger_name":"com.Cleanup","message":"3 orphelins","retry":2}' \
    | "$FMT" | assert_contains "2e ligne alignee sous le message" \
    "                                        retry=2"

printf '%s\n' '{"level":"INFO","message":"x","trace_id":"4bf92f35","span_id":"00f067aa","trace_flags":"01"}' \
    | "$FMT" | assert_equals "trace_id, span_id et trace_flags masques" \
    "             INFO  x"

printf '%s\n' '{"level":"INFO","message":"x","nested":{"a":1}}' \
    | "$FMT" | assert_contains "valeur structuree serialisee" 'nested={"a":1}'

printf '%s\n' '{"level":"ERROR","message":"Boom","stack_trace":"java.lang.Error: Boom","retry":2}' \
    | "$FMT" | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "extras et stack : 3 lignes" "3"
```

Le deuxième cas fixe l'alignement attendu : préfixe `             WARN  [main] com.Cleanup - ` = 12 + 1 + 5 + 1 + 7 + 12 + 2 = 40 caractères, donc 40 espaces d'indentation.

- [ ] **Step 2 : Lancer le vérificateur pour constater l'échec**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: cas 1, 2, 4 et 5 échouent. Le cas 3 (champs de traçage masqués) passe déjà, puisque aucun extra n'est rendu — il devient un garde-fou pour cette tâche.

- [ ] **Step 3 : Rendre les champs extra**

Dans le bloc `try`, ajouter après la capture de `$st` :

```jq
  (del(
    .["@timestamp"], .timestamp, .time,
    .level, .severity, .lvl,
    .message, .msg,
    .thread_name, .logger_name,
    .stack_trace, .exception, .stacktrace, .throwable,
    .trace_id, .span_id, .trace_flags
   ) | to_entries
     | map("\(.key)=\(if (.value | type) == "string" then .value else (.value | tojson) end)")
     | join("  ")) as $extra |
```

Puis remplacer l'expression finale par :

```jq
  $head
  + (if $extra == "" then ""
     else "\n" + (" " * ($pre_plain | length)) + c("2"; $extra)
     end)
  + (if $st == "" then ""
     else "\n" + c("2";
       ($st | gsub("\t"; "    ") | sub("\n+$"; "") | split("\n") | map("  " + .) | join("\n")))
     end)
```

L'ordre compte : les extras se placent juste sous le message, la stack trace ferme l'événement.

- [ ] **Step 4 : Lancer le vérificateur pour constater le succès**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: `27 ok, 0 echec(s)`.

- [ ] **Step 5 : Vérifier le rendu complet sur les fixtures**

Run: `scripts/k9s-log-fmt.sh < config/k9s/fixtures/logs-sample.jsonl`

Expected: le rendu correspond à l'exemple de la section « Format de rendu » de la spec. Contrôler en particulier que la ligne `WARN` porte `http.status=503  retry=2` aligné sous son message, et que la ligne avec `trace_id` / `span_id` n'affiche aucun extra.

- [ ] **Step 6 : Commit**

```bash
git add scripts/k9s-log-fmt.sh scripts/tests/k9s-log-fmt.test.sh
git commit -m "feat(k9s): rendu logback — champs MDC sur une 2e ligne alignee"
```

---

## Task 5 : Mode `--pairs`

**Files:**
- Modify: `scripts/k9s-log-fmt.sh` (filtre `jq` : branche `$pairs`)
- Modify: `scripts/tests/k9s-log-fmt.test.sh` (nouvelle section de cas)

**Interfaces:**
- Consumes: `$head`, `$extra`, `$st`, `short_exception`, `$line`, et l'argument `--argjson pairs` déjà passé en Task 1.
- Produces: le format consommé par `k9s-log-view.sh` en Task 6 — `<texte rendu><TAB><json source>`, une ligne par entrée.

- [ ] **Step 1 : Écrire les cas qui échouent**

Ajouter à `scripts/tests/k9s-log-fmt.test.sh`, avant le bloc final :

```bash
echo
echo "== mode --pairs =="

PAIRS_JSON='{"@timestamp":"2026-07-28T08:00:01.456Z","level":"ERROR","thread_name":"main","logger_name":"com.Foo","message":"Boom","stack_trace":"java.lang.IllegalStateException: Boom\n\tat com.Foo.bar(Foo.java:17)","retry":2}'

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | wc -l | tr -d ' ' \
    | assert_equals "un evenement avec stack et extras tient sur une ligne" "1"

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | cut -f1 \
    | assert_contains "stack reduite au nom court de l exception" "⤷ IllegalStateException"

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | strip_ansi | cut -f1 \
    | assert_contains "extras concatenes en fin de ligne" "retry=2"

printf '%s\n' "$PAIRS_JSON" | "$FMT" --pairs | cut -f2- \
    | assert_equals "2e champ = JSON source intact" "$PAIRS_JSON"

printf '%s\n' '{"level":"INFO","message":"Ligne 1\nLigne 2"}' | "$FMT" --pairs | strip_ansi | cut -f1 \
    | assert_contains "retours a la ligne du message remplaces par un symbole" "Ligne 1↵Ligne 2"

printf '%s\n' 'texte brut' | "$FMT" --pairs | assert_equals "texte brut duplique dans les deux champs" \
    "$(printf 'texte brut\ttexte brut')"

echo
echo "== contrat --pairs sur les fixtures =="

n_in=$(wc -l < "$FIXTURES" | tr -d ' ')
n_out=$("$FMT" --pairs < "$FIXTURES" | wc -l | tr -d ' ')
printf '%s\n' "$n_out" | assert_equals "$n_in ligne(s) en entree, autant en sortie" "$n_in"

"$FMT" --pairs < "$FIXTURES" | awk -F'\t' '{print NF}' | sort -u | tr '\n' ' ' | sed 's/ $//' \
    | assert_equals "chaque ligne porte exactement 2 champs" "2"

printf '%s\n' '{"level":"INFO","message":"x"}' | "$FMT" --oops 2>/dev/null
printf '%s\n' "$?" | assert_equals "option inconnue : code de sortie 2" "2"
```

- [ ] **Step 2 : Lancer le vérificateur pour constater l'échec**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: les cas `--pairs` échouent — `--pairs` est accepté mais ignoré, donc la sortie reste multi-ligne et sans second champ. Le dernier cas (code de sortie 2) passe déjà.

- [ ] **Step 3 : Implémenter la branche `--pairs`**

Dans `JQ_FILTER`, ajouter après `def short_exception` :

```jq
# Rend une chaine sure pour une ligne unique.
def oneline: gsub("\n"; "↵") | gsub("\t"; " ");
```

Le message est déjà capturé par `(.message // .msg // "" | tostring) as $msg` ; en mode `--pairs`, il doit passer par `oneline`. Remplacer sa capture par :

```jq
  (.message // .msg // "" | tostring | if $pairs then oneline else . end) as $msg |
```

Puis remplacer l'expression finale (celle construite en Task 4) par :

```jq
  (if $pairs then
     $head
     + (if $st == "" then "" else " " + c("2"; "⤷ " + ($st | short_exception)) end)
     + (if $extra == "" then "" else "  " + c("2"; ($extra | oneline | trunc(120))) end)
     + "\t" + $line
   else
     $head
     + (if $extra == "" then ""
        else "\n" + (" " * ($pre_plain | length)) + c("2"; $extra) end)
     + (if $st == "" then ""
        else "\n" + c("2";
          ($st | gsub("\t"; "    ") | sub("\n+$"; "") | split("\n") | map("  " + .) | join("\n"))) end)
   end)
```

Et remplacer le `catch $line` final par :

```jq
) catch (if $pairs then $line + "\t" + $line else $line end)
```

- [ ] **Step 4 : Lancer le vérificateur pour constater le succès**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: `36 ok, 0 echec(s)`.

- [ ] **Step 5 : Commit**

```bash
git add scripts/k9s-log-fmt.sh scripts/tests/k9s-log-fmt.test.sh
git commit -m "feat(k9s): mode --pairs — une ligne par evenement + JSON source"
```

---

## Task 6 : Viewer interactif

**Files:**
- Create: `scripts/k9s-log-view.sh`
- Modify: `scripts/tests/k9s-log-fmt.test.sh` (section de cas sur le repli sans `fzf`)

**Interfaces:**
- Consumes: le format `--pairs` de Task 5.
- Produces: `scripts/k9s-log-view.sh`, lit stdin, sans argument. Consommé par les plugins de Task 7.

- [ ] **Step 1 : Écrire les cas qui échouent**

Ajouter à `scripts/tests/k9s-log-fmt.test.sh`, avant le bloc final :

```bash
echo
echo "== viewer (repli sans fzf) =="

VIEW="$ROOT/scripts/k9s-log-view.sh"

# PATH vide de fzf : le viewer doit se rabattre sur un affichage simple et
# n afficher que le premier champ. LESS=-FX evite d ouvrir un pager interactif.
printf '%s\n' '{"level":"INFO","message":"Bonjour"}' \
    | "$FMT" --pairs \
    | env PATH="/usr/bin:/bin" LESS="-FX" "$VIEW" \
    | assert_contains "repli sans fzf : premier champ affiche" "INFO  Bonjour"

printf '%s\n' '{"level":"INFO","message":"Bonjour"}' \
    | "$FMT" --pairs \
    | env PATH="/usr/bin:/bin" LESS="-FX" "$VIEW" \
    | assert_equals "repli sans fzf : JSON source masque" "             INFO  Bonjour"
```

- [ ] **Step 2 : Lancer le vérificateur pour constater l'échec**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: les 2 nouveaux cas échouent — `scripts/k9s-log-view.sh` n'existe pas, la sortie est vide.

- [ ] **Step 3 : Écrire le viewer**

Créer `scripts/k9s-log-view.sh` :

```bash
#!/usr/bin/env bash
# k9s-log-view.sh — explorateur interactif de logs, pilote par fzf.
# Consomme le format --pairs de k9s-log-fmt.sh : <texte rendu>TAB<json source>.
# Ne connait rien du format des logs : il ne manipule que deux champs.
#
# Usage : kubectl logs ... | k9s-log-fmt.sh --pairs | k9s-log-view.sh
set -uo pipefail

FMT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/k9s-log-fmt.sh"

# --- presse-papier -----------------------------------------------------------
# Resolu une fois : les bindings fzf ne sont construits qu ensuite.
clip=""
if command -v pbcopy >/dev/null 2>&1; then
    clip="pbcopy"
elif command -v wl-copy >/dev/null 2>&1; then
    clip="wl-copy"
elif command -v xclip >/dev/null 2>&1; then
    clip="xclip -selection clipboard"
fi

# --- repli sans fzf ----------------------------------------------------------
# Seul le premier champ est affiche : le JSON source n a d interet qu en
# interactif. sed retire tout ce qui suit la premiere tabulation.
if ! command -v fzf >/dev/null 2>&1; then
    sed 's/\t.*$//' | less -R
    exit $?
fi

# --- construction des options ------------------------------------------------
strip_ansi='sed "s/\x1b\[[0-9;]*m//g"'

header="⏎ evenement complet   ?  preview"
opts=(
    --ansi
    --multi
    --no-sort
    --delimiter=$'\t'
    --with-nth=1
    --prompt="log > "
    --header="$header"
    --preview="printf '%s' {2..} | jq -C . 2>/dev/null || printf '%s' {2..}"
    --preview-window="right:50%:wrap"
    --bind="?:toggle-preview"
    --bind="enter:execute(printf '%s' {2..} | \"$FMT\" | less -R)"
)

if [[ -n "$clip" ]]; then
    header="ctrl-y copier   ctrl-o JSON   ⏎ evenement complet   ?  preview"
    opts+=(
        --header="$header"
        # Copie le texte rendu, sans ANSI ni indicateur de stack.
        --bind="ctrl-y:execute-silent(printf '%s\n' {+1} | $strip_ansi | $clip)"
        --bind="ctrl-o:execute-silent(printf '%s\n' {+2..} | $clip)"
    )
else
    opts+=(--header="$header   (presse-papier indisponible)")
fi

fzf "${opts[@]}" >/dev/null
```

Rendre exécutable : `chmod +x scripts/k9s-log-view.sh`

Notes d'implémentation :
- `--with-nth=1` masque le second champ à l'affichage ; `{2..}` reste disponible aux bindings et récupère tout ce qui suit la première tabulation, ce qui couvre le cas d'une ligne de texte brut contenant elle-même une tabulation.
- `{+1}` et `{+2..}` prennent en compte la sélection multiple (`Tab`) ; sans sélection, `fzf` retombe sur la ligne courante.
- `--header` est passé deux fois quand le presse-papier existe : la dernière occurrence gagne, ce qui évite de dupliquer la liste d'options.
- `>/dev/null` en sortie : le viewer est un terminal d'affichage, il n'émet pas de résultat sur stdout.

- [ ] **Step 4 : Lancer le vérificateur pour constater le succès**

Run: `scripts/tests/k9s-log-fmt.test.sh`
Expected: `38 ok, 0 echec(s)`.

- [ ] **Step 5 : Vérifier l'interactif à la main**

Run: `scripts/k9s-log-fmt.sh --pairs < config/k9s/fixtures/logs-sample.jsonl | scripts/k9s-log-view.sh`

Contrôler, un point après l'autre :
1. Les 10 événements s'affichent sur 10 lignes, la stack réduite à `⤷ IllegalStateException`.
2. Taper `ERROR` : une seule ligne reste, le compteur `fzf` affiche `1/10`.
3. Le panneau de droite montre le JSON coloré par `jq` ; sur la ligne de texte brut, il montre le texte.
4. `?` masque puis rétablit le panneau.
5. `⏎` sur la ligne `ERROR` ouvre `less` avec la stack complète sur 4 lignes ; `q` revient à la liste.
6. `ctrl-y` puis `pbpaste` : le texte rendu, sans codes ANSI.
7. `Tab` sur deux lignes puis `ctrl-y` puis `pbpaste` : les deux lignes.
8. `ctrl-o` puis `pbpaste` : le JSON source de la ligne.
9. `Esc` quitte, code de sortie 0 (`echo $?`).

- [ ] **Step 6 : Commit**

```bash
git add scripts/k9s-log-view.sh scripts/tests/k9s-log-fmt.test.sh
git commit -m "feat(k9s): k9s-log-view.sh — explorateur de logs fzf (filtre, copie)"
```

---

## Task 7 : Plugins k9s et intégration

**Files:**
- Modify: `config/k9s/plugins.yaml` (2 entrées créées, 2 descriptions corrigées)
- Modify: `modules/kube/kube_config.zsh` (`kube_help`, ligne k9s)

**Interfaces:**
- Consumes: `scripts/k9s-log-fmt.sh --pairs` et `scripts/k9s-log-view.sh` (Tasks 5-6).

- [ ] **Step 1 : Corriger les descriptions obsolètes**

Dans `config/k9s/plugins.yaml`, les deux entrées `log-json-pod` et `log-json-container` portent `description: Logs JSON formatés (humanlog)`. Le formatage est assuré par `jq`, pas par `humanlog`. Remplacer les deux occurrences par :

```yaml
    description: Logs formatés (logback)
```

- [ ] **Step 2 : Ajouter les deux plugins interactifs**

Toujours dans `config/k9s/plugins.yaml`, insérer après l'entrée `log-json-container` (avant le commentaire `# YAML live formaté via delta`) :

```yaml
  # Explorateur de logs interactif (fzf) — filtrer, rechercher, copier
  log-view-pod:
    shortCut: Ctrl-L
    description: Logs interactifs (fzf)
    scopes:
      - po
    command: bash
    background: false
    confirm: false
    args:
      - -c
      - '"$@" | $ZANVIL_DIR/scripts/k9s-log-fmt.sh --pairs | $ZANVIL_DIR/scripts/k9s-log-view.sh'
      - dummy-arg
      - kubectl
      - logs
      - $NAME
      - -n
      - $NAMESPACE
      - --context
      - $CONTEXT
      - --tail
      - "500"
      - --all-containers=true

  # Note: dans le scope containers, $NAME = container, $POD = pod
  log-view-container:
    shortCut: Ctrl-L
    description: Logs interactifs (fzf)
    scopes:
      - containers
    command: bash
    background: false
    confirm: false
    args:
      - -c
      - '"$@" | $ZANVIL_DIR/scripts/k9s-log-fmt.sh --pairs | $ZANVIL_DIR/scripts/k9s-log-view.sh'
      - dummy-arg
      - kubectl
      - logs
      - -c
      - $NAME
      - $POD
      - -n
      - $NAMESPACE
      - --context
      - $CONTEXT
      - --tail
      - "500"
```

`$ZANVIL_DIR` est laissé tel quel dans le fichier source : `kube_k9s_setup` le résout à la copie.

- [ ] **Step 3 : Vérifier que le YAML est valide**

Run: `ZANVIL_DIR=/tmp yq '.plugins | keys' config/k9s/plugins.yaml 2>/dev/null || python3 -c "import yaml,sys; print(list(yaml.safe_load(open('config/k9s/plugins.yaml'))['plugins']))"`

Expected: la liste des 7 plugins, dont `log-view-pod` et `log-view-container`.

- [ ] **Step 4 : Compléter l'aide**

Dans `modules/kube/kube_config.zsh`, fonction `kube_help`, sous la ligne `k [ctx] [ns]`, ajouter :

```
  k9s: Shift-L    Logs formatés (logback) dans less
  k9s: Ctrl-L     Logs interactifs (fzf) — filtrer, copier
```

- [ ] **Step 5 : Déployer et contrôler l'absence de warning**

```bash
source ~/.zshrc
kube_k9s_setup
grep -c 'log-view' ~/Library/Application\ Support/k9s/plugins.yaml   # attendu : 2
grep -c '\$ZANVIL_DIR' ~/Library/Application\ Support/k9s/plugins.yaml  # attendu : 0
```

Le second contrôle vérifie que la résolution à la copie a bien opéré : plus aucune variable non résolue dans le fichier déployé.

- [ ] **Step 6 : Valider dans k9s, et arbitrer `Ctrl-L`**

Noter la taille du log avant, pour ne relire que le nouveau :

```bash
wc -l < ~/Library/Application\ Support/k9s/k9s.log
```

Lancer `k9s`, aller sur un pod, puis :
1. `Shift-L` — rendu logback dans `less`, stack traces indentées. `q` pour sortir.
2. `Ctrl-L` — explorateur `fzf`. Filtrer, `ctrl-y`, `⏎`, `Esc`.
3. Entrer dans le pod (`⏎`), se placer sur un conteneur, refaire `Shift-L` et `Ctrl-L` — les deux plugins de scope `containers`.

Puis relire la fin du log :

```bash
tail -n +<ligne notée> ~/Library/Application\ Support/k9s/k9s.log | grep -iE 'plugin|environment matching|shortcut|hotkey'
```

Expected: aucune occurrence de `No k9s environment matching key`, aucun conflit de raccourci.

**Si `Ctrl-L` ne déclenche rien** (interception probable par `tcell` comme rafraîchissement d'écran) : remplacer `shortCut: Ctrl-L` par `shortCut: Shift-F` dans les deux entrées, redéployer via `kube_k9s_setup`, refaire cette étape, et corriger `kube_help` ainsi que la section « Interface » de la spec en conséquence.

- [ ] **Step 7 : Vérification finale de bout en bout**

```bash
scripts/tests/k9s-log-fmt.test.sh
bash -c '"$@" | '"$ZANVIL_DIR"'/scripts/k9s-log-fmt.sh | less -R +G' dummy-arg \
  cat "$ZANVIL_DIR/config/k9s/fixtures/logs-sample.jsonl"
```

Expected: `38 ok, 0 echec(s)`, puis le rendu complet dans `less` — ce second appel reproduit l'invocation exacte de k9s, deux pipes compris.

- [ ] **Step 8 : Commit**

```bash
git add config/k9s/plugins.yaml modules/kube/kube_config.zsh
git commit -m "feat(k9s): plugin Ctrl-L — explorateur de logs interactif

Corrige au passage la description des plugins log-json-*, qui creditait
humanlog alors que le formatage est assure par jq."
```

---

## Self-review

**Couverture de la spec** — chaque section a sa tâche :

| Exigence de la spec | Tâche |
|---|---|
| Horodatage `HH:mm:ss.SSS`, heure seule, 3 champs reconnus, colonne vide si absent | 1 |
| Niveau complété à 5, 3 champs reconnus, défaut `INFO`, couleurs conservées | 1 |
| Ligne non-JSON réémise à l'identique | 1 (statique), 5 (`--pairs`) |
| Thread entre crochets, tronqué à 20, omis si absent | 2 |
| Logger abrégé `%logger{36}`, omis si absent, pas de tiret orphelin | 2 |
| Ni thread ni logger complétés à largeur fixe | 2 |
| Stack trace : 4 champs reconnus, `\n` restitués, indentation, gris | 3 |
| Champs extra : `clé=valeur`, 2e ligne alignée, `trace_id`/`span_id`/`trace_flags` masqués | 4 |
| Message : `\n` restitués en statique, `↵` en `--pairs` | 1 (capture), 5 (`oneline`) |
| Contrat `--pairs` : 1 ligne pour 1 ligne, TAB + JSON source, indicateur `⤷` | 5 |
| Codes ANSI embarqués, indépendants du TTY | 1 (`\u001b`) |
| `fzf` : `--ansi --multi --delimiter --with-nth=1`, filtrage natif | 6 |
| Bindings `ctrl-y`, `ctrl-o`, `⏎`, `?` | 6 |
| Preview `jq -C .` avec repli texte brut | 6 |
| Presse-papier `pbcopy`/`wl-copy`/`xclip`, bindings retirés si absent | 6 |
| Repli `less -R` si `fzf` absent | 6 |
| Flag `-h`/`--help`, option inconnue → code 2 | 1 (implémentation), 5 (cas de test) |
| Plugins `Ctrl-L` scopes `po` et `containers`, arbitrage du raccourci | 7 |
| Correction de la mention `humanlog` | 7 |
| `kube_help` | 7 |
| Fixtures `logs-sample.jsonl`, 10 cas du tableau de vérification | 1 (création), 3-5 (exploitation) |
| Vérification de bout en bout reproduisant l'invocation k9s | 7 |

**Hors périmètre, conforme à la spec** : `klog` n'est pas modifié, aucun mode `--follow` interactif, pas de compteurs par niveau dans le header, aucun nettoyage de `~/.config/k9s` ni de `k9s.log`.

**Cohérence des noms** — fonctions `jq` : `c`, `pad`, `trunc`, `hhmmss`, `level_color` (Task 1), `abbrev_logger` (Task 2), `short_exception` (Task 3), `oneline` (Task 5). Variables : `$lvl`, `$hh`, `$msg` (1), `$thr`, `$log`, `$thr_plain`, `$log_plain`, `$sep`, `$pre_plain`, `$head` (2), `$st` (3), `$extra` (4), `$pairs` (argument, déclaré en 1, consommé en 5). Scripts : `k9s-log-fmt.sh`, `k9s-log-view.sh`, `k9s-log-fmt.test.sh`. Aucun renommage entre tâches.

**Comptage cumulé des assertions** : 7 (T1) → 14 (T2) → 22 (T3) → 27 (T4) → 36 (T5) → 38 (T6). Les totaux annoncés aux étapes « constater le succès » suivent cette progression.
