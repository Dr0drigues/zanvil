# Rapport — douze défauts injectés volontairement, et ce que la suite en attrape

**But :** savoir ce que la suite couvre réellement, et distinguer ce qui relève d'une dette de zanvil de
ce qui relève d'une limite de gaveldrop.

**Méthode.** Worktree git isolé (`git worktree add`), copie du cache de compilation, référence verte
établie avant toute injection (59/59). Pour chaque défaut : restaurer, appliquer **en vérifiant que le
fichier a réellement changé**, reconstruire si le Rust est touché, lancer `gaveldrop` *et* les deux
suites bash, restaurer. Un harnais fait les douze passes pour que rien ne dépende de mon attention.

La classification n'est pas cosmétique : elle prédit ce qu'on doit exiger de la suite. Un défaut mineur
qui passe est un choix ; un défaut majeur qui passe est un trou.

## Le tableau

| # | Classe | Défaut injecté | Résultat |
|---|---|---|---|
| M1 | mineur | `_ui_check` passe de `✓` à `+` | passe inaperçu — assumé |
| M2 | mineur | alignement des sections : 14 → 12 colonnes | passe inaperçu — assumé |
| M3 | mineur | symbole de continuation `⤷` → `>` | **attrapé**, 2 cas |
| J1 | majeur | le niveau de log n'est plus mis en majuscules | **attrapé**, 1 cas |
| J2 | majeur | le logger n'est plus tronqué à 36 caractères | **attrapé**, 2 cas |
| J3 | majeur | le raccourci `Ctrl-R` disparaît du viewer | **attrapé**, 1 cas |
| J4 | majeur | `pad()` neutralisé, plus aucun alignement | **attrapé**, 17 cas |
| C1 | complexe | la délégation vise `zanvil themes` au lieu de `zanvil theme` | passait inaperçu → **comblé** |
| C2 | complexe | `local path=` réintroduit dans une fonction du hook `cd` | gaveldrop non, **lint bash oui** |
| C3 | complexe | la sortie d'erreur de `jq` est jetée | *mutation équivalente — écartée* |
| C4 | complexe | le `.module.toml` de kube perd sa description | **attrapé**, 1 cas |
| C5 | complexe | inversion de condition : les statuts `actif`/`inactif` sont échangés | passait inaperçu → **comblé** |

**Onze défauts réels** — C3 n'en est pas un, voir plus bas. Six attrapés par gaveldrop, un par le lint
bash, quatre passaient : deux comblés dans ce rapport, deux assumés.

## Les quatre majeurs sont tous attrapés, avec la bonne portée

C'est le résultat qui compte le plus, et la **portée** est aussi informative que la détection :

- `pad()` neutralisé fait rougir **17 cas** — l'alignement traverse tout le formatteur ;
- le troncage du logger, **2 cas** ; la majuscule du niveau, **1** ; le `Ctrl-R`, **1**.

Aucune portée n'est ni nulle ni totale. Un défaut local fait rougir peu de cas, un défaut transversal en
fait rougir beaucoup : c'est la signature d'une suite dont les cas testent des choses distinctes plutôt
que la même chose répétée.

## C3 n'est pas un trou : c'est une mutation équivalente

Ajouter `2>/dev/null` à l'appel `jq` du formatteur ne change **rien** d'observable. Vérifié plutôt que
supposé :

```console
$ printf '{ceci nest pas du json\n' | ./scripts/k9s-log-fmt.sh 2>/tmp/err
{ceci nest pas du json
$ wc -c </tmp/err
0
```

`jq -Rr` lit du texte brut et gère le parsing dans son filtre : il n'écrit jamais sur sa sortie d'erreur,
même sur du JSON malformé. La mutation est donc sémantiquement neutre, et la compter comme « défaut non
détecté » aurait gonflé le bilan d'un trou inexistant.

## C2 : la couverture vient d'ailleurs, et c'est légitime

Réintroduire `local path="$1"` dans `_zanvil_local_load` — le bug réel qui cassait `work_es_apps` — ne
fait rougir aucun cas gaveldrop, et **fait rougir le lint bash** (`zsh-special-vars.test.sh`).

C'est le bon partage. Un `local path=` dans une fonction qu'aucun cas n'appelle ne produit aucun
comportement observable ; gaveldrop teste des comportements, un lint teste du texte. Exiger de gaveldrop
qu'il attrape ça reviendrait à lui demander d'être un analyseur statique.

**Mais l'exercice a révélé un piège dans le lint**, et il m'a trompé pendant deux passes. Son
`ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"` audite le répertoire que la variable désigne, pas celui d'où il est
lancé. Depuis le worktree, il analysait donc le dépôt principal — sain — et annonçait `7 ok, 0 échec`
alors que le défaut était sous ses yeux. La CI l'échappe parce qu'elle fait `export ZANVIL_DIR="$PWD"`
juste avant ; un développeur qui lance le test à la main dans une copie ou un worktree, non.

À corriger : dériver `ROOT` de la position du script, pas de l'environnement. Consigné, non fait ici —
c'est un défaut de l'outillage de test, pas de la suite.

## C1 : le trou grave, et c'est la panne du chantier 1 qui revient

Renommer `zanvil theme` en `zanvil themes` dans `core/commands/theme.zsh` ne faisait rougir **aucun des
59 cas**. La délégation cassait, le repli zsh prenait la main, la suite restait verte.

La raison est structurelle : les cas `cli-theme-*` invoquent le binaire **par chemin absolu**
(`$GAVELDROP_PROJECT/cli/target/release/zanvil`) et ne passent jamais par la fonction zsh, qui est le
seul point d'entrée sur un poste. Toute la couverture portait sur le Rust ; le raccord entre les deux
langages n'était testé nulle part.

C'est exactement ce qui a coûté quatre mois : `command -v zanvil` échouait, trois commandes tournaient en
mode dégradé, et rien ne le disait.

**Comblé** par `tests/cases/cli/theme-delegates-to-the-cli-with-the-right-subcommand.yaml`, qui falsifie
notre propre binaire pour vérifier avec quels arguments la fonction l'appelle. Le verdict sous mutation :

```console
FAIL theme-delegates-to-the-cli-with-the-right-subcommand  0/7
    expect.exit_code            expected 0        got 127
    expect.stdout.contains[0]   expected "Available themes:"   got (empty)
    unexpected calls            got zanvil
```

`zanvil` a été ajouté à `fake.bins` de `gaveldrop.yaml`. Mesuré avant de s'y engager : aucun des 59 cas
existants ne change, parce que ceux qui veulent le vrai binaire l'invoquent par chemin absolu, que le
shadowing du `PATH` n'atteint pas.

**Ce cas a d'abord été écrit faux, et c'est le point le plus utile de ce rapport.** Ma première règle
était `args_contain: "theme"`, et le cas passait *aussi* sous la mutation : `args_contain` est une
sous-chaîne, et « themes » contient « theme ». Un cas qui ne peut pas échouer ressemble exactement à un
cas qui passe. Seule la mutation l'a montré.

## C5 : `contains` ne voit pas une association

Inverser `if enabled` en `if !enabled` dans `modules.rs` échange tous les statuts. Le cas assertait
`["KUBE", "DOCKER", "actif", "inactif"]` : les quatre mots restent présents, l'assertion reste vraie, et
la sortie est entièrement fausse.

C'est la limite de `contains` sur une table : il dit qu'un fragment existe, jamais que deux fragments
sont sur la même ligne.

**Comblé** par `- "KUBE         actif"`, la seule expression disponible aujourd'hui. Elle mord :

```console
    expect.stdout.contains[8]
      expected  contains "KUBE         actif"
```

Le coût est assumé et écrit dans le cas : treize espaces figés, donc passer `{:<12}` à `{:<14}` fera
rougir un test de comportement pour une raison cosmétique. C'est le motif que `writing-cases.md`
déconseille — « a case that breaks for that reason gets deleted rather than maintained » — et c'est
pourquoi il en sort une demande à gaveldrop plutôt qu'une satisfaction.

## M1 et M2 : assumés

Le symbole `✓` et la largeur d'alignement des sections ne sont assertés nulle part, et ne le seront pas.
Les deux sont du ressort du thème : une palette peut légitimement changer un symbole, et un cas qui
figerait `✓` rougirait au premier thème qui préfère `●`. Le seul symbole asserté dans la suite est celui
du formatteur k9s (`⤷`), parce que là il fait partie du **format de sortie** que le plugin promet, pas de
l'habillage.

## Ce que l'exercice demande à gaveldrop

Deux findings nés de l'usage, ajoutés au document de demandes :

1. **`args_contain` ne distingue pas un nom de son préfixe.** « theme » matche « themes ». C'est le motif
   exact du bug qui a coûté quatre mois à zanvil — un renommage — et la seule parade est d'inclure
   l'argument suivant (`"theme list"`), ce qui couple la règle à la forme de l'appel.
2. **Rien n'exprime « ces deux fragments sur la même ligne ».** Il faut figer l'espacement, donc coupler
   un test de comportement à une décision de présentation.

## Sur la méthode

Trois de mes gestes ont été faux et méritent d'être écrits, parce que deux d'entre eux auraient produit
un rapport erroné :

- **le harnais annonçait `BUILD-ECHOUE` jamais** : `cargo build 2>&1 | tail -5` rend le code de retour de
  `tail`, toujours nul. Une mutation Rust qui ne compile pas aurait été mesurée contre l'ancien binaire
  et comptée comme « passe inaperçu » ;
- **cinq des douze cibles étaient absentes du code** au premier essai. Le harnais les a signalées au lieu
  de muter dans le vide, ce qui est la seule raison pour laquelle le tableau ci-dessus veut dire quelque
  chose ;
- **le lint bash m'a menti deux fois** avant que je regarde son `ROOT`, et j'ai failli conclure qu'un
  garde-fou écrit exprès pour ce bug ne mordait pas.

C'est la même leçon que la vérification par mutation, appliquée à l'outillage : un test qui passe sans
qu'on ait vu son échec ne prouve rien, et cela vaut aussi pour le harnais qui mesure les tests.
