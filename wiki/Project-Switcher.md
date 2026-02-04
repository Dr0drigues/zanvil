# Project Switcher

Le Project Switcher permet de changer de contexte complet en une commande : dossier, contexte Kubernetes, version Node, session tmux, variables d'environnement.

## Commandes

```bash
proj [name|path]       # Charge un projet
proj --add [name]      # Enregistre le projet courant
proj --list            # Liste les projets enregistrés
proj --scan [dir]      # Scanne et propose des projets
proj --auto [dir]      # Auto-enregistre les projets avec .proj
proj --init            # Crée un fichier .proj
proj --remove <name>   # Supprime un projet
```

## Fichier .proj

Créez un fichier `.proj` à la racine de votre projet :

```bash
proj --init
```

Contenu du fichier :

```yaml
# Nom du projet (pour l'enregistrement)
name: mon-projet

# Contexte Kubernetes
kube_context: my-cluster-dev

# Version Node (ou utilise .nvmrc)
node_version: 18

# Session tmux suggérée
tmux_session: mon-projet

# Fichier d'environnement à charger
env_file: .env.local

# Commande post-chargement
post_cmd: echo "Projet chargé!"
```

## Registre des projets

Les projets sont enregistrés dans `~/.config/zsh_env/projects.yml` :

```yaml
mon-projet: "/Users/user/work/mon-projet"
autre-projet: "/Users/user/work/autre-projet"
```

## Scanner des projets

```bash
# Scanne le dossier de travail (défaut: $WORK_DIR ou ~/projects)
proj --scan

# Scanne un dossier spécifique avec profondeur
proj --scan ~/work 3
```

Le scan détecte les marqueurs de projet :
- `.proj`, `.project.yml` - Configuration zsh_env
- `.git` - Repository Git
- `package.json` - Projet Node.js
- `Cargo.toml` - Projet Rust
- `go.mod` - Projet Go
- `pyproject.toml`, `setup.py` - Projet Python
- `pom.xml`, `build.gradle` - Projet Java

## Auto-enregistrement

```bash
# Enregistre automatiquement tous les projets avec .proj
proj --auto ~/work
```

## Workflow typique

```bash
# 1. Dans un projet, créer le fichier de config
cd ~/work/mon-projet
proj --init

# 2. Éditer le fichier .proj
vim .proj

# 3. Enregistrer le projet
proj --add

# 4. Plus tard, charger le projet
proj mon-projet
```

## Intégration tmux

Si `tmux_session` est défini et tmux disponible :

```bash
# Charge le projet puis suggère la session tmux
proj mon-projet
# -> "Tmux: utilisez 'tm mon-projet' pour la session dédiée"

# Créer directement la session avec le projet
tm-project ~/work/mon-projet
```
