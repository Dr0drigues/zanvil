---
title: Tests
description: La suite de cas gaveldrop, ce qu'elle couvre, et comment la lancer localement.
---

zanvil est testé par [gaveldrop](https://github.com/Dr0drigues/gaveldrop), un moteur où **un cas est un
fichier YAML**. Il prépare un environnement isolé, invoque le sujet, observe, et rend un verdict.

Le projet ne change rien pour être testable : aucune instrumentation, aucun mode test dans le code.

## Lancer la suite

```bash
cd ~/.zanvil
gaveldrop                    # tous les cas
gaveldrop --only cli/        # ceux dont le chemin contient « cli/ »
gaveldrop --watch            # relance à chaque enregistrement
gaveldrop --verbose          # ce que le moteur a décidé pour chaque cas
```

Installation, deux binaires — le second est ce qui remplace les dépendances qu'un cas simule :

```bash
cargo install gaveldrop-cli gaveldrop-fake --locked
```

Deux suites en bash complètent les cas, pour ce que le format n'exprime pas :

```bash
bash scripts/tests/k9s-log-fmt.test.sh      # decoupage de champs, contrat --pairs, viewer
bash scripts/tests/zsh-special-vars.test.sh # lint des variables reservees zsh
```

## Ce qui est couvert

| Famille | Ce qui est vérifié |
|---------|--------------------|
| Chargement | `rc.zsh` charge complètement, `ZANVIL_VERSION` est exposé, et `stderr` ne contient ni `command not found` ni `parse error` |
| CLI Rust | `theme list`, `theme current`, `modules list`, `doctor`, `--help` — code de sortie et contenu de la sortie |
| Modules d'outils | Les **deux** branches de posting, delta, lazygit et atuin : binaire présent et binaire absent |
| Rendu k9s | Le pattern logback, les niveaux numériques, l'abréviation du logger, les stack traces, les champs MDC, le mode `--pairs` |
| Documentation | Tout module portant un `.module.toml` est cité dans `configuration.md` — ce garde-fou existe parce que la doc avait dérivé de huit modules |

## Deux mécanismes qui font l'intérêt de la suite

**Le binaire d'un outil peut être simulé.** Tester `posting_setup` supposait jusqu'ici d'installer
posting sur la machine. Un cas déclare l'outil comme simulé, décide ce qu'il répond, et vérifie ensuite
le fichier déployé ainsi que le nombre d'appels — sans rien installer.

**Un outil peut aussi être déclaré absent.** C'est l'autre moitié de chaque module : le message
`brew install …` quand le binaire manque. Le verdict est alors le même sur un poste équipé et sur un
runner vide, ce qu'une amputation du `PATH` ne garantissait que par accident.

## L'isolation, et pourquoi elle compte ici

Un cas s'exécute avec `HOME` redirigé vers un répertoire temporaire. Les fonctions qui écrivent dans
`~/.config/…` sont donc observables sans machinerie, et n'altèrent rien sur la machine.

Un hook construit au besoin un `ZANVIL_DIR` **dans** cette isolation, plutôt que de faire pointer les
cas sur le dépôt. Quatre raisons, toutes constatées :

- `.current_theme` et `config.zsh` ne sont pas versionnés : un cas qui les lirait dans le dépôt rendrait
  un verdict dépendant de la machine ;
- `delta_setup` écrit dans `$ZANVIL_DIR/config/lazygit/config.yml` ;
- `rc.zsh` y écrit `.last_update_check` et `.work_context_cache` ;
- le dépôt pèse près de deux gigaoctets avec `cli/target`, donc la copie est sélective.

Le `config.zsh` que le hook écrit déclare `ZANVIL_PLUGINS=()` : le cas de chargement n'atteint jamais le
réseau, là où copier `examples/config.zsh.example` déclencherait un `git clone`.

## En intégration continue

Trois jobs dans `.github/workflows/tests.yml`, sur Ubuntu et macOS :

| Job | Rôle |
|-----|------|
| `cases` | La suite gaveldrop, avec les échecs annotés sur la ligne de l'assertion qui casse |
| `smoke-test` | Présence des fichiers du cœur et des modules, plus les deux suites bash |
| `rust-cli` | Compilation du CLI |

## Écrire un cas

Un cas nomme ce qu'il fait, ce qu'il invoque, et ce qu'il attend :

```yaml
name: k9s-uppercases-the-level
weight: 3
setup:
  stdin: |
    {"@timestamp":"2026-07-28T08:00:01.456Z","level":"error","message":"Boom"}
  run: ["$GAVELDROP_PROJECT/scripts/k9s-log-fmt.sh"]
expect:
  exit_code: 0
  stdout:
    ignore_ansi: true
    equals: "08:00:01.456 ERROR Boom"
```

`$GAVELDROP_PROJECT` est la racine du dépôt : le répertoire courant, lui, est l'isolation.
`ignore_ansi` est nécessaire parce que le formatteur colore chaque champ.

Une règle vaut d'être suivie : **écrire l'attendu délibérément faux d'abord**, constater l'échec, puis
le corriger avec ce que le rapport affiche. Un cas dont on n'a jamais vu l'échec risque de ne pas
pouvoir échouer du tout — et il ressemblerait alors à de la couverture sans en être.
