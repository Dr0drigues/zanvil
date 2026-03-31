# Audit de Securite

Verification des permissions et detection des problemes de securite. En v2, le CLI Rust propose un audit avance et un mecanisme de confiance protege le chargement des fichiers `.zsh-env.local`.

## Commandes

| Commande | Description |
|----------|-------------|
| `zsh-env-audit` | Audit complet des permissions |
| `zsh-env-audit-fix` | Correction automatique |
| `zsh-env-cli audit` | Audit avance via le CLI Rust |

## Lancer un audit

```bash
# Audit standard (zsh)
zsh-env-audit

# Audit avance (Rust, plus rapide, verifications supplementaires)
zsh-env-cli audit
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

## Mecanisme de confiance (.zsh-env.local)

Le fichier `.zsh-env.local` permet de definir des variables d'environnement specifiques a un repertoire. Pour eviter l'execution de code malveillant, un mecanisme de confiance base sur un hash est mis en place.

### Fonctionnement

1. Lorsque vous entrez dans un repertoire contenant `.zsh-env.local`, zsh-env calcule le hash SHA-256 du fichier
2. Si le hash n'est pas dans la liste des fichiers approuves, zsh-env affiche un avertissement et demande confirmation
3. Une fois approuve, le hash est enregistre et le fichier sera charge automatiquement
4. Si le fichier est modifie (hash different), une nouvelle approbation est requise

### Utilisation

```bash
# Creer un fichier .zsh-env.local dans un projet
cat > /path/to/project/.zsh-env.local << 'EOF'
export NODE_ENV=development
export DATABASE_URL=postgres://localhost/mydb
EOF

# Entrer dans le repertoire -> zsh-env demande d'approuver
cd /path/to/project
# > .zsh-env.local detecte (non approuve). Approuver ? [y/N]
```

### Securite

- Le hash est calcule sur le contenu complet du fichier
- Les fichiers approuves sont stockes de maniere securisee
- Toute modification invalide l'approbation precedente
- `zsh-env-cli audit` verifie l'integrite des fichiers approuves

## Exemple de sortie

```
╭──────────────────────────────────────────╮
│  ZSH_ENV Security Audit          v2.0.0  │
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
Correction auto: zsh-env-audit-fix
```

### Legende

- `✓` : OK (permissions correctes)
- `✗` : Erreur (permissions incorrectes, affiche la valeur)
- `○` : Optionnel/Non configure

## Correction automatique

```bash
zsh-env-audit-fix
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
3. **Verifier regulierement** avec `zsh-env-audit` ou `zsh-env-cli audit`
4. **Credential helper Git** pour eviter les tokens en clair
5. **Variables d'environnement** plutot que fichiers pour les tokens CI/CD
6. **Approuver avec precaution** les fichiers `.zsh-env.local` inconnus
7. **Surveiller les PAT** - les alertes d'expiration evitent les interruptions de service
