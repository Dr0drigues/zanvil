# Tmux Manager

Gestion simplifiée des sessions tmux.

## Commandes

| Commande | Description |
|----------|-------------|
| `tm [session]` | Attach ou crée une session |
| `tm-list` | Liste les sessions actives |
| `tm-kill [session]` | Tue une session |
| `tm-kill-others` | Tue toutes les sessions sauf la courante |
| `tm-rename [name]` | Renomme la session courante |
| `tm-project [dir] [name]` | Crée une session avec layout projet |
| `tm-help` | Affiche l'aide |

## Utilisation basique

```bash
# Sans argument : sélection interactive ou création
tm

# Créer/attacher à une session nommée
tm dev

# Lister les sessions
tm-list

# Tuer une session
tm-kill dev
```

## Sélection interactive

Avec fzf :
```
Sessions tmux (ENTER: attach, Ctrl-N: nouvelle)

> main
  dev
  staging
```

- **ENTER** : Attach à la session sélectionnée
- **Ctrl-N** : Créer une nouvelle session

## Session projet

```bash
# Crée une session avec layout projet
tm-project ~/work/mon-projet

# Avec nom personnalisé
tm-project ~/work/mon-projet mon-projet-dev
```

Layout créé :
- **Fenêtre 1 (edit)** : Pour l'éditeur
- **Fenêtre 2 (term)** : Terminal général
- **Fenêtre 3 (git)** : Git et logs

## Dans tmux

```bash
# Renommer la session courante
tm-rename nouveau-nom

# Tuer toutes les autres sessions
tm-kill-others
```

## Intégration Project Switcher

Dans le fichier `.proj` :

```yaml
tmux_session: mon-projet
```

Quand vous chargez le projet avec `proj mon-projet`, il suggère :
```
Tmux: utilisez 'tm mon-projet' pour la session dédiée
```

## Liste des sessions

```bash
tm-list
```

Affiche :
```
Sessions tmux:
──────────────────────────────────────────
*   main (3 fenêtres, créé 10:30)
    dev (2 fenêtres, créé 09:15)
──────────────────────────────────────────
* = session attachée
```
