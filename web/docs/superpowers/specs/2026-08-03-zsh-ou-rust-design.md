# zsh ou Rust — la ligne de partage, et ce qui doit la traverser

## Problème

zanvil porte ~14 700 lignes de zsh et 5 359 de Rust, réparties sans critère écrit. Chaque nouvelle
fonction pose donc la même question sans réponse, et deux réponses opposées ont déjà été données au
même endroit : `zanvil-doctor` délègue au CLI avec un repli zsh complet, tandis que `zanvil-sync`
ignore un `zanvil sync` qui fait la même chose.

Ce document fixe la ligne, chiffre ce qui la traverse, et donne l'ordre.

## La carte, mesurée

**Volumes.** zsh : core 3 124, git 2 262, kube 1 576, ai 1 382, project 1 165, tools 1 144,
gitlab 1 015, work 836, security 743, zproject 604, ssh 339, docker 315, utils 166. Rust : project
1 628, mr_fanout 1 147, tui_config 514, doctor 390, sync 288, update 236, secrets 216, audit 197,
theme 195, config 139, modules 116, context 91, bench 52, plus main 100 et mod 50.

**Le résultat contre-intuitif, et il ferme un débat avant qu'il s'ouvre.** La performance n'est pas un
argument pour migrer :

| Étape du démarrage | Coût |
|---|---|
| Les 12 modules zsh cumulés | 0,22 s |
| Completions des modules | 0,07 s |
| `compinit` | 0,02 s |
| **Hooks** — `starship`, `mise`, `zoxide`, `direnv`, `atuin` init | **0,63 s** |
| `rc.zsh` complet | 1,76 s |

Le code zsh du projet coûte ~0,3 s ; les `eval "$(outil init)"` en coûtent le double, et aucune
réécriture n'y changera quoi que ce soit. Le démarrage d'un binaire Rust, lui, coûte **14 ms** —
acceptable pour une commande interactive, cher à chaque prompt.

## Trois catégories

### Ce qui ne peut pas migrer

Un binaire ne modifie pas le shell qui l'appelle. Environ 150 occurrences de `cd`, `export`, `unset`,
`alias`, `source`, `compdef` et `setopt`, concentrées dans git (26), zproject (23), kube (23),
gitlab (16), tools (12) — plus les hooks `chpwd` de `.zanvil.local` et de `zproject`.

C'est une contrainte, pas un arbitrage. Une fonction qui doit changer de répertoire, exporter une
variable ou déclarer une complétion **est** du shell.

### Ce qui ne devrait pas migrer

**Ce qui est appelé à haute fréquence.** 14 ms par invocation, multipliés par chaque prompt ou chaque
`cd`. Le prompt Starship appelle déjà `zanvil context` : c'est la limite haute de ce qu'on peut se
permettre, pas un modèle à étendre.

**Ce qui ne fait qu'orchestrer un outil externe.** `klog` (142 lignes) et `kube_azure` (121) sont des
enchaînements autour de `kubectl` et `az`. Les réécrire déplacerait le code sans toucher ni au coût ni
à la fragilité. La règle, formulée pour être citable : **on ne migre pas un `for` autour d'un
`kubectl`.**

### Ce qui devrait migrer

La dépendance à des outils dont le comportement diverge selon la plateforme, là où il n'y a pas d'effet
shell :

| Fichier | `date` | `jq` | `awk`/`sed` | effet shell | lignes |
|---|---|---|---|---|---|
| `modules/work/elasticsearch.zsh` | **14** | **22** | 2 | **0** | 551 |
| `core/commands/commands.zsh` | 0 | 9 | 19 | **0** | 414 |
| `core/lifecycle/sync.zsh` | 1 | 15 | 6 | **0** | 274 |
| `modules/gitlab/gitlab_logic.zsh` | 6 | 14 | 0 | 7 | 360 |

Sur l'ensemble du zsh : 159 `grep`, 82 `sed`, 65 `jq`, 59 `tr`, 49 `date`, 41 `awk`. Deux dettes sont
déjà payées à la main, et ce sont elles qui justifient le critère :

- `elasticsearch.zsh:81-88` embarque un **détecteur de variante `date`** GNU/BSD, écrit parce que
  `date -d` et `date -j -f` ne coexistent pas ;
- son en-tête admet une duplication : « Duplication annotee de modules/work/fetch_es_logs.sh (bash) :
  reecrit en zsh. Garder les deux versions synchronisees. »

`chrono` et `serde` les font disparaître toutes les deux.

## Un principe, tiré d'une panne

Le repli zsh derrière une délégation est documenté comme une garantie. C'en est une, mais elle a un
prix qu'il faut écrire : **un repli silencieux masque une panne.**

Constaté sur la machine de développement pendant la cartographie : `~/.local/bin/` contient
`zsh-env-cli` v3.0.0 daté d'avril, et pas `zanvil`. Depuis le renommage de la v4.0.0,
`command -v zanvil` échoue, donc :

- `zproject list|config|doctor|diff` **est cassé** — `command not found: zanvil` ;
- `git_mr_fanout` refuse de démarrer, et 1 147 lignes de Rust avec lui ;
- `zanvil-doctor`, `zanvil-theme` et `security_audit` tournent en mode dégradé **sans le dire**.

`core/lifecycle/migrate_zanvil.zsh` ne prévoit pas le renommage du binaire installé. Quatre mois se
sont écoulés sans que rien ne le signale, précisément parce que le repli fonctionnait.

Conséquence pour la ligne de partage : un repli est acceptable s'il est **visible**. Le premier
chantier répare le binaire *et* ajoute le cas qui rendra ce silence impossible.

**Réparé le 3 août 2026**, et le défaut avait un volet de plus que les trois annoncés :

1. `install.sh` retire désormais l'ancien binaire, qui survivait au renommage ;
2. `_zanvil_do_update` reconstruit le binaire après un `git pull`, au lieu de le laisser périmer ;
3. `doctor` porte une section `Binaire` et compte son absence comme une erreur ;
4. **`auto-release.yml` bump les deux versions.** `cli/Cargo.toml` était resté en 3.1.0 quand le projet
   affichait v4.4.0 : le même binaire annonçait deux versions contradictoires. C'est ce qui a fait
   passer `zsh-env-cli` v3.0.0 pour une installation valide — un binaire qui répond à `--version`
   inspire confiance, même quand le numéro n'a plus de rapport avec le dépôt.

Deux cas gaveldrop tiennent la position : l'un vérifie que `doctor` parle de son binaire, l'autre
qu'aucune délégation ne revient à l'ancien nom. Aucun des deux n'asserte que le binaire est installé —
ce serait vrai sur un poste et faux sur un runner.

Sur la machine : `zproject list`, `zanvil-mr-fanout` et `zanvil-doctor` répondent, ce dernier depuis le
Rust et non plus depuis son repli.

## Les cinq chantiers, dans l'ordre

| # | Chantier | Ce qui le motive |
|---|---|---|
| 1 | **Réparer le binaire** | `zsh-env-cli` au lieu de `zanvil` : trois commandes cassées ou dégradées, 5 359 lignes de Rust inertes. La migration doit renommer, et un cas doit l'attraper. |
| 2 | **`sync`** | Doublon pur : 274 lignes de zsh et 288 de Rust pour le même export/import/diff, avec **zéro** délégation entre les deux. |
| | ↳ **fait le 5 août 2026**, et « doublon » était faux — voir ci-dessous. |
| 3 | **`work/elasticsearch`** | 38 dépendances fragiles, le détecteur `date`, la duplication annotée avec `fetch_es_logs.sh`. |
| 4 | **`core/commands/commands.zsh`** | 24 appels `jq`/`awk`/`sed` dans `zanvil-list`, `-status`, `-help`, `-doctor-conflicts`. `zanvil-doctor` est hors périmètre : il délègue déjà. |
| | ↳ **fait le 5 août 2026** — 7 appels sur 22, pas 24 : voir ci-dessous. |
| 5 | **`gitlab_logic`** | 20 fragiles, mais 7 effets shell : migration **partielle**, la façade et les `export` restent en zsh. |
| | ↳ **fait le 5 août 2026** — les 6 `date`, pas les 14 `jq` : voir ci-dessous. |

### Chantier 2 — ce que la caractérisation a corrigé dans ce spec

Le tableau ci-dessus annonce un « doublon pur ». **C'était faux, et c'est la caractérisation qui l'a
montré** — avant qu'une ligne de Rust ne soit écrite. Les deux implémentations ne faisaient pas la même
chose, et le CLI était incomplet en silence :

| Sous-commande | Ce que le CLI perdait |
|---|---|
| `export` | les plugins — `plugins: vec![]` en dur, donc un poste qui en déclarait les perdait à la synchronisation |
| `import` | **cinq réglages sur sept** : les trois d'auto-update et les deux thèmes clair/sombre, avec « Config importee » quand même |
| `diff` | le thème n'était pas comparé, donc deux différences annoncées là où il y en avait trois |
| les trois | aucun header, ce que la convention UI du projet exige |

Brancher la délégation sur cet état aurait donc **régressé**, silencieusement, sur la commande dont le
métier est justement de ne rien perdre entre deux machines. C'est l'argument le plus concret pour l'ordre
des quatre étapes : ce n'est pas une précaution de principe, c'est ce qui a évité de casser `sync` en
croyant l'améliorer.

**Le critère « aucune dépendance à `jq` ni à `date` » demande une nuance.** `sync.zsh` en compte toujours
15 et 2 : ils sont dans le **repli**, que CLAUDE.md exige de garder complet. Sur un poste équipé, plus
aucun appel n'a lieu — la délégation intervient avant. Le critère se lit donc « plus aucune dépendance
fragile sur le chemin emprunté », et le repli reste ce qu'il est : un mode dégradé, seul recours quand le
binaire manque.

**Un défaut trouvé en chemin, hors périmètre mais corrigé.** `cmd::print_header` dessinait une bordure de
40 caractères pour une ligne de 44 : le cadre était ouvert à droite dans les **sept** commandes qui
l'appellent. Le zsh compte les quatre espaces intérieurs, le Rust les oubliait. Sans cette correction, la
délégation aurait dégradé l'affichage — les deux dessinent maintenant la même boîte, au caractère près.

### Chantiers 4 et 5 — les comptes du tableau sont trop larges

Le tableau annonce 24 appels fragiles pour `commands.zsh` et 20 pour `gitlab_logic`. Le critère du spec
lui-même n'en retient qu'une fraction, et il faut le dire plutôt que de laisser croire à une dette non
payée :

| Fonction | Appels | Verdict du critère |
|---|---|---|
| `zanvil-list` | 10 | **Orchestration** — extraire un numéro de version de dix outils externes. « On ne migre pas un `for` autour d'un `kubectl` ». |
| `zanvil-doctor` | 5 | **Dans son repli** — il délègue depuis sa première ligne. |
| `zanvil-doctor-conflicts` | 7 | **Migré.** Analyse statique de fichiers, zéro effet shell. |
| `gitlab_logic` — les `jq` | 14 | **Restent.** Ils parsent des réponses de l'API GitLab ; les migrer demanderait de porter le client HTTP, ce qui est un chantier distinct — `mr_fanout.rs` en est le précédent. |
| `gitlab_logic` — les `date` | 6 | **Migrés.** Le calcul d'expiration d'un jeton, écrit **deux fois** avec son propre embranchement GNU/BSD. |

**Deux défauts trouvés en caractérisant, et corrigés.** `zanvil-doctor-conflicts` annonçait « 4 hooks
chpwd » et n'en affichait que 2, parce que le compte et la liste employaient des filtres différents — les
deux de trop étaient ses propres lignes, et elles n'apparaissaient pas parce qu'elles portent un dièse
dans leur motif. Et sa détection de fonctions ignorait la syntaxe `function nom() {`, donc les neuf
fonctions de `modules/gitlab/` lui étaient invisibles.

**Une primitive a changé de place.** `zanvil es convert` est devenue `zanvil convert` : le chantier 5 a
trouvé le même calcul de date dans GitLab, et une primitive partagée par deux modules n'a pas à porter le
nom de l'un d'eux. Les 86 cas sont passés inchangés à travers ce déplacement, ce qui est la meilleure
démonstration qu'ils ignorent la mécanique interne.

## La méthode : caractériser avant de migrer

Aucune des fonctions visées n'a de cas gaveldrop aujourd'hui — vérifié pour `zanvil-status`,
`zanvil-info`, `zanvil-sync` et `zanvil-theme`. Déplacer du code sans filet serait la seule manière de
transformer ce chantier en régression.

Pour **chaque** chantier, dans cet ordre :

1. **Écrire les cas qui capturent le comportement actuel, en zsh.** Attendu délibérément faux d'abord,
   constater l'échec, puis calibrer sur la sortie réelle.
2. **Vérifier par mutation qu'ils peuvent échouer.** Une assertion dérivée d'une sortie observée passe
   par construction ; seule une mutation du sujet prouve qu'elle mord.
3. **Migrer en Rust.**
4. **Les mêmes cas doivent passer, inchangés.**

Un cas invoque `zanvil-sync export` et asserte la sortie : il ne sait pas quel langage répond. C'est ce
qui rend la non-régression démontrable plutôt qu'espérée, et c'est l'usage pour lequel la suite de 57
cas a été construite.

## Ce qui ne bouge pas

**`context` reste tel quel.** Il coûte 160 ms à chaque prompt, dont 145 pour le
`kubectl config current-context` qu'il lance (`context.rs:get_current_context`). Le langage n'y est
pour rien : ce qui le corrigerait est un cache, et c'est un autre sujet.

**Les fonctions d'orchestration restent en zsh** : `klog`, `kube_azure`, `kube_switch`, `kube_ns`.

**Les scaffolds restent en zsh pour l'instant.** `_proj_scaffold_java` (153 lignes) et
`_proj_scaffold_node` (122) sont les deux plus grosses fonctions du projet et n'ont aucun effet shell,
donc elles sont migrables — mais elles écrivent des fichiers depuis des gabarits, sans dépendance
fragile. Elles relèvent du critère « volume », qui n'a pas été retenu.

## Vérification

Chaque chantier est terminé quand :

- les cas de caractérisation écrits à l'étape 1 passent **sans avoir été modifiés** ;
- une mutation du code migré fait rougir au moins un cas ;
- `gaveldrop` est vert, et les deux suites bash aussi ;
- aucune dépendance à `jq` ni à `date` ne subsiste dans le périmètre traité — vérifiable par
  `grep -c` sur le fichier.

Le chantier 1 a un critère de plus, qui lui est propre : un cas doit échouer si le binaire attendu par
une délégation n'est pas installable. C'est ce qui empêchera un repli de masquer une panne pendant
quatre mois.
