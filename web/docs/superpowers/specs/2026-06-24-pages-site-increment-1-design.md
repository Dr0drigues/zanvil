# Site GitHub Pages (Astro Starlight) — Incrément 1 : site live (MVP)

**Date** : 2026-06-24
**Statut** : Validé (en attente d'implémentation)
**Release cible** : minor (feature)

## Contexte & roadmap

Sous-projet #5 du programme zanvil : remplacer le GitHub Wiki par un **site de documentation Astro Starlight**, aux couleurs forge. Décomposé en 2 incréments :

1. **Incrément 1 (ce spec)** : scaffold + thème forge + pipeline de déploiement Pages + landing + 3-4 pages core → **le site est en ligne**.
2. Incrément 2 (ultérieur) : migration des pages restantes + retrait de `wiki.yml` + redirection du wiki.

**Séquencement** : le repo s'appelle encore `zsh_env` (rename = sous-projet #4). Ce site est construit en **nommage transitionnel** (URL `…/zsh_env/`, install `~/.zsh_env`, commandes `zsh-env-*`) ; une passe de mise à jour post-rename est prévue (hors périmètre ici).

## Architecture

- **Projet Astro Starlight** dans `site/` (racine du repo), distinct de `docs/` (specs/plans superpowers).
- **Stack** : Astro + `@astrojs/starlight`, Node 20+ (CI), build statique.
- **Base path** : déployé sur une *project page* `https://dr0drigues.github.io/zsh_env/` → `astro.config.mjs` doit définir `site: 'https://dr0drigues.github.io'` et `base: '/zsh_env/'` (sinon liens/assets cassés).
- **Déploiement** : workflow `.github/workflows/pages.yml` (Actions) — build Astro puis `actions/upload-pages-artifact` + `actions/deploy-pages`. Déclenché sur push `main` touchant `site/**` (+ `workflow_dispatch`). `wiki.yml` reste inchangé (coexistence pendant l'incrément 1).
- **Activation Pages** : la source Pages doit être réglée sur **GitHub Actions** (manuel via Settings → Pages, ou API `PUT /repos/.../pages` avec `build_type=workflow`) — étape documentée dans le plan.

## Composants & fichiers

### `site/` — projet Astro Starlight
- `site/package.json` — deps : `astro`, `@astrojs/starlight`. Scripts `dev`/`build`/`preview`.
- `site/astro.config.mjs` — intégration Starlight avec :
  - `site` + `base` (cf. ci-dessus)
  - `title: 'zanvil'`, `tagline`/description « craft your shell »
  - `logo` : `src/assets/logo-mark.svg` (copié depuis `assets/branding/`)
  - `customCss: ['./src/styles/forge.css']`
  - `social` (lien GitHub repo)
  - `sidebar` : groupes **Guides** (Installation, Configuration), **Référence** (Commandes) — étendu en incrément 2
- `site/src/content/config.ts` — collection docs Starlight standard.
- `site/src/styles/forge.css` — override des variables Starlight (`--sl-color-accent*`, `--sl-color-bg*`) avec la palette forge : charbon `#1a1613`, braise `#ff8a3d` (accent), acier `#8896a3`, étincelle `#ffd479`, cendre `#d8cdbf`. Dark mode par défaut.
- `site/src/assets/logo-mark.svg` (+ light) — copie depuis `assets/branding/` (Astro veut les assets sous `src/`).
- `site/public/favicon.svg` — copie du favicon forge.
- `site/.gitignore` — `node_modules/`, `dist/`, `.astro/`.

### Pages de contenu (Markdown Starlight)
- `site/src/content/docs/index.mdx` — **landing** : template `splash`, hero (logo, titre « zanvil », tagline « craft your shell », commande d'install en 1 ligne, boutons CTA → Installation / GitHub).
- `site/src/content/docs/installation.md` — migré de `wiki/Installation.md` (frontmatter Starlight `title`/`description` ajouté, liens internes adaptés).
- `site/src/content/docs/configuration.md` — migré de `wiki/Configuration.md`.
- `site/src/content/docs/commandes.md` — migré de `wiki/Commandes.md`.

(Le contenu `wiki/Home.md` alimente la landing + l'intro.)

### `.github/workflows/pages.yml`
```yaml
name: Deploy Pages
on:
  push: { branches: [main], paths: ['site/**', '.github/workflows/pages.yml'] }
  workflow_dispatch:
permissions: { contents: read, pages: write, id-token: write }
concurrency: { group: pages, cancel-in-progress: false }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm, cache-dependency-path: site/package-lock.json }
      - run: npm ci
        working-directory: site
      - run: npm run build
        working-directory: site
      - uses: actions/upload-pages-artifact@v3
        with: { path: site/dist }
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: { name: github-pages, url: '${{ steps.deployment.outputs.page_url }}' }
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

## Périmètre

**Inclus** : scaffold Astro Starlight, thème forge, logo/favicon, pipeline Pages, landing, 3 pages core migrées (Installation, Configuration, Commandes).

**Exclus (incrément 2 / ultérieur)** : migration des 13 autres pages wiki, retrait de `wiki.yml`, redirection du wiki, passe de renommage post-v4.0.0, domaine custom, recherche avancée/i18n.

## Migration / impact

- Aucune migration côté utilisateur (le site est une nouvelle surface).
- `wiki.yml` et le GitHub Wiki **continuent de fonctionner** en parallèle pendant l'incrément 1.
- `Tmux-Manager.md` (module supprimé) **n'est pas** migré.

## Tests / vérification

- `cd site && npm ci && npm run build` réussit (build Astro sans erreur, `site/dist/` généré).
- Le build ne signale **aucun lien interne cassé** (Starlight échoue le build sur lien mort).
- `astro.config.mjs` : `base: '/zsh_env/'` présent (sinon assets 404 en prod).
- `pages.yml` : YAML valide (parse), permissions `pages: write` + `id-token: write` présentes.
- Vérification visuelle locale (`npm run dev` / `preview`) : landing affiche logo + tagline + couleurs forge ; les 3 pages s'affichent dans la nav.
- Après déploiement : l'URL `https://dr0drigues.github.io/zsh_env/` répond (étape post-merge, après activation Pages).
