# Thèmes Starship

Plusieurs thèmes de prompt Starship sont inclus.

## Commandes

```bash
# Lister les thèmes disponibles
zsh-env-theme list

# Appliquer un thème
zsh-env-theme minimal
```

## Thèmes disponibles

| Thème | Description |
|-------|-------------|
| `minimal` | Prompt minimaliste et rapide |
| `default` | Configuration équilibrée |
| `powerline` | Style powerline avec séparateurs |
| `plain` | Sans icônes (compatible tous terminaux) |

## Créer un thème personnalisé

1. Créez un fichier dans `~/.zsh_env/themes/` :

```bash
cp ~/.zsh_env/themes/minimal.toml ~/.zsh_env/themes/custom.toml
```

2. Éditez le fichier selon la [documentation Starship](https://starship.rs/config/)

3. Appliquez :

```bash
zsh-env-theme custom
```

## Configuration manuelle

Le thème actif est un lien symbolique vers `~/.config/starship.toml`.

```bash
# Voir le thème actuel
ls -la ~/.config/starship.toml

# Appliquer manuellement
ln -sf ~/.zsh_env/themes/minimal.toml ~/.config/starship.toml
```

## Exemple de thème minimal

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
