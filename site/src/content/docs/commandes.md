---
title: Référence des commandes
description: Toutes les commandes zanvil (zanvil-*) et le CLI Rust
---

## Commandes zanvil

| Commande | Description |
|----------|-------------|
| `zanvil-list` | Liste les outils installés avec versions (format tableau) |
| `zanvil-doctor` | Diagnostic complet de l'installation (compact) |
| `zanvil-status` | Statut rapide (version, modules, git) |
| `zanvil-profile` | Profile le temps de démarrage par module |
| `zanvil-benchmark [n]` | Benchmark sur n exécutions (défaut: 5) |
| `zanvil-audit` | Audit de sécurité des permissions (compact) |
| `zanvil-audit-fix` | Corrige automatiquement les permissions |
| `zanvil-theme [nom]` | Gère les thèmes unifiés (Starship + palette) |
| `zanvil-ghostty [nom\|sync]` | Gère les thèmes Ghostty |
| `zanvil-completions` | Charge les auto-complétions |
| `zanvil-completion-add` | Ajoute une complétion personnalisée |
| `zanvil-completion-remove` | Supprime une complétion personnalisée |
| `zanvil-update` | Force la mise à jour |
| `zanvil-help` | Affiche l'aide (format tableau) |
| `zanvil-modules list` | Liste les modules disponibles et leur statut |
| `zanvil-modules enable <nom>` | Active un module |
| `zanvil-modules disable <nom>` | Désactive un module |
| `zanvil-backup` | Sauvegarde la configuration zanvil |
| `zanvil-restore` | Restaure une sauvegarde |
| `zanvil-switch <profil>` | Change de profil d'environnement |
| `zanvil-config-reset` | Réinitialise la configuration |

Toutes les commandes `zanvil-*` utilisent un style visuel moderne et compact via le système UI.

## CLI Rust (zanvil)

| Commande | Description |
|----------|-------------|
| `zanvil theme` | Gestion des thèmes (list, apply, preview) |
| `zanvil doctor` | Diagnostic complet en Rust (rapide) |
| `zanvil audit` | Audit de sécurité avancé |
| `zanvil context` | Génération de contexte projet |
| `zanvil modules` | Gestion des modules (list, enable, disable) |

## GitLab

| Commande | Description |
|----------|-------------|
| `zanvil-gitlab-status` | Affiche le statut des pipelines GitLab |
| `zanvil-gitlab-browse` | Ouvre le projet GitLab dans le navigateur |
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
