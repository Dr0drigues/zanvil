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

- [ ] T1: `rc.zsh` se source sans erreur
- [ ] T1: Les modules desactives ne sont pas charges (`ZSH_ENV_MODULE_*=false`)
- [ ] T1: Les fichiers manquants affichent un warning sur stderr
- [ ] T1: `config.zsh` est source si present
- [ ] T1: `~/.secrets` est source si present
- [ ] T1: `SCRIPTS_DIR` est ajoute au PATH
- [ ] T1: PATH est deduplique (`typeset -U PATH`)

## Variables (variables.zsh)

- [ ] T1: `$WORK_DIR` est exporte
- [ ] T1: `$SCRIPTS_DIR` est exporte
- [ ] T1: `$HISTFILE` vaut `~/.zsh_history`
- [ ] T1: `$HISTSIZE` vaut 50000
- [ ] T1: `$SAVEHIST` vaut 50000
- [ ] T1: `$SOPS_AGE_KEY_FILE` est exporte
- [ ] T2: Les dossiers requis sont crees si manquants
- [ ] T2: `mkdir` echoue gracieusement (message stderr, pas de crash)

## Lazy Loading (functions.zsh)

- [ ] T1: Les fichiers non-lazy dans `functions/` sont sources
- [ ] T1: `ai_context.zsh` et `ai_tokens.zsh` ne sont PAS sources au chargement
- [ ] T1: Le stub `ai-context` est defini comme fonction
- [ ] T1: Le stub `ai-tokens` est defini comme fonction
- [ ] T2: Appeler `ai-context help` charge le vrai fichier et execute la commande
- [ ] T2: Appeler `ai-tokens help` charge le vrai fichier et execute la commande
- [ ] T2: Les stubs sont supprimes apres le premier appel
- [ ] T2: Les arguments sont transmis correctement a la fonction chargee

## NVM

- [ ] T3: Lazy loading : `node` charge NVM au premier appel
- [ ] T3: Lazy loading : `npm` charge NVM au premier appel
- [ ] T3: Mode normal : NVM charge au demarrage si `ZSH_ENV_NVM_LAZY=false`
- [ ] T3: Auto-switch : detection du `.nvmrc` via hook `chpwd`

## Aliases (aliases.zsh)

- [ ] T1: `gst` est alias de `git status`
- [ ] T1: `gl` est alias de `git fetch --all; git pull`
- [ ] T1: `gld` est alias de `git log --oneline --decorate --graph --all`
- [ ] T1: `ls` utilise `eza` si disponible
- [ ] T1: `ls` fonctionne sans `eza`
- [ ] T1: `cat` est alias de `bat` si disponible
- [ ] T1: `npmi` est alias de `npm install`
- [ ] T2: `git-clean-branches` liste les branches mergees
- [ ] T2: `git-clean-branches` exclut master/main/dev/develop/release/*
- [ ] T2: `git-clean-branches` retourne 0 si aucune branche a supprimer
- [ ] T1: `nci` utilise `/bin/rm` et non `rmi`
- [ ] T1: `rm` utilise `trash` en mode interactif (si disponible)
- [ ] T1: `rm` utilise le vrai `rm` en mode non-interactif

## Commandes zsh-env-*

- [ ] T1: `zsh-env-list` affiche les outils installes avec version
- [ ] T1: `zsh-env-list` marque les outils manquants
- [ ] T1: `zsh-env-doctor` retourne 0 si tout est OK
- [ ] T1: `zsh-env-help` affiche l'aide
- [ ] T2: `zsh-env-theme list` liste les themes Starship
- [ ] T2: `zsh-env-theme <nom>` applique un theme
- [ ] T1: `zsh-env-status` affiche la configuration et les modules

## Completions

- [ ] T1: `zsh-env-completion-add` requiert nom et commande
- [ ] T2: `zsh-env-completion-add` ajoute une entree dans `completions.zsh`
- [ ] T2: `zsh-env-completion-remove` supprime une entree
- [ ] T2: `zsh-env-completion-remove` echoue si entree non trouvee

## Fonctions utilitaires (utils.zsh)

- [ ] T2: `mkcd` cree un dossier et y entre
- [ ] T2: `mkcd` cree des dossiers imbriques
- [ ] T1: `bak` requiert un argument
- [ ] T2: `bak` cree une copie `.bak.TIMESTAMP`
- [ ] T1: `cx` requiert un argument
- [ ] T1: `cx` echoue si le fichier n'existe pas
- [ ] T2: `cx` rend un fichier executable
- [ ] T1: `trash` retourne 1 si aucune commande trash disponible

## Extract (extract.zsh)

- [ ] T2: `extract` decompresse `.tar.gz`
- [ ] T2: `extract` decompresse `.zip`
- [ ] T2: `extract` decompresse `.tar.bz2`
- [ ] T2: `extract` decompresse `.tar.xz`
- [ ] T2: `extract` decompresse `.gz`
- [ ] T1: `extract` echoue sur un format non supporte
- [ ] T1: `extract` echoue sur un fichier inexistant

## Git Root (git_root.zsh)

- [ ] T2: `gr` navigue a la racine du depot Git
- [ ] T1: `gr` affiche une erreur hors d'un depot Git

## Git Change Author (git_change_author.zsh)

- [ ] T1: `gc-author` requiert 3 arguments minimum
- [ ] T1: `gc-author` affiche l'usage sans arguments
- [ ] T1: `gc-author` utilise `HEAD~10..HEAD` comme plage par defaut
- [ ] T1: `gc-author` accepte une plage personnalisee en 4eme argument
- [ ] T3: `gc-author` prefere `git-filter-repo` si disponible
- [ ] T3: `gc-author` cree un tag de backup avant reecriture

## Git Hooks (git_hooks.zsh)

- [ ] T2: `hooks_list` echoue hors d'un depot Git
- [ ] T2: `hooks_install_precommit` cree le fichier pre-commit
- [ ] T2: `hooks_install_precommit` rend le hook executable

## Security Audit (security_audit.zsh)

- [ ] T2: `zsh-env-audit` verifie les permissions de `~/.ssh` (700)
- [ ] T2: `zsh-env-audit` verifie les permissions des cles privees (600/400)
- [ ] T2: `zsh-env-audit` verifie `~/.ssh/config` (600)
- [ ] T2: `zsh-env-audit` verifie `~/.secrets` (600)
- [ ] T2: `zsh-env-audit` verifie `~/.kube` (700)
- [ ] T2: `zsh-env-audit` detecte des credentials dans l'historique
- [ ] T2: `zsh-env-audit` retourne le nombre d'issues
- [ ] T2: `zsh-env-audit-fix` corrige les permissions SSH
- [ ] T2: `zsh-env-audit-fix` corrige les permissions secrets

## SSH Manager (ssh_manager.zsh)

- [ ] T2: `_ssh_list_hosts` parse le fichier ssh config
- [ ] T2: `_ssh_list_hosts` ignore les wildcards (`*`, `?`)
- [ ] T2: `_ssh_list_hosts` retourne les hosts tries
- [ ] T2: `_ssh_get_host_info` extrait la configuration d'un host
- [ ] T1: `ssh_select` echoue sans fichier config
- [ ] T2: `ssh_select` filtre par pattern
- [ ] T2: `ssh_list` affiche HostName et User
- [ ] T2: `ssh_list` compte le total
- [ ] T1: `ssh_info` requiert un argument
- [ ] T2: `ssh_info` echoue pour un host inconnu
- [ ] T2: `ssh_add` detecte les doublons
- [ ] T2: `ssh_add` cree le fichier config si manquant (permissions 600)
- [ ] T2: `ssh_add` ajoute l'entree au bon format
- [ ] T2: `ssh_remove` cree un backup avant suppression
- [ ] T1: `ssh_copy_key` echoue si la cle n'existe pas

## Tmux Manager (tmux_manager.zsh)

- [ ] T3: `tm` cree une session "main" si aucune n'existe
- [ ] T3: `tm` s'attache a une session existante
- [ ] T3: `tm-list` affiche les sessions actives
- [ ] T3: `tm-kill` echoue pour une session inconnue
- [ ] T3: `tm-rename` echoue hors de tmux
- [ ] T3: `tm-project` cree la session avec 3 fenetres (edit/term/git)
- [ ] T3: `tm-project` echoue si le dossier n'existe pas

## Test Runner (test_runner.zsh)

- [ ] T1: `trun` echoue sans `package.json`
- [ ] T2: `trun` detecte jest dans package.json
- [ ] T2: `trun` detecte vitest dans package.json
- [ ] T2: `trun` detecte mocha dans package.json
- [ ] T1: `trun -c` inclut le flag coverage
- [ ] T1: `trun -v` active le mode verbose

## Project Switcher (project_switcher.zsh)

- [ ] T2: `_proj_find_config` detecte `.proj`
- [ ] T2: `_proj_find_config` detecte `.project.yml`
- [ ] T2: `_proj_find_config` detecte `.project.yaml`
- [ ] T1: `_proj_find_config` retourne 1 si aucun fichier trouve
- [ ] T1: `_proj_get_value` parse une cle YAML simple
- [ ] T1: `_proj_get_value` supprime les guillemets
- [ ] T2: `_proj_load_by_path` change le repertoire courant
- [ ] T2: `_proj_load_by_path` verifie le proprietaire du fichier env ($UID)
- [ ] T2: `_proj_load_by_path` refuse un fichier env avec mauvais proprietaire
- [ ] T1: `_proj_load_by_path` ignore post_cmd en mode non-interactif
- [ ] T2: `proj_add` cree le fichier registre
- [ ] T2: `proj_add` detecte les chemins dupliques
- [ ] T2: `proj_add` detecte les noms dupliques
- [ ] T2: `proj_list` affiche les projets enregistres
- [ ] T2: `proj_list` marque les dossiers manquants
- [ ] T2: `proj_remove` supprime l'entree du registre
- [ ] T2: `proj_init` cree un fichier `.proj` template
- [ ] T1: `proj_init` echoue si `.proj` existe deja
- [ ] T2: `proj_scan` detecte les dossiers `.git`
- [ ] T2: `proj_scan` detecte `package.json`, `Cargo.toml`, `go.mod`
- [ ] T2: `proj_scan` respecte la limite de profondeur

## Plugins (plugins.zsh)

- [ ] T1: `plugins.zsh` se source sans erreur
- [ ] T1: `ZSH_ENV_PLUGINS=()` vide ne cause pas d'erreur
- [ ] T1: `_zsh_env_plugin_name` extrait le nom depuis `owner/repo`
- [ ] T1: `_zsh_env_plugin_name` extrait le nom depuis une URL complete
- [ ] T1: `_zsh_env_plugin_url` genere l'URL GitHub depuis `owner/repo`
- [ ] T1: `_zsh_env_plugin_url` prefixe avec `ZSH_ENV_PLUGINS_ORG` si pas de `/`
- [ ] T1: `_zsh_env_plugin_url` retourne l'URL telle quelle si `https://`
- [ ] T2: `_zsh_env_find_plugin_file` detecte `*.plugin.zsh`
- [ ] T2: `_zsh_env_find_plugin_file` detecte `init.zsh`
- [ ] T2: `_zsh_env_find_plugin_file` detecte `<nom>.zsh`
- [ ] T1: `zsh-plugin-install` sans argument affiche l'usage
- [ ] T1: `zsh-plugin-remove` sans argument affiche l'usage

## Docker (docker_utils.zsh)

- [ ] T1: Module skip si `ZSH_ENV_MODULE_DOCKER != true`
- [ ] T3: `dex` echoue si Docker n'est pas lance
- [ ] T3: `dstop` retourne 0 si aucun conteneur
- [ ] T3: `dstop` affiche le nombre de conteneurs
- [ ] T3: `dstop` echoue si Docker n'est pas lance

## Kube Config (kube_config.zsh)

- [ ] T3: `kube_init` cree `~/.kube` et `~/.kube/configs.d`
- [ ] T3: `kube_select` liste les configs disponibles
- [ ] T3: `kube_status` affiche le KUBECONFIG actif
- [ ] T3: `kube_add` valide l'existence du fichier
- [ ] T3: `kube_add` detecte les doublons
- [ ] T3: `kube_reset` vide les configs chargees

## Auto-Update (auto_update.zsh)

- [ ] T1: `_zsh_env_should_check_update` retourne 0 si frequence = 0
- [ ] T1: `_zsh_env_should_check_update` retourne 0 si fichier timestamp absent
- [ ] T1: `_zsh_env_should_check_update` retourne 0 apres N jours
- [ ] T1: `_zsh_env_should_check_update` retourne 1 si check recent
- [ ] T2: `_zsh_env_check_update` compare HEAD vs origin/main
- [ ] T1: `zsh-env-status` affiche la version et les modules

## Work Context (work_context.zsh)

- [ ] T1: `_blg_cache_valid` retourne 1 si pas de fichier cache
- [ ] T2: `_blg_cache_valid` retourne 0 si age < TTL
- [ ] T2: `_blg_cache_valid` retourne 1 si age > TTL
- [ ] T2: `_blg_cache_write` ecrit timestamp + valeur
- [ ] T1: Cache TTL est configurable via `ZSH_ENV_WORK_CACHE_TTL`
- [ ] T1: Timeout est configurable via `ZSH_ENV_WORK_TIMEOUT`
- [ ] T3: `_blg_test_nexus` utilise curl avec timeout
- [ ] T3: `work_is_context` utilise le cache si valide
- [ ] T2: `blg_refresh` supprime le fichier cache

## Net Utils (net_utils.zsh)

- [ ] T1: `port` requiert 2 arguments (host et port)
- [ ] T3: `myip` utilise curl avec `--max-time 5`
- [ ] T3: `myip` gere le timeout gracieusement

## GitLab Logic (gitlab_logic.zsh)

- [ ] T1: Module skip si `ZSH_ENV_MODULE_GITLAB != true`
- [ ] T1: Warning si `~/.gitlab_secrets` n'existe pas

## Check Env Deps (check_env_deps.zsh)

- [ ] T1: `check_env_health` verifie les outils core
- [ ] T1: `check_env_health` marque les outils manquants
- [ ] T1: `check_env_health` fournit la commande brew install

## Scripts GitLab

- [ ] T1: `trigger-jobs.sh --help` affiche l'aide (exit 0)
- [ ] T1: `trigger-jobs.sh` echoue sans GITLAB_TOKEN (exit 1)
- [ ] T1: `trigger-jobs.sh` echoue sans argument -j (exit 1)
- [ ] T1: `trigger-jobs.sh` echoue sans cible (-p/-P/-g) (exit 1)
- [ ] T1: `clone-projects.sh --help` affiche l'aide (exit 0)
- [ ] T1: `clone-projects.sh` echoue avec moins de 2 arguments (exit 1)

---

## Statistiques

| Tier | Description | Cas | Difficulte |
|------|-------------|-----|------------|
| T1 | Unit tests (pas de deps) | ~85 | Facile |
| T2 | Integration (git/fichiers) | ~75 | Moyen |
| T3 | Mocks necessaires | ~30 | Avance |
| **Total** | | **~190** | |

## Priorite d'implementation

1. **T1** - Tous les tests unitaires (pas de setup complexe)
2. **T2 critiques** - variables.zsh, functions.zsh, extract, utils, plugins
3. **T2 securite** - security_audit, ssh_manager, project_switcher
4. **T2 git** - git_root, git_hooks, git_change_author, aliases git
5. **T3** - Docker, Kube, Tmux, NVM (necessite framework de mocking)
