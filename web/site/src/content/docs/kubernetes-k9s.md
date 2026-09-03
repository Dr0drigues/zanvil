---
title: Kubernetes et k9s
description: Contextes, namespaces et les trois plugins de logs k9s — rendu logback, explorateur interactif, rechargement.
---

Le module `kube` gère les kubeconfigs, les alias de contexte, et déploie dans k9s trois plugins qui
transforment des logs JSON en quelque chose de lisible.

## Alias de contexte

Les noms de contexte Kubernetes réels sont longs. `~/.kube/.context_aliases` associe un nom court à
chacun :

```
blg-dev=aks-blg-caasplatform-dev-common-001
blg-qlf=aks-blg-caasplatform-qlf-common-001
```

Le fichier est lu par `kube_switch`, par `k` et par le prompt Starship, qui affiche l'alias plutôt que
le nom complet.

```bash
kube_switch blg-dev     # bascule sur le contexte complet
kube_switch             # sélection fzf si aucun argument
kube_ns                 # sélection du namespace
k blg-dev default       # k9s sur un contexte et un namespace
k blg-dev all           # tous les namespaces
```

## Déployer les plugins

```bash
kube_k9s_setup
```

La commande copie hotkeys, skin et `plugins.yaml` vers le répertoire de configuration de k9s, en
résolvant `$ZANVIL_DIR` **au moment de la copie** : le plugin déployé ne dépend d'aucune variable que
k9s devrait connaître.

:::caution[Emplacement selon la plateforme]
k9s ne lit pas `~/.config/k9s/` sur macOS depuis la v0.32 mais
`~/Library/Application Support/k9s/`. `kube_k9s_setup` écrit au bon endroit ; en cas de doute,
`k9s info` affiche le chemin réellement utilisé.
:::

## Les trois plugins

| Touche | Ce que ça fait |
|--------|----------------|
| `Shift-L` | Logs formatés façon logback, dans `less` |
| `Ctrl-L` | Explorateur interactif `fzf` — filtrer, copier, rejouer un événement |
| `Ctrl-R` | Dans l'explorateur : recharge les logs |

Les deux premiers s'appliquent à un pod comme à un conteneur.

### `Shift-L` — le rendu logback

```
kubectl logs … | k9s-log-fmt.sh | less -R +G
```

Le rendu suit le pattern console de logback
`%d{HH:mm:ss.SSS} %-5level [%thread] %logger{36} - %msg` :

```
08:00:00.123 INFO  [main] c.b.f.FooService - Démarrage terminé
08:00:01.456 ERROR [nio-8080-exec-2] c.b.f.BarClient - Timeout amont
  java.lang.IllegalStateException: Timeout amont
      at com.boulanger.foo.BarClient.send(BarClient.java:17)
      ... 24 more
08:00:02.001 WARN  [scheduling-1] c.b.f.Cleanup - 3 orphelins ignorés
                                  http.status=503  retry=2
```

Ce que le formatteur fait des champs :

- **Horodatage** — l'heure seule, `HH:mm:ss.SSS`. Champs reconnus : `@timestamp`, `timestamp`, `time`.
  Absent, la colonne est remplie d'espaces pour préserver l'alignement.
- **Niveau** — complété à cinq caractères. `level`, `severity` ou `lvl`, texte comme numérique
  (pino, bunyan). Coloré selon la gravité.
- **Thread** — tronqué à 20 caractères, entre crochets, omis s'il manque.
- **Logger** — abrégé selon la règle `%logger{36}` : `com.boulanger.foo.FooService` devient
  `c.b.f.FooService`, la classe finale étant toujours préservée.
- **Stack trace** — restituée et indentée, depuis `stack_trace`, `exception`, `stacktrace` ou
  `throwable`.
- **Champs MDC** — sur une seconde ligne alignée sous le message. `trace_id` et `span_id` sont masqués :
  ils encombrent la ligne et restent consultables dans l'aperçu de l'explorateur.

Une ligne qui n'est pas du JSON valide est réémise telle quelle.

### `Ctrl-L` — l'explorateur

```
kubectl logs … | k9s-log-fmt.sh --pairs | k9s-log-view.sh
```

`fzf` filtre sur le texte rendu — par correspondance exacte, et non en fuzzy — tandis que le JSON
source reste accessible aux raccourcis. Le fuzzy retrouve les lettres d'un motif dispersées n'importe
où dans la ligne : sur des lignes de log, longues, il ramène presque tout (une recherche de `contact`
remontait 486 événements sur 500, dont aucun ne contenait le mot). Il reste joignable terme à terme.

| Touche | Action |
|--------|--------|
| *(saisie)* | Garde les lignes qui contiennent le motif. `'motif` pour un filtrage fuzzy |
| `Ctrl-X` | Bascule en recherche par expression régulière, et en revient |
| `Tab` | Marque une ligne (sélection multiple) |
| `Ctrl-R` | Recharge les logs — relance la commande `kubectl` d'origine |
| `Ctrl-Y` | Copie le texte rendu, codes ANSI retirés |
| `Ctrl-O` | Copie le JSON source complet |
| `⏎` | Rejoue l'événement seul dans le formatteur, stack trace complète, dans `less` |
| `?` | Déplie ou replie l'aperçu JSON — replié au démarrage |
| `Esc` | Quitte et rend le terminal à k9s |

Le presse-papier est résolu au démarrage : `pbcopy`, sinon `wl-copy`, sinon
`xclip -selection clipboard`. Si aucun n'est disponible, les raccourcis de copie disparaissent et
l'en-tête le signale. Si `fzf` est absent, l'explorateur se rabat sur `less`.

`Ctrl-R` rejoue la commande `kubectl` telle qu'elle a été lancée, et ne remplace la liste qu'une fois
la nouvelle sortie complète — la liste ne se vide pas entre-temps. Il réécrit aussi les lignes que le
mode regex filtre, et reste dans le mode où on l'a appelé.

### Le mode regex

`fzf` ne sait pas chercher par expression régulière : sa syntaxe ne connaît que l'exact, les ancres
`^` et `$`, la négation `!` et le `|`. `Ctrl-X` lui retire donc la recherche et la confie à
`k9s-log-grep.sh`, relancé à chaque frappe ; le prompt passe à `regex > `, et un second `Ctrl-X`
rend la main à `fzf`. La requête tapée est conservée d'un mode à l'autre.

Le motif est une expression régulière étendue (POSIX ERE) : `ERROR.*[Cc]laims`,
`gravitee/(sales|supply)`, `BL[0-9]{6}`. Deux choses la distinguent d'un `grep` sur la sortie :

- elle ne voit que le **texte rendu**, jamais le JSON source de la seconde colonne — sinon un motif
  comme `level` ramènerait des lignes où le mot n'apparaît nulle part à l'écran ;
- les **codes ANSI sont retirés** avant comparaison, faute de quoi `^06:49` ne matcherait jamais,
  la ligne commençant par une couleur, et `31m` matcherait tout ce qui est rouge.

Un motif incomplet — `ERROR.*[` pendant la frappe — n'affiche rien et ne dit rien : le compteur
tombe à zéro le temps de finir de taper. Un motif vide laisse passer toutes les lignes.

:::note[Pas de suivi continu]
L'explorateur affiche un instantané des 500 dernières lignes, que `Ctrl-R` rafraîchit. Il n'y a pas
d'équivalent de `tail -f` : `fzf` n'avance pas automatiquement vers les nouvelles lignes, donc un flux
continu remplirait la liste sans que rien ne bouge à l'écran.
:::

## Rejouer sans cluster

`config/k9s/fixtures/logs-sample.jsonl` permet d'éprouver le rendu à la main :

```bash
scripts/k9s-log-fmt.sh         < config/k9s/fixtures/logs-sample.jsonl
scripts/k9s-log-fmt.sh --pairs < config/k9s/fixtures/logs-sample.jsonl | scripts/k9s-log-view.sh
```

## Autres plugins déployés

| Touche | Portée | Action |
|--------|--------|--------|
| `Shift-Y` | deployments, pods, configmaps | YAML live via `delta`, sinon `bat`, sinon `less` |
| `Shift-R` | deployments | `rollout restart`, avec confirmation |
