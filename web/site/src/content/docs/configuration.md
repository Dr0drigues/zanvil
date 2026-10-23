---
title: Configuration
description: Configurer zanvil (zanvil) via config.zsh et les modules
---

La configuration se fait via `~/.zanvil/config.zsh`.

## Fichier de configuration

```bash
# Créer depuis le template
cp ~/.zanvil/examples/config.zsh.example ~/.zanvil/config.zsh
```

## Architecture

La configuration est répartie dans `core/` :

| Fichier | Rôle |
|---------|------|
| `core/ui.zsh` | Système UI — chargé en premier, fournit les `_ui_*` et la palette du thème |
| `core/variables.zsh` | Variables d'environnement |
| `core/aliases.zsh` | Alias globaux |
| `core/loader.zsh` | Découverte et chargement des modules |
| `core/hooks.zsh` | Init des outils (starship, fzf, mise, zoxide, direnv, `.zanvil.local`) |
| `core/completions.zsh` | Complétions des commandes core |
| `core/commands/` | Commandes `zanvil-*` : `commands.zsh`, `admin.zsh`, `theme.zsh`, `setup.zsh`, `check_env_deps.zsh` |
| `core/lifecycle/` | Cycle de vie : `auto_update.zsh`, `migrate.zsh`, `sync.zsh` |

## Modules

Les modules sont maintenant gérés via `zanvil-modules` :

```bash
# Lister les modules
zanvil-modules list

# Activer un module
zanvil-modules enable gitlab

# Désactiver un module
zanvil-modules disable nvm
```

Chaque module est dans `modules/<name>/` avec un `init.zsh` et optionnellement un `completions.zsh`.

Configuration manuelle dans `config.zsh` :

```zsh
# Modules metier
ZANVIL_MODULE_GITLAB=true     # Alias GitLab, clone de groupes, statut PAT
ZANVIL_MODULE_KUBE=true       # Gestion kubeconfig (kube_select, Azure/AWS/GCP)
ZANVIL_MODULE_DOCKER=true     # Utilitaires Docker (dex, dstop)
ZANVIL_MODULE_SECURITY=false  # Audit de securite et scan de secrets
ZANVIL_MODULE_AI=false        # Estimation de tokens LLM et contexte repo
ZANVIL_MODULE_TOOLS=false     # mise hooks, test runner, profiler zsh

# Outils tiers — chacun deploie sa configuration avec <outil>_setup
ZANVIL_MODULE_DELTA=true      # Pager syntaxique pour git diff
ZANVIL_MODULE_LAZYGIT=true    # TUI Git ergonomique (alias lg)
ZANVIL_MODULE_ATUIN=true      # Historique shell enrichi SQLite (fuzzy search)
ZANVIL_MODULE_POSTING=true    # Client HTTP TUI (alias po)

# Integrations
ZANVIL_MODULE_MISE=true       # Gestionnaire de versions (Node, Java, Maven)
ZANVIL_MODULE_NUSHELL=true    # Integration Nushell
```

Un module dont le guard est absent de `config.zsh` reste inactif. Les modules `git`, `ssh`, `utils`,
`project` et `work` n'ont pas de guard : ils sont toujours chargés.

:::note[Migration depuis NVM]
`ZANVIL_MODULE_NVM` est déprécié au profit de `ZANVIL_MODULE_MISE`, qui gère Node mais aussi Java et
Maven. `rc.zsh` reporte automatiquement l'ancienne valeur sur la nouvelle et retire `ZANVIL_NVM_LAZY`,
qui n'a plus d'effet — rien à changer dans un `config.zsh` existant.
:::

## Variables dynamiques (env.d/)

Le dossier `env.d/` permet de définir des variables d'environnement par fichier. Chaque fichier `.env` est chargé automatiquement au démarrage.

```bash
# Créer une variable
echo 'MY_VAR=value' > ~/.zanvil/env.d/my-project.env
```

### Chiffrement sops

Les fichiers `env.d/` supportent le chiffrement sops :

```bash
# Créer un fichier chiffré
sops ~/.zanvil/env.d/secrets.env

# Le déchiffrement est automatique au chargement
```

## Chargement local (.zanvil.local)

Le fichier `.zanvil.local` est auto-chargé lorsque vous entrez dans un répertoire (similaire à direnv). Un mécanisme de confiance basé sur un hash empêche l'exécution de fichiers non approuvés.

```bash
# Créer un fichier local
echo 'export NODE_ENV=development' > /path/to/project/.zanvil.local

# La première fois, zanvil demandera d'approuver le fichier
# Après approbation, il sera chargé automatiquement
```

### Héritage hiérarchique

Le système gère les arborescences : en entrant dans un dossier, zanvil charge **toute la chaîne** des `.zanvil.local`, de la racine projet vers le dossier courant. L'enfant override les variables du parent.

```text
~/ctf/otw/.zanvil.local          # racine : serveur, port, fonctions helper
~/ctf/otw/bandit0/.zanvil.local  # enfant : USER, PASSWORD
```

Règles :

- La remontée s'arrête à `$HOME` (exclu) — pour du global, utilisez `config.zsh` ou `env.d/`
- Le trust est évalué **par fichier** ; refuser un parent coupe l'héritage pour ses enfants
- Au déchargement : variables ajoutées supprimées, variables modifiées restaurées, fonctions définies retirées
- N'utilisez que des `export VAR=...` (les assignations non exportées ne sont pas tracées)

Un exemple complet (serveur/port + fonction qui génère les dossiers enfants) est disponible dans [`examples/zanvil.local.overthewire.example`](https://github.com/Dr0drigues/zanvil/blob/main/examples/zanvil.local.overthewire.example).

## Profils d'environnement

Les profils permettent de basculer entre différents jeux de configuration :

```bash
# Changer de profil
zanvil-switch work
zanvil-switch personal

# Réinitialiser la configuration
zanvil-config-reset
```

Les profils sont stockés dans `~/.zanvil/profiles/`.

## Thèmes

```zsh
# Définir le thème (via commande)
zanvil-theme minimal
```

Le thème actif est enregistré dans `~/.zanvil/.current_theme`.

Les fichiers générés vont dans `~/.config/zanvil/theme/` (hors du dépôt dotfiles) :

- `starship.toml` : zanvil exporte `STARSHIP_CONFIG` vers ce fichier au démarrage, si la variable n'est pas déjà définie ;
- `ghostty` : la config Ghostty l'inclut avec `config-file = ?~/.config/zanvil/theme/ghostty` (le `?` le rend facultatif) ;
- k9s : le skin est choisi par la variable `K9S_SKIN`, sans toucher à `config.yaml` ;
- `colors.sh` : couleurs du thème au format `0xAARRGGBB` (`ZANVIL_BAR_BG`, `ZANVIL_BAR_TEXT`, `ZANVIL_BAR_DIM`, `ZANVIL_ACCENT`), à sourcer depuis SketchyBar ou JankyBorders (sh ou zsh). Accent, texte et texte atténué viennent de `_ui_blue`, `_ui_white` et `_ui_dim` ; le fond, de `_theme_bg` (valeurs de repli si la palette ne les définit pas). Après `zanvil-theme`, zanvil lance `~/.config/sketchybar/recolor` s'il est exécutable (sinon `sketchybar --reload`) et `~/.config/borders/bordersrc`, si ces programmes tournent ; il ne les démarre jamais.

Un CLI `zanvil` compilé avant ce changement écrit ailleurs : reconstruisez-le (`cd ~/.zanvil/cli && cargo build --release`).

### Fond d'écran

Sur macOS, si `~/.config/zanvil/wallpapers/<thème>.jpg` existe (ou `.jpeg`, `.png`, `.heic`, dans cet ordre), `zanvil-theme <thème>` le pose sur tous les écrans. Les images vous appartiennent : placez-les dans votre dépôt dotfiles. Sans image pour le thème, le fond ne change pas. Un fond imposé par une gestion de parc (MDM) peut reprendre le dessus.

### Clair et sombre

```zsh
# config.zsh
ZANVIL_THEME_LIGHT=tokyo-light-pro
ZANVIL_THEME_DARK=tokyo-night-pro
```

`zanvil-theme auto` applique celui qui correspond à l'apparence du système ; zanvil le fait aussi à l'ouverture de chaque shell. Pour suivre un changement d'apparence en direct, faites lancer `zanvil-theme auto` à la notification `AppleInterfaceThemeChangedNotification`, par exemple par un élément SketchyBar (voir [Bureau macOS](/zanvil/bureau-macos/)).

Ghostty sait suivre l'apparence lui-même, sans rechargement : `zanvil-ghostty auto` écrit dans le fichier généré une paire `theme = light:…,dark:…` (par défaut `tokyo-light-storm` et `tokyo-night-storm`, réglables par `ZANVIL_GHOSTTY_LIGHT` et `ZANVIL_GHOSTTY_DARK`). Rechargez la config Ghostty une fois.

## Profil machine et dotfiles

```zsh
ZANVIL_PROFILE=pro                                        # pro ou perso
ZANVIL_DOTFILES_REPO="git@github.com:<toi>/dotfiles.git"  # pas de valeur par défaut
ZANVIL_DOTFILES_DIR="$HOME/.dotfiles"                     # défaut
```

`install.sh` écrit `ZANVIL_PROFILE`, `ZANVIL_DOTFILES_REPO` et `ZANVIL_DOTFILES_DIR` dans `config.zsh`. `zanvil-dotfiles` lit `ZANVIL_PROFILE` et `ZANVIL_DOTFILES_DIR` (voir la page Commandes).

## Versions de runtimes (mise)

`mise` remplace NVM et couvre Node, Java et Maven. Il est activé par défaut et branché dans
`core/hooks.zsh`, qui appelle `mise activate zsh` au démarrage si le binaire est présent.

```zsh
ZANVIL_MODULE_MISE=true
```

Les hooks du module `tools` (`modules/tools/mise_hooks.zsh`) ajoutent la détection du fichier
`.mise.toml` d'un projet au `cd`.

## Auto-update

```zsh
ZANVIL_AUTO_UPDATE=true      # Activer
ZANVIL_UPDATE_FREQUENCY=7    # Vérifier tous les X jours
ZANVIL_UPDATE_MODE="prompt"  # "prompt" ou "auto"
```

## Plugins

```zsh
# Organisation par défaut
ZANVIL_PLUGINS_ORG=zsh-users

# Plugins à installer
ZANVIL_PLUGINS=(
    zsh-autosuggestions
    zsh-syntax-highlighting
    Aloxaf/fzf-tab
)
```

## Variables d'environnement

```zsh
# Dossier de travail
WORK_DIR="$HOME/work"

# Dossier des scripts
SCRIPTS_DIR="$ZANVIL_DIR/scripts"
```

## Secrets

Créez `~/.secrets` pour vos tokens (ignoré par git) :

```zsh
export GITLAB_TOKEN="glpat-xxxx"
export GITHUB_TOKEN="ghp_xxxx"
export AWS_PROFILE="default"
```

## Aliases locaux

Créez `~/.zanvil/aliases.local.zsh` pour vos alias personnels :

```zsh
alias myproj="cd ~/Projects/mon-projet && code ."
alias vpn="sudo openvpn /etc/openvpn/client.conf"
```

## Sauvegarde et restauration

```bash
# Sauvegarder la config
zanvil-backup

# Restaurer
zanvil-restore
```

## Structure des fichiers

| Fichier | Description | Versionné |
|---------|-------------|-----------|
| `config.zsh` | Configuration personnelle | Non |
| `aliases.local.zsh` | Aliases personnels | Non |
| `.current_theme` | Thème actif | Non |
| `env.d/*.env` | Variables dynamiques | Non (sauf chiffrées) |
| `profiles/` | Profils d'environnement | Non |
| `~/.secrets` | Tokens et secrets | Non |
| `~/.gitlab_secrets` | Config GitLab | Non |
| `~/.kube/.context_aliases` | Alias de contextes Kube | Non |
