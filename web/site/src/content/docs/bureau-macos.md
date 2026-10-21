---
title: Bureau macOS
description: AeroSpace, SketchyBar et JankyBorders branchés sur les thèmes zanvil — mise en place, réglages macOS et limites connues.
---

zanvil ne livre pas de config de gestionnaire de fenêtres : `aerospace.toml`, `sketchybarrc` et
`bordersrc` vivent dans votre [dépôt dotfiles](/zanvil/installation/) et sont liés par
`zanvil-dotfiles link`. zanvil fournit le reste : les couleurs du thème, le rechargement à chaque
changement de thème, et l'application des réglages macOS du dépôt.

Les trois outils s'installent par Homebrew (Brewfile `common` du dépôt dotfiles) :

```ruby
cask "nikitabobko/tap/aerospace", trusted: true
brew "FelixKratz/formulae/sketchybar", trusted: true
brew "FelixKratz/formulae/borders", trusted: true
```

## Couleurs du thème

`zanvil-theme <nom>` génère `~/.config/zanvil/theme/colors.sh`. Le détail des variables est dans
[Configuration](/zanvil/configuration/). La barre et les bordures le sourcent avec des valeurs de
repli, pour fonctionner avant le premier `zanvil-theme` :

```sh
# sketchybarrc, bordersrc (sh)
COLORS="$HOME/.config/zanvil/theme/colors.sh"
[ -r "$COLORS" ] && . "$COLORS"
: "${ZANVIL_ACCENT:=0xff2e7de9}"
borders active_color="$ZANVIL_ACCENT" inactive_color=0x00000000 width=5.0 style=round
```

Après `zanvil-theme`, zanvil lance `sketchybar --reload` et `~/.config/borders/bordersrc` si ces
programmes tournent. Il ne les démarre jamais. `bordersrc` doit être exécutable.

Tant que `colors.sh` n'existe pas (première installation, ou thème appliqué avant cette
fonctionnalité), la barre garde ses couleurs de repli : relancer `zanvil-theme <nom>` une fois.

## Démarrage

Une seule source de démarrage, pour éviter les doublons : AeroSpace démarre à l'ouverture de session
et lance la barre et les bordures. Ne pas activer `brew services` pour SketchyBar ni JankyBorders.

```toml
# aerospace.toml
start-at-login = true
after-startup-command = ['exec-and-forget sketchybar', 'exec-and-forget borders']
exec-on-workspace-change = ['/bin/bash', '-c',
    'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE']
```

Au premier lancement, macOS demande l'accès **Accessibilité** pour AeroSpace (Réglages Système >
Confidentialité et sécurité > Accessibilité). Vérifier la config sans l'appliquer :

```bash
aerospace reload-config --dry-run --warnings-as-errors
```

## Touche Hyper

Les raccourcis utilisent **Hyper** (⌃⌥⇧⌘), portée par Verr. Maj. Le réglage se fait dans Raycast :
Réglages > Advanced > **Hyper Key**, sur Caps Lock.

Option+lettre est à éviter : en AZERTY comme en QWERTY, Option sert aux caractères (`@`, `|`, `{`,
accents). AeroSpace lie des **positions** de touches, nommées en QWERTY : pour un clavier utilisé dans
les deux dispositions, ne lier aux actions que des touches à la même place dans les deux (pas `a`,
`q`, `z`, `w`, `m`, ni les chiffres).

## Réglages macOS

S'il existe, `macos.sh` à la racine du dépôt dotfiles est lancé par `zanvil-dotfiles install`, sur
macOS, après les paquets (voir [Installation](/zanvil/installation/)). Exemple pour ce bureau :

```sh
#!/bin/sh
# Barre des menus masquée : la barre SketchyBar prend sa place.
defaults write NSGlobalDomain _HIHideMenuBar -bool true
osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to true' >/dev/null 2>&1 || true

# Dock masqué : les fenêtres vont jusqu'au bord bas.
if [ "$(defaults read com.apple.dock autohide 2>/dev/null)" != 1 ]; then
  defaults write com.apple.dock autohide -bool true
  killall Dock
fi

# « Les écrans disposent d'espaces distincts » désactivé, recommandé par AeroSpace (vaut à la reconnexion).
defaults write com.apple.spaces spans-displays -bool true
```

Le script est relancé à chaque `install` : il doit pouvoir l'être sans effet de bord.

## Barre et marges

- Barre des menus visible : SketchyBar se place de lui-même sous elle. Ne pas ajouter sa hauteur par
  `notch_offset`, sinon la barre est décalée deux fois.
- Barre des menus masquée : la barre est tout en haut. Sur un écran à encoche, macOS réserve encore la
  rangée de l'encoche (32 pt environ), et AeroSpace compte `outer.top` depuis le bas de cette rangée :
  une petite marge suffit sur l'écran intégré, alors qu'un écran externe demande la hauteur de la
  barre plus l'écart voulu.

```toml
[gaps]
    outer.top = [{ monitor."built-in" = 6 }, 48]   # barre de 36 en haut, barre des menus masquée
```

- Les marges d'AeroSpace supposent un état de la barre des menus : la réafficher fait recouvrir la
  barre par les fenêtres.
- Un élément SketchyBar dont l'écran est débranché ne reçoit plus d'événements avec
  `updates=when_shown` (valeur par défaut) : mettre `updates=on` sur les éléments qui changent d'écran,
  comme les espaces.
- Un libellé SketchyBar qui commence par des espaces est tronqué à droite : aligner avec l'icône
  plutôt qu'avec des espaces.

## Limites connues

- **Capot fermé** : sans écran intégré actif, les espaces affectés à `built-in` n'ont plus d'écran
  dédié. Terminer la liste d'affectation par un repli (`['secondary', 'built-in']`), et s'attendre à
  ce que ces espaces partagent un écran externe.
- **Plantage au branchement d'écrans** : AeroSpace est en bêta publique, et un bug ouvert
  ([#506](https://github.com/nikitabobko/AeroSpace/issues/506)) peut le faire quitter quand un écran
  est branché ou débranché. Le relancer avec `open -a AeroSpace` : il relance la barre et les
  bordures.
- **Fenêtres flottantes** : AeroSpace ne redimensionne jamais une fenêtre flottante. Lui donner sa
  taille une fois à la main ; la plupart des applis la mémorisent.
