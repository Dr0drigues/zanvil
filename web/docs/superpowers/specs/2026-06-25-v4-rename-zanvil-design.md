# v4.0.0 — Rename technique `zsh_env` → `zanvil` — Design

**Date** : 2026-06-25
**Statut** : Validé (en attente d'implémentation)
**Release cible** : **v4.0.0** (major, breaking)

## Contexte & prérequis

Capstone du rebranding zanvil : renommer toute la tuyauterie technique (`zsh_env`/`ZSH_ENV_*`/`zsh-env-*`/`zsh-env-cli`/`~/.zsh_env`/repo) en `zanvil`. Breaking → major.

**Prérequis déjà livrés :**
- Chemin de bump **major** (`breaking/*`) dans `auto-release.yml` (v3.13.0).
- Secret `RELEASE_TOKEN` présent (push sur main protégée).

**Rayon d'impact mesuré** : `ZSH_ENV_*` 435 occ./76 fichiers, `zsh-env-*` 623/41, `zsh-env-cli` 403/20, `~/.zsh_env` 67/26 — surtout `modules/`, `core/`, `cli/`.

## Décisions verrouillées

- **Migration des installs existants** : automatique au prochain chargement (garde précoce + backup + `exec zsh`).
- **Hard cut** : aucun shim de compat ; les commandes deviennent `zanvil-*`, plus de `zsh-env-*`.
- Rename **atomique** = une seule release v4.0.0 (pas de demi-rename).

## A. Rename mécanique du code

Substitutions **ordonnées** (l'ordre est critique : `zsh-env-cli` ⊂ `zsh-env-`), sur les fichiers trackés **hors `docs/superpowers/`** (archives historiques) :

| Ordre | De | Vers | Portée |
|-------|----|----|--------|
| 1 | `zsh-env-cli` | `zanvil` | binaire (commande + Cargo `name`) |
| 2 | `zsh-env-` | `zanvil-` | commandes (`zsh-env-doctor`→`zanvil-doctor`, etc.) |
| 3 | `ZSH_ENV_` | `ZANVIL_` | variables, guards modules, `ZSH_ENV_DIR`→`ZANVIL_DIR` |
| 4 | `zsh_env` | `zanvil` | dossier, repo, divers |
| 5 | `.zsh-env.local` | `.zanvil.local` | fichier direnv-like (point, pas tiret → échappe à l'étape 2) |
| 6 | `.zsh_env` | `.zanvil` | `~/.zsh_env`→`~/.zanvil` (souvent déjà couvert par l'étape 4) |
| 7 | `zsh-env` (nu, restant) | `zanvil` | occurrences résiduelles en prose/affichage |
| 8 | `Dr0drigues/zsh_env` | `Dr0drigues/zanvil` | URLs repo |
| 9 | base Pages `/zsh_env/` | `/zanvil/` | `site/astro.config.mjs` + liens site |

**Méthode** : script de rename appliquant ces substitutions dans l'ordre, **puis revue manuelle** des cas limites :
- chaînes affichées à l'utilisateur (bannières, help, messages) → cohérence visuelle ;
- faux positifs éventuels ;
- `cli/Cargo.toml` : `name = "zsh-env-cli"` → `name = "zanvil"` (le binaire produit devient `zanvil`) ; vérifier `cli/src` (clap `bin_name`, `env!` éventuels) ;
- `.zsh-env.local` (fichier direnv-like) → `.zanvil.local` : le chemin détecté dans `core/hooks.zsh` change ; documenter (les projets utilisateurs avec un ancien `.zsh-env.local` devront le renommer — noter dans le changelog/migration).
- `core/migrate.zsh` : `zsh-env-migrate` → `zanvil-migrate` ; état `.migration_version` lu depuis `$ZANVIL_DIR`.

Le hard cut implique : aucune définition d'alias `zsh-env-*` résiduelle.

## B. Migration des installs existants (garde précoce)

**Problème** : l'auto-update fait `git pull` **dans `~/.zsh_env`**. Après update, le code v4 (qui attend `~/.zanvil` + `ZANVIL_*` + `.zshrc` sourçant le nouveau chemin) s'exécute depuis l'ancien dossier avec l'ancien `.zshrc`. Le runner de migration normal (`core/migrate.zsh`, qui tourne pendant le load avec les anciens chemins et lit le dossier qu'on déplace) ne convient pas.

**Solution** : un **garde de migration au tout début de `rc.zsh`** (avant le chargement normal), idempotent :

```zsh
# Tout début de rc.zsh, avant toute logique de chargement
if [[ -z "$ZANVIL_DIR" && -d "$HOME/.zsh_env" && ! -d "$HOME/.zanvil" ]]; then
    # ... backup, mv, réécriture .zshrc + config.zsh, exec zsh ...
fi
```

Étapes du garde (extraites dans `core/migrate_zanvil.zsh`, sourcé par le garde) :
1. **Backup** : `cp -a ~/.zsh_env ~/.zsh_env.bak-<timestamp>` (timestamp passé en argument, pas de `date` interdit côté zsh — utiliser `strftime`/`$EPOCHSECONDS`).
2. **Déplacer** : `mv ~/.zsh_env ~/.zanvil`.
3. **Réécrire `.zshrc`** : remplacer `export ZSH_ENV_DIR="$HOME/.zsh_env"` → `export ZANVIL_DIR="$HOME/.zanvil"` et `source …/.zsh_env/rc.zsh` → `…/.zanvil/rc.zsh` (sed ciblé, idempotent).
4. **Réécrire `config.zsh`** : `ZSH_ENV_*` → `ZANVIL_*` (le fichier utilisateur, dans `~/.zanvil/config.zsh`).
5. **Message** clair (« Migration zanvil effectuée, backup dans ~/.zsh_env.bak-… »).
6. **`exec zsh`** : recharge proprement depuis `~/.zanvil` (évite de continuer à sourcer un dossier déplacé).

Sûreté : ne s'exécute que si `~/.zsh_env` existe ET `~/.zanvil` absent ET `ZANVIL_DIR` non défini → idempotent (rien sur une install déjà migrée ou neuve). Le `.zshrc` n'est réécrit que sur les lignes ciblées (backup `.zshrc` aussi avant sed).

Le runner de migration normal (`zanvil-migrate` + `migrations/NNN_*.zsh`) reste pour les futurs breaking changes de config ; le rename de dossier est géré par ce garde dédié (hors du runner numéroté).

## C. Séquencement du rename de repo GitHub

La base Pages `/zanvil/` casse si le repo s'appelle encore `zsh_env`. Ordre impératif :
1. **Rename manuel du repo** `Dr0drigues/zsh_env` → `Dr0drigues/zanvil` (Settings → rename ; GitHub redirige les anciennes URLs ; `RELEASE_TOKEN` scopé par ID survit).
2. **Puis** la PR `breaking/rename-zanvil` (rename code + base `/zanvil/` + URLs + migration) → merge → **v4.0.0** auto.

Le rename de repo se fait donc **avant** le merge de la PR (mais la branche peut être préparée avant). Étape manuelle documentée dans le plan.

## D. Stratégie de test

- **Rename** : `zsh -n` sur tous les `*.zsh` (pas d'erreur de syntaxe) ; `cargo build` du CLI OK et binaire nommé `zanvil` ; `git grep -iE 'zsh.env'` (motif large couvrant `ZSH_ENV`, `zsh-env`, `zsh_env`) ne trouve **plus aucune** occurrence hors `docs/superpowers/` (= zéro résiduel). Tout hit restant est soit un faux positif légitime à justifier, soit un oubli à corriger.
- **Migration** (bac à sable, sans toucher la vraie install) : créer un faux `$HOME` temporaire avec un `~/.zsh_env` + `.zshrc` + `config.zsh` factices, lancer le garde de migration, vérifier : dossier déplacé en `~/.zanvil`, backup présent, `.zshrc` et `config.zsh` réécrits, **idempotence** (2ᵉ exécution = no-op), et que la détection ne se déclenche pas sur une install déjà en `~/.zanvil`.
- **Site** : `cd site && npm run build` OK avec base `/zanvil/`.

## Périmètre

**Inclus** : rename mécanique complet, migration auto, séquencement repo, mise à jour site (base path) + docs (README, CLAUDE.md, ROADMAP) + `uninstall.sh`.

**Exclus / hors v4.0.0** : nouvelles features (pistes A/B/D), incrément 2 du site (migration des pages wiki). Les archives `docs/superpowers/` ne sont PAS renommées (historique). Pas de shims de compat (hard cut assumé).

## Migration / changelog

Le changelog v4.0.0 doit prévenir : breaking, dossier `~/.zanvil`, commandes `zanvil-*`, et que les fichiers projet `.zsh-env.local` doivent être renommés en `.zanvil.local` manuellement (non couvert par la migration auto qui ne gère que l'install centrale).

## Release

Branche **`breaking/rename-zanvil`** → `auto-release.yml` bump **major** → v4.0.0 (tag + release + bump `core/ui.zsh` via `RELEASE_TOKEN`). ⚠️ Le rename de repo (C.1) doit être fait avant le merge.
