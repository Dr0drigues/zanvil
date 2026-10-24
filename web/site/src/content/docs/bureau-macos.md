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

Après `zanvil-theme`, zanvil relance `~/.config/borders/bordersrc` et met la barre à jour si ces
programmes tournent. Il ne les démarre jamais. `bordersrc` doit être exécutable.

Pour la barre, `sketchybar --reload` la détruit puis la reconstruit, en attendant chaque script : le
changement de thème se voit pendant plusieurs secondes. Si `~/.config/sketchybar/recolor` existe et
est exécutable, zanvil le lance à la place. Ce script réapplique les couleurs de `colors.sh` aux
éléments existants, puis `--update` :

```sh
#!/bin/sh
. "$HOME/.config/zanvil/theme/colors.sh"
sketchybar --set '/_island$/' background.color="$ZANVIL_BAR_BG" \
           --set '/^space\.[DBNS]$/' label.color="$ZANVIL_BAR_DIM" background.color="$ZANVIL_ACCENT" \
           --set '/^right\.clock$/' label.color="$ZANVIL_BAR_TEXT" \
           --update
```

Un motif sans élément n'est qu'un avertissement : la suite s'applique. Les motifs ne gèrent pas
l'alternance `(a|b)`. Appelé aussi en fin de `sketchybarrc`, ce script reste le seul endroit où les
couleurs sont posées.

Tant que `colors.sh` n'existe pas (première installation, ou thème appliqué avant cette
fonctionnalité), la barre garde ses couleurs de repli : relancer `zanvil-theme <nom>` une fois.

### Clair et sombre en direct

Avec `ZANVIL_THEME_LIGHT` et `ZANVIL_THEME_DARK` dans `config.zsh`, un élément SketchyBar invisible
peut suivre le passage clair/sombre de macOS, sans outil supplémentaire : SketchyBar écoute la
notification distribuée et lance `zanvil-theme auto`.

```sh
# sketchybarrc
sketchybar --add event appearance_change AppleInterfaceThemeChangedNotification \
           --add item appearance left \
           --set appearance drawing=off updates=on script="$PLUGIN_DIR/appearance.sh" \
           --subscribe appearance appearance_change
```

```sh
# plugins/appearance.sh : zsh minimal, en arrière-plan (zanvil-theme recharge la barre)
ZANVIL_DIR="$HOME/.zanvil" zsh -fc '
  source "$ZANVIL_DIR/config.zsh"; source "$ZANVIL_DIR/core/ui.zsh"
  source "$ZANVIL_DIR/core/commands/theme.zsh"; zanvil-theme auto' >/dev/null 2>&1 &
```

Le rechargement de la barre relance le script, mais le thème est alors déjà le bon : il ne se passe
plus rien. Pour Ghostty, `zanvil-ghostty auto` lui fait suivre l'apparence lui-même.

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

### Terminal déroulant

Ghostty a un terminal qui descend du haut de l'écran sur un raccourci global (accès Accessibilité
requis pour Ghostty). Pour qu'il réponde dès l'ouverture de session, AeroSpace lance Ghostty en
arrière-plan (`'exec-and-forget open -g -a Ghostty'` dans `after-startup-command`) et Ghostty
n'ouvre pas de fenêtre au démarrage :

```
# ~/.config/ghostty/config
keybind = global:cmd+alt+ctrl+shift+space=toggle_quick_terminal
quick-terminal-position = top
quick-terminal-screen = mouse
quick-terminal-autohide = true
initial-window = false
```

## Touche Hyper

Les raccourcis utilisent **Hyper** (⌃⌥⇧⌘), portée par Verr. Maj. Le réglage se fait dans Raycast :
Réglages > Advanced > **Hyper Key**, sur Caps Lock.

Option+lettre est à éviter : en AZERTY comme en QWERTY, Option sert aux caractères (`@`, `|`, `{`,
accents). AeroSpace lie des **positions** de touches, nommées en QWERTY : pour un clavier utilisé dans
les deux dispositions, ne lier aux actions que des touches à la même place dans les deux (pas `a`,
`q`, `z`, `w`, `m`, ni les chiffres).

## Ouvrir une MR

Un script Raycast ouvre la MR GitLab copiée dans le presse-papiers (`project open`) : worktree, Orca et
IntelliJ IDEA. Dans Raycast, Extensions > **Script Commands** > Add Script Directory, ajouter
`~/.zanvil/scripts/raycast`. Assigner ensuite **Hyper+O** à la commande « Ouvrir la MR copiée ».

Raycast lance le script sans le `PATH` Homebrew ni le jeton GitLab : il ajoute `/opt/homebrew/bin` au
`PATH`, lit `~/.gitlab_secrets` et `config.zsh` (`$WORK_DIR` vaut `~/work` par défaut) avant d'appeler
zanvil. La CLI d'Orca, absente de tout `PATH`, est prise dans `/Applications/Orca.app` ; sans elle,
IntelliJ IDEA s'ouvre quand même. Un presse-papiers qui n'est pas un lien de MR
donne une notification d'erreur.

Le même dossier fournit trois autres commandes, à lancer depuis Raycast ou à raccourcir :

- **Thème zanvil** : liste déroulante des thèmes (plus `auto`), appelle `zanvil-theme`. La liste est
  statique dans l'en-tête du script (`scripts/raycast/zanvil-theme.sh`) : la mettre à jour quand
  `config/themes` change.
- **Contexte kube** : un alias (`ctx-dev`) ou un nom de contexte complet, résolu par le module kube. Un
  contexte dont le nom ou l'alias finit par `-prd` ou `-prod` ouvre d'abord une confirmation
  (Annuler par défaut) ; annuler, ou un dialogue en échec, ne change rien. Le résultat arrive en notification.
- **Ménage des worktrees** : lance `project clean`, qui notifie lui-même son résumé.

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

## Plusieurs écrans

Les espaces s'affectent aux écrans par une liste de motifs, essayés dans l'ordre : le premier qui
correspond à un écran branché l'emporte. Ainsi, la même config sert au Mac seul, à la maison et au
bureau, sans dépendre de l'ordre dans lequel les écrans sont branchés.

```toml
[workspace-to-monitor-force-assignment]
    N = 'built-in'                                    # toujours l'écran du Mac
    D = ['^(?!.*(built-in|samsung)).*$', 'built-in']  # 1er externe hors TV, sinon le Mac
    B = [3, 'secondary', 'built-in']                  # 3e en partant de la gauche, sinon l'autre écran
    V = ['SAMSUNG', 'secondary', 'built-in']          # la TV, par son nom
```

- `built-in` reconnaît l'écran intégré par son nom. Un autre nom (`SAMSUNG`) ou une expression
  régulière vise un écran précis ; la casse est ignorée.
- Un nombre désigne la position en partant de la gauche ; il change de sens selon les écrans
  branchés, donc à réserver aux configurations à trois écrans ou plus.
- `secondary` n'existe qu'avec exactement deux écrans : celui qui n'est pas l'écran principal de
  macOS (Réglages Système > Moniteurs).
- Quand plusieurs écrans correspondent à une expression, AeroSpace prend celui de gauche.
- Toujours finir par `'built-in'` : sans écran externe, l'espace retombe sur le Mac.

Pour exclure un écran (la TV pour l'espace de travail, par exemple), une expression avec un
lookahead négatif fait l'affaire : `'^(?!.*(built-in|samsung)).*$'`. Les noms exacts des écrans
s'obtiennent avec `aerospace list-monitors`.

### Une barre par écran

SketchyBar dessine la barre sur chaque écran. Pour qu'un élément d'espace n'apparaisse que sur
l'écran où AeroSpace place cet espace, le script de l'élément lui donne `display=` à chaque événement.
Les deux outils ne numérotent pas les écrans de la même façon : `%{monitor-id}` d'AeroSpace va de
gauche à droite, alors que `display=` suit l'ordre de macOS. Le format
`%{monitor-appkit-nsscreen-screens-id}` donne directement le numéro attendu par SketchyBar :

```sh
display=$(aerospace list-workspaces --all --format '%{workspace} %{monitor-appkit-nsscreen-screens-id}' \
  | awk -v s="$sid" '$1 == s { print $2 }')
[ -n "$display" ] && sketchybar --set "$NAME" display="$display"
```

L'élément s'abonne à `aerospace_workspace_change`, à `display_change` (branchement et débranchement)
et à `system_woke`, avec `updates=on`. Sur `display_change`, attendre une seconde avant d'interroger
AeroSpace : l'événement peut arriver avant qu'AeroSpace ait réaffecté les espaces.

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
