# Zanvil Environment & Productivity Suite

Bienvenue sur le wiki de **zanvil** v2 - une configuration Zsh modulaire et orientee productivite pour developpeurs.

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
~/.zanvil/
├── rc.zsh                    # Point d'entree principal
├── core/                     # Noyau du framework
│   ├── loader.zsh            # Chargement des modules (ex functions.zsh)
│   ├── variables.zsh         # Variables d'environnement
│   ├── aliases.zsh           # Alias globaux
│   ├── hooks.zsh             # Hooks shell (chpwd, precmd, etc.)
│   ├── ui.zsh                # Systeme UI (couleurs, formatage)
│   ├── commands.zsh          # Commandes zanvil-* principales
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
├── zanvil/              # CLI Rust (zanvil)
└── install.sh                # Bootstrapper cross-platform
```

### Flux de chargement v2

1. `.zshrc` source `rc.zsh` via `$ZANVIL_DIR`
2. `rc.zsh` charge : secrets (`~/.secrets`), `core/variables.zsh`, `core/loader.zsh`, `core/aliases.zsh`, `core/hooks.zsh`
3. `core/loader.zsh` charge `core/ui.zsh` en premier, puis les fichiers core, puis les modules actifs
4. Chaque module est charge via `modules/<name>/init.zsh`
5. `env.d/` est evalue pour les variables dynamiques (support sops)
6. `.zanvil.local` est auto-charge si present et approuve (mecanisme de confiance)
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
| `zanvil` | CLI Rust pour theme, doctor, audit, context, modules |

## Modules

| Module | Description | Activation |
|--------|-------------|------------|
| GitLab | Scripts clone/trigger en masse | `zanvil-modules enable gitlab` |
| Docker | Utilitaires Docker (dex) | `zanvil-modules enable docker` |
| NVM | Auto-switch Node.js | `zanvil-modules enable nvm` |
| Kube | Gestion multi-config K8s | `zanvil-modules enable kube` |

Voir `zanvil-modules list` pour la liste complete.

## Commandes essentielles

```bash
ss                      # Recharger la config
zanvil-doctor          # Diagnostic complet
zanvil-status          # Statut rapide
zanvil-profile         # Profiler le temps de demarrage
zanvil-audit           # Audit de securite
zanvil-modules list    # Lister les modules
zanvil-theme list      # Lister les themes
zanvil-backup          # Sauvegarder la configuration
zanvil-switch <profil> # Changer de profil d'environnement
```

## CLI Rust (zanvil)

Le binaire `zanvil` fournit des commandes performantes :

```bash
zanvil theme       # Gestion des themes
zanvil doctor      # Diagnostic
zanvil audit       # Audit de securite
zanvil context     # Contexte projet
zanvil modules     # Gestion des modules
```

## Interface visuelle

Toutes les commandes `zanvil-*` utilisent un style moderne et compact :

```
╭──────────────────────────────────────────╮
│  ZANVIL Doctor                   v2.0.0  │
╰──────────────────────────────────────────╯

Config         rc.zsh ✓  aliases ✓  variables ✓
Requis         git ✓  curl ✓  jq ✓

────────────────────────────────────────────
✓ Tout est OK
```

## Contribuer

Voir [[Contributing]] pour les conventions de documentation.
