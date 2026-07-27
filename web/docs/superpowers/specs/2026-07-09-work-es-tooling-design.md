# Module work — Outillage Elasticsearch générique — Design

**Date** : 2026-07-09
**Statut** : Implémenté
**Release cible** : minor

## Contexte

Le module `work` n'expose qu'une commande ES : `work_fetch_logs` (wrapper de
`fetch_es_logs.sh`, export par scroll). Lors des investigations sur l'ES d'observabilité,
tout le reste (requêtes ad hoc, comptages, découverte des applications) se fait en curl
manuel. Ce projet ajoute un outillage ES **générique** au module : 4 nouvelles
commandes (`work_es_query`, `work_es_apps`, `work_es_count`, `work_es_tail`),
un garde-fou sur `work_fetch_logs` et un volet Elasticsearch dans `work_status`.

**Périmètre strict** : ergonomie d'accès ES uniquement. Aucune logique métier
d'investigation (saleId, détecteurs, baselines) — ça vivra dans le futur projet
`analysis-tools`.

## Décisions structurantes

1. **Tout en zsh** — le CLI Rust n'a pas de client HTTP (il shell-out vers git/fzf),
   et le pattern de délégation du projet exige un fallback zsh complet : déporter
   doublerait l'implémentation sans gain (les commandes sont network-bound).
   Le vrai gain Rust (export massif, tail keep-alive) appartient à `analysis-tools`.
2. **Un seul fichier** : tout dans `modules/work/elasticsearch.zsh` (helpers privés +
   5 commandes publiques + wrapper). Cohésion thématique, pattern du module.
3. **Pas de tests shellspec** — la suite (229 specs) a été délibérément supprimée
   (commit `8135460`) : « tests will be rebuilt in the Rust CLI ». Vérifications :
   `zsh -n`, chargement des complétions, comportement hors réseau.
4. **`fetch_es_logs.sh` intact** — source de vérité externe (`~/work/misc/analysis-tools`
   à terme), resynchronisé récemment. Le garde-fou vit dans le wrapper zsh.
5. **Parsing dates dupliqué, pas factorisé** — le script est bash (`BASH_REMATCH`),
   le module est zsh (`$match`) : duplication propre annotée d'un commentaire
   pointant la source.

## Configuration (env)

| Variable | Défaut | Rôle |
|---|---|---|
| `ES_URL` puis `ZANVIL_WORK_ES_URL` | `https://hote-interne` | URL ES (ordre de résolution) |
| `ES_USER` / `ES_PASSWORD` | — | credentials (env.d/work.zsh), requis avant tout appel |
| `ZANVIL_WORK_ES_INDEX` | `es-apis-*` | index par défaut |
| `ZANVIL_WORK_ES_APPS_TTL` | `3600` | TTL cache work_es_apps (s) |
| `ZANVIL_WORK_ES_MAX_DOCS` | `100000` | seuil du garde-fou work_fetch_logs |

`SSL_CERT_FILE` → `--cacert` (pattern `_work_test_nexus`).

## Helpers privés (elasticsearch.zsh)

- `_work_es_url` / `_work_es_index` : résolution config ci-dessus ;
- `_work_es_require` : garde `ES_USER`/`ES_PASSWORD` + `jq` + `curl`,
  messages `_ui_msg_fail`, return 1 ;
- `_work_es_curl` : curl -s, auth, `Content-Type: application/json`,
  `--cacert` si `SSL_CERT_FILE`, timeouts ;
- `_work_es_parse_duration` : `Xs/Xm/Xh/Xd` → secondes (zsh `$match`) ;
- `_work_es_paris_to_epoch` / `_work_es_epoch_to_iso` : dates Europe/Paris DST auto,
  GNU/BSD date (duplication annotée de fetch_es_logs.sh).

## Commandes

### 1. `work_es_query [METHOD] PATH [BODY]`
- METHOD optionnel (détecté si 1er arg ∈ GET/POST/PUT/DELETE/HEAD) ;
  défaut GET sans body, POST si BODY fourni ;
- PATH relatif à l'URL ES (ex : `es-apis-*/_search`, `_cluster/health`) ;
- BODY : JSON inline ou `-` = stdin (heredocs) ;
- sortie : `jq .` si stdout TTY, brute sinon (pipe-friendly) ;
- HTTP ≥ 400 → corps d'erreur ES affiché, return 1.

### 2. `work_es_apps [RANGE] [--refresh]`
- terms agg sur `application` (size 500), plage en date-math ES (`now-24h` défaut,
  RANGE au format Xm/Xh/Xd) ;
- sortie : `app<TAB>doc_count`, tri volume décroissant ;
- cache `$ZANVIL_DIR/.work_es_apps_cache` (gitignored) : ligne 1 timestamp,
  ligne 2 plage, puis données ; valide si TTL ok **et** plage identique ;
  `--refresh` force.

### 3. `work_es_count --app APP [--since X | --from D [--to D]] [--search TEXT]`
- mêmes options et exclusivités que fetch_es_logs.sh (dates Europe/Paris DST) ;
- scindé : `_work_es_count_query` (JSON brut total/min/max, réutilisé par le
  garde-fou) + `work_es_count` (formatage `_ui_section` : total, fenêtre min→max, durée) ;
- `size: 0` + `track_total_hits` + aggs min/max ; jamais de scroll, aucun fichier.

### 4. Garde-fou dans `work_fetch_logs` (wrapper uniquement)
- extrait `--yes` des args avant délégation ;
- sans `--yes` : comptage via `_work_es_count_query` ; si total >
  `ZANVIL_WORK_ES_MAX_DOCS` → `read -q` de confirmation ;
- **fail-open** : comptage en échec (réseau) → warning + délégation directe,
  le garde-fou ne bloque jamais plus que le script.

### 5. Volet Elasticsearch dans `work_status`
- `_work_es_status_section` définie dans elasticsearch.zsh, appelée par **une ligne**
  ajoutée dans work_context.zsh (détection de contexte intouchée) ;
- hors contexte work → « hors réseau », aucune requête ;
- sinon : creds définis/absents (jamais les valeurs), ping `_cluster/health`
  timeout 2s (green/yellow/red coloré, « injoignable » sinon), rétention =
  agg min `@timestamp` (« n/a » si échec, non bloquant).

### 6. `work_es_tail --app APP [--search TEXT] [--interval N]`
- poll toutes les N s (défaut 5, min 2), démarrage `now-1m` ;
- tri `@timestamp` asc + `search_after` sur le sort value du dernier hit ;
- affichage : `HH:MM:SS [level] message` tronqué à `$COLUMNS` ;
- > 1000 docs par itération → `_ui_msg_warn` « filtre trop large » + saut à now ;
- aucun fichier temporaire → Ctrl-C propre par nature.

## Complétions (completions.zsh)

- une fonction `_work_es_*` + `compdef` par commande publique ;
- `--app` complété depuis le cache apps (lecture fichier seule, **jamais d'appel
  réseau pendant la complétion**, cache périmé accepté), fallback complétion libre ;
- `--yes` ajouté à `_work_fetch_logs`.

## Fichiers touchés

| Fichier | Changement |
|---|---|
| `modules/work/elasticsearch.zsh` | helpers + 4 nouvelles commandes + garde-fou + section status |
| `modules/work/completions.zsh` | 4 nouvelles complétions + `--yes` + `--app` dynamique |
| `modules/work/work_context.zsh` | 1 ligne : appel `_work_es_status_section` dans `work_status` |
| `modules/work/.lazy` | + `work_es_query`, `work_es_apps`, `work_es_count`, `work_es_tail` |
| `.gitignore` | + `.work_es_apps_cache` |
| `examples/env.d/work.zsh` | documenter les nouvelles variables `ZANVIL_WORK_ES_*` |

## Vérifications avant de conclure

- `zsh -n` sur chaque fichier modifié ;
- `.lazy` : les 4 nouvelles fonctions publiques, rien d'autre ;
- complétions chargées sans erreur en shell propre ; `work_fetch_logs --app <TAB>`
  complète depuis le cache si présent ;
- hors réseau : chaque commande échoue proprement (message clair, pas de hang
  au-delà des timeouts) ;
- test réel contre l'ES : **manuel, en contexte work uniquement** (à signaler
  dans le résumé final).

## Hors périmètre

- `fetch_es_logs.sh` (source de vérité externe) ;
- logique métier d'investigation (saleId, sentinelles, timelines, détecteurs) ;
- dépendances au-delà de curl + jq ;
- détection de contexte (`work_is_context`, cache Nexus) ;
- CLI Rust (tail/export haute perf → futur `analysis-tools`).
