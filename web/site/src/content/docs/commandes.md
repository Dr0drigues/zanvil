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
| `zanvil-dotfiles [sous-commande]` | Dépôt dotfiles : Brewfiles et liens Stow (voir ci-dessous) |
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

## Dotfiles

`zanvil-dotfiles` gère le dépôt dotfiles (`ZANVIL_DOTFILES_DIR`, défaut `~/.dotfiles`) pour le profil `ZANVIL_PROFILE`.

| Sous-commande | Description |
|---------------|-------------|
| `status` (défaut) | Profil, dépôt, état et Brewfiles utilisés |
| `pull` | Met à jour le dépôt (fast-forward uniquement), ou le clone depuis `ZANVIL_DOTFILES_REPO` s'il est absent |
| `install` | Installe ce qui manque (base + `common` + profil), sans mettre à jour le reste |
| `cleanup` | Liste les formules, casks et taps que `brew` retirerait, puis demande confirmation |
| `link` | Relie `stow/common` et `stow/<profil>` dans `$HOME` (un dossier absent est ignoré) |
| `adopt <chemin> [couche]` | Déplace un fichier réel de `$HOME` dans le dépôt (`common` par défaut) et le relie |
| `apply` | Commande quotidienne : `pull`, `install`, `link`, puis `cleanup` (arrêt à la première erreur) |
| `migrate` | Applique le dépôt sur une machine déjà configurée, sans réinstaller ni perdre de config (voir ci-dessous) |

- `install` approuve (`brew trust`) les paquets de taps tiers nommés dans les Brewfile (`brew "tap/depot/nom"`, `cask "tap/depot/nom"`) avant `brew bundle install`, faute de quoi Homebrew 7 les refuse. Seules les entrées nommées sont approuvées, jamais le tap entier. `cleanup` fait de même avant d'appeler brew.
- **Déclarer les approbations dans le Brewfile** avec l'option native de Homebrew : `brew "tap/depot/nom", trusted: true` (idem pour `cask`). `brew bundle cleanup --force` remet en effet les approbations de Homebrew aux seules valeurs déclarées dans le Brewfile : sans `trusted:`, chaque nettoyage retire l'approbation, et `brew upgrade` refuse ensuite ces paquets. `cleanup` signale avant sa question les entrées concernées. Une **dépendance venant du même tap tiers** (par exemple `mongodb/brew/mongodb-database-tools` pour `mongodb-community`) doit être nommée elle aussi avec `trusted: true` : l'option `trusted:` posée sur une ligne `tap` n'est pas appliquée avant que brew résolve les dépendances.
- `cleanup` affiche la liste, puis ne supprime qu'après une réponse explicite `o`, `oui`, `y` ou `yes`. Toute autre réponse, ou une entrée qui n'est pas un terminal, n'efface rien. Le nettoyage se limite à brew : extensions VSCode, paquets npm, outils uv ou cargo ne sont jamais touchés.
- `link` utilise Stow avec `--no-folding` : les dossiers restent réels, seuls les fichiers sont des liens. En cas de conflit (un fichier réel à la place d'un lien), il affiche les conflits et s'arrête sans rien écraser. Lancer alors `adopt` sur ce fichier, puis `link`.
- `adopt` refuse si le dépôt contient déjà une autre version du fichier (comparer avec `diff`), et refuse les secrets et ce que gère `install.sh` : `gh/hosts.yml`, `glab-cli`, `sops`, `gcloud`, `~/.ssh/*` et `~/.zshrc`.

```bash
zanvil-dotfiles adopt .config/lazygit/config.yml
zanvil-dotfiles link
```

### Migrer une machine déjà configurée

`zanvil-dotfiles migrate` amène une machine installée à la main dans l'état décrit par le dépôt. Elle est interactive et refuse de tourner hors d'un terminal. Étapes :

1. **Profil et dépôt** : demande le profil (`pro` ou `perso`) et l'URL du dépôt s'ils ne sont pas déjà définis, clone ou met à jour le dépôt (le pull est sauté si le dépôt a des modifications non commitées). Dans `config.zsh`, seules les clés absentes parmi `ZANVIL_PROFILE`, `ZANVIL_DOTFILES_REPO`, `ZANVIL_DOTFILES_DIR` et `ZANVIL_WORK_DETECTED` sont ajoutées (une clé présente mais vide, comme `ZANVIL_DOTFILES_REPO=""`, compte comme absente et sa ligne est remplacée sur place) ; le reste du fichier n'est pas touché. Si le pull échoue (par exemple un commit local non poussé alors que le dépôt distant a bougé), pousser ou rebaser dans le dépôt, puis relancer.
2. **Paquets de taps tiers** : approuvés comme pour `install`. Juste avant, `migrate` demande le mot de passe administrateur **une seule fois** (`sudo -v`) et garde le jeton actif jusqu'à la fin : brew en a besoin pour adopter certaines applis et pour les installeurs `.pkg`, et le jeton expirerait pendant les téléchargements. Si sudo est refusé, brew redemandera au besoin.
3. **Applis installées à la main** : les casks des Brewfile dont l'application est déjà dans `/Applications` sont proposés pour `brew install --cask --adopt`, après confirmation. Un échec est signalé avec la commande à lancer à la main.
4. **Installation** de ce qui manque (`install`). Si `brew bundle` échoue (conflit de liens entre deux formules, installeur `.pkg` en erreur…), `migrate` s'arrête : corriger d'après le message de brew, puis relancer, ce qui est déjà fait n'est pas redemandé. Homebrew adopte de lui-même une appli déjà présente : un cask refusé à l'étape 3, ou dont l'adoption a échoué, est donc retiré de la liste donnée à `brew bundle` et rappelé dans le récapitulatif avec la commande manuelle.
5. **Configs en conflit** : un fichier de `$HOME` identique à celui du dépôt est simplement mis de côté. Sinon, le `diff` est affiché et l'outil demande :
   - `d` : garder la version du dépôt (la version locale est sauvegardée) ;
   - `l` : garder la version locale, qui est commitée dans le dépôt **en local seulement** (jamais de push), puis sauvegardée ;
   - `p` (défaut) : passer ; le fichier reste en place et la question revient à la prochaine relance.
6. **Liens** (`link`, simulation puis application). Les fichiers passés sont laissés de côté, le reste est lié ; les fichiers en attente sont nommés et une relance de `migrate` les traite. Avec un `.stow-local-ignore` ou un `~/.stow-global-ignore`, migrate ne sait pas interpréter les règles : le paquet n'est pas lié, à faire à la main avec `link`. Si les liens échouent, le chemin de la sauvegarde est affiché.
7. **Simulation du nettoyage** : affiche ce que `cleanup` retirerait. **`migrate` ne désinstalle jamais rien** ; s'il y a quelque chose à retirer, lancer ensuite `zanvil-dotfiles cleanup`.
8. **Récapitulatif** : profil, dépôt, paquets approuvés, applis passées sous brew (échecs et casks laissés hors de `brew bundle`), configs liées, sauvegardées et passées, chemin de la sauvegarde, rappel `git -C <dépôt> push` s'il y a des commits locaux.

Tout fichier retiré de `$HOME` est **déplacé** dans `~/.zanvil-backup/<AAAAMMJJ-HHMMSS>/`, avec son chemin relatif, jamais supprimé. Une relance ne repose de question que pour ce qui n'est pas encore en ordre. Après une mise à jour de zanvil, si aucun profil n'est défini, une ligne propose `migrate` (une seule fois).

## CLI Rust (zanvil)

| Commande | Description |
|----------|-------------|
| `zanvil theme` | Gestion des thèmes (list, apply, preview) |
| `zanvil doctor` | Diagnostic complet en Rust (rapide) |
| `zanvil audit` | Audit de sécurité avancé |
| `zanvil context` | Génération de contexte projet |
| `zanvil modules` | Gestion des modules (list, enable, disable) |

## Project

| Commande | Description |
|----------|-------------|
| `project open <lien-de-MR>` | Ouvre la MR dans un worktree sous `$WORK_DIR`, puis dans Orca et IntelliJ IDEA |
| `project clean` | Supprime les worktrees des MR terminées |

Le worktree se range sous le sous-groupe GitLab, dans un dossier `.worktrees` :
`$WORK_DIR/group/sub/.worktrees/repo/<branche>`. Le dépôt principal (`$WORK_DIR/group/sub/repo`) est cloné
au besoin et jamais modifié. Un `.zanvil.local` présent à la racine du dépôt est copié dans le worktree.

```bash
project open https://gitlab.example.com/group/sub/repo/-/merge_requests/42
project clean
```

Le ménage tourne aussi tout seul, en arrière-plan, au plus une fois par 24 h au démarrage du shell : il
retire les worktrees dont la MR est fermée ou fusionnée, sans travail local non poussé. Le résultat
arrive en notification. Pour ouvrir la MR copiée d'un raccourci clavier, voir
[Ouvrir une MR](/zanvil/bureau-macos/#ouvrir-une-mr).

## GitLab

| Commande | Description |
|----------|-------------|
| `zanvil-gitlab-status` | Affiche le statut des pipelines GitLab |
| `zanvil-gitlab-browse` | Ouvre le projet GitLab dans le navigateur |
| `gpr` | Alias pour créer une merge request GitLab |
| `clone-projects [--dry-run] [--parallel]` | Clone en masse des projets GitLab |
| `gclone <clé\|group-id>` | Clone un groupe GitLab depuis `$WORK_DIR` et s'y positionne |
| `git-bulk [--dry-run]` | Opérations Git en masse sur plusieurs repos |

## Navigation

| Commande | Description |
|----------|-------------|
| `z <pattern>` | Jump intelligent (zoxide) |
| `gr` | Va à la racine du repo git |
| `mkcd <dir>` | Crée un dossier et y entre |

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
| `kube_k9s_setup` | Déploie hotkeys, skin et plugins k9s depuis le dépôt |
| `klog [pod] [ctn]` | Logs d'un pod, sélection fzf — suivi continu par défaut, JSON brut |

`klog` accepte `--no-follow`, `-p` pour le conteneur précédent après un crash, `-n` pour le namespace,
`--tail N` (100 par défaut), `-g` pour filtrer par expression régulière, `-A` pour tous les pods du même
label `app=`, et `-t` pour les horodatages `kubectl`. Il affiche le JSON tel quel : le rendu formaté est
du ressort des plugins k9s.

Les trois plugins de logs k9s — `Shift-L`, `Ctrl-L` et `Ctrl-R` — ont leur propre page :
[Kubernetes et k9s](/zanvil/kubernetes-k9s/).

## SSH

| Commande | Description |
|----------|-------------|
| `ssh_select` | Sélection interactive des hosts |
| `ssh_list` | Liste les hosts configurés |
| `ssh_add` | Ajoute un host interactivement |
| `ssh_remove [host]` | Supprime un host |
| `ssh_test <host>` | Teste la connexion |

## Outils tiers

Chaque module d'outil déploie la configuration versionnée du dépôt vers le `$HOME` de la machine. Le
module ne fait rien si son binaire est absent : il affiche la commande `brew install` correspondante.

| Commande | Description |
|----------|-------------|
| `delta_setup` | Écrit `~/.gitconfig.d/delta` et ajoute l'`[include]` dans `~/.gitconfig` |
| `lazygit_setup` | Affiche la configuration active (`LG_CONFIG_FILE`) et l'état de `config-local.yml` |
| `atuin_setup` | Déploie `~/.config/atuin/config.toml` et affiche le chemin de la base |
| `posting_setup` | Déploie `~/.config/posting/config.yaml` |
| `lg` | Lance lazygit en suivant le changement de répertoire à la sortie |
| `po` | Alias de `posting` |

## Elasticsearch (module work)

Interrogation de l'Elasticsearch interne. `ES_USER` et `ES_PASSWORD` sont attendus dans
l'environnement — voir `env.d/` et le chiffrement sops.

| Commande | Description |
|----------|-------------|
| `work_es_apps [plage]` | Applications par volume sur la plage (défaut `24h`), avec cache d'une heure |
| `work_es_count <app>` | Compte les événements, avec la fenêtre temporelle observée |
| `work_es_tail <app>` | Derniers événements d'une application |
| `work_es_query [METHODE] <chemin>` | Requête brute, corps sur `stdin` avec `-` |
| `work_fetch_logs` | Récupère les logs d'une application vers un fichier |

Les plages s'écrivent `Xs`, `Xm`, `Xh` ou `Xd`. `work_es_apps --refresh` ignore le cache.

## API produits merch (module work)

Recherche un produit par l'un de quatre identifiants. Les hôtes et les clés sont attendus
dans l'environnement — voir `examples/env.d/work.zsh` ; les clés vont dans `~/.secrets` ou
sous sops, jamais dans un fichier versionné.

| Commande | Description |
|----------|-------------|
| `work_merch_product <critère>` | Interroge l'API produits ; `get_merch_product` est le même |

Un seul critère à la fois, l'API n'en accepte pas davantage : `-e/--ean`, `-o/--offerId`,
`-s/--sapId`, `-p/--pimId`. L'environnement se choisit avec `--prod` (défaut) ou `--qlf`.
La sortie est indentée par `jq` sur un terminal et brute dans un pipe, donc composable :

```bash
get_merch_product -e 3660000000000
get_merch_product --offerId 12345 --qlf
get_merch_product -s 987654 | jq '.products[0].label'
```

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
