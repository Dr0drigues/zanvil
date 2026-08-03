# Demandes d'évolution gaveldrop — depuis zanvil, après les lots 1 et 2a

**Pour un agent travaillant dans `~/work/misc/gaveldrop`.** Rien n'a été modifié là-bas ; tout ce qui
suit est décrit, jamais corrigé sur place.

## Ce qui a produit ces demandes

zanvil est le premier consommateur réel de l'adaptateur shell. État actuel : **26 cas**, `104/104`, sur
ubuntu et macOS, plus 43 assertions bash qui n'ont pas pu migrer. Quatre étapes de `tests.yml`
remplacées, dont trois qui ne pouvaient pas échouer.

Deux de mes findings précédents ont déjà produit un correctif — `setup.hide` acceptant un outil faké, et
le `got` complet. Les demandes ci-dessous sont ce qui reste, par ordre de ce qui coûte.

Le rapport complet, avec les huit findings et leurs preuves :
`~/.zanvil/web/docs/superpowers/reports/2026-08-03-gaveldrop-shell-adapter.md`.

---

## 1. Bloquant : `equals` dans `TextExpectation`

C'est la seule demande qui empêche du travail déjà planifié.

`TextExpectation` n'accepte que `contains` et `absent`, et c'est le seul schéma utilisé par
`expect.stdout`, `expect.stderr` **et** `expect.files`. Il n'existe donc aucun moyen d'asserter qu'une
sortie *est* une valeur.

Pour un texte, `contains` est souvent assez proche. Pour une mesure, il affirme le contraire de ce
qu'il vérifie. Reproduction, telle quelle :

```yaml
name: does-contains-2-match-12
weight: 1
setup:
  run: ["printf", "12"]
expect:
  exit_code: 0
  stdout:
    contains: ["2"]
```

```
ok   does-contains-2-match-12  1/1
```

Un cas qui compte des lignes et asserte `contains: ["2"]` passe sur un résultat de `12`. Ce n'est pas
une assertion faible : c'est une assertion fausse, et elle échappe au critère « tout cas doit pouvoir
échouer » en passant toujours — donc au seul garde-fou qui rende une suite crédible.

**Ce que ça bloque, concrètement.** Des 59 assertions de `scripts/tests/k9s-log-fmt.test.sh`, 30 sont
des égalités, dont 12 des comptages (`wc -l`, `awk -F'\t' '{print NF}'`, `grep -c`). Elles sont restées
en bash. Le lot 2b est écrit et attend : le wrapper les sert déjà, seuls les attendus manquent d'une
clé pour être exprimés.

Deux contournements ont été considérés et écartés, pour que vous n'ayez pas à les proposer :

- **les migrer en `contains`** — produit une suite qui mente, donc pire que le `|| true` qu'elle
  remplace ;
- **faire imprimer `[lines=2]` par le wrapper** pour que `contains` redevienne discriminant — invente
  une convention dans chaque cas afin de compenser l'absence d'une clé, et il faudrait la retirer le
  jour où elle arrive.

**Demande :** `equals` dans `TextExpectation`, applicable partout où le schéma est déjà utilisé. Son
diff serait plus utile que celui d'un `contains`, puisque les deux côtés sont connus — et le `got`
complet de la v0.1.1 le rend immédiatement lisible.

Une question de conception vous appartient : `equals` compare-t-il en ignorant le saut de ligne final ?
Un sujet shell en émet presque toujours un, et l'attendu d'un cas ne l'écrit jamais. Si la réponse est
« à l'octet près », dites-le dans le message d'échec, sinon chaque adoptant y perdra une itération.

---

## 2. Couplées : `setup.stdin` et la normalisation ANSI

Ces deux-là ne bloquent rien — elles imposent un programme intermédiaire côté projet. Prises
séparément, chacune est un désagrément ; ensemble, elles forcent le wrapper.

**`setup` n'a pas de `stdin:`.** `scripts/k9s-log-fmt.sh` est un filtre `stdin → stdout`, la forme la
plus courante d'un outil de terminal. Il n'est pas invocable directement : il faut soit
`run: ["sh", "-c", "… < fixture"]`, qui met de la logique dans un fichier censé tenir des faits, soit un
wrapper.

**Aucune assertion ne normalise les codes ANSI.** Le formatteur en met autour de *chaque* champ —
`^[[2m08:00:00.123^[[0m ^[[1;32mINFO ^[[0m…` — donc un `contains` sur une ligne rendue casse sur les
escapes intercalés. Les écrire dans l'attendu (`"\x1b[2m…"`) fonctionne et devient illisible, ce qui
contredit la première propriété du projet.

**Le point qui compte :** un sujet qui lit stdin **et** colore sa sortie est banal pour un outil de
terminal. C'est le seul endroit où la deuxième propriété — « le projet sous test ne change rien pour
devenir testable » — s'est trouvée en tension : zanvil a dû ajouter `tests/bin/k9s-fmt-plain`, 60 lignes
de plomberie qui n'existent que pour ces deux manques.

Ce sont deux décisions de format, pas des correctifs. Si l'arbitrage est « non », il mérite d'être écrit
dans `docs/shell.md` avec sa raison : un adoptant qui teste un filtre coloré le rencontrera au premier
cas.

---

## 3. Petites corrections, sans arbitrage à rendre

**`min_score` comparé à un score absolu.** L'exemple de `docs/ci.md` — `min_score: 80` — se lit comme
« 80 % », d'autant que `docs/adopting.md` montre juste avant un `score 1/1`. Je l'ai recopié dans mon
spec, où il aurait fait échouer le gate à chaque exécution : le total des poids valait 56. Le message
est exact mais laisse chercher :

```
the weighted score is 68 of 68, below the 80 this project requires
```

Un seuil supérieur au total atteignable est **détectable au chargement de la configuration**, pas
seulement à la fin du run. C'est là qu'il devrait être refusé.

**`docs/adopting.md`, deux lignes qui manquent.** C'est le premier fichier qu'on lit, et les deux
manques m'ont coûté une probe chacun :

- `setup.env` vaut pour **tous** les adaptateurs. Le briefing recommandait un contournement par symlink
  parce que ce n'était écrit nulle part ; il était inutile.
- L'installation demande **deux** crates, `gaveldrop-cli` *et* `gaveldrop-fake`. `cargo` n'installe pas
  les binaires des dépendances, et sans le second toute exécution meurt.

**L'action n'est dans aucun tag.** `Dr0drigues/gaveldrop/action@v0.1.0` ne résout pas — l'action a été
ajoutée après le tag, et `git tag --contains` sur son commit ne renvoie rien. GitHub échoue au démarrage
du job, en trois secondes :

```
Can't find 'action.yml', 'action.yaml' or 'Dockerfile' for action 'Dr0drigues/gaveldrop/action@v0.1.0'
```

Le prochain tag suffira à le régler. zanvil télécharge l'archive de la release en attendant, avec
vérification `sha256` — vingt lignes que l'action remplacera par une, et le workflow porte déjà le
commentaire qui dit d'y rebasculer.

**`hide` retire tout le répertoire de l'outil.** Documenté, et sans conséquence pour zanvil :
`hide: [posting]` fait disparaître `/opt/homebrew/bin` donc aussi delta, lazygit et atuin, mais la
branche testée n'appelle rien d'autre et `zsh`, `cp`, `jq`, `git` vivent ailleurs. À garder en tête si
quelqu'un a besoin de cacher un exécutable sans perdre ses voisins.

---

## Ce que je ne demande pas

**Que `unexpected calls` tolère un appel non prévu.** Mon rapport signalait que le cas chargeant tout un
shell doit porter cinq règles `fake:` pour des outils qui ne l'intéressent pas, uniquement parce que
d'autres cas de la même configuration les déclarent. La réponse — c'est un refus assumé, le combler
affaiblirait la garantie qu'un cas prouve quelque chose — me paraît juste. Le coût réel est cinq lignes
dans un seul cas, et elles documentent au passage les cinq appels d'outils que zanvil fait à chaque
ouverture de shell. Sujet clos de mon côté.

**Des `bins` déclarables par cas.** Je l'avais proposé quand `hide` refusait encore un outil faké ;
`setup.hide` par cas a réglé le besoin par l'autre bout, et mieux. Rien à faire.

---

## Comment vérifier vos correctifs

zanvil est un banc d'essai utilisable en une commande, et c'est probablement ce qu'il apporte de plus
utile maintenant :

```sh
cd ~/.zanvil
gaveldrop                                   # 26 cas, 104/104 attendu
bash scripts/tests/k9s-log-fmt.test.sh      # 43 assertions, ce qui n'a pas pu migrer
```

Les cas couvrent des choses qu'une suite de conformité écrit rarement : un shell complet chargé avec ses
cinq appels d'outils externes, quatre modules dans leurs deux branches — outil présent via `fake.bins`,
outil absent via `setup.hide` — et un `ZANVIL_DIR` construit dans l'isolation par un hook `setup.exec`.

Pour `equals`, le lot 2b est prêt : 30 assertions à traduire, chacune avec son entrée et son attendu
déjà écrits dans `scripts/tests/k9s-log-fmt.test.sh`. Dites-moi quand la clé existe et je les migre —
ce sera aussi le premier usage réel de votre diff d'égalité.
