# Audit de Securite

Verification des permissions et detection des problemes de securite. En v2, le CLI Rust propose un audit avance et un mecanisme de confiance protege le chargement des fichiers `.zanvil.local`.

## Commandes

| Commande | Description |
|----------|-------------|
| `zanvil-audit` | Audit complet des permissions |
| `zanvil-audit-fix` | Correction automatique |
| `zanvil audit` | Audit avance via le CLI Rust |

## Lancer un audit

```bash
# Audit standard (zsh)
zanvil-audit

# Audit avance (Rust, plus rapide, verifications supplementaires)
zanvil audit
```

## Elements verifies

### SSH

- Dossier `~/.ssh` : permissions 700
- Cles privees (`id_*`) : permissions 600 ou 400
- `~/.ssh/config` : permissions 600

### Fichiers secrets

- `~/.secrets`
- `~/.gitlab_secrets`
- `~/.env`
- `~/.netrc`
- `~/.npmrc`
- `~/.pypirc`

Permissions attendues : 600

### Kubernetes

- Dossier `~/.kube` : permissions 700
- Fichiers config : permissions 600
- Detection de tokens inline

### Cloud credentials

- `~/.aws/credentials` : permissions 600
- `~/.config/gcloud/application_default_credentials.json` : permissions 600

### Git

- Presence d'un credential helper
- `~/.git-credentials` (si present, avertissement)

### Historique shell

- `~/.zsh_history`, `~/.bash_history` : permissions 600
- Detection de secrets potentiels dans l'historique

### PAT (Personal Access Token)

- Alerte au demarrage si un PAT (GitLab, GitHub) est proche de l'expiration
- Verification automatique a chaque ouverture de shell

### env.d/

- Verification des permissions des fichiers `env.d/*.env`
- Validation de l'integrite des fichiers chiffres sops

## Mecanisme de confiance (.zanvil.local)

Un `.zanvil.local` est du zsh execute au `cd`. Avant le premier chargement, zanvil l'affiche
en entier et demande l'autorisation ; l'empreinte SHA-256 du contenu est alors notee dans
`$ZANVIL_DIR/.trusted/`, et toute modification redemande l'autorisation. Detail complet
(heritage, refus, limites) : [Variables par dossier (.zanvil.local)](https://dr0drigues.github.io/zanvil/zanvil-local/).

## Exemple de sortie

```
╭──────────────────────────────────────────╮
│  ZANVIL Security Audit           v2.0.0  │
╰──────────────────────────────────────────╯

SSH           ~/.ssh ✓  id_ed25519 ✓  config ✓
Secrets       .secrets ✓  .gitlab_secrets ✗644  .npmrc ✓
Kubernetes    ~/.kube ✓  config ✓  2 configs.d/
Git           credential.helper ✓osxkeychain
Cloud         AWS ○  Azure ✓  GCP ○
History       .zsh_history ✓
PAT           GitLab ✓ (expire dans 45j)  GitHub ○
env.d         2 fichiers ✓  1 sops ✓
Local trust   3 approuves  0 invalides

────────────────────────────────────────────
✗ 1 erreur(s), 2 avertissement(s)
Correction auto: zanvil-audit-fix
```

### Legende

- `✓` : OK (permissions correctes)
- `✗` : Erreur (permissions incorrectes, affiche la valeur)
- `○` : Optionnel/Non configure

## Correction automatique

```bash
zanvil-audit-fix
```

Corrige automatiquement :
- Permissions SSH
- Permissions secrets
- Permissions kubeconfig
- Permissions historique
- Permissions env.d/

## Bonnes pratiques

1. **Ne jamais committer de secrets** dans git
2. **Utiliser SOPS/Age** pour les fichiers sensibles versionnes (env.d/, kubeconfigs)
3. **Verifier regulierement** avec `zanvil-audit` ou `zanvil audit`
4. **Credential helper Git** pour eviter les tokens en clair
5. **Variables d'environnement** plutot que fichiers pour les tokens CI/CD
6. **Approuver avec precaution** les fichiers `.zanvil.local` inconnus
7. **Surveiller les PAT** - les alertes d'expiration evitent les interruptions de service
