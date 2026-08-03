# Rapport — premier consommateur de l'adaptateur shell de gaveldrop

**Pour le dépôt gaveldrop.** Rien n'y a été modifié. Ce document décrit ce qui a coûté du temps, ce
qu'il a fallu réimplémenter, et ce qui s'est révélé faux dans les documents d'entrée.

Contexte : le lot 1 de l'adoption dans zanvil est terminé — quatorze cas, deux configurations,
`56/56` et `12/12`, et quatre étapes de `tests.yml` remplacées ou supprimées. Le spec est
`web/docs/superpowers/specs/2026-07-30-gaveldrop-test-suite-design.md`.

## Ce qui a bien marché, brièvement

`setup.env` et `setup.hide` étaient exactement ce qu'il fallait. Les deux ont été construits pour ce
travail avant qu'un seul cas ne soit écrit, et les deux ont fonctionné du premier coup contre les vrais
modules. Le faker aussi : la branche « binaire présent » de quatre modules n'avait jamais été exercée
par aucune CI, et elle l'est maintenant sans qu'aucun outil soit installé.

Le rapport `also written, not asserted` mérite une mention à part. Il a révélé, sans qu'on le cherche,
que `rc.zsh` écrit `.last_update_check` et `.work_context_cache` **dans `$ZANVIL_DIR`** — ce qui a
fondé une décision d'architecture — et que `zanvil doctor` invoque réellement `az` et dépose onze
fichiers dans `$HOME/.azure/`. Aucun test écrit à la main ne nous aurait dit ça.

## 1. Le briefing recommandait un contournement inutile

Il proposait un hook posant `ln -s "$GAVELDROP_PROJECT" "$HOME/.zanvil"`, parce que
`cli/src/config.rs` retombe sur `~/.zanvil`. C'est inutile : `setup.env` alimente l'adaptateur process
exactement comme l'adaptateur shell, donc `ZANVIL_DIR` passé en clair suffit. Vérifié en une probe
(`cli-theme-list-needs-no-symlink`, `ok 1/1`) avant d'écrire le moindre cas.

**Ce que ça dit de gaveldrop :** `setup.env` est moins visible qu'il ne le mérite. Les tests unitaires
de `process.rs` le couvrent pourtant explicitement. Si l'auteur du briefing ne l'a pas vu, un adoptant
ne le verra pas non plus. Une ligne dans `docs/adopting.md` sur le fait que `env` vaut pour **tous** les
adaptateurs coûterait moins que le hook qu'on écrirait à sa place.

## 2. `cargo install` d'un seul crate produit un binaire cassé

`cargo install --path crates/gaveldrop-cli` installe un `gaveldrop` qui meurt sur la première exécution
d'un cas :

```
gaveldrop: the fake binary was not found beside this executable, and it is what shadows the
dependencies a case fakes: no `gaveldrop-fake` beside the running executable
```

Le message est bon — il nomme ce qui manque. Ce qui manquait, c'était la documentation :
`docs/ci.md:18` disait `cargo install gaveldrop`. Corrigé depuis dans le document de mise à jour, qui
donne `cargo install gaveldrop-cli gaveldrop-fake --locked`.

**Suggestion :** la même phrase dans `docs/adopting.md`, qui est le premier fichier qu'on lit.

## 3. Le mur qui subsiste : les deux branches d'un module, une seule configuration

`setup.hide` a levé l'impossibilité de prouver une absence. Il n'a pas levé ceci :

```
case hides `posting` and the project fakes it: `fake.bins` lays down a symlink, which makes it
findable, while `setup.hide` exists to make it unfindable. Take it out of one of them
```

Le refus est juste. Le problème est ailleurs : `fake.bins` vit dans la **configuration**, `cases:`
n'accepte qu'**un seul motif**, et le bloc `fake:` d'un cas n'accepte que `render` et `rules`. Un
module qui a deux branches — présent, absent — ne peut donc pas voir ses deux branches testées dans une
même configuration.

Coût réel pour zanvil : deux fichiers de configuration, deux répertoires de cas, deux invocations en
CI. Ce n'est pas une couverture perdue, c'est une structure imposée par l'outil plutôt que par le sujet.
Et les deux exemples que le briefing donne côte à côte — `posting-warns-when-its-binary-is-missing` et
`posting-deploys-its-config-when-the-binary-is-there` — ne peuvent toujours pas coexister dans le
fichier que le briefing sous-entend.

**Le correctif qui refermerait le sujet :** des `bins` déclarables par cas, en complément de ceux de la
configuration. Un cas qui ne déclare rien hériterait de la configuration ; un cas qui déclare
`fake: { bins: [] }` ou `hide: [...]` s'en soustrairait. Vu de l'extérieur, c'est le pendant naturel de
`setup.hide` : l'un rend introuvable, l'autre devrait pouvoir renoncer à rendre trouvable.

**Corollaire mesuré :** `unexpected calls` est jugé par cas alors que `bins` est global. Le cas qui
charge tout le shell (`rc-loads-without-an-error`) doit donc porter cinq règles `fake:` pour des outils
qui ne l'intéressent pas, uniquement parce que d'autres cas de la même configuration les déclarent.
Sans ces règles :

```
FAIL rc-loads-without-an-error  0/9
    unexpected calls
      got       atuin, delta, lazygit, posting
```

## 4. `got` n'affiche que la première ligne, et ça envoie sur une fausse piste

C'est le point qui m'a coûté le plus de temps sur un cas qui n'avait aucun problème.

`lazygit_setup` produit une sortie dont le premier octet est une séquence de couleur suivie d'un saut de
ligne (`_ui_header` commence par là). Le rapport affiche donc :

```
FAIL lazygit-points-at-the-committed-config-when-the-binary-is-there  0/5
    expect.stdout.contains[0]
      expected  contains "un-chemin-qui-nexiste-pas"
      got
```

Un `got` vide sur une assertion de sortie se lit comme « le sujet n'a rien écrit ». J'ai conclu que la
fonction ne s'exécutait pas, reproduit hors gaveldrop — où elle marchait —, puis écrit un **cas-sonde**
pour interroger l'isolation. La sonde a montré `FN=1`, `HASBIN=oui`, `LG_CONFIG_FILE` correct : tout
allait bien depuis le début, et l'assertion échouait simplement parce que je l'avais voulue fausse.

**Suggestion :** quelques lignes de contexte dans le `got` d'une assertion de flux, ou une mention
explicite du genre `got (first line of 12)`. La troisième propriété du projet — un échec diagnosticable
sans lire gaveldrop — tient ici sur un détail d'affichage.

À noter : `--verbose` n'aurait pas aidé, parce que la question n'était pas « qu'a décidé le moteur »
mais « qu'a écrit le sujet ». Le document de mise à jour conseille `--verbose` plutôt qu'un cas-sonde ;
dans ce cas précis, la sonde était le seul moyen de voir la sortie complète.

## 5. `min_score` se compare à un score absolu

`gate.min_score` est comparé à `summary.score`, pas à un pourcentage (`report.rs:88`). L'exemple de
`docs/ci.md` — `min_score: 80` — se lit naturellement comme « 80 % », d'autant que `docs/adopting.md`
montre juste avant un `score 1/1`. J'ai recopié cet exemple dans le spec, où il aurait fait échouer le
gate à **chaque** exécution : le total des poids de la suite vaut 56.

Le message ne désigne pas la confusion :

```
the weighted score is 56 of 56, below the 80 this project requires
```

Il est exact et pourtant il laisse chercher. « below the 80 this project requires » avec un score
maximal de 56 devrait pouvoir dire que le seuil dépasse le total atteignable — c'est une condition
détectable au chargement de la configuration, pas seulement à la fin du run.

**Autre observation sur le gate :** pour un projet qui ne tolère aucun échec, `min_score` et
`fail_above_weight` sont redondants avec le code de sortie, puisque `is_success()` teste déjà
`failed == 0`. Des trois seuils, seul `max_tolerated` observe quelque chose d'invisible autrement — un
`allow_fail` qui casse, lequel n'incrémente pas `failed` (`report.rs:67`). zanvil n'a donc aucun bloc
`gate:`, et c'est le choix exact.

## 6. Ce qu'il a fallu réimplémenter

**Rien pour le lot 1.** Le hook `tests/hooks/prepare-zanvil-dir.sh` n'est pas une réimplémentation :
il construit un `ZANVIL_DIR` dans l'isolation, ce qui est le travail d'un `setup.exec` et rien d'autre.
Il fait 40 lignes, dont la moitié de commentaires expliquant pourquoi.

**Pour le lot 2, deux manques imposeront un exécutable de plomberie** — annoncé ici parce qu'il n'est
pas encore écrit :

- **`setup` n'a pas de `stdin:`.** `scripts/k9s-log-fmt.sh` est un filtre `stdin → stdout`, la forme la
  plus courante en shell. Il n'est pas invocable directement : il faut soit `run: ["sh", "-c", "… < fixture"]`,
  ce qui met de la logique dans un fichier qui doit tenir des faits, soit un wrapper.
- **Aucune normalisation ANSI avant assertion.** Le formatteur entoure *chaque champ* de codes
  (`^[[2m08:00:00.123^[[0m ^[[1;32mINFO ^[[0m…`), donc un `contains:` sur une ligne rendue casse sur les
  escapes intercalés. Les mettre dans l'attendu (`"\x1b[2m…"`) est possible et illisible, ce qui
  contredit la première propriété du projet. `expect.invariants` ne comble pas le manque : les
  invariants portent sur des *events* JSONL, pas sur du texte.

Ces deux-là se combinent : un sujet qui lit stdin **et** colore sa sortie — un cas très banal pour un
outil de terminal — exige aujourd'hui un programme intermédiaire côté projet. C'est le seul endroit où
la deuxième propriété (« le projet sous test ne change rien ») s'est trouvée en tension.

## 7. `setup.hide` retire tout le répertoire

Documenté, et malgré tout une source de surprise possible. Sur macOS avec Homebrew, `hide: [posting]`
fait disparaître `/opt/homebrew/bin` — donc aussi `delta`, `lazygit` et `atuin`, et tout ce qu'un cas
pourrait vouloir appeler de là. Sans conséquence pour zanvil : la branche absente n'appelle rien
d'autre, et `zsh`, `cp`, `jq`, `git` vivent dans `/bin` et `/usr/bin`. Vérifié avant d'écrire les cas
plutôt qu'après.

La mention dans le document de mise à jour est claire. Ce qui manquerait, si le besoin apparaît un jour,
c'est de cacher **un exécutable** plutôt que son répertoire.

## Ce que je referais pareil

Écrire chaque cas avec un attendu **délibérément faux**, constater le `FAIL`, puis corriger. Sur
quatorze cas, ce cycle a détecté deux fois que j'allais asserter quelque chose qui ne prouvait rien, et
il donne la sortie réelle dans le `got` — ce qui évite d'écrire un attendu de mémoire. Le critère du
briefing — « tout cas remplaçant un `|| true` doit pouvoir échouer » — est exactement la bonne barre, et
il est facile à tenir avec ce cycle.

Et pour le cas de poids 9, aller plus loin : injecter une faute de frappe dans un module chargé au
démarrage, vérifier que le cas rougit, puis restaurer.

```
FAIL rc-loads-without-an-error  0/9
    expect.stderr.absent[0]
      expected  nowhere: "command not found"
      got       …/zanvil/modules/utils//init.zsh:11: command not found: echoo
```

C'est le défaut exact que l'étape CI qu'il remplace laissait passer sans broncher depuis toujours.
