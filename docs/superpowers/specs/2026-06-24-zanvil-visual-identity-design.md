# Identité visuelle « zanvil » — Design (sous-projet #1)

**Date** : 2026-06-24
**Statut** : Validé (en attente d'implémentation)
**Release cible** : v3.9.0 (minor, non-breaking)

## Contexte & roadmap

Programme de rebranding + nouvelles features (~14 releases prévues, pour exercer le pipeline `auto-release` à grande échelle). Ce document couvre **le sous-projet #1 : l'identité visuelle**, volontairement séparé du rename technique lourd (sous-projet #2).

Ordre du backlog global :
1. **Identité visuelle zanvil** ← *ce spec* (non-breaking, v3.9.0)
2. Rename technique complet (breaking, v4.0.0 : `~/.zsh_env`, `ZSH_ENV_*`, `zsh-env-cli`, commandes `zsh-env-*`, repo + migration + shims)
3. Thème signature « forge » (palette braise/fer/étincelle) — sous-projet dédié
4. Piste A — productivité shell (~7 features)
5. Piste B — onboarding/DX (~3 features)
6. Piste D — méta/écosystème (~2 features)

## Décisions de marque (verrouillées)

- **Nom affiché** : `zanvil`
- **Tagline** : `craft your shell`
- **Logo splash (3A)** — enclume en blocs unicode, cohérente avec le style `░▒▓█` du projet :

```
      ▟████████████████▆▄
      ████████████████████
      ▝▀▀▀▀▀▜██████▛▀▀▀▀▀▘
              ██████
            ▟██████████▙
            ▀▀▀▀▀▀▀▀▀▀▀▀

        zanvil · craft your shell
```

- **Ligne compacte** (démarrage / reload) :

```
  ░▒▓█ zanvil █▓▒░  ⚒  craft your shell
```

## Où apparaît quoi

| Contexte | Affichage |
|----------|-----------|
| Install (`install.sh`, fin) | **Splash complet 3A** + version |
| Update réussie (`core/auto_update.zsh`) | **Splash complet 3A** |
| Démarrage de chaque shell interactif | **Ligne compacte** (défaut on, opt-out) |
| Reload (`ss` → `_zsh_env_banner`) | **Ligne compacte** + ligne d'infos (branche · hash · plugins · reloaded) |

Le splash complet est volontairement réservé aux moments rares (install/update) ; le quotidien (startup/reload) reste sur la ligne compacte.

## Composants & fichiers

### `assets/zanvil-logo.txt` (nouveau)
Source unique de l'art du splash (l'enclume + wordmark + tagline ci-dessus, **sans** la version). Rendu par `cat` à la fois par `core/ui.zsh` (en zsh, colorisé) et `install.sh` (en bash), pour éviter toute divergence du dessin entre les deux.

### `core/ui.zsh`
- **`_zanvil_logo()`** (nouveau) : `cat` le fichier `assets/zanvil-logo.txt`, colorisé via les `_ui_*` (l'enclume en `_ui_cyan`/`_ui_bold`, la tagline en `_ui_dim`). Affiche la version en dessous.
- **`_zsh_env_banner()`** (modifié) : conserve son nom (plomberie interne, renommée au sous-projet #2 ; un seul appelant : l'alias `ss` dans `core/aliases.zsh`). La ligne `█ zsh-env █` devient la **ligne compacte zanvil** + glyphe `⚒` + tagline. La ligne d'infos existante est conservée.
- **`_zanvil_banner_compact()`** (nouveau) : imprime uniquement la ligne compacte (sans infos), réutilisée par le hook de démarrage.

### `core/hooks.zsh`
À la fin (dernier fichier sourcé), appel de `_zanvil_banner_compact` si shell interactif **et** `ZSH_ENV_STARTUP_BANNER != false` :
```zsh
if [[ -o interactive && "${ZSH_ENV_STARTUP_BANNER:-true}" != "false" ]]; then
    _zanvil_banner_compact
fi
```

### `core/auto_update.zsh`
Après une mise à jour réussie, appeler `_zanvil_logo` (remplace/complète le message de fin d'update existant).

### `install.sh`
À la fin du script (avant le message final), `cat "$TARGET_DIR/assets/zanvil-logo.txt"` puis afficher la version. En bash : pas de dépendance aux `_ui_*`, rendu brut (ou avec les variables couleur déjà définies dans `install.sh`).

### `config.zsh` (documentation)
Documenter le toggle `ZSH_ENV_STARTUP_BANNER` (défaut `true`) dans les commentaires de config.

## Ce qui NE change PAS (transitionnel, assumé)

Commandes `zsh-env-*`, dossier `~/.zsh_env`, variables `ZSH_ENV_*` (y compris le nouveau toggle `ZSH_ENV_STARTUP_BANNER`), binaire `zsh-env-cli`, repo GitHub. Seul l'**affichage** devient zanvil. Le rename de la tuyauterie est le sous-projet #2.

## Hors périmètre

- Thème signature « forge » (sous-projet dédié, via le skill `theme`)
- Rename technique (sous-projet #2)
- README / wiki (plus tard)
- Le binaire `zsh-env-cli` n'expose pas de commande `zanvil` (le splash CLI viendra avec le rename #2)

## Migration

**Aucune migration nécessaire** : ajout d'affichage + un nouveau toggle avec défaut rétrocompatible. Aucun état utilisateur invalidé. Le seul changement de comportement observable (bannière au démarrage) est opt-out.

## Tests (sourcing zsh isolé + bash)

- `_zanvil_logo` : sortie contient `zanvil` et `craft your shell` (vérifie aussi que `assets/zanvil-logo.txt` existe et a le bon nombre de lignes/caractères clés).
- `_zsh_env_banner` : sortie contient la ligne compacte zanvil + la ligne d'infos (branche/plugins/reloaded).
- `_zanvil_banner_compact` : contient `zanvil` + `craft your shell`, **sans** ligne d'infos.
- Toggle : `ZSH_ENV_STARTUP_BANNER=false` → le hook n'imprime rien ; non défini ou `true` → ligne affichée. Test du hook en sourcing avec shell interactif simulé.
- `install.sh` : `bash -n` + `grep` du `cat assets/zanvil-logo.txt`.
- `assets/zanvil-logo.txt` : présent, contient l'enclume (caractères `▟█▙▆▀▝▘`) et la tagline.
