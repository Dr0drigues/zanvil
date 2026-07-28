# k9s — rendu logback et explorateur de logs interactif

## Problème

Le plugin k9s `Shift-L` formate les logs JSON via `scripts/k9s-log-fmt.sh`, mais son rendu reste pauvre par rapport à une console logback :

- `logger_name` et `thread_name` sont supprimés et **jamais affichés** — impossible de savoir quelle classe ou quel thread a émis l'événement ;
- une stack trace arrive sous forme de champ JSON aux `\n` échappés, illisible sur une seule ligne ou noyée dans les champs extra ;
- le rendu est déversé dans `less`, sans moyen de copier un événement, ni de filtrer autrement qu'avec la recherche de `less`.

Un bug distinct a été corrigé en amont de cette spec : le `plugins.yaml` déployé référençait `$ZSH_ENV_DIR` (nom d'avant le renommage `zsh_env` → `zanvil`). k9s ne résolvant pas cette clé, le chemin du script devenait vide et `less` s'ouvrait sur zéro ligne. `kube_k9s_setup` résout désormais `$ZANVIL_DIR` à la copie.

## Solution

Deux scripts aux responsabilités disjointes, exposés par deux plugins k9s :

```
Shift-L  kubectl logs … | k9s-log-fmt.sh          | less -R +G
Ctrl-L   kubectl logs … | k9s-log-fmt.sh --pairs  | k9s-log-view.sh
```

`k9s-log-fmt.sh` reste un filtre pur `stdin → stdout`, sans état ni fichier temporaire : il gagne le pattern logback et le rendu des stack traces. `k9s-log-view.sh` prend en charge l'interaction et ignore tout du format des logs.

Le formatage ne connaît pas le viewer, le viewer ne connaît pas le format. Le mode statique conserve le streaming, et reste donc le seul compatible avec un éventuel `--follow`.

## Interface

### `scripts/k9s-log-fmt.sh`

Filtre sans argument obligatoire. Un seul flag :

| Flag | Effet |
|------|-------|
| *(aucun)* | Rendu multi-ligne : stack trace complète indentée, champs extra sur une seconde ligne alignée. |
| `--pairs` | **Une ligne de sortie par ligne d'entrée** : texte rendu, TAB, JSON source. Stack trace réduite à un indicateur, champs extra concaténés en fin de ligne. |

Une ligne d'entrée qui n'est pas du JSON valide est réémise telle quelle (comportement actuel, conservé). En `--pairs`, elle occupe le premier champ et se retrouve dupliquée dans le second.

### `scripts/k9s-log-view.sh`

Lit sur stdin un flux au format `--pairs` et lance `fzf` :

```
fzf --ansi --multi --delimiter=$'\t' --with-nth=1
```

`--with-nth=1` masque le JSON source à l'affichage, mais `{2..}` reste accessible aux bindings et au preview. Pas de buffer : `fzf` consomme le flux en continu, l'affichage est progressif.

| Touche | Action |
|--------|--------|
| *(saisie)* | Filtrage fuzzy natif. `'motif` pour une correspondance exacte. Le compteur de matches de `fzf` tient lieu de décompte par niveau. |
| `Tab` | Marque une ligne (sélection multiple). |
| `ctrl-y` | Copie le texte rendu des lignes sélectionnées, codes ANSI et stack trace retirés. Sans sélection, la ligne sous le curseur. |
| `ctrl-o` | Copie le JSON source complet. |
| `⏎` | Rejoue l'événement seul dans `k9s-log-fmt.sh` en mode statique, ouvert dans `less -R` : stack trace complète, puis retour à l'explorateur. |
| `?` | Bascule le panneau de preview. |

Le preview affiche `jq -C .` sur le JSON source, avec repli sur la ligne brute quand `jq` échoue (log non-JSON).

Le presse-papier est résolu une fois au démarrage : `pbcopy`, sinon `wl-copy`, sinon `xclip -selection clipboard`. Si aucun n'est disponible, les bindings de copie sont retirés et le header le signale. Si `fzf` est absent, le viewer se rabat sur `less -R` en n'affichant que le premier champ.

## Format de rendu

Calqué sur le pattern console logback `%d{HH:mm:ss.SSS} %-5level [%thread] %logger{36} - %msg` :

```
08:00:00.123 INFO  [main] c.b.f.FooService - Démarrage terminé
08:00:01.456 ERROR [nio-8080-exec-2] c.b.f.BarClient - Timeout amont
  java.lang.IllegalStateException: Timeout amont
      at com.boulanger.foo.BarClient.send(BarClient.java:17)
      ... 24 more
08:00:02.001 WARN  [scheduling-1] c.b.f.Cleanup - 3 orphelins ignorés
                                  http.status=503  retry=2
```

**Horodatage** — `HH:mm:ss.SSS`, heure seule, extraite du champ ISO par troncature de la partie date. La date reste consultable dans le preview du mode interactif. Champs reconnus, dans l'ordre : `@timestamp`, `timestamp`, `time`. Si aucun n'est présent, la colonne est remplie d'espaces pour préserver l'alignement.

**Niveau** — complété à 5 caractères (`%-5level`). Champs reconnus : `level`, `severity`, `lvl` ; défaut `INFO`. Couleurs inchangées : rouge gras pour `ERROR`/`FATAL`/`CRITICAL`, jaune gras pour `WARN`/`WARNING`, cyan pour `DEBUG`/`TRACE`, vert gras sinon.

**Thread** — `thread_name`, entre crochets, tronqué à 20 caractères avec `…` au-delà. Omis si le champ est absent.

**Logger** — `logger_name`, abrégé selon la règle `%logger{36}` : si le nom dépasse 36 caractères, chaque segment de package est réduit à son initiale, la classe finale étant toujours préservée (`com.boulanger.foo.FooService` → `c.b.f.FooService`). Si le résultat dépasse encore 36 caractères, il est tronqué par la gauche derrière `…`. Omis si le champ est absent.

**Ni le thread ni le logger ne sont complétés à largeur fixe** — c'est le comportement de logback, et un padding cumulé sur les deux colonnes repousserait le message à plus de 80 caractères du bord.

**Message** — `message`, sinon `msg`. Les séquences `\n` et `\t` qu'il contient sont restituées ; en mode `--pairs`, elles sont remplacées par `↵` et un espace pour garantir l'unicité de la ligne.

**Stack trace** — premier champ présent parmi `stack_trace`, `exception`, `stacktrace`, `throwable`. En mode statique, les `\n` sont restitués et chaque ligne est préfixée de deux espaces, en gris. En mode `--pairs`, la stack est réduite au nom court de l'exception extrait de sa première ligne, précédé de `⤷` (`⤷ IllegalStateException`).

**Champs extra (MDC)** — tout ce qui reste après retrait des champs ci-dessus et de `trace_id`, `span_id`, `trace_flags`, rendu en `clé=valeur` séparés par deux espaces, en gris. Sur une seconde ligne indentée en mode statique ; concaténés en fin de ligne et tronqués à 120 caractères en mode `--pairs`. `trace_id` et `span_id` restent masqués — ils encombrent la ligne et sont consultables dans le preview.

Les codes ANSI restent embarqués dans les chaînes produites par `jq`, comme aujourd'hui : le rendu ne dépend pas de la détection d'un TTY, ce qui est nécessaire puisque k9s exécute le plugin à travers deux pipes.

## Déroulé

Mode statique, `Shift-L` sur un pod :

1. k9s suspend son UI et exécute `bash -c '"$@" | … | less -R +G'`.
2. `kubectl logs --tail 500 --all-containers` écrit sur le pipe.
3. `k9s-log-fmt.sh` transforme chaque ligne, en flux.
4. `less -R +G` s'ouvre en fin de log. `q` rend le terminal à k9s.

Mode interactif, `Ctrl-L` sur un pod :

1. Idem, mais `k9s-log-fmt.sh --pairs | k9s-log-view.sh`.
2. `k9s-log-view.sh` résout le presse-papier, construit les bindings, exécute `fzf` en lui passant le flux.
3. L'utilisateur filtre, marque, copie, ou ouvre un événement dans `less`.
4. `Esc` quitte `fzf` et rend le terminal à k9s.

## Modifications

### `scripts/k9s-log-fmt.sh`

Réécriture du filtre `jq`. Le mode est passé à `jq` via `--argjson pairs true|false` plutôt que par deux filtres dupliqués. Ajout du parsing d'argument `--pairs`, et de deux fonctions `jq` : `abbrev_logger` et `short_exception`.

### `scripts/k9s-log-view.sh`

Nouveau, exécutable. Résolution du presse-papier, construction du tableau d'options `fzf`, exécution. Repli `less -R` si `fzf` est absent.

### `config/k9s/plugins.yaml`

Deux entrées supplémentaires, `log-view-pod` (scope `po`) et `log-view-container` (scope `containers`), sur `Ctrl-L`, calquées sur les entrées `log-json-*` existantes. Correction au passage de la description des plugins `log-json-*`, qui mentionne `humanlog` alors que le formatage est assuré par `jq`.

`Ctrl-L` est à confirmer : `tcell` peut l'intercepter comme un rafraîchissement d'écran. Vérification dans `k9s.log` après déploiement ; repli sur `Shift-F` en cas de conflit.

### `config/k9s/fixtures/logs-sample.jsonl`

Nouveau. Jeu de fixtures permettant de rejouer le rendu sans cluster (voir Vérification).

### `modules/kube/kube_config.zsh`

Ajout de la ligne `Ctrl-L` dans `kube_help`, section k9s.

## Hors périmètre

- Brancher `klog` sur `k9s-log-fmt.sh` — il affiche encore du JSON brut. Le formatteur restant un filtre pur, le branchement sera trivial.
- Mode `--follow` interactif : `fzf` exige un flux fini pour rester utilisable.
- Compteurs par niveau dans le header de `fzf` : imposerait de bufferiser tout le flux avant le premier affichage.
- Nettoyage des vestiges repérés pendant le diagnostic : `~/.config/k9s/hotkeys.yaml` divergent et inutilisé sur macOS, `k9s.log` à 12,6 Mo saturé par un `CRDs load Fail` toutes les 15 s (droits RBAC manquants sur `customresourcedefinitions`).

## Vérification

Le projet n'a pas de framework de test et shellspec a été écarté. La vérification repose sur des fixtures rejouables sans cluster :

```bash
scripts/k9s-log-fmt.sh         < config/k9s/fixtures/logs-sample.jsonl
scripts/k9s-log-fmt.sh --pairs < config/k9s/fixtures/logs-sample.jsonl | scripts/k9s-log-view.sh
```

Cas couverts par les fixtures, et attente pour chacun :

| Cas | Attente |
|-----|---------|
| JSON complet (timestamp, level, thread, logger, message, MDC) | Ligne au pattern logback, MDC sur la seconde ligne. |
| Ligne de texte brut (non-JSON) | Statique : réémise à l'identique, sans préfixe ni couleur. `--pairs` : `ligne<TAB>ligne`, affichée à l'identique par `fzf`, preview en repli sur le texte brut. |
| JSON malformé (accolade manquante) | Traité comme du texte brut, réémis à l'identique. |
| Événement avec `stack_trace` | Statique : stack indentée sur plusieurs lignes. `--pairs` : `⤷ NomException`, une seule ligne. |
| Logger de plus de 36 caractères | Packages réduits à leur initiale, classe préservée. |
| Thread de plus de 20 caractères | Tronqué avec `…`. |
| `level` absent | `INFO`, en vert. |
| `thread_name` et `logger_name` absents | Colonnes omises, pas de crochets vides ni de tiret orphelin. |
| Message contenant `\n` | Statique : retour à la ligne restitué. `--pairs` : `↵`, une seule ligne. |
| Champ `severity` au lieu de `level` | Niveau reconnu et coloré. |

Contrôle du contrat `--pairs`, qui conditionne tout le mode interactif :

```bash
# Le nombre de lignes en sortie doit égaler le nombre de lignes en entrée
wc -l < config/k9s/fixtures/logs-sample.jsonl
scripts/k9s-log-fmt.sh --pairs < config/k9s/fixtures/logs-sample.jsonl | wc -l
```

Vérification de bout en bout, en reproduisant l'invocation exacte de k9s :

```bash
bash -c '"$@" | '"$ZANVIL_DIR"'/scripts/k9s-log-fmt.sh | less -R +G' dummy-arg \
  cat "$ZANVIL_DIR/config/k9s/fixtures/logs-sample.jsonl"
```

Puis, dans k9s après `kube_k9s_setup` : `Shift-L` et `Ctrl-L` sur un pod réel, et relecture de `k9s.log` pour confirmer l'absence de warning `No k9s environment matching key` et de conflit de raccourci.
