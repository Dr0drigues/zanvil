# ZSH Environment & Productivity Suite

Bienvenue sur le wiki de **zsh_env** v2 - une configuration Zsh modulaire et orientee productivite pour developpeurs.

## Navigation rapide

### Demarrage
- [[Installation]]
- [[Configuration]]
- [[Troubleshooting]]

### Fonctionnalites principales
- [[Commandes]] - Reference complete des commandes
- [[Project-Switcher]] - Gestion de contexte projet
- [[Kubernetes]] - Multi-config Kubernetes, kube_switch, kube_ns, k9s
- [[SSH-Manager]] - Gestion des connexions SSH
- [[Tmux-Manager]] - Gestion des sessions tmux
- [[Git-Hooks]] - Gestionnaire de hooks Git
- [[Security]] - Audit de securite et mecanisme de confiance

### Outils IA
- [[AI-Context]] - Generation de contexte pour assistants IA (Claude, Cursor, Copilot)
- [[AI-Tokens]] - Estimation et optimisation des tokens LLM

### Personnalisation
- [[Themes]] - Themes unifies (Starship + palette terminal)
- [[Plugins]] - Gestionnaire de plugins
- [[Aliases]] - Alias et fonctions personnalisees

## Architecture v2

```
~/.zsh_env/
├── rc.zsh                    # Point d'entree principal
├── core/                     # Noyau du framework
│   ├── loader.zsh            # Chargement des modules (ex functions.zsh)
│   ├── variables.zsh         # Variables d'environnement
│   ├── aliases.zsh           # Alias globaux
│   ├── hooks.zsh             # Hooks shell (chpwd, precmd, etc.)
│   ├── ui.zsh                # Systeme UI (couleurs, formatage)
│   ├── commands.zsh          # Commandes zsh-env-* principales
│   ├── admin.zsh             # Commandes d'administration
│   ├── theme.zsh             # Gestion des themes
│   └── setup.zsh             # Setup initial
├── modules/                  # Modules optionnels
│   └── <name>/
│       ├── init.zsh          # Point d'entree du module
│       └── completions.zsh   # Completions du module
├── themes/                   # Themes (prompt.toml + palette.zsh)
├── env.d/                    # Variables d'env dynamiques (support sops)
├── profiles/                 # Profils d'environnement
├── scripts/                  # Scripts autonomes
├── zsh-env-cli/              # CLI Rust (zsh-env-cli)
└── install.sh                # Bootstrapper cross-platform
```

### Flux de chargement v2

1. `.zshrc` source `rc.zsh` via `$ZSH_ENV_DIR`
2. `rc.zsh` charge : secrets (`~/.secrets`), `core/variables.zsh`, `core/loader.zsh`, `core/aliases.zsh`, `core/hooks.zsh`
3. `core/loader.zsh` charge `core/ui.zsh` en premier, puis les fichiers core, puis les modules actifs
4. Chaque module est charge via `modules/<name>/init.zsh`
5. `env.d/` est evalue pour les variables dynamiques (support sops)
6. `.zsh-env.local` est auto-charge si present et approuve (mecanisme de confiance)
7. mise est active via `eval "$(mise activate zsh)"`

## Outils installes

| Outil | Description |
|-------|-------------|
| `zoxide` | Navigation intelligente (remplace `cd`) |
| `starship` | Prompt moderne et rapide |
| `eza` | Remplace `ls` avec couleurs et icones |
| `fzf` | Fuzzy finder interactif |
| `bat` | `cat` avec coloration syntaxique |
| `tmux` | Multiplexeur de terminal |
| `zsh-env-cli` | CLI Rust pour theme, doctor, audit, context, modules |

## Modules

| Module | Description | Activation |
|--------|-------------|------------|
| GitLab | Scripts clone/trigger en masse | `zsh-env-modules enable gitlab` |
| Docker | Utilitaires Docker (dex) | `zsh-env-modules enable docker` |
| NVM | Auto-switch Node.js | `zsh-env-modules enable nvm` |
| Kube | Gestion multi-config K8s | `zsh-env-modules enable kube` |

Voir `zsh-env-modules list` pour la liste complete.

## Commandes essentielles

```bash
ss                      # Recharger la config
zsh-env-doctor          # Diagnostic complet
zsh-env-status          # Statut rapide
zsh-env-profile         # Profiler le temps de demarrage
zsh-env-audit           # Audit de securite
zsh-env-modules list    # Lister les modules
zsh-env-theme list      # Lister les themes
zsh-env-backup          # Sauvegarder la configuration
zsh-env-switch <profil> # Changer de profil d'environnement
```

## CLI Rust (zsh-env-cli)

Le binaire `zsh-env-cli` fournit des commandes performantes :

```bash
zsh-env-cli theme       # Gestion des themes
zsh-env-cli doctor      # Diagnostic
zsh-env-cli audit       # Audit de securite
zsh-env-cli context     # Contexte projet
zsh-env-cli modules     # Gestion des modules
```

## Interface visuelle

Toutes les commandes `zsh-env-*` utilisent un style moderne et compact :

```
╭──────────────────────────────────────────╮
│  ZSH_ENV Doctor                  v2.0.0  │
╰──────────────────────────────────────────╯

Config         rc.zsh ✓  aliases ✓  variables ✓
Requis         git ✓  curl ✓  jq ✓

────────────────────────────────────────────
✓ Tout est OK
```

## Contribuer

Voir [[Contributing]] pour les conventions de documentation.
