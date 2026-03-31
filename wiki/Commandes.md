# Reference des commandes

## Commandes zsh-env

| Commande | Description |
|----------|-------------|
| `zsh-env-list` | Liste les outils installes avec versions (format tableau) |
| `zsh-env-doctor` | Diagnostic complet de l'installation (compact) |
| `zsh-env-status` | Statut rapide (version, modules, git) |
| `zsh-env-profile` | Profile le temps de demarrage par module |
| `zsh-env-benchmark [n]` | Benchmark sur n executions (defaut: 5) |
| `zsh-env-audit` | Audit de securite des permissions (compact) |
| `zsh-env-audit-fix` | Corrige automatiquement les permissions |
| `zsh-env-theme [nom]` | Gere les themes unifies (Starship + palette) |
| `zsh-env-ghostty [nom\|sync]` | Gere les themes Ghostty |
| `zsh-env-completions` | Charge les auto-completions |
| `zsh-env-completion-add` | Ajoute une completion personnalisee |
| `zsh-env-completion-remove` | Supprime une completion personnalisee |
| `zsh-env-update` | Force la mise a jour |
| `zsh-env-help` | Affiche l'aide (format tableau) |
| `zsh-env-modules list` | Liste les modules disponibles et leur statut |
| `zsh-env-modules enable <nom>` | Active un module |
| `zsh-env-modules disable <nom>` | Desactive un module |
| `zsh-env-backup` | Sauvegarde la configuration zsh-env |
| `zsh-env-restore` | Restaure une sauvegarde |
| `zsh-env-switch <profil>` | Change de profil d'environnement |
| `zsh-env-config-reset` | Reinitialise la configuration |

Toutes les commandes `zsh-env-*` utilisent un style visuel moderne et compact via le systeme UI.

## CLI Rust (zsh-env-cli)

| Commande | Description |
|----------|-------------|
| `zsh-env-cli theme` | Gestion des themes (list, apply, preview) |
| `zsh-env-cli doctor` | Diagnostic complet en Rust (rapide) |
| `zsh-env-cli audit` | Audit de securite avance |
| `zsh-env-cli context` | Generation de contexte projet |
| `zsh-env-cli modules` | Gestion des modules (list, enable, disable) |

## GitLab

| Commande | Description |
|----------|-------------|
| `zsh-env-gitlab-status` | Affiche le statut des pipelines GitLab |
| `zsh-env-gitlab-browse` | Ouvre le projet GitLab dans le navigateur |
| `gpr` | Alias pour creer une merge request GitLab |
| `clone-projects [--dry-run] [--parallel]` | Clone en masse des projets GitLab |
| `git-bulk [--dry-run]` | Operations Git en masse sur plusieurs repos |

## Navigation

| Commande | Description |
|----------|-------------|
| `z <pattern>` | Jump intelligent (zoxide) |
| `gr` | Va a la racine du repo git |
| `mkcd <dir>` | Cree un dossier et y entre |

## Project Switcher

| Commande | Description |
|----------|-------------|
| `proj [name]` | Charge un projet |
| `proj --add [name]` | Enregistre le projet courant |
| `proj --list` | Liste les projets |
| `proj --scan [dir]` | Scanne et propose des projets |
| `proj --auto [dir]` | Auto-enregistre les projets avec .proj |
| `proj --init` | Cree un fichier .proj |
| `proj --remove <name>` | Supprime un projet |

Voir [[Project-Switcher]] pour plus de details.

## Kubernetes

| Commande | Description |
|----------|-------------|
| `kube_select` | Selection interactive des configs |
| `kube_status` | Affiche les configs actives |
| `kube_add <file>` | Ajoute une config |
| `kube_reset` | Remet la config minimale |
| `kube_switch [context]` | Change de contexte Kubernetes (fzf si sans arg) |
| `kube_ns [namespace]` | Change de namespace (fzf si sans arg) |
| `k [alias]` | Lance k9s avec support des alias de contexte |
| `kube_azure [cluster]` | Recupere credentials Azure AKS |
| `kube_aws [cluster]` | Recupere credentials AWS EKS |
| `kube_gcp [cluster]` | Recupere credentials GCP GKE |

Voir [[Kubernetes]] pour plus de details.

## SSH

| Commande | Description |
|----------|-------------|
| `ssh_select` | Selection interactive des hosts |
| `ssh_list` | Liste les hosts configures |
| `ssh_add` | Ajoute un host interactivement |
| `ssh_remove [host]` | Supprime un host |
| `ssh_test <host>` | Teste la connexion |

Voir [[SSH-Manager]] pour plus de details.

## Tmux

| Commande | Description |
|----------|-------------|
| `tm [session]` | Attach ou cree une session |
| `tm-list` | Liste les sessions |
| `tm-kill [session]` | Tue une session |
| `tm-project [dir]` | Cree une session projet |
| `tm-rename [name]` | Renomme la session courante |

Voir [[Tmux-Manager]] pour plus de details.

## Git Hooks

| Commande | Description |
|----------|-------------|
| `hooks_install` | Installe tous les hooks standards |
| `hooks_list` | Liste les hooks installes |
| `hooks_remove [hook]` | Supprime un hook |
| `hooks_enable <hook>` | Active un hook |
| `hooks_disable <hook>` | Desactive un hook |

Voir [[Git-Hooks]] pour plus de details.

## Docker

| Commande | Description |
|----------|-------------|
| `dex [container]` | Exec dans un conteneur (fzf) |
| `dstop` | Arrete tous les conteneurs |

## Utilitaires

| Commande | Description |
|----------|-------------|
| `ss` | Recharge ~/.zshrc |
| `please` | Relance la derniere commande avec sudo |
| `extract <file>` | Extrait n'importe quelle archive |
| `trash <files>` | Deplace vers la corbeille |
| `bak <file>` | Cree une backup horodatee |
| `cx <file>` | Rend un fichier executable |
| `fkill` | Tue un processus (fzf) |
| `myip` | Affiche IP publique et locale |

## Plugins

| Commande | Description |
|----------|-------------|
| `zsh-plugin-list` | Liste les plugins |
| `zsh-plugin-install <repo>` | Installe un plugin |
| `zsh-plugin-remove <nom>` | Supprime un plugin |
| `zsh-plugin-update` | Met a jour les plugins |

## AI Context

| Commande | Description |
|----------|-------------|
| `ai-context detect` | Affiche les infos detectees du projet |
| `ai-context init` | Cree un fichier .ai-context.yml |
| `ai-context generate` | Genere CLAUDE.md, .cursorrules, copilot-instructions |
| `ai-context generate -f` | Genere en ecrasant les fichiers existants |
| `ai-context templates` | Liste les templates disponibles |

Voir [[AI-Context]] pour plus de details.

## AI Tokens

| Commande | Description |
|----------|-------------|
| `ai-tokens estimate [file\|dir]` | Estime les tokens d'un fichier ou dossier |
| `ai-tokens analyze [dir]` | Analyse detaillee avec suggestions |
| `ai-tokens compress [file]` | Compresse le contenu (supprime commentaires) |
| `ai-tokens select [dir] [query]` | Selectionne les fichiers pertinents |
| `ai-tokens export [dir]` | Exporte le contexte optimise |

Alias: `ait` (raccourci pour ai-tokens)

Voir [[AI-Tokens]] pour plus de details.
