# Roadmap — zanvil

> Programme de rebranding (`zsh_env` → **zanvil**) + nouvelles fonctionnalités.
> Chaque item = une PR (`feature/*`/`feat/*` → minor, `hotfix/*` → patch, `breaking/*` → major) = une release auto via `auto-release.yml`.
> Version actuelle : voir `core/ui.zsh` (`ZSH_ENV_VERSION`).

## Livré

| Item | Version | Notes |
|------|---------|-------|
| Modern CLI replacements (rg/fd/dust/duf/procs/btop/gping/tldr) | v3.8.0 | hybride : drop-in + outils sous nom propre |
| Identité visuelle zanvil (logo ASCII, bannière, tagline « craft your shell ») | v3.9.0 | cosmétique, non-breaking |
| Branding assets (logos SVG sombre/clair/mono + favicon + en-tête README) | v3.10.0 | mark vectoriel reconstruit depuis l'export design |
| Thème signature **forge** | v3.11.0 | défaut des nouveaux installs ; existants non affectés |
| Site de doc Astro Starlight — **incrément 1** | v3.12.0 | Pages live, thème forge, landing + 3 pages migrées |
| Chemin de bump major (`breaking/*`) dans `auto-release.yml` | v3.13.0 | prérequis #3b pour la v4.0.0 |
| **Rename technique complet** (`zsh_env` → `zanvil`, repo GitHub, migration auto) | **v4.0.0** | **🔴 hard cut** (pas de shims) ; migration auto via garde précoce de `rc.zsh` |

## Backlog

| # | Item | Version visée | Type | Statut | Breaking |
|---|------|---------------|------|--------|----------|
| 5 | Site Pages — **incrément 2** (migration complète + audit doc + retrait `wiki.yml`) | v4.x | feat | 🧠 inc1 ✅, inc2 à brainstormer | non |
| 6 | Piste A — productivité shell (×7) | v4.x | feat | 💡 idées | non |
| 7 | Piste B — onboarding / DX (×3) | v4.x | feat | 💡 idées | non |
| 8 | Piste D — méta / écosystème (×2) | v4.x | feat | 💡 idées | non |
| 9 | Tests e2e en moteur de règles (pilotés par YAML) | v4.x | test | 💡 idée — à brainstormer | non |

### Détail des pistes features (1 ligne = 1 release)
- **A — productivité** : command-not-found intelligent · widgets fzf (gco / process / env) · marque-pages de répertoires · `web_search` · `copypath`/`copyfile`/`copybuffer` · `alias-finder` · `bgnotify` (notif commandes longues)
- **B — onboarding/DX** : wizard `zanvil init` · dashboard / MOTD · `zanvil profile` (breakdown startup)
- **D — méta** : registre de modules + `module install` · profils/presets (work / perso / minimal)

## Tests e2e en moteur de règles (#9)

Le projet n'a aucun harnais de test (shellspec écarté) : chaque fonction est vérifiée à la main, et les scripts qui dépendent d'un cluster ou d'un remote ne sont pas testables du tout.

Modèle à reprendre : **`~/work/misc/armadai`, `tests/e2e/`** — un cas = un fichier YAML, un harnais qui les exécute et produit un rapport.

> **Cadrage fait le 2026-07-28 :** l'outil ne sera pas construit dans zanvil. Il devient un **projet distinct**, réutilisable comme dépendance, dont armadai est le prototype et zanvil le second consommateur. Décisions d'architecture, découpage en incréments et critères de succès : `~/work/misc/e2e-harness/PROJECT-BRIEF.md` (dossier au nom provisoire). L'entrée #9 se réduit donc à « zanvil adopte cet outil », ce qui dépend de son incrément 2.

```yaml
name: direct
weight: 5
setup:
  pattern: direct
  flags: ["--json"]
fake:
  rules:
    - match: { agent: t-writer }
      respond: "done"
    - match: {}                     # catch-all : ne doit jamais être atteint
      respond: "unexpected"
expect:
  exit_code: 0
  events: [...]
  event_counts: { agent_start: 1 }
  invariants: [agent_start_end_symmetric, no_orphan_events]
```

Les briques intéressantes à transposer : les **fakes pilotés par règles de `match`** (avec catch-all explicite pour détecter les appels non prévus), les **invariants nommés et réutilisables** entre cas, le **poids par cas**, et la séparation `case.rs` / `harness.rs` / `runner.rs` / `report.rs`.

Transposition à concevoir pour zanvil : les fakes porteraient sur les binaires externes (`kubectl`, `git`, `glab`, `k9s`) injectés en tête de `PATH` ; les attentes sur le code de sortie, stdout/stderr, et les effets de bord fichiers. Harnais en Rust dans `cli/` (le binaire `zanvil` existe déjà) ou en zsh — à arbitrer. Fournirait au passage un vrai socle aux fixtures introduites par la spec du viewer de logs k9s.

## ✅ v4.0.0 — Rename technique (LIVRÉ)

**Périmètre breaking — hard cut** (pas de shims de compat ; migration auto via garde précoce de `rc.zsh`) :
- `~/.zsh_env` → `~/.zanvil` (dossier d'install)
- variables `ZSH_ENV_*` → `ZANVIL_*` (guards de modules, `ZSH_ENV_DIR`, `ZSH_ENV_STARTUP_BANNER`, etc.)
- binaire `zsh-env-cli` → `zanvil` ; commandes `zsh-env-*` → `zanvil-*`
- **repo GitHub `Dr0drigues/zsh_env` → `Dr0drigues/zanvil`** (action manuelle, propriétaire uniquement, réversible)
- **script de migration automatique** : détecte ancien install en `~/.zsh_env`, renomme le dossier, réécrire `.zshrc`, migre `config.zsh` ; invoque la migration au prochain shell après upgrade

**Note utilisateur :** les fichiers `.zsh-env.local` dans les projets doivent être renommés manuellement en `.zanvil.local` (la migration auto couvre uniquement `~/.zsh_env` → `~/.zanvil`)

### Rename du repo GitHub — effets en cascade

**Géré automatiquement par GitHub (redirections) :**
- Les anciennes URLs (`…/zsh_env`, `…/zsh_env.git`) redirigent vers `zanvil` — git clone/push, web et API continuent de fonctionner. Forks/stars/issues/PRs suivent.
- Le secret **`RELEASE_TOKEN`** (PAT fine-grained) est scopé par **ID de repo**, pas par nom → survit au rename (à confirmer rapidement après l'opération).
- Les workflows (`auto-release.yml`, `pages.yml`, `wiki.yml`) utilisent `github.repository` **dynamique** → s'adaptent seuls.

**À mettre à jour explicitement (cassent sinon) :**
- **GitHub Pages** : l'URL devient `dr0drigues.github.io/zanvil/` → changer `base: '/zsh_env/'` → `/zanvil/` dans `site/astro.config.mjs`, **tous les liens du site** (hero actions, favicon), le lien site du `README` et la **social preview**.
- **Wiki** : URL `…/zanvil/wiki`.
- **Instructions d'install** : `git clone …/zanvil.git ~/.zanvil` (couplé au rename du dossier).
- **Docs/README/ROADMAP** : toutes les URLs `Dr0drigues/zsh_env` codées en dur.

**Séquencement :** le rename de repo est **interdépendant** avec le reste (le base path Pages dépend du nom du repo) → à faire **dans le même sous-projet v4.0.0**, pas isolément. Le **prérequis CI #3b** (chemin major) doit être livré **avant**.

**Prérequis CI (#3b) :** ✅ Livré en v3.13.0 — `auto-release.yml` gère désormais `major` (`breaking/*`), `minor` (`feature/*`/`feat/*`) et `patch` (`hotfix/*`). Une PR sur branche `breaking/*` déclenche automatiquement un bump major.

## Ordre conseillé

Livrer le **prérequis CI #3b** d'abord, puis le **rename #4 en capstone v4.0.0** — après quoi les pistes A/B/D se construisent directement avec le nommage zanvil (plus de couches transitionnelles). Le site Pages incrément 2 (#5) peut s'intercaler avant ou après le rename (s'il passe après, sa migration intègre directement le nouveau nommage).

## Site / Wiki (#5)

État actuel : dossier `wiki/` synchronisé vers le GitHub Wiki par `.github/workflows/wiki.yml` (déclenché sur push `wiki/**`). Site GitHub Pages (Astro Starlight, `site/`) en construction :
- **Incrément 1 ✅ (v3.12.0)** : site déployé sur GitHub Pages via `.github/workflows/pages.yml`, landing + 3 pages migrées, thème forge.
- **Incrément 2** : migration des 13 pages restantes du wiki, **audit de complétude documentaire** (toutes les pages migrées et à jour, rien d'obsolète — ex. section Tmux du module supprimé, chemin CLI `~/.zsh_env/cli`, liens valides, renvois inter-pages restaurés), puis retrait du `wiki.yml`.
- Décision finale : Pages **remplace** le wiki une fois l'audit terminé et approuvé.
