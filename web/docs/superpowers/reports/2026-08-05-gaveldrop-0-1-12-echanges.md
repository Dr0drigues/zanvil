# Rapport — les échanges de gaveldrop v0.1.12 à l'épreuve

**Pour le dépôt gaveldrop.** Rien n'y a été modifié. Tout a été joué contre l'archive publiée de
`v0.1.12` (somme de contrôle vérifiée), depuis un répertoire de sondes séparé.

Contexte : zanvil est passé de la 0.1.5 à la 0.1.12 d'un coup, sans document de mise à jour dans le
canal. Sept versions, dont quatre corrigent des findings du rapport précédent et trois introduisent un
concept neuf — les échanges. Ce rapport porte sur ce concept, parce que c'est le code le plus récent et
que zanvil en est le premier consommateur shell.

## D'abord, la non-régression

Les **59 cas de zanvil passent sans une modification** : score 223/223, en 11,2 s contre 13,8 s en
0.1.5 — 19 % plus rapide. La deuxième propriété du projet tient donc à travers sept versions, ce qui
est le résultat le plus important de cette session et le seul qui autorisait la suite.

## Ce qui tient, et qu'il faut dire d'abord

Éprouvé et solide :

**L'état de la racine isolée persiste entre les échanges.** Le second lit ce que le premier a écrit.
C'est la condition pour tester un export suivi d'un import, et c'est exactement l'usage que le chantier
2 du spec zsh/Rust attendait.

**Tous les échanges tournent, même après un échec, et toutes les assertions sont rapportées.** Deux
échanges fautifs sur quatre produisent deux verdicts, plus celui de l'assertion globale — dans l'ordre
global puis échanges. Rien ne s'arrête au premier rouge.

**Le verdict situe l'assertion par index *et* par nom** : `steps[1] "le deuxieme se trompe".stdout.contains[0]`.
On ouvre le bon fichier et on trouve la bonne ligne sans compter.

**Le finding #130 est bien appliqué aux échanges.** Un échange sans nom donne `<testcase name="step 1">`
dans le JUnit, pas le `name=""` que le nom de cas vide produisait. Je m'attendais à retrouver là le
motif « le raisonnement appliqué à moitié » ; il ne s'y trouve pas.

**Les effets fichiers sont correctement segmentés par échange**, via un `Snapshot` avant/après dans la
boucle (`process.rs:92-94`). C'est ce qui rend le finding nº 3 ci-dessous surprenant : le remède est
déjà écrit deux lignes plus haut, pour un autre observable.

**`capture` est refusé pour un sujet process, avec sa raison** — « a process answers text, and deciding
that its output is a JSON document to walk by path would invent a meaning for the format rather than
implement one ». Le cas est prévenu à `steps[0].capture.<nom>` au lieu d'échouer plus loin sur un nom
resté littéral.

**Le catch-all reste obligatoire**, et le message le justifie : « without it an unexpected call would
pass for an expected one, and the case would stop proving anything ».

---

## 1. Le `timeout:` borne chaque échange, pas le cas

```yaml
name: quatre-echanges-bloques
timeout: 2
steps:
  - { name: "premier bloque",   request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
  - { name: "deuxieme bloque",  request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
  - { name: "troisieme bloque", request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
  - { name: "quatrieme bloque", request: { run: ["sh", "-c", "while true; do sleep 1; done"] }, expect: {} }
```

```console
FAIL quatre-echanges-bloques  0/1  8.3s
    timeout
      expected  the subject exits within 2.0s
      got       still running after 2.0s, so it was killed. […] it wrote nothing at all
```

**Le cas annonce une limite de 2 s et tient 8,3 s.** Le verdict imprime « exits within 2.0s » à trois
caractères du `8.3s` qu'il vient de mesurer, sans réconcilier les deux. Un cas à vingt échanges avec
`timeout: 30` peut tenir dix minutes en annonçant trente secondes.

Le comptage est également partiel. `gathered()` fait :

```rust
let timed_out_after_ms = steps.iter().filter_map(|seen| seen.timed_out_after_ms).next();
```

`.next()` retient le premier dépassement. Quatre échanges ont été tués ; le rapport en mentionne un.

**Pourquoi ça mérite mieux qu'une ligne de documentation.** C'est le motif exact du finding `timeout: 0`
de la 0.1.5, que la 0.1.6 a corrigé en refusant la valeur : une protection qui paraît resserrée et qui
se relâche. Ici elle se dilue par le nombre d'échanges, et le facteur n'apparaît nulle part —
`grep -i timeout docs/*.md` ne renvoie rien sur les échanges, et le schéma dit « how many seconds **this
case's subject** may run before it is killed », au singulier.

**Piste.** Deux lectures cohérentes, et le choix vous appartient : soit `timeout:` borne le cas et
chaque échange consomme le reste du budget, soit il borne l'échange et le dire dans le schéma — auquel
cas le verdict gagnerait à écrire « each exchange exits within 2.0s » et à compter les dépassements
plutôt que d'en garder un.

## 2. Le diagnostic du timeout cite la sortie d'un échange postérieur

Deux échanges : le premier boucle sans fin, le second écrit `suivant`.

```console
FAIL premier-echange-bloque  0/1  2.1s
    timeout
      got  still running after 2.0s, so it was killed. Raise `timeout:` on the case if it is meant to
           take this long, otherwise start from the last thing it said: suivant
    steps[0] "celui qui ne rend jamais la main".exit_code
      expected  0
      got       -1
```

`suivant` n'a pas été dit par l'échange tué. Il a été dit par le suivant, **après** la mort du premier.
Le message invite à « partir de la dernière chose qu'il a dite » et désigne une sortie postérieure au
blocage — la piste part dans le mauvais sens.

La cause est la même agrégation qu'au nº 1 : le message se sert du `stdout` global, qui concatène les
échanges, alors que le dépassement appartient à un échange précis.

**Ce n'est pas cosmétique.** La troisième propriété du projet est qu'un échec se diagnostique sans lire
gaveldrop. Ici le lecteur cherche pourquoi son sujet a bloqué juste après avoir écrit `suivant`, alors
que `suivant` vient d'ailleurs et d'après. C'est le même service que rendait la version sans échanges,
devenu trompeur du fait qu'il y en a plusieurs.

**Piste.** Prendre la dernière ligne du `stdout` de **l'échange** qui a dépassé, et nommer l'échange
dans le message comme le fait déjà `steps[0] "…"` juste en dessous.

## 3. `expect.calls` dans un échange compte depuis le début du cas

Deux échanges, un appel au binaire falsifié chacun, chacun assertant le sien :

| Échange | Appels réels | Ce qu'il voit |
|---|---|---|
| `steps[0]` | 1 | **1** ✓ |
| `steps[1]` | 1 | **2** ✗ |
| global | 2 | 2 ✓ |

```console
FAIL un-appel-par-echange  0/3
    expect.calls.outil
      expected  1
      got       2
```

Vérifié par élimination : `calls: { outil: 1 }` au premier échange seul passe, la même assertion au
second échoue, et `{ outil: 2 }` au second passe. Le journal n'est donc pas segmenté par échange.

**La conséquence pratique est celle que `writing-cases.md` promet d'éviter.** Cette page défend les
assertions qui ne cassent pas « the day the subject gains one log line » : ici, insérer un échange en
amont fausse l'assertion `calls` de tous les suivants, et écrire celle du troisième échange demande de
compter les appels des deux premiers. Pour zanvil ça mord tout de suite : nos cas du viewer k9s
assertent `calls: { fzf: 1 }`, et leur forme naturelle en échanges — ouvrir, puis rafraîchir par
`Ctrl-R` — verrait 2 au second.

**Le remède est déjà écrit, deux lignes plus haut.** Dans la même boucle, `process.rs:92-94` segmente
les effets fichiers ainsi :

```rust
let before = crate::iso::snapshot::Snapshot::take(iso.root());
let mut seen = one_run(case, iso, &argv)?;
seen.files = before.changes_since(iso.root());
```

Le même avant/après appliqué au journal d'appels donnerait aux `calls` la granularité que les fichiers
ont déjà.

**Un détail qui explique pourquoi ça n'a pas été vu.** Le commentaire de `gathered()` dit « the last
exit and **the last call journal**, because that is what "the run" ended as ». Comme le journal est
cumulatif, « le dernier » vaut « tous » : le global est donc juste, mais pour une raison différente de
celle que le commentaire énonce. Le code et son commentaire décrivent deux mécanismes qui coïncident au
niveau global et divergent par échange.

## 4. Un `calls` violé dans un échange est rapporté comme s'il était global

Dans le verdict ci-dessus, le chemin est `expect.calls.outil`. Il ne nomme aucun échange, alors que
l'assertion violée est celle de `steps[1]`. On cherche donc un défaut dans le bloc `expect:` du cas,
qui est correct.

`verdict.rs:230` est **la seule des sept vérifications de `check()` à ne pas recevoir le préfixe `at`** :

```rust
if let Some(expected) = &expect.calls {
    diffs.extend(calls::check(expected, &observations.calls));   // ← pas de `at`
}
```

Ses voisines le prennent toutes — `stdout` via `&format!("{at}.stdout")`, `stderr`, `events`,
`event_counts`, `invariants`, `status`. Et `verdict/calls.rs:21` écrit le chemin en dur :

```rust
path: format!("expect.calls.{bin}"),
```

**Piste.** Ajouter le paramètre `at` à `calls::check` et composer le chemin comme les six autres. C'est
une correction mécanique, indépendante du nº 3 — elle ne rend pas les comptes justes, elle dit
seulement où regarder.

## 5. « The body was empty » pour un sujet qui n'a pas de body

Un `capture:` déclaré sur un sujet process est correctement refusé (voir plus haut), mais le message
emprunte le vocabulaire du web :

```console
steps[0] "il capture un identifiant".capture.ident
  expected  a value at id
  got       the path yielded no value, so `$ident` stays literal in every later request.
            The body was empty
```

Le sujet avait écrit `{"id":7}` sur sa sortie standard. Le lecteur va donc chercher pourquoi son sujet
n'a rien produit, alors qu'il a produit exactement ce qui était attendu — et que le vrai motif est
qu'un process n'a pas de body du tout.

**Piste.** Pour l'adaptateur process, dire ce que le commentaire du code dit déjà si bien : un process
répond du texte, il n'y a pas de chemin à parcourir. La phrase existe, elle est juste restée dans la
source.

## 6. Les nœuds JUnit d'échange n'ont pas de durée

```xml
<testcase name="the run as a whole" classname="gaveldrop.timeout-par-echange" time="4.645"/>
<testcase name="un et demi"         classname="gaveldrop.timeout-par-echange"/>
<testcase name="encore un et demi"  classname="gaveldrop.timeout-par-echange"/>
<testcase name="et encore"          classname="gaveldrop.timeout-par-echange"/>
```

`writing-cases.md` pose que les durées « are reported everywhere and asserted nowhere », et la 0.1.12 a
ajouté la durée par cas. Les échanges n'en ont pas, ce qui laisse les 4,645 s du run indécomposables :
c'est précisément l'information qui aurait rendu le nº 1 visible sans qu'il faille le chercher.

Mineur seul, utile en même temps que le nº 1.

---

## Un point de documentation, qui n'est pas un défaut

`expect.exit_code` au niveau du cas vaut celui du **dernier** échange. Le cas suivant passe :

```yaml
steps:
  - { name: "celui du milieu echoue vraiment", request: { run: ["sh", "-c", "echo boum >&2; exit 42"] },
      expect: { stderr: { contains: ["boum"] } } }
  - { name: "le dernier reussit", request: { run: ["sh", "-c", "echo fini"] },
      expect: { stdout: { contains: ["fini"] } } }
expect:
  exit_code: 0        # ← vrai, et un échange est sorti en 42
```

C'est assumé par `gathered()` — « that is what "the run" ended as ». Je ne demande pas de le changer :
la définition se défend, et un échange qui échoue exprès au milieu d'un scénario est un usage légitime.

Ce qui manque, c'est de le dire côté utilisateur. `expect.stdout` concatène tous les échanges,
`expect.exit_code` en sélectionne un : deux clés voisines dans le même bloc, deux règles d'agrégation
opposées, aucune des deux écrite dans le schéma. Un cas qui n'observe pas ses échanges un par un croira
avoir vérifié que rien n'a échoué.

## Ce qui manque à côté du code

`docs/shell.md` ne mentionne pas les échanges. Le support existe pourtant, et il est double :
`request: { run: [...] }` pour une commande propre à l'échange, et un échange **sans** `request` qui
réinvoque le `setup.run` — la répétition d'invocation de la #142. J'ai dû le lire dans
`adapters/process.rs` pour l'écrire, ce qui est précisément le geste que la troisième propriété du
projet cherche à rendre inutile.

Deux détails valent d'y figurer, parce qu'ils m'ont coûté un aller-retour chacun : `weight` est requis,
et `expect:` au niveau du cas l'est aussi — même quand chaque échange porte le sien, il faut un
`expect: {}`.

## Ce que je n'ai pas réussi à casser

Consigné pour éviter qu'on le retente : `steps: []` est accepté et se comporte comme un cas sans
échanges ; un échange déclaré mais non effectué est rapporté avec le compte des deux côtés ; un échange
anonyme reste localisable (`steps[0]`, et `step 1` dans le JUnit) ; les fichiers écrits par un échange
sont bien attribués à cet échange ; le nombre d'échanges effectués supérieur au nombre déclaré est
traité comme « the same class of surprise as an unexpected call ».

## Sur la méthode

Une de mes conclusions a été fausse en cours de route. En lisant `gathered()` — `let calls =
steps.last()...` — j'ai d'abord annoncé que les `calls` globaux seraient amputés des échanges
antérieurs, et j'ai construit la sonde pour le prouver. Elle est passée. Le journal étant cumulatif,
le global est juste et c'est **l'attribution par échange** qui est fausse : le défaut existait, un cran
à côté de là où le code me l'avait fait attendre.

C'est la même leçon que la vérification par mutation, prise par l'autre bout : une hypothèse tirée de la
lecture du code se vérifie contre le comportement, pas contre le code.
