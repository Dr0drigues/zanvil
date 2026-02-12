# Tests ShellSpec - Checklist

> Genere apres revue de code complete (v1.3.0+)
> Tiers: T1 = unit (pas de deps externes), T2 = integration (git/fichiers), T3 = mock necessaire

---

## Installation

- [ ] `install.sh` s'execute sans erreur (mode --default)
- [ ] `install.sh` cree le fichier `config.zsh`
- [ ] `install.sh` modifie le `.zshrc` avec ZSH_ENV_DIR
- [ ] `install.sh` utilise `--proto '=https' --tlsv1.2` pour les telecharges
- [ ] `uninstall.sh` restaure le `.zshrc`

## Chargement (rc.zsh)

- [x] T1: `rc.zsh` se source sans erreur
- [x] T1: Les modules desactives ne sont pas charges (`ZSH_ENV_MODULE_*=false`)
- [x] T1: Les fichiers manquants affichent un warning sur stderr
- [x] T1: `config.zsh` est source si present
- [ ] T1: `~/.secrets` est source si present
- [x] T1: `SCRIPTS_DIR` est ajoute au PATH
- [x] T1: PATH est deduplique (`typeset -U PATH`)

## Variables (variables.zsh)

- [x] T1: `$WORK_DIR` est exporte
- [x] T1: `$SCRIPTS_DIR` est exporte
- [x] T1: `$HISTFILE` vaut `~/.zsh_history`
- [x] T1: `$HISTSIZE` vaut 50000
- [x] T1: `$SAVEHIST` vaut 50000
- [x] T1: `$SOPS_AGE_KEY_FILE` est exporte
- [x] T2: Les dossiers requis sont crees si manquants
- [ ] T2: `mkdir` echoue gracieusement (message stderr, pas de crash)

## Lazy Loading (functions.zsh)

- [x] T1: Les fichiers non-lazy dans `functions/` sont sources
- [x] T1: `ai_context.zsh` et `ai_tokens.zsh` ne sont PAS sources au chargement
- [x] T1: Le stub `ai-context` est defini comme fonction
- [x] T1: Le stub `ai-tokens` est defini comme fonction
- [ ] T2: Appeler `ai-context help` charge le vrai fichier et execute la commande
- [ ] T2: Appeler `ai-tokens help` charge le vrai fichier et execute la commande
- [ ] T2: Les stubs sont supprimes apres le premier appel
- [ ] T2: Les arguments sont transmis correctement a la fonction chargee

## NVM

- [ ] T3: Lazy loading : `node` charge NVM au premier appel
- [ ] T3: Lazy loading : `npm` charge NVM au premier appel
- [ ] T3: Mode normal : NVM charge au demarrage si `ZSH_ENV_NVM_LAZY=false`
- [x] T3: Auto-switch : detection du `.nvmrc` via hook `chpwd`

## Aliases (aliases.zsh)

- [x] T1: `gst` est alias de `git status`
- [x] T1: `gl` est alias de `git fetch --all; git pull`
- [x] T1: `gld` est alias de `git log --oneline --decorate --graph --all`
- [x] T1: `ls` utilise `eza` si disponible
- [x] T1: `ls` fonctionne sans `eza`
- [x] T1: `cat` est alias de `bat` si disponible
- [x] T1: `npmi` est alias de `npm install`
- [ ] T2: `git-clean-branches` liste les branches mergees
- [x] T1: `git-clean-branches` exclut master/main/dev/develop/release/*
- [x] T1: `git-clean-branches` retourne 0 si aucune branche a supprimer
- [x] T1: `nci` utilise `/bin/rm` et non `rmi`
- [x] T1: `rm` utilise `trash` en mode interactif (si disponible)
- [ ] T1: `rm` utilise le vrai `rm` en mode non-interactif

## Commandes zsh-env-*

- [x] T1: `zsh-env-list` affiche les outils installes avec version
- [x] T1: `zsh-env-list` marque les outils manquants
- [ ] T1: `zsh-env-doctor` retourne 0 si tout est OK
- [x] T1: `zsh-env-help` affiche l'aide
- [ ] T2: `zsh-env-theme list` liste les themes Starship
- [ ] T2: `zsh-env-theme <nom>` applique un theme
- [x] T1: `zsh-env-status` affiche la configuration et les modules

## Completions

- [x] T1: `zsh-env-completion-add` requiert nom et commande
- [x] T2: `zsh-env-completion-add` ajoute une entree dans `completions.zsh`
- [x] T2: `zsh-env-completion-remove` supprime une entree
- [x] T2: `zsh-env-completion-remove` echoue si entree non trouvee

## Fonctions utilitaires (utils.zsh)

- [x] T2: `mkcd` cree un dossier et y entre
- [x] T2: `mkcd` cree des dossiers imbriques
- [x] T1: `bak` requiert un argument
- [x] T2: `bak` cree une copie `.bak.TIMESTAMP`
- [x] T1: `cx` requiert un argument
- [x] T1: `cx` echoue si le fichier n'existe pas
- [x] T2: `cx` rend un fichier executable
- [x] T1: `trash` retourne 1 si aucune commande trash disponible

## Extract (extract.zsh)

- [x] T2: `extract` decompresse `.tar.gz`
- [x] T2: `extract` decompresse `.zip`
- [x] T2: `extract` decompresse `.tar.bz2`
- [x] T2: `extract` decompresse `.tar.xz`
- [x] T2: `extract` decompresse `.gz`
- [x] T1: `extract` echoue sur un format non supporte
- [x] T1: `extract` echoue sur un fichier inexistant

## Git Root (git_root.zsh)

- [x] T2: `gr` navigue a la racine du depot Git
- [x] T1: `gr` affiche une erreur hors d'un depot Git

## Git Change Author (git_change_author.zsh)

- [x] T1: `gc-author` requiert 3 arguments minimum
- [x] T1: `gc-author` affiche l'usage sans arguments
- [x] T1: `gc-author` utilise `HEAD~10..HEAD` comme plage par defaut
- [x] T1: `gc-author` accepte une plage personnalisee en 4eme argument
- [x] T3: `gc-author` prefere `git-filter-repo` si disponible
- [x] T3: `gc-author` cree un tag de backup avant reecriture

## Git Hooks (git_hooks.zsh)

- [x] T2: `hooks_list` echoue hors d'un depot Git
- [x] T2: `hooks_install_precommit` cree le fichier pre-commit
- [x] T2: `hooks_install_precommit` rend le hook executable

## Security Audit (security_audit.zsh)

- [x] T2: `zsh-env-audit` verifie les permissions de `~/.ssh` (700)
- [x] T2: `zsh-env-audit` verifie les permissions des cles privees (600/400)
- [x] T2: `zsh-env-audit` verifie `~/.ssh/config` (600)
- [x] T2: `zsh-env-audit` verifie `~/.secrets` (600)
- [x] T2: `zsh-env-audit` verifie `~/.kube` (700)
- [x] T2: `zsh-env-audit` detecte des credentials dans l'historique
- [x] T2: `zsh-env-audit` retourne le nombre d'issues
- [x] T2: `zsh-env-audit-fix` corrige les permissions SSH
- [x] T2: `zsh-env-audit-fix` corrige les permissions secrets

## SSH Manager (ssh_manager.zsh)

- [x] T2: `_ssh_list_hosts` parse le fichier ssh config
- [x] T2: `_ssh_list_hosts` ignore les wildcards (`*`, `?`)
- [x] T2: `_ssh_list_hosts` retourne les hosts tries
- [x] T2: `_ssh_get_host_info` extrait la configuration d'un host
- [x] T1: `ssh_select` echoue sans fichier config
- [x] T2: `ssh_select` filtre par pattern
- [x] T2: `ssh_list` affiche HostName et User
- [x] T2: `ssh_list` compte le total
- [x] T1: `ssh_info` requiert un argument
- [x] T2: `ssh_info` echoue pour un host inconnu
- [x] T2: `ssh_add` detecte les doublons
- [x] T2: `ssh_add` cree le fichier config si manquant (permissions 600)
- [ ] T2: `ssh_add` ajoute l'entree au bon format (interactif)
- [x] T2: `ssh_remove` cree un backup avant suppression
- [x] T1: `ssh_copy_key` echoue si la cle n'existe pas

## Tmux Manager (tmux_manager.zsh)

- [x] T3: `tm` cree une session "main" si aucune n'existe
- [x] T3: `tm` s'attache a une session existante
- [x] T3: `tm-list` affiche les sessions actives
- [x] T3: `tm-kill` echoue pour une session inconnue
- [x] T3: `tm-rename` echoue hors de tmux
- [x] T3: `tm-project` cree la session avec 3 fenetres (edit/term/git)
- [x] T3: `tm-project` echoue si le dossier n'existe pas

## Test Runner (test_runner.zsh)

- [x] T1: `trun` echoue sans `package.json`
- [x] T2: `trun` detecte jest dans package.json
- [x] T2: `trun` detecte vitest dans package.json
- [x] T2: `trun` detecte mocha dans package.json
- [x] T1: `trun -c` inclut le flag coverage
- [x] T1: `trun -v` active le mode verbose

## Project Switcher (project_switcher.zsh)

- [x] T2: `_proj_find_config` detecte `.proj`
- [x] T2: `_proj_find_config` detecte `.project.yml`
- [x] T2: `_proj_find_config` detecte `.project.yaml`
- [x] T1: `_proj_find_config` retourne 1 si aucun fichier trouve
- [x] T1: `_proj_get_value` parse une cle YAML simple
- [x] T1: `_proj_get_value` supprime les guillemets
- [x] T2: `_proj_load_by_path` change le repertoire courant
- [x] T2: `_proj_load_by_path` verifie le proprietaire du fichier env ($UID)
- [ ] T2: `_proj_load_by_path` refuse un fichier env avec mauvais proprietaire
- [x] T1: `_proj_load_by_path` ignore post_cmd en mode non-interactif
- [x] T2: `proj_add` cree le fichier registre
- [x] T2: `proj_add` detecte les chemins dupliques
- [x] T2: `proj_add` detecte les noms dupliques
- [x] T2: `proj_list` affiche les projets enregistres
- [x] T2: `proj_list` marque les dossiers manquants
- [x] T2: `proj_remove` supprime l'entree du registre
- [x] T2: `proj_init` cree un fichier `.proj` template
- [x] T1: `proj_init` echoue si `.proj` existe deja
- [x] T2: `proj_scan` detecte les dossiers `.git`
- [x] T2: `proj_scan` detecte `package.json`, `Cargo.toml`, `go.mod`
- [x] T2: `proj_scan` respecte la limite de profondeur

## Plugins (plugins.zsh)

- [x] T1: `plugins.zsh` se source sans erreur
- [x] T1: `ZSH_ENV_PLUGINS=()` vide ne cause pas d'erreur
- [x] T1: `_zsh_env_plugin_name` extrait le nom depuis `owner/repo`
- [x] T1: `_zsh_env_plugin_name` extrait le nom depuis une URL complete
- [x] T1: `_zsh_env_plugin_url` genere l'URL GitHub depuis `owner/repo`
- [x] T1: `_zsh_env_plugin_url` prefixe avec `ZSH_ENV_PLUGINS_ORG` si pas de `/`
- [x] T1: `_zsh_env_plugin_url` retourne l'URL telle quelle si `https://`
- [x] T2: `_zsh_env_find_plugin_file` detecte `*.plugin.zsh`
- [x] T2: `_zsh_env_find_plugin_file` detecte `init.zsh`
- [x] T2: `_zsh_env_find_plugin_file` detecte `<nom>.zsh`
- [x] T1: `zsh-plugin-install` sans argument affiche l'usage
- [x] T1: `zsh-plugin-remove` sans argument affiche l'usage

## Docker (docker_utils.zsh)

- [x] T1: Module skip si `ZSH_ENV_MODULE_DOCKER != true`
- [x] T3: `dex` echoue si Docker n'est pas lance
- [x] T3: `dstop` retourne 0 si aucun conteneur
- [x] T3: `dstop` affiche le nombre de conteneurs
- [x] T3: `dstop` echoue si Docker n'est pas lance

## Kube Config (kube_config.zsh)

- [x] T3: `kube_init` cree `~/.kube` et `~/.kube/configs.d`
- [x] T3: `kube_select` liste les configs disponibles
- [x] T3: `kube_status` affiche le KUBECONFIG actif
- [x] T3: `kube_add` valide l'existence du fichier
- [x] T3: `kube_add` detecte les doublons
- [x] T3: `kube_reset` vide les configs chargees

## Auto-Update (auto_update.zsh)

- [x] T1: `_zsh_env_should_check_update` retourne 0 si frequence = 0
- [x] T1: `_zsh_env_should_check_update` retourne 0 si fichier timestamp absent
- [x] T1: `_zsh_env_should_check_update` retourne 0 apres N jours
- [x] T1: `_zsh_env_should_check_update` retourne 1 si check recent
- [ ] T2: `_zsh_env_check_update` compare HEAD vs origin/main
- [x] T1: `zsh-env-status` affiche la version et les modules

## Work Context (work_context.zsh)

- [x] T1: `_blg_cache_valid` retourne 1 si pas de fichier cache
- [x] T2: `_blg_cache_valid` retourne 0 si age < TTL
- [x] T2: `_blg_cache_valid` retourne 1 si age > TTL
- [x] T2: `_blg_cache_write` ecrit timestamp + valeur
- [x] T1: Cache TTL est configurable via `ZSH_ENV_WORK_CACHE_TTL`
- [x] T1: Timeout est configurable via `ZSH_ENV_WORK_TIMEOUT`
- [x] T3: `_blg_test_nexus` utilise curl avec timeout
- [x] T3: `work_is_context` utilise le cache si valide
- [x] T2: `blg_refresh` supprime le fichier cache

## Net Utils (net_utils.zsh)

- [x] T1: `port` requiert 2 arguments (host et port)
- [x] T3: `myip` utilise curl avec `--max-time 5`
- [x] T3: `myip` gere le timeout gracieusement

## GitLab Logic (gitlab_logic.zsh)

- [x] T1: Module skip si `ZSH_ENV_MODULE_GITLAB != true`
- [x] T1: Warning si `~/.gitlab_secrets` n'existe pas

## Check Env Deps (check_env_deps.zsh)

- [x] T1: `check_env_health` verifie les outils core
- [x] T1: `check_env_health` marque les outils manquants
- [x] T1: `check_env_health` fournit la commande brew install

## Scripts GitLab

- [x] T1: `trigger-jobs.sh --help` affiche l'aide (exit 0)
- [x] T1: `trigger-jobs.sh` echoue sans GITLAB_TOKEN (exit 1)
- [x] T1: `trigger-jobs.sh` echoue sans argument -j (exit 1)
- [x] T1: `trigger-jobs.sh` echoue sans cible (-p/-P/-g) (exit 1)
- [x] T1: `clone-projects.sh --help` affiche l'aide (exit 0)
- [x] T1: `clone-projects.sh` echoue avec moins de 2 arguments (exit 1)

---

## Statistiques

| Tier | Description | Total | Implementes | Restants |
|------|-------------|-------|-------------|----------|
| T1 | Unit tests (pas de deps) | ~85 | **73** | ~12 |
| T2 | Integration (git/fichiers) | ~75 | **58** | ~17 |
| T3 | Mocks necessaires | ~30 | **46** | ~0 |
| **Total** | | **~190** | **177** | **~29** |

## Priorite d'implementation (restant)

1. **T1 restants** - rm non-interactif, secrets source, doctor
2. **T2 restants** - mkdir erreur, theme list/apply, auto-update compare, ssh_add format, env mauvais proprio, lazy-loading stubs
3. **T3 restants** - NVM lazy loading (node/npm/lazy=false)
