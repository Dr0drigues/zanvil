# Roadmap — zanvil

> Programme de rebranding (`zsh_env` → **zanvil**) + nouvelles fonctionnalités.
> Chaque item = une PR (`feature/*` → minor, `hotfix/*` → patch) = une release auto via `auto-release.yml`.
> Version actuelle : voir `core/ui.zsh` (`ZSH_ENV_VERSION`).

## Livré

| Item | Version | Notes |
|------|---------|-------|
| Modern CLI replacements (rg/fd/dust/duf/procs/btop/gping/tldr) | v3.8.0 | hybride : drop-in + outils sous nom propre |
| Identité visuelle zanvil (logo ASCII, bannière, tagline « craft your shell ») | v3.9.0 | cosmétique, non-breaking |
| Site de doc Astro Starlight (incrément 1) | v4.0.0 | déployé sur GitHub Pages, thème forge, pages essentielles migrées |

## Backlog

| # | Item | Version visée | Type | Statut | Breaking |
|---|------|---------------|------|--------|----------|
| 2 | Thème signature **forge** | v3.10.0 | feat | 📝 spec prêt (`specs/2026-06-24-forge-theme-design.md`) | non |
| 3 | Branding assets (logos repo + README) | v3.11.0 | feat | 🎨 mark vectoriel récupéré (sombre+clair) ; wordmark/pixel à ré-exporter | non |
| 3b | Prérequis CI : chemin de bump **major** dans `auto-release.yml` | v3.x | feat | 🧠 à faire avant le #4 | non |
| 4 | **🔴 Rename technique complet** | **v4.0.0** | major | 🧠 à brainstormer | **OUI** |
| 5 | Refonte wiki / **site GitHub Pages** | v4.x | feat | 🧠 à brainstormer (cf. ci-dessous) | non |
| 6 | Piste A — productivité shell (×7) | v4.x | feat | 💡 idées | non |
| 7 | Piste B — onboarding / DX (×3) | v4.x | feat | 💡 idées | non |
| 8 | Piste D — méta / écosystème (×2) | v4.x | feat | 💡 idées | non |

### Détail des pistes features (1 ligne = 1 release)
- **A — productivité** : command-not-found intelligent · widgets fzf (gco / process / env) · marque-pages de répertoires · `web_search` · `copypath`/`copyfile`/`copybuffer` · `alias-finder` · `bgnotify` (notif commandes longues)
- **B — onboarding/DX** : wizard `zanvil init` · dashboard / MOTD · `zanvil profile` (breakdown startup)
- **D — méta** : registre de modules + `module install` · profils/presets (work / perso / minimal)

## 🔴 Passage en 4.0.0 (rename technique)

**Périmètre breaking :**
- `~/.zsh_env` → `~/.zanvil`
- variables `ZSH_ENV_*` → `ZANVIL_*` (guards de modules, `ZSH_ENV_DIR`, etc.)
- binaire `zsh-env-cli` → `zanvil` ; commandes `zsh-env-*` → `zanvil-*`
- repo GitHub `zsh_env` → `zanvil`
- **script de migration** (renommer le dossier, réécrire `.zshrc`, migrer `config.zsh`) + **shims de compat** (alias dépréciés `zsh-env-*` → `zanvil-*` avec avertissement)

**Prérequis CI (#3b)** : `auto-release.yml` ne gère que `minor` (`feature/*`) et `patch` (`hotfix/*`) — **aucun chemin major**. Avant le 4.0.0 : ajouter un déclencheur major (ex. préfixe `breaking/*` ou label PR `major`), sinon tag manuel.

## Ordre conseillé

Livrer les **non-breaking d'abord** (forge #2, assets #3, prérequis CI #3b), **puis le rename #4 en capstone v4.0.0** — après quoi A/B/D se construisent directement avec le nommage zanvil (plus de couches transitionnelles). Le site/wiki (#5) peut s'intercaler dès que l'identité visuelle est figée.

## Site / Wiki (#5) — en cours

État actuel : dossier `wiki/` synchronisé vers le GitHub Wiki par `.github/workflows/wiki.yml` (déclenché sur push `wiki/**`). Site GitHub Pages (Astro Starlight) en construction :
- **Incrément 1 ✅** : site déployé sur GitHub Pages via `.github/workflows/pages.yml`, pages essentielles migrées, thème forge.
- **Incrément 2** : migration des 13 pages restantes du wiki, **audit de complétude documentaire** (vérifier que toutes les pages wiki sont migrées et à jour, rien d'obsolète, liens valides), puis retrait du `wiki.yml`.
- Décision finale : Pages **remplace** le wiki une fois l'audit terminé et approuvé.
