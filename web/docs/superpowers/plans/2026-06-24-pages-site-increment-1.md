# Site Pages (Astro Starlight) — Incrément 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mettre en ligne un site de documentation Astro Starlight aux couleurs forge (landing + 3 pages core), déployé sur GitHub Pages.

**Architecture:** Projet Astro Starlight isolé dans `site/`, thème forge via CSS override, contenu en Markdown, build statique déployé par GitHub Actions (`pages.yml`). Le GitHub Wiki coexiste (retrait en incrément 2).

**Tech Stack:** Astro 5 + `@astrojs/starlight`, Node 20+, GitHub Actions + Pages.

## Global Constraints

- Marque affichée : `zanvil` ; tagline : `craft your shell` (verbatim).
- **Nommage transitionnel** : URL `/zsh_env/`, install `~/.zsh_env`, commandes `zsh-env-*` — INCHANGÉS (rename = sous-projet #4). Le site les utilise tels quels.
- `astro.config.mjs` DOIT définir `site: 'https://dr0drigues.github.io'` et `base: '/zsh_env/'` (project page).
- Palette forge : charbon `#1a1613`, panel `#241d18`, braise `#ff8a3d`, étincelle `#ffd479`, acier `#8896a3`, cendre `#d8cdbf`.
- Tout le projet site vit sous `site/` ; ne pas toucher à `docs/` (specs/plans).
- `wiki.yml` et le dossier `wiki/` restent INCHANGÉS dans cet incrément.
- **⚠️ ÉTAPE OBLIGATOIRE AVANT CHAQUE CRÉATION DE PR** : mettre à jour la documentation impactée (README, `CLAUDE.md`, `docs/ROADMAP.md`, et le contenu du site concerné) AVANT de créer la PR. C'est la Task finale de ce plan, et la règle s'applique à toute PR future.
- Vérification = `cd site && npm run build` réussit (Astro/Starlight échoue le build sur lien interne mort) ; pas de framework de test unitaire.
- `$SCRATCHPAD` = `/private/tmp/claude-502/-Users-bl209054--zsh-env/518614f2-a551-4e43-9135-dfc256ae2d6e/scratchpad`

---

### Task 1: Scaffold Astro Starlight dans site/

**Files:**
- Create: `site/package.json`, `site/package-lock.json` (généré), `site/astro.config.mjs`, `site/src/content.config.ts`, `site/.gitignore`
- Create (placeholder remplacé en Task 3): `site/src/content/docs/index.md`

**Interfaces:**
- Produces: un projet Astro buildable. `npm run build` (dans `site/`) génère `site/dist/`.

- [ ] **Step 1: Installer Astro + Starlight**

```bash
mkdir -p site && cd site
npm init -y >/dev/null
npm install astro @astrojs/starlight sharp
```

- [ ] **Step 2: Écrire `site/package.json` (scripts)**

Remplacer le `package.json` généré par (en conservant les versions de deps que `npm install` a écrites) :

```json
{
  "name": "zanvil-site",
  "type": "module",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview"
  }
}
```

Puis relancer `npm install` pour réinjecter les deps dans ce package.json (ou conserver les blocs `dependencies` écrits par Step 1 — ne PAS perdre les versions résolues).

- [ ] **Step 3: Écrire `site/.gitignore`**

```
node_modules/
dist/
.astro/
```

- [ ] **Step 4: Écrire `site/astro.config.mjs`**

```js
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://dr0drigues.github.io',
  base: '/zsh_env/',
  integrations: [
    starlight({
      title: 'zanvil',
      logo: { src: './src/assets/logo-mark.svg', alt: 'zanvil' },
      customCss: ['./src/styles/forge.css'],
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/Dr0drigues/zsh_env' },
      ],
      sidebar: [
        { label: 'Guides', items: [
          { label: 'Installation', slug: 'installation' },
          { label: 'Configuration', slug: 'configuration' },
        ]},
        { label: 'Référence', items: [
          { label: 'Commandes', slug: 'commandes' },
        ]},
      ],
    }),
  ],
});
```

> Note : les API Starlight (`social`, loaders) varient selon la version installée. Si le build échoue sur ces clés, adapter à la version résolue par `npm install` (consulter `node_modules/@astrojs/starlight/package.json`). Les Task 2/3 créent `forge.css`, `logo-mark.svg` et les pages référencées — d'ici là le build peut échouer sur fichiers manquants, c'est attendu.

- [ ] **Step 5: Écrire `site/src/content.config.ts`**

```ts
import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
};
```

> Note : si la version de Starlight est antérieure aux loaders (≤ 0.28), utiliser `src/content/config.ts` avec `docsSchema()` seul. Adapter selon la version.

- [ ] **Step 6: Placeholder index pour valider le build**

`site/src/content/docs/index.md` :
```md
---
title: zanvil
description: craft your shell
---

Placeholder — remplacé par la landing en Task 3.
```

- [ ] **Step 7: Vérifier le build (placeholder forge.css/logo manquants → créer stubs temporaires si besoin)**

Pour isoler le scaffold, créer des stubs vides :
```bash
mkdir -p src/styles src/assets
: > src/styles/forge.css
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>' > src/assets/logo-mark.svg
npm run build
```
Expected: build réussit, `site/dist/` généré.

- [ ] **Step 8: Commit**

```bash
cd /Users/bl209054/.zsh_env
git add site
git commit -m "feat(site): scaffold Astro Starlight (base path /zsh_env/)"
```

---

### Task 2: Thème forge + assets (logo, favicon)

**Files:**
- Create: `site/src/styles/forge.css` (remplace le stub)
- Create: `site/src/assets/logo-mark.svg`, `site/src/assets/logo-mark-light.svg` (copies depuis `assets/branding/`)
- Create: `site/public/favicon.svg` (copie)

**Interfaces:**
- Consumes: `astro.config.mjs` (référence `forge.css` + `logo-mark.svg`).
- Produces: site stylé forge.

- [ ] **Step 1: Copier les assets de branding dans le site**

```bash
cd /Users/bl209054/.zsh_env
cp assets/branding/logo-mark.svg site/src/assets/logo-mark.svg
cp assets/branding/logo-mark-light.svg site/src/assets/logo-mark-light.svg
mkdir -p site/public
cp assets/branding/favicon.svg site/public/favicon.svg
```

- [ ] **Step 2: Écrire `site/src/styles/forge.css`**

```css
/* Thème forge pour Starlight — fer froid + braise sur charbon */
:root {
  --sl-color-accent-low: #2f2620;
  --sl-color-accent: #ff8a3d;
  --sl-color-accent-high: #ffd479;
}
/* Mode sombre (par défaut du site) */
:root[data-theme='dark'] {
  --sl-color-bg: #1a1613;
  --sl-color-bg-nav: #241d18;
  --sl-color-bg-sidebar: #1a1613;
  --sl-color-hairline: #3d322a;
  --sl-color-gray-7: #221d18;
  --sl-color-gray-6: #2f2620;
  --sl-color-gray-5: #3d322a;
  --sl-color-text: #d8cdbf;
  --sl-color-text-accent: #ff8a3d;
  --sl-color-white: #f0e9df;
}
/* Mode clair : accent forge conservé */
:root[data-theme='light'] {
  --sl-color-accent-low: #ffe9d6;
  --sl-color-accent: #d4541e;
  --sl-color-accent-high: #7a2f12;
}
```

> Note : si une variable `--sl-color-*` n'existe plus dans la version installée, le style dégrade proprement (var ignorée). Vérifier visuellement en Step 4.

- [ ] **Step 3: Référencer le favicon (déjà dans `public/`)**

Starlight sert `site/public/favicon.svg` automatiquement. Aucune action si présent. Si un `<head>` custom est requis, ajouter `head` dans la config starlight :
```js
head: [{ tag: 'link', attrs: { rel: 'icon', href: '/zsh_env/favicon.svg', type: 'image/svg+xml' } }],
```

- [ ] **Step 4: Build + vérification visuelle**

```bash
cd site && npm run build
```
Expected: build OK. Lancer `npm run dev` et vérifier dans le navigateur : logo enclume visible, accent braise sur les liens, fond charbon en mode sombre. (Vérification visuelle obligatoire car le rendu est l'objet du livrable.)

- [ ] **Step 5: Commit**

```bash
cd /Users/bl209054/.zsh_env
git add site
git commit -m "feat(site): thème forge (palette + logo + favicon)"
```

---

### Task 3: Landing + migration des 3 pages core

**Files:**
- Modify: `site/src/content/docs/index.md` → renommer/réécrire en `index.mdx` (landing splash)
- Create: `site/src/content/docs/installation.md` (migré de `wiki/Installation.md`)
- Create: `site/src/content/docs/configuration.md` (migré de `wiki/Configuration.md`)
- Create: `site/src/content/docs/commandes.md` (migré de `wiki/Commandes.md`)

**Interfaces:**
- Consumes: slugs `installation`/`configuration`/`commandes` (référencés par la sidebar en Task 1).
- Produces: site avec landing + 3 pages dans la nav.

- [ ] **Step 1: Écrire la landing `site/src/content/docs/index.mdx`**

Supprimer `index.md`, créer `index.mdx` :
```mdx
---
title: zanvil
description: craft your shell — suite Zsh modulaire et orientée productivité (macOS & Linux)
template: splash
hero:
  tagline: craft your shell
  image:
    file: ../../assets/logo-mark.svg
  actions:
    - text: Installation
      link: /zsh_env/installation/
      icon: right-arrow
    - text: GitHub
      link: https://github.com/Dr0drigues/zsh_env
      icon: external
      variant: minimal
---

import { Card, CardGrid } from '@astrojs/starlight/components';

<CardGrid>
  <Card title="Modulaire" icon="puzzle">Modules zsh chargés à la demande, guardés par config.</Card>
  <Card title="Rust + zsh" icon="rocket">CLI Rust pour les commandes lourdes, fallback zsh complet.</Card>
  <Card title="Thèmes unifiés" icon="sun">Prompt Starship + couleurs des commandes pilotés ensemble.</Card>
  <Card title="Productivité" icon="setting">Git, GitLab, Docker, Kubernetes, outils modernes.</Card>
</CardGrid>
```

> Note : les liens `actions` incluent le base path `/zsh_env/` explicitement. Vérifier qu'ils ne sont pas doublés par Astro (sinon retirer le préfixe). Le build signalera un lien mort sinon.

- [ ] **Step 2: Migrer Installation**

Créer `site/src/content/docs/installation.md` : frontmatter Starlight puis le corps de `wiki/Installation.md`. Adapter les liens internes inter-pages au format Starlight (`/zsh_env/configuration/` ou liens relatifs). Conserver les chemins `~/.zsh_env` / commandes `zsh-env-*` (transitionnel).
```md
---
title: Installation
description: Installer zanvil (zsh_env) sur macOS et Linux
---

<!-- corps adapté de wiki/Installation.md -->
```

- [ ] **Step 3: Migrer Configuration et Commandes**

Idem pour `configuration.md` (depuis `wiki/Configuration.md`) et `commandes.md` (depuis `wiki/Commandes.md`) : ajouter le frontmatter `title`/`description`, adapter les liens internes.

- [ ] **Step 4: Build (échoue sur lien interne mort)**

```bash
cd site && npm run build
```
Expected: build OK, aucun avertissement de lien mort. Corriger tout lien cassé signalé (wiki-links `[X](X)` → slugs Starlight).

- [ ] **Step 5: Vérification visuelle de la nav**

`npm run dev` : la landing s'affiche (hero + cards), la sidebar montre Guides (Installation, Configuration) et Référence (Commandes), chaque page s'ouvre.

- [ ] **Step 6: Commit**

```bash
cd /Users/bl209054/.zsh_env
git add site
git commit -m "feat(site): landing + pages Installation/Configuration/Commandes"
```

---

### Task 4: Pipeline de déploiement GitHub Pages

**Files:**
- Create: `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: `site/` buildable (Tasks 1-3).
- Produces: déploiement automatique du site sur Pages au push `main`.

- [ ] **Step 1: Écrire `.github/workflows/pages.yml`**

```yaml
name: Deploy Pages

on:
  push:
    branches: [main]
    paths:
      - 'site/**'
      - '.github/workflows/pages.yml'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: site/package-lock.json
      - run: npm ci
        working-directory: site
      - run: npm run build
        working-directory: site
      - uses: actions/upload-pages-artifact@v3
        with:
          path: site/dist

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Valider le YAML**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/pages.yml'); puts 'YAML valide'"
```
Expected: `YAML valide`. Vérifier que `permissions` contient `pages: write` et `id-token: write`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pages.yml
git commit -m "ci(site): workflow de déploiement GitHub Pages"
```

---

### Task 5: Documentation (OBLIGATOIRE avant la PR)

**Files:**
- Modify: `README.md` (section Documentation), `CLAUDE.md` (architecture : ajout `site/`), `docs/ROADMAP.md` (statut incrément 1 + note audit incrément 2)

**Interfaces:**
- Consumes: l'existence du site (Tasks 1-4).
- Produces: documentation à jour reflétant le nouveau site.

- [ ] **Step 1: README — pointer vers le site**

Dans `README.md`, sous l'en-tête, ajouter une ligne vers le futur site (en gardant le lien wiki pendant la coexistence) :
```md
<p align="center"><strong><a href="https://dr0drigues.github.io/zsh_env/">Site de documentation</a></strong> · <a href="https://github.com/Dr0drigues/zsh_env/wiki">Wiki</a></p>
```

- [ ] **Step 2: CLAUDE.md — architecture**

Dans la section Architecture de `CLAUDE.md`, ajouter une entrée décrivant `site/` :
```
├── site/               # Site de doc Astro Starlight (GitHub Pages, thème forge)
```
Et une phrase : « Le site (`site/`) est un projet Astro Starlight déployé sur GitHub Pages via `.github/workflows/pages.yml`. Contenu Markdown sous `site/src/content/docs/`. »

- [ ] **Step 3: ROADMAP — statut + note audit incrément 2**

Dans `docs/ROADMAP.md`, mettre à jour la ligne #5 : incrément 1 livré, et ajouter explicitement que **l'incrément 2 inclura un audit de complétude documentaire** (vérifier que toutes les pages wiki sont migrées et à jour, rien d'obsolète, liens valides) avant retrait du `wiki.yml`.

- [ ] **Step 4: Vérifier**

```bash
cd /Users/bl209054/.zsh_env
grep -q "dr0drigues.github.io/zsh_env" README.md && echo "README OK"
grep -q "site/" CLAUDE.md && echo "CLAUDE OK"
grep -qi "audit" docs/ROADMAP.md && echo "ROADMAP OK"
```
Expected: les 3 `OK`.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md docs/ROADMAP.md
git commit -m "docs(site): référencer le site + architecture + roadmap (audit incrément 2)"
```

---

## Notes d'exécution

- Branche : `feature/pages-site-mvp` (préfixe `feature/*` → bump **minor** au merge). Elle portera aussi le commit local du spec (`acde443`).
- Au **merge** : `pages.yml` déploie le site **et** `auto-release.yml` publie la release minor (cohérent — le site fait partie de la release).
- **Étape manuelle post-merge** (une fois) : activer GitHub Pages avec source **GitHub Actions** (Settings → Pages → Build and deployment → Source: GitHub Actions), sinon `deploy-pages` échoue. Peut aussi se faire via `gh api -X POST repos/Dr0drigues/zsh_env/pages -f build_type=workflow` (à tenter pendant l'implémentation).
- L'**incrément 2** (futur) : migration des 13 pages restantes + **audit de complétude documentaire** + retrait de `wiki.yml` + redirection du wiki.
