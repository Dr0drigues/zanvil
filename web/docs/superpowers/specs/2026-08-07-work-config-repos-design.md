# Repos de configs — création et mise aux normes

**Date** : 2026-08-07
**Module** : `work`
**Statut** : conception validée, à planifier

## Besoin

Disposer d'une commande qui, pour un repo de configuration donné :

- le crée s'il n'existe pas,
- vérifie qu'il respecte la norme de branches par environnement s'il existe,
- ne fait rien s'il est conforme,
- propose de corriger les écarts sinon.

## État des lieux constaté

Relevé le 2026-08-07 sur `gitlab.forge.tsc.azr.intranet` (GitLab **18.11.7 CE**, `enterprise: false`).

### La topologie réelle

`configurations` n'est pas un repo mais un **groupe** :

```
<bu>/applications/<app>/configurations/<repo>
```

Environ 40 apps portent un `technical-assets` sous ce groupe. Certaines ont d'autres repos
(`docs`, `schema-registry`, `caas-namespaces`). `frontlibreservice` porte en plus un
**sous-groupe** `companion` (`configurations/companion/{app,api,loader}`).

Le besoin a été formulé avec `application` au singulier ; le réel est **`applications`** au
pluriel, côté disque comme côté forge. C'est le pluriel qui fait foi.

### La norme, telle qu'elle existe dans les repos `cls-*`

Les repos de référence sont `blg/applications/frontlibreservice/configurations/cls-*`.
Quatre d'entre eux (`cls-bff`, `cls-front`, `cls-valkey`, `cls-borne`) sont conformes :

```
branches    dev, qlf, pprd, prd
défaut      dev
dev, qlf    non protégées
pprd, prd   protégées
              push_access_level  = 40 (Maintainers)
              merge_access_level = 40 (Maintainers)
              allow_force_push   = false
              code_owner_approval_required = false
visibility  internal
```

Deux dérives observées, qui justifient l'audit :

- **`cls-docs`** : `qlf` et `pprd` n'existent pas, alors qu'une *règle de protection* `pprd`
  existe. GitLab autorise une règle sur une branche absente — comparer seulement la liste des
  branches raterait ce cas.
- **`cls-apk-deletion_scheduled-8725`** : défaut `qlf`, pas de `dev`, `qlf` protégée en
  `Developers + Maintainers`. Son nom indique une suppression programmée.

Aucun contenu commun entre ces repos : chacun a son arborescence propre (`helm/`, `k8s/`,
`java/`, `apim/`). Il n'existe pas de squelette à copier.

### `technical-assets`

**Entièrement hors périmètre**, sur décision explicite : ni écriture, ni audit. La commande le
refuse avant tout appel réseau, quels que soient les flags.

Ce repo appartient à une autre chaîne de responsabilité et sa topologie n'est de toute façon
pas celle de la norme : il est mono-branche (`master` ou `main`), là où la norme en attend
quatre. L'auditer produirait un rapport d'écarts qui n'aurait aucun sens à corriger. Ses
protections ont servi de point de comparaison pendant la conception ; elles ne sont pas lues
à l'exécution.

## Périmètre

**Dans le périmètre** : un repo à la fois, désigné explicitement par flags ou déduit du `cwd`.

**Hors périmètre, refusé avant tout appel réseau** :

- `technical-assets` — **refusé entièrement**, audit compris
- tout chemin sous `configurations/companion/`
- une BU hors `blg|edt|udb|tsc|shared`
- un chemin hors d'un groupe `configurations`

Le groupe `configurations` n'est **jamais créé**. S'il manque, échec net.

## Surface

```
work_config_repo [<repo>] [options]

  --bu <blg|edt|udb|tsc|shared>   BU        (défaut : déduite du cwd)
  --app <nom>                     app       (défaut : déduite du cwd)
  --envs dev,qlf,pprd,prd         envs      (défaut : les quatre)
  --readme                        autorise la réécriture des README préexistants
  --fix                           applique ; sans lui, audit en lecture seule
  -h | --help
```

Sans argument, la cible est déduite du `cwd` s'il correspond au chemin canonique :

```
$WORK_DIR/<bu>/applications/<app>/configurations/<repo>
```

Le namespace GitLab est l'image exacte de ce chemin. Créer un repo qui n'existe pas encore
passe nécessairement par les flags — la déduction depuis le `cwd` ne peut désigner qu'un repo
déjà cloné.

**Aucune persistance.** Le sous-ensemble d'envs n'est mémorisé nulle part : il est passé par
`--envs`, ou saisi dans le dialogue, ou vaut les quatre branches par défaut.

## Audit

Trois appels de lecture (`GET /projects/:id`, `/repository/branches`, `/protected_branches`)
plus un `GET /repository/files/README.md/raw?ref=<branche>` par branche d'env.

| # | Contrôle | Écart |
|---|---|---|
| 1 | chaque env de `--envs` a sa branche | `✗ absente → créer depuis <défaut>` |
| 2 | la branche par défaut est `dev` | `✗ défaut=<x> → basculer sur dev` |
| 3 | `pprd`/`prd` protégées : push=40, merge=40, force=off | `✗ protection divergente → réappliquer` |
| 4 | `dev`/`qlf` **non** protégées | `✗ protégée → déprotéger` |
| 5 | pas de règle de protection sans branche | `! orpheline → supprimer la règle` |
| 6 | `README.md` conforme sur chaque branche d'env | `✗ divergent → réécrire` (opt-in, cf. plus bas) |
| 7 | branches hors norme | voir ci-dessous |

**La protection se décide par nom de branche, pas par rang** : `dev` et `qlf` non protégées,
`pprd` et `prd` protégées. Donc `--envs dev,qlf` produit un repo sans aucune branche protégée.

**La branche par défaut attendue est `dev`.** Si `--envs` ne contient pas `dev`, c'est la
première env dans l'ordre canonique `dev < qlf < pprd < prd` qui devient le défaut attendu —
`--envs qlf,prd` attend donc `qlf` en défaut. La saisie est normalisée dans cet ordre, quel que
soit l'ordre de frappe.

### Contrôle 7 : deux populations de branches hors norme

- `master` / `main` → candidates à la migration puis suppression
- **tout le reste** (`feature/*`, `config/*`, `unprotected`…) → **listé, jamais touché**

Cette séparation est une exigence de sûreté, pas un confort : `cls-borne` porte deux branches
`config/*` vivantes et `cls-bff` une `feature/*`. Une règle « supprimer ce qui n'est pas dans
la norme » les détruirait.

### Garde sur la suppression de `master`

Avant toute suppression :

```
GET /projects/:id/repository/merge_base?refs[]=master&refs[]=dev
```

Si le merge-base n'est pas exactement le SHA de `master`, alors `master` porte des commits
absents de `dev` : la suppression est **refusée et signalée**, même après un `y`. Pas de clone
nécessaire, pas d'heuristique de contenu.

## Règle README

Sur chaque branche d'env du périmètre, `README.md` contient exactement :

```markdown
# <nom du repo> <branche>
```

soit, sur la branche `dev` de `cls-docs` :

```markdown
# cls-docs dev
```

Un titre H1, une ligne, un saut de ligne final, rien d'autre.

**Réécriture opt-in.** Un README **préexistant** qui diverge est signalé comme écart mais n'est
corrigé qu'avec `--readme`. C'est la protection contre l'écrasement d'un README qui porte du
contenu utile.

**Exception : les branches créées dans le run courant.** Une branche dérivée de `dev` hérite du
README de `dev` (donc `# cls-x dev` sur une `qlf` fraîchement créée). Il n'y a rien à écraser :
elle est normalisée d'office, sans `--readme`.

La règle ne s'applique qu'aux branches d'env. `feature/*` et `config/*` gardent le leur.
Un README strictement identique au contenu attendu ne produit aucun commit : la commande est
rejouable sans polluer l'historique. Seul `README.md` est considéré ; une variante de casse est
signalée, jamais renommée.

## Plan et dialogue

L'audit produit un rapport. `--fix` transforme le même rapport en plan et demande.

```
work_config_repo — blg/applications/frontlibreservice/configurations/cls-docs

  dev     ✓ existe   ✓ défaut   ✓ non protégée   ✓ README
  prd     ✓ existe              ✓ protégée (Maintainers/Maintainers, force=off)
  qlf     ✗ absente
  pprd    ✗ absente
          ! règle de protection « pprd » orpheline

Plan (3 actions)
  + créer qlf  depuis dev   (README normalisé)
  + créer pprd depuis dev   (README normalisé)
  - supprimer la règle orpheline « pprd »

Appliquer ? [y/N/u]
```

- `y` — applique le plan
- `N` (défaut) — n'écrit rien ; une frappe sur Entrée est sans conséquence
- `u` — redemande la liste d'envs, recalcule le plan, repropose le même prompt

Répondre `u` puis `dev,qlf` sur l'exemple ci-dessus ramène le plan à une seule action : la
suppression de la règle orpheline.

## Ordre d'application

L'API impose deux contraintes qui se croisent — on ne supprime pas la branche par défaut, on ne
supprime pas une branche protégée. D'où :

1. créer les branches manquantes depuis la branche par défaut courante
2. basculer le défaut sur `dev`
3. déprotéger `dev`/`qlf` si elles le sont
4. **normaliser les README** — d'office sur les branches créées à l'étape 1, seulement sous
   `--readme` sur les branches préexistantes
5. appliquer les protections `pprd`/`prd`
6. supprimer les règles orphelines
7. `master`/`main` : `merge_base`, puis déprotéger, puis supprimer

L'étape 4 précède l'étape 5 : sur un repo neuf, l'inverse ferait buter la commande sur les
règles qu'elle vient d'écrire.

Chaque étape échouée arrête la suite et affiche le code HTTP **et** le corps de la réponse.

### Commits sur branche protégée

Sur un repo existant déjà conforme côté protections, l'étape 5 est sautée — donc l'étape 4
écrit sur `pprd`/`prd` protégées. Le commit part via `POST /repository/commits` sous l'identité
du token : Maintainer, il passe ; sinon GitLab répond 403 et la branche est signalée.

**La commande ne déprotège jamais d'elle-même pour se faire de la place.** Ouvrir une fenêtre
de non-protection sur `prd` sans le dire serait pire que l'écart corrigé.

### Modifier une protection existante sur GitLab CE

`PATCH /projects/:id/protected_branches/:name` existe en 18.11, mais sur l'édition Free il ne
sait modifier que `allow_force_push` : les paramètres `allowed_to_push` / `allowed_to_merge`
sont Premium. Donc :

| Situation | Appel | Fenêtre de non-protection |
|---|---|---|
| règle absente | `POST /protected_branches` | non |
| seul `allow_force_push` diverge | `PATCH /protected_branches/:name` | non |
| un niveau d'accès diverge | `DELETE` puis `POST` | **oui, brève** |

Le troisième cas est **marqué comme tel dans le plan**, ligne par ligne. La fenêtre ne peut pas
être supprimée sur cette édition ; elle est rendue visible.

## Création d'un repo absent

Une fois le plan accepté :

1. résoudre le groupe `<bu>/applications/<app>/configurations` (`GET /groups/<path encodé>`) —
   absent, échec net
2. `POST /projects` : `namespace_id`, `path`, `visibility=internal`, `default_branch=dev`,
   `initialize_with_readme=true`
3. normaliser le README de `dev`
4. dériver `qlf`, `pprd`, `prd` depuis `dev`, README normalisé sur chacune
5. appliquer les protections
6. `git clone` au chemin canonique, via l'URL retournée par l'API, en réutilisant la mécanique
   d'authentification déjà en place pour les clones existants
7. `cd` dans le clone

`visibility=internal` et le `merge_method` par défaut : c'est ce que portent les six `cls-*`
existants, on ne s'en écarte pas.

## Accès réseau

- Token : `GITLAB_TOKEN` depuis `~/.gitlab_secrets`, sourcé par la garde `_work_cfg_require` si
  la variable est absente — le module `work` ne dépend pas de l'activation du module `gitlab`
- Domaine : `GITLAB_BASE_DOMAIN`
- TLS : `--cacert "$SSL_CERT_FILE"` si la variable est définie, sinon appel nu.
  **Pas de `-k`**, contrairement à `gitlab_logic.zsh` : vérifié le 2026-08-07, la forge répond
  200 sans désactiver la vérification. Un échec TLS renvoie un message pointant `SSL_CERT_FILE`.
- Helper `_work_cfg_curl METHOD PATH [BODY]`, calqué sur `_work_es_curl` : première ligne = code
  HTTP, reste = corps.

## Codes de sortie

| Code | Sens |
|---|---|
| 0 | conforme, ou corrigé avec succès |
| 1 | erreur (refus dur, réseau, API, groupe absent) |
| 2 | écarts détectés en mode audit |

Le `2` permet de boucler sur plusieurs repos sans lire la sortie.

## Implémentation

| Fichier | Nature |
|---|---|
| `modules/work/config_repos.zsh` | nouveau — toute la logique |
| `modules/work/init.zsh` | ajouter la ligne `source` |
| `modules/work/.lazy` | ajouter `work_config_repo` |
| `modules/work/completions.zsh` | compdef : flags, BUs, envs |

Tout en zsh, dans le moule d'`elasticsearch.zsh` : garde `_work_cfg_require`, helper
`_work_cfg_curl`, affichage via les fonctions `_ui_*`, aucune couleur en dur.

Le CLI Rust est écarté : il n'a aujourd'hui aucun client GitLab, et le travail ici est
I/O-bound sur l'API plus un dialogue interactif — Rust n'apporterait que de la surface.

## Vérification

Pas de shellspec (convention du projet).

- `zsh -n modules/work/config_repos.zsh`
- chargement dans un `zsh -f` propre, puis `work_config_repo --help`
- hors réseau borné : `GITLAB_BASE_DOMAIN=127.0.0.1:9` échoue immédiatement, ne pend pas
- refus durs à sec — `technical-assets`, un chemin `companion/`, une BU inconnue — chacun doit
  sortir **avant** le premier `curl`
- audit réel en lecture seule : `cls-bff` attendu conforme (code 0), `cls-docs` attendu à
  3 écarts (code 2)
- parsing d'options : `work_config_repo --envs` en dernier argument ne doit pas boucler
  (`shift 2` gardé — piège zsh déjà rencontré en review)

## Hors périmètre

Volontairement écartés :

- création de groupes sur la forge
- persistance du sous-ensemble d'envs (topic GitLab, fichier local, fichier dans le repo)
- balayage de tous les repos d'un groupe en une commande
- alignement des `merge_method`, `squash_option`, règles d'approbation
- toute opération sur `technical-assets`, audit compris
- suppression de branches autres que `master`/`main`
