# Aliases

Aliases globaux et personnalisation.

## Aliases globaux

Définis dans `~/.zsh_env/aliases.zsh` :

### Configuration

| Alias | Commande |
|-------|----------|
| `s` | `source` |
| `ss` | `source ~/.zshrc && echo "reloaded"` |

### Listing (eza)

| Alias | Commande |
|-------|----------|
| `ls` | `eza --color=auto` |
| `l` | `ls -lah` |
| `ll` | `ls -la` |
| `l.` | `ls -d .*` |

### Git

| Alias | Commande |
|-------|----------|
| `gst` | `git status` |
| `gl` | `git fetch --all; git pull` |
| `ga` | `git add` |
| `gp` | `git push` |
| `gc` | `git commit -v` |
| `gld` | `git log --oneline --decorate --graph --all` |
| `git-clean-branches` | Nettoie les branches mergées |

### Navigation

| Alias | Commande |
|-------|----------|
| `..` | `cd ..` |
| `...` | `cd ../..` |

### Utilitaires

| Alias | Commande |
|-------|----------|
| `c` | `clear` |
| `h` | `history` |
| `please` | `sudo $(fc -ln -1)` |
| `x` | `extract` |
| `cat` | `bat` (si disponible) |
| `rm` | `trash` (si disponible) |

### Node.js

| Alias | Commande |
|-------|----------|
| `npmi` | `npm install` |
| `npmu` | `npm update` |
| `npml` | `npm list --depth=0` |
| `nci` | `npm cache clean && npm install` |

## Aliases locaux

Créez `~/.zsh_env/aliases.local.zsh` pour vos aliases personnels (non versionnés) :

```bash
cp ~/.zsh_env/aliases.local.zsh.example ~/.zsh_env/aliases.local.zsh
```

Exemple :

```zsh
# Raccourcis projet
alias myproj="cd ~/Projects/mon-projet && code ."

# Commandes spécifiques
alias vpn="sudo openvpn /etc/openvpn/client.conf"
alias k="kubectl"
alias kgp="kubectl get pods"
```

## Fonctions utilitaires

| Fonction | Description |
|----------|-------------|
| `mkcd <dir>` | Crée un dossier et y entre |
| `trash <files>` | Déplace vers la corbeille |
| `bak <file>` | Crée une backup horodatée |
| `cx <file>` | Rend exécutable |
| `extract <file>` | Extrait n'importe quelle archive |
| `gr` | Va à la racine du repo git |
| `fkill` | Tue un processus (fzf) |
| `myip` | Affiche IP publique et locale |
