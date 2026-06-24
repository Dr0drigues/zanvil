# Thème signature « forge » — Design

**Date** : 2026-06-24
**Statut** : Validé (en attente d'implémentation)
**Release cible** : minor (nouveau thème, non-breaking)

## Contexte & roadmap

Sous-projet du programme de rebranding zanvil. Thème signature « forge » : identité chromatique propre au projet (atelier de forge — fer froid, braise, étincelle, trempe), au-delà du `tokyo-night-pro` par défaut. La palette a été validée visuellement (swatches) et confirmée par les logos générés (même famille de couleurs).

Position dans le backlog : sous-projet #3 (après identité visuelle #1 et rename technique #2, mais indépendant — peut être livré quand on veut).

## Architecture

Nouveau **thème directory** `themes/forge/` composé de deux fichiers, branché sur le système de thèmes existant **sans le modifier** :

- `themes/forge/palette.zsh` — override des variables `_ui_*` (couleurs des commandes `zsh-env-*`). Sourcé au startup par le loader de `core/ui.zsh` quand `.current_theme` vaut `forge`.
- `themes/forge/prompt.toml` — prompt Starship powerline. Copié vers `~/.config/starship.toml` par `zsh-env-theme apply forge`.

Aucune modification du moteur de thèmes, du loader, ni du CLI. Le thème est auto-découvert par `zsh-env-theme list` (qui énumère les dossiers de `themes/`).

## Composant 1 — `themes/forge/palette.zsh`

Mappe les 8 slots sémantiques `_ui_*` (true color), palette validée :

```zsh
# Forge - Shell palette (true color)
# Atelier de forge : fer froid, braise, etincelle, trempe.
_ui_red=$'\033[38;2;226;83;58m'         # #e2533a  feu
_ui_green=$'\033[38;2;138;154;91m'      # #8a9a5b  patine / laiton oxyde
_ui_yellow=$'\033[38;2;240;169;59m'     # #f0a93b  ambre / braise
_ui_blue=$'\033[38;2;125;148;166m'      # #7d94a6  acier froid
_ui_magenta=$'\033[38;2;168;127;160m'   # #a87fa0  violet trempe
_ui_cyan=$'\033[38;2;95;174;159m'       # #5fae9f  trempe
_ui_white=$'\033[38;2;216;205;191m'     # #d8cdbf  cendre claire
_ui_dim=$'\033[38;2;107;96;85m'         # #6b6055  cendre froide
```

(Structure identique aux palettes existantes `tokyo-night-pro/palette.zsh` : 8 affectations `_ui_*` via séquences `\033[38;2;R;G;Bm`.)

Note : `_ui_blue` (`#7d94a6`) et le « fer froid » du prompt (`#8896a3`, identique aux logos) sont la même famille « acier froid » dans deux contextes distincts (sortie des commandes vs segments powerline). Léger écart de teinte assumé, non un bug.

## Composant 2 — `themes/forge/prompt.toml`

**Dérivé de `themes/tokyo-night-pro/prompt.toml`** (même mise en page powerline : cap de tête `░▒▓`, segments dir → git → langages → contexte → time → `$character`, mêmes séparateurs ``, mêmes modules custom `work`/`zproject`/`zsh_env_context`). Seules les **couleurs** changent (schéma C : fer froid + détails chauds).

### Table de recoloration (tokyo → forge)

| Élément | Tokyo | Forge |
|---|---|---|
| Cap tête `░▒▓` (fg) + work bg | `#a3aed2` | acier `#8896a3` |
| Work icon fg | `#090c0c` | charbon `#1a1613` |
| Segment dir — bg | `#769ff0` | acier `#8896a3` |
| Segment dir — fg (texte) | `#e3e5e5` | charbon `#1a1613` |
| Segment git — bg | `#394260` | `#2f2620` |
| Segment git — fg | `#769ff0` | **braise `#ff8a3d`** |
| Segments langages (node/rust/go/php) — bg | `#212736` | `#241d18` |
| Segments langages — fg | `#769ff0` | acier `#8896a3` |
| Java — fg | `#f7768e` | rouge feu `#e2533a` |
| Segment time — bg | `#1d2230` | charbon `#1a1613` |
| Segment time — fg | `#a0a9cb` | **étincelle `#ffd479`** |
| Work output — fg | `#e0af68` | étincelle `#ffd479` |
| zproject — fg | `#bb9af7` | violet trempé `#a87fa0` |
| zsh_env_context — fg | `#7dcfff` | trempe `#5fae9f` |

Toutes les occurrences des séparateurs powerline (`[](fg:X bg:Y)`) doivent voir leurs `fg:`/`bg:` substitués selon les bg de segments correspondants ci-dessus (transitions `#769ff0`→`#8896a3`, `#394260`→`#2f2620`, `#212736`→`#241d18`, `#1d2230`→`#1a1613`).

### Éléments conservés à l'identique (transitionnel)

- `command = "zsh-env-cli context"` et `when = "test -x ${HOME}/.local/bin/zsh-env-cli"` — le binaire n'est pas renommé (rename = sous-projet #2).
- Chemins `~/.zsh_env/.work_context_cache` — inchangés.
- Symboles/glyphes des segments, `command_timeout`, `truncation_*`, `time_format`, `detect_files`, etc. — inchangés.
- Le commentaire d'en-tête est adapté : `# Starship Theme: Forge`.

## Hors périmètre

- **Pas de variante claire** (`forge-light`) : la forge est intrinsèquement sombre/chaude (YAGNI).
- Aucun changement au moteur de thèmes, au loader `core/ui.zsh`, ni au CLI.
- Aucun rename de tuyauterie.
- **MAJ** : forge devient le **thème par défaut des nouveaux installs** (`install.sh` : option recommandée + mode `--default`). Les utilisateurs **existants ne sont pas affectés** (`.current_theme` n'est posé qu'à l'install, jamais par l'auto-update) — ils gardent leur thème et peuvent basculer via `zsh-env-theme apply forge`. Aucune migration.
- Logos / assets graphiques : hors de ce sous-projet (branding assets séparé).

## Migration

**Aucune** : ajout pur d'un nouveau thème optionnel. Aucun état utilisateur invalidé, `.current_theme` inchangé tant que l'utilisateur n'applique pas `forge`.

## Tests

- **`palette.zsh`** : se source sans erreur ; après sourcing, les 8 variables `_ui_*` valent exactement les séquences forge (vérifier p.ex. `_ui_cyan` contient `38;2;95;174;159`).
- **`prompt.toml`** : fichier TOML valide ; si `starship` est installé, `STARSHIP_CONFIG=themes/forge/prompt.toml starship config` ne renvoie pas d'erreur de parsing. Vérifier qu'il ne reste **aucune** couleur tokyo résiduelle (`#769ff0`, `#394260`, `#212736`, `#1d2230`, `#a3aed2`, `#e3e5e5`, `#a0a9cb`, `#f7768e`, `#bb9af7`, `#7dcfff`, `#e0af68`) dans le fichier.
- **Découverte/application** : `zsh-env-theme list` inclut `forge` ; `zsh-env-theme apply forge` copie `prompt.toml` vers `~/.config/starship.toml` et écrit `forge` dans `.current_theme` ; le loader de `core/ui.zsh` source alors `themes/forge/palette.zsh` au prochain startup.
- **Non-régression** : appliquer puis revenir à `tokyo-night-pro` restaure les couleurs précédentes (le thème forge n'altère aucun fichier partagé).
