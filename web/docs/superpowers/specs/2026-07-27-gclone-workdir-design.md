# gclone — clone d'un groupe GitLab depuis WORK_DIR

**Date** : 2026-07-27
**Statut** : design validé
**Module** : `modules/gitlab/`

## Problème

`scripts/clone-projects.sh` clone les projets d'un groupe GitLab dans le répertoire
courant. L'utilisateur doit donc penser à se placer dans `$WORK_DIR` avant de le
lancer, sous peine de disséminer des dépôts un peu partout.

Les alias générés `gc-<composant>-<env>` contournent le problème avec
`cd $WORK_DIR && clone-projects.sh $id $GITLAB_TOKEN`, mais cette forme a trois
défauts :

1. Le token GitLab est inscrit en clair dans la définition de l'alias, visible via
   `alias` ou `alias gc-frontco-ptf`.
2. Le `cd` s'arrête à `$WORK_DIR` : après un clone, l'utilisateur doit encore
   descendre à la main dans l'arborescence du groupe.
3. La logique est dupliquée dans chaque alias généré, sans validation des
   préconditions (token absent, `WORK_DIR` non défini, script introuvable).

## Solution

Une fonction zsh `gclone` qui encapsule le déplacement, l'appel au script et le
positionnement final du shell. Les alias `gc-*` deviennent de simples délégations.

## Interface

```
gclone <clé|group-id> [options de clone-projects.sh]
```

**Premier argument** :

- une valeur purement numérique est traitée comme un group ID GitLab brut ;
- toute autre valeur est traitée comme une clé de `GITLAB_PROJECTS`
  (format `env-composant`, ex. `ptf-frontco`).

Une clé inconnue produit une erreur `_ui_msg_fail` suivie de la liste des clés
configurées, et `return 1`.

**Arguments suivants** : transmis tels quels à `clone-projects.sh`
(`ssh`, `https`, `full`, `shallow`, `--parallel N`, `--dry-run`).

**Exemples** :

```zsh
gclone ptf-frontco ssh --parallel 8
gclone 35621 --dry-run
gclone --help
```

## Déroulé

1. **Aide** — `--help` / `-h` en premier argument affiche l'usage de `gclone`, la
   liste des clés `GITLAB_PROJECTS`, et renvoie vers `clone-projects.sh --help`
   pour le détail des options. `return 0`.

2. **Résolution de l'ID** — numérique → ID direct ; sinon lookup dans
   `GITLAB_PROJECTS`. Échec → erreur + liste des clés, `return 1`.

3. **Préconditions** — vérifiées dans cet ordre, chacune sortant en erreur
   explicite via `_ui_msg_fail` :
   - `GITLAB_TOKEN` non vide (sinon : pointer vers `~/.gitlab_secrets`) ;
   - `GITLAB_BASE_DOMAIN` non vide (sinon : pointer vers `env.d/gitlab.zsh`) ;
   - `WORK_DIR` défini et répertoire existant ;
   - script trouvable : `$SCRIPTS_DIR/clone-projects.sh` si présent, sinon
     `command -v clone-projects.sh`.

4. **Résolution du dossier cible** — appel `GET /groups/<id>` sur
   `https://$GITLAB_BASE_DOMAIN/api/v4` pour lire `.full_path`
   (ex. `blg-caas/ptf`). L'appel utilise `--max-time 5`, et `-k` si
   `GITLAB_IGNORE_SSL` vaut `true`. En cas d'échec ou de `jq` absent, on
   n'interrompt pas : `full_path` reste vide et l'étape 6 se contente de laisser
   le shell dans `$WORK_DIR`.

5. **Exécution** — mémorisation du cwd de départ, `cd "$WORK_DIR"`, puis
   `clone-projects.sh <id> "$GITLAB_TOKEN" "$@"`. Le code de sortie est conservé.

6. **Positionnement final** :
   - script en succès et `$WORK_DIR/<full_path>` existe → `cd` dans ce répertoire ;
   - script en succès sans `full_path` exploitable → le shell reste dans `$WORK_DIR` ;
   - script en échec → retour au cwd de départ, et `gclone` propage le code
     de sortie du script.

   « Échec » désigne ici un code de sortie non nul de `clone-projects.sh`,
   c'est-à-dire une erreur bloquante (arguments manquants, `jq` absent,
   `GITLAB_BASE_DOMAIN` non défini, erreur API critique). Les échecs de clone ou
   de pull sur des dépôts individuels sont comptabilisés dans le résumé du script
   sans changer son code de sortie : `gclone` positionne alors normalement le
   shell dans le groupe.

   Le `cd` final s'applique aussi en `--dry-run` si le répertoire existe déjà : le
   mode dry-run ne crée rien, donc ce cas ne se présente que sur un groupe déjà
   cloné, où le déplacement reste le comportement attendu.

La fonction ne peut pas s'exécuter dans un sous-shell, puisque le `cd` doit
persister dans le shell appelant. D'où la mémorisation explicite du cwd et le
retour manuel en cas d'échec.

## Modifications

### `modules/gitlab/gitlab_logic.zsh`

- Nouvelle fonction `gclone`, placée après `load_gitlab_aliases` / avant
  `list-gitlab-cmds`.
- Ligne 43 : `alias "$alias_name"="gclone $key"` au lieu de
  `"cd $WORK_DIR && clone-projects.sh $id $GITLAB_TOKEN"`. Le token disparaît de
  la définition des alias.

Les alias conservent leur nom (`gc-<composant>-<env>`) et acceptent toujours des
options en suffixe : `gc-frontco-ptf ssh --parallel 8`.

### `modules/gitlab/completions.zsh`

Nouvelle fonction `_gclone` enregistrée via `compdef _gclone gclone` :

- premier argument : clés de `GITLAB_PROJECTS`, décrites par leur group ID ;
- arguments suivants : `ssh`, `https`, `full`, `shallow`, `--parallel`,
  `--dry-run`, `--help`.

Les `compdef` existants des alias `gc-*` restent inchangés.

### Documentation

- `web/wiki/Commandes.md` et `web/site/src/content/docs/commandes.md` : ajouter
  une ligne `gclone` dans le tableau des commandes GitLab.

## Hors périmètre

- Clonage de tous les groupes `GITLAB_PROJECTS` en une commande (`--all`) :
  écarté, un groupe à la fois suffit.
- Modification de `scripts/clone-projects.sh` : le script reste utilisable seul
  depuis n'importe quel répertoire, son comportement ne change pas.
- Délégation au CLI Rust : la logique est trop fine pour justifier une commande
  `zanvil`.

## Vérification

Aucun harnais de test zsh dans le projet (pas de shellspec). Vérification
manuelle après `source ~/.zshrc` :

1. `gclone --help` → usage + liste des clés.
2. `gclone cle-inexistante` → erreur + liste des clés, code 1, cwd inchangé.
3. `gclone <clé> --dry-run` depuis un répertoire quelconque → le script tourne
   bien depuis `$WORK_DIR`, aucune écriture, shell positionné dans le groupe.
4. `gclone <clé>` → dépôts sous `$WORK_DIR/<full_path>`, shell positionné dedans.
5. `alias gc-frontco-ptf` → plus aucun token affiché.
6. `gclone <TAB>` → complétion des clés `GITLAB_PROJECTS`.
7. Token invalide → le script échoue, `gclone` propage le code et rend le cwd
   de départ.
