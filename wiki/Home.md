# ZSH Environment & Productivity Suite

Bienvenue sur le wiki de **zsh_env** - une configuration Zsh modulaire et orientée productivité pour développeurs.

## Navigation rapide

### Démarrage
- [[Installation]]
- [[Configuration]]
- [[Troubleshooting]]

### Fonctionnalités principales
- [[Commandes]] - Référence complète des commandes
- [[Project-Switcher]] - Gestion de contexte projet
- [[Kubernetes]] - Multi-config Kubernetes (Azure, AWS, GCP)
- [[SSH-Manager]] - Gestion des connexions SSH
- [[Tmux-Manager]] - Gestion des sessions tmux
- [[Git-Hooks]] - Gestionnaire de hooks Git
- [[Security]] - Audit de sécurité

### Outils IA
- [[AI-Context]] - Génération de contexte pour assistants IA (Claude, Cursor, Copilot)
- [[AI-Tokens]] - Estimation et optimisation des tokens LLM

### Personnalisation
- [[Themes]] - Thèmes Starship
- [[Plugins]] - Gestionnaire de plugins
- [[Aliases]] - Alias et fonctions personnalisées

## Outils installés

| Outil | Description |
|-------|-------------|
| `zoxide` | Navigation intelligente (remplace `cd`) |
| `starship` | Prompt moderne et rapide |
| `eza` | Remplace `ls` avec couleurs et icônes |
| `fzf` | Fuzzy finder interactif |
| `bat` | `cat` avec coloration syntaxique |
| `tmux` | Multiplexeur de terminal |

## Modules

| Module | Description | Activation |
|--------|-------------|------------|
| GitLab | Scripts clone/trigger en masse | `ZSH_ENV_MODULE_GITLAB=true` |
| Docker | Utilitaires Docker (dex) | `ZSH_ENV_MODULE_DOCKER=true` |
| NVM | Auto-switch Node.js | `ZSH_ENV_MODULE_NVM=true` |
| Kube | Gestion multi-config K8s | `ZSH_ENV_MODULE_KUBE=true` |

## Commandes essentielles

```bash
ss                  # Recharger la config
zsh-env-doctor      # Diagnostic complet
zsh-env-profile     # Profiler le temps de démarrage
zsh-env-audit       # Audit de sécurité
```

## Contribuer

Voir [[Contributing]] pour les conventions de documentation.
