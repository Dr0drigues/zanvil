# Themes

En v2, le systeme de themes est unifie : chaque theme est un repertoire contenant un fichier de prompt Starship (`prompt.toml`) et une palette de couleurs terminal (`palette.zsh`).

## Commandes

```bash
# Lister les themes disponibles
zanvil-theme list

# Appliquer un theme
zanvil-theme minimal

# Via le CLI Rust
zanvil theme list
zanvil theme apply minimal
```

## Structure d'un theme

Chaque theme est un repertoire dans `~/.zanvil/themes/` :

```
themes/
├── minimal/
│   ├── prompt.toml       # Configuration Starship
│   └── palette.zsh       # Palette de couleurs terminal
├── default/
│   ├── prompt.toml
│   └── palette.zsh
├── powerline/
│   ├── prompt.toml
│   └── palette.zsh
└── plain/
    ├── prompt.toml
    └── palette.zsh
```

### prompt.toml

Le fichier `prompt.toml` est une configuration Starship standard :

```toml
format = "$directory$git_branch$git_status$character"

[character]
success_symbol = "[❯](green)"
error_symbol = "[❯](red)"

[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
format = "[$branch]($style) "
style = "purple"

[git_status]
format = '[$all_status$ahead_behind]($style) '
style = "red"
```

### palette.zsh

Le fichier `palette.zsh` definit les couleurs utilisees par les commandes `zanvil-*` et peut configurer les couleurs du terminal :

```zsh
# Couleurs du theme
_THEME_PRIMARY="blue"
_THEME_SECONDARY="cyan"
_THEME_ACCENT="magenta"
_THEME_SUCCESS="green"
_THEME_ERROR="red"
_THEME_WARNING="yellow"
```

## Themes disponibles

| Theme | Description |
|-------|-------------|
| `minimal` | Prompt minimaliste et rapide |
| `default` | Configuration equilibree |
| `powerline` | Style powerline avec separateurs |
| `plain` | Sans icones (compatible tous terminaux) |

## Theme actif

Le theme actif est enregistre dans `~/.zanvil/.current_theme`.

```bash
# Voir le theme actuel
cat ~/.zanvil/.current_theme

# Le prompt Starship utilise le prompt.toml du theme actif
# La palette est sourcee automatiquement
```

## Creer un theme personnalise

1. Creez un repertoire dans `~/.zanvil/themes/` :

```bash
mkdir -p ~/.zanvil/themes/custom
```

2. Copiez un theme existant comme base :

```bash
cp ~/.zanvil/themes/minimal/prompt.toml ~/.zanvil/themes/custom/
cp ~/.zanvil/themes/minimal/palette.zsh ~/.zanvil/themes/custom/
```

3. Editez les fichiers selon vos preferences :
   - `prompt.toml` : voir la [documentation Starship](https://starship.rs/config/)
   - `palette.zsh` : definir les couleurs du theme

4. Appliquez :

```bash
zanvil-theme custom
```

## Integration Ghostty

Le theme Ghostty peut etre synchronise avec le theme zanvil :

```bash
# Appliquer un theme Ghostty
zanvil-ghostty gruvbox

# Synchroniser avec le theme zanvil actif
zanvil-ghostty sync
```
