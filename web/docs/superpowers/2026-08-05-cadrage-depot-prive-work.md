# Cadrage — extraire `modules/work/` dans un dépôt privé

**À décider, pas encore fait.** Ce document cadre l'idée pour qu'elle soit arbitrable, pas pour la
mettre en œuvre.

## Le fait qui rend ce cadrage urgent

`gh repo view` dit **`zanvil: PUBLIC`**. Et :

```
modules/work/elasticsearch.zsh:11   https://es-observability.prd.api.udb.azr.intranet
modules/work/fetch_es_logs.sh:192   https://es-observability.prd.api.udb.azr.intranet
```

Ce nom d'hôte est en dur, comme valeur par défaut, à deux endroits d'un dépôt public. Il n'y a **aucun
secret** dans le dépôt — pas de jeton, pas de mot de passe, les credentials passent par `env.d/*.sops.zsh`
et `~/.secrets` comme la convention l'exige. Ce qui est exposé est de la nomenclature d'infrastructure :
le préfixe de production, le nom du service d'observabilité, le domaine Azure interne.

**Il faut être juste sur la portée.** Un `.intranet` ne résout pas depuis l'extérieur, donc personne ne
peut s'y connecter avec cette information. Le préjudice est de la reconnaissance : quelqu'un qui
préparerait une intrusion contre l'entreprise apprend gratuitement comment ses services sont nommés. C'est
une pratique à corriger, pas une urgence à traiter cette nuit.

Le correctif minimal ne demande pas de dépôt séparé — il suffit de remplacer le défaut par une chaîne
vide et de refuser proprement quand la variable n'est pas réglée. Le dépôt séparé répond à une question
plus large, qui est celle que tu poses.

## Ce que l'extraction résoudrait vraiment

Trois choses, dont une seule est la sécurité :

**Les valeurs internes vivent au bon endroit.** Aujourd'hui il n'y a que deux niveaux : le code versionné
public, et `env.d/` gitignoré donc non partageable. Un dépôt privé en offre un troisième : versionné,
partagé avec les collègues qui en ont besoin, invisible au public. C'est exactement ce qui manque pour
« avoir les valeurs qui m'intéressent » sans les mettre en dur ni les recopier sur chaque poste.

**Le module devient partageable.** `work_es_apps`, `work_es_tail`, `work_fetch_logs` sont utiles à
quiconque interroge le même Elasticsearch. Aujourd'hui ils ne peuvent pas être partagés autrement qu'en
partageant tout zanvil, avec sa configuration personnelle.

**Le dépôt public redevient homogène.** `modules/work/` est le seul module dont l'utilité dépend d'un
employeur. Les onze autres marchent pour n'importe qui.

## Ce qui partirait, mesuré

| Fichier | Lignes | Contenu |
|---|---|---|
| `modules/work/elasticsearch.zsh` | 550 | Requêtes ES, fenêtres, comptage, tail |
| `modules/work/fetch_es_logs.sh` | 339 | Export paginé par scroll |
| `modules/work/work_context.zsh` | 215 | Détection de contexte via sonde Nexus |
| `modules/work/completions.zsh` | 69 | Complétions |
| `modules/work/init.zsh` | 2 | Chargeur |

Plus les **12 cas gaveldrop** écrits pendant le chantier 3 (`tests/cases/es/` et `tests/cases/fetch/`), le
hook `tests/hooks/prepare-sync-fixture.sh` ne concernant pas ce module.

## Ce qui resterait, et c'est le point délicat

**`cli/src/cmd/es.rs` doit rester dans zanvil.** Le calcul temporel qu'il porte — conversions,
Europe/Paris, fenêtres — n'a rien de spécifique à un employeur : c'est du `chrono` sur des dates. Le
sortir signifierait publier un second binaire, ou faire dépendre le dépôt privé d'un crate du dépôt
public. Le laisser signifie que le module privé appelle `zanvil es convert`, donc que **le dépôt privé
dépend du public** — ce qui est le bon sens de la dépendance.

Rien d'autre du code de zanvil ne connaît `work`. Vérifié : les seules références sont
`modules/work/init.zsh` et le loader générique, qui découvre les modules par leur dossier.

## Trois formes possibles, par ordre de préférence

**1. Un dépôt privé cloné dans `modules/`, découvert par le loader existant.**

Le loader parcourt `modules/*/init.zsh` : un dossier cloné là est chargé sans une ligne de code en plus.
Le guard `ZANVIL_MODULE_WORK` fonctionne déjà par dérivation du nom du dossier. `config.zsh` déclare le
dépôt à cloner, `install.sh` le clone s'il y a accès et passe sinon.

C'est la forme qui demande le moins de mécanique nouvelle. Son défaut : un dossier de `modules/` doit être
gitignoré, ce qui se lit mal — quelqu'un qui inspecte le dépôt voit un module absent sans savoir pourquoi.

**2. Un plugin, via le mécanisme `ZANVIL_PLUGINS` qui existe.**

`plugins.zsh` clone déjà des dépôts déclarés dans `config.zsh`. Un plugin privé n'est qu'une URL de plus,
et la nature « externe » est explicite. Défaut : les plugins sont chargés après les modules, donc l'ordre
change, et le guard de module ne s'appliquerait plus de la même façon.

**3. Un dépôt sœur, source par `.zanvil.local` ou `env.d/`.**

Le plus découplé, et le plus manuel. À écarter sauf si les deux premiers butent : ça revient à ce que
`env.d/` fait déjà, sans le versionnement qui est le motif de l'opération.

## Ce qu'il faut décider avant de commencer

1. **Le correctif minimal d'abord ?** Retirer le nom d'hôte en dur des deux fichiers coûte dix minutes et
   règle le point de sécurité indépendamment de l'extraction. Je le recommande dans tous les cas — le
   cadrage d'une extraction ne doit pas retarder une correction de trois lignes.
2. **Qui d'autre en a besoin ?** Si personne, `env.d/` suffit peut-être et l'extraction est du travail
   pour rien. Si des collègues, la forme 1 ou 2 se décide sur la façon dont ils y accéderont.
3. **Les cas gaveldrop partent-ils avec le module ?** Ils devraient — un test vit avec son sujet — mais
   alors le dépôt privé a besoin de sa propre CI et de son propre `gaveldrop.yaml`. C'est le même travail
   que pour le dépôt autonome du plugin k9s, et les deux gagneraient à être faits ensemble.
4. **Que devient `fetch_es_logs.sh` ?** Il duplique le zsh depuis toujours ; la duplication de calcul est
   payée, mais deux implémentations de l'export subsistent. L'extraction est le bon moment pour choisir
   laquelle survit.

## Ce que ce cadrage ne tranche pas

La forme de la dépendance, parce qu'elle dépend de la réponse à la question 2. Et le calendrier : les deux
chantiers du spec zsh/Rust encore ouverts — `commands.zsh` et `gitlab_logic` — ne touchent pas à `work`,
donc rien n'oblige à décider maintenant.
