---
title: Référence des commandes
description: Toutes les commandes zanvil (zsh-env-*) et le CLI Rust
---

## Commandes zsh-env

| Commande | Description |
|----------|-------------|
| `zsh-env-list` | Liste les outils installés avec versions (format tableau) |
| `zsh-env-doctor` | Diagnostic complet de l'installation (compact) |
| `zsh-env-status` | Statut rapide (version, modules, git) |
| `zsh-env-profile` | Profile le temps de démarrage par module |
| `zsh-env-benchmark [n]` | Benchmark sur n exécutions (défaut: 5) |
| `zsh-env-audit` | Audit de sécurité des permissions (compact) |
| `zsh-env-audit-fix` | Corrige automatiquement les permissions |
| `zsh-env-theme [nom]` | Gère les thèmes unifiés (Starship + palette) |
| `zsh-env-ghostty [nom\|sync]` | Gère les thèmes Ghostty |
| `zsh-env-completions` | Charge les auto-complétions |
| `zsh-env-completion-add` | Ajoute une complétion personnalisée |
| `zsh-env-completion-remove` | Supprime une complétion personnalisée |
| `zsh-env-update` | Force la mise à jour |
| `zsh-env-help` | Affiche l'aide (format tableau) |
| `zsh-env-modules list` | Liste les modules disponibles et leur statut |
| `zsh-env-modules enable <nom>` | Active un module |
| `zsh-env-modules disable <nom>` | Désactive un module |
| `zsh-env-backup` | Sauvegarde la configuration zsh-env |
| `zsh-env-restore` | Restaure une sauvegarde |
| `zsh-env-switch <profil>` | Change de profil d'environnement |
| `zsh-env-config-reset` | Réinitialise la configuration |

Toutes les commandes `zsh-env-*` utilisent un style visuel moderne et compact via le système UI.

## CLI Rust (zsh-env-cli)

| Commande | Description |
|----------|-------------|
| `zsh-env-cli theme` | Gestion des thèmes (list, apply, preview) |
| `zsh-env-cli doctor` | Diagnostic complet en Rust (rapide) |
| `zsh-env-cli audit` | Audit de sécurité avancé |
| `zsh-env-cli context` | Génération de contexte projet |
| `zsh-env-cli modules` | Gestion des modules (list, enable, disable) |

## GitLab

| Commande | Description |
|----------|-------------|
| `zsh-env-gitlab-status` | Affiche le statut des pipelines GitLab |
| `zsh-env-gitlab-browse` | Ouvre le projet GitLab dans le navigateur |
| `gpr` | Alias pour créer une merge request GitLab |
| `clone-projects [--dry-run] [--parallel]` | Clone en masse des projets GitLab |
| `git-bulk [--dry-run]` | Opérations Git en masse sur plusieurs repos |

## Navigation

| Commande | Description |
|----------|-------------|
| `z <pattern>` | Jump intelligent (zoxide) |
| `gr` | Va à la racine du repo git |
| `mkcd <dir>` | Crée un dossier et y entre |

## Project Switcher

| Commande | Description |
|----------|-------------|
| `proj [name]` | Charge un projet |
| `proj --add [name]` | Enregistre le projet courant |
| `proj --list` | Liste les projets |
| `proj --scan [dir]` | Scanne et propose des projets |
| `proj --auto [dir]` | Auto-enregistre les projets avec .proj |
| `proj --init` | Crée un fichier .proj |
| `proj --remove <name>` | Supprime un projet |

## Kubernetes

| Commande | Description |
|----------|-------------|
| `kube_select` | Sélection interactive des configs |
| `kube_status` | Affiche les configs actives |
| `kube_add <file>` | Ajoute une config |
| `kube_reset` | Remet la config minimale |
| `kube_switch [context]` | Change de contexte Kubernetes (fzf si sans arg) |
| `kube_ns [namespace]` | Change de namespace (fzf si sans arg) |
| `k [alias]` | Lance k9s avec support des alias de contexte |
| `kube_azure [cluster]` | Récupère credentials Azure AKS |
| `kube_aws [cluster]` | Récupère credentials AWS EKS |
| `kube_gcp [cluster]` | Récupère credentials GCP GKE |

## SSH

| Commande | Description |
|----------|-------------|
| `ssh_select` | Sélection interactive des hosts |
| `ssh_list` | Liste les hosts configurés |
| `ssh_add` | Ajoute un host interactivement |
| `ssh_remove [host]` | Supprime un host |
| `ssh_test <host>` | Teste la connexion |

## Tmux

| Commande | Description |
|----------|-------------|
| `tm [session]` | Attach ou crée une session |
| `tm-list` | Liste les sessions |
| `tm-kill [session]` | Tue une session |
| `tm-project [dir]` | Crée une session projet |
| `tm-rename [name]` | Renomme la session courante |

## Git Hooks

| Commande | Description |
|----------|-------------|
| `hooks_install` | Installe tous les hooks standards |
| `hooks_list` | Liste les hooks installés |
| `hooks_remove [hook]` | Supprime un hook |
| `hooks_enable <hook>` | Active un hook |
| `hooks_disable <hook>` | Désactive un hook |

## Docker

| Commande | Description |
|----------|-------------|
| `dex [container]` | Exec dans un conteneur (fzf) |
| `dstop` | Arrête tous les conteneurs |

## Utilitaires

| Commande | Description |
|----------|-------------|
| `ss` | Recharge ~/.zshrc |
| `please` | Relance la dernière commande avec sudo |
| `extract <file>` | Extrait n'importe quelle archive |
| `trash <files>` | Déplace vers la corbeille |
| `bak <file>` | Crée une backup horodatée |
| `cx <file>` | Rend un fichier exécutable |
| `fkill` | Tue un processus (fzf) |
| `myip` | Affiche IP publique et locale |

## Plugins

| Commande | Description |
|----------|-------------|
| `zsh-plugin-list` | Liste les plugins |
| `zsh-plugin-install <repo>` | Installe un plugin |
| `zsh-plugin-remove <nom>` | Supprime un plugin |
| `zsh-plugin-update` | Met à jour les plugins |

## AI Context

| Commande | Description |
|----------|-------------|
| `ai-context detect` | Affiche les infos détectées du projet |
| `ai-context init` | Crée un fichier .ai-context.yml |
| `ai-context generate` | Génère CLAUDE.md, .cursorrules, copilot-instructions |
| `ai-context generate -f` | Génère en écrasant les fichiers existants |
| `ai-context templates` | Liste les templates disponibles |

## AI Tokens

| Commande | Description |
|----------|-------------|
| `ai-tokens estimate [file\|dir]` | Estime les tokens d'un fichier ou dossier |
| `ai-tokens analyze [dir]` | Analyse détaillée avec suggestions |
| `ai-tokens compress [file]` | Compresse le contenu (supprime commentaires) |
| `ai-tokens select [dir] [query]` | Sélectionne les fichiers pertinents |
| `ai-tokens export [dir]` | Exporte le contexte optimisé |

Alias: `ait` (raccourci pour ai-tokens)
