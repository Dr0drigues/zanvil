# Audit de Sécurité

Vérification des permissions et détection des problèmes de sécurité.

## Commandes

| Commande | Description |
|----------|-------------|
| `zsh-env-audit` | Audit complet des permissions |
| `zsh-env-audit-fix` | Correction automatique |

## Lancer un audit

```bash
zsh-env-audit
```

## Éléments vérifiés

### SSH

- Dossier `~/.ssh` : permissions 700
- Clés privées (`id_*`) : permissions 600 ou 400
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
- Détection de tokens inline

### Cloud credentials

- `~/.aws/credentials` : permissions 600
- `~/.config/gcloud/application_default_credentials.json` : permissions 600

### Git

- Présence d'un credential helper
- `~/.git-credentials` (si présent, avertissement)

### Historique shell

- `~/.zsh_history`, `~/.bash_history` : permissions 600
- Détection de secrets potentiels dans l'historique

## Exemple de sortie

```
╭──────────────────────────────────────────╮
│  ZSH_ENV Security Audit          v1.2.0  │
╰──────────────────────────────────────────╯

SSH           ~/.ssh ✓  id_ed25519 ✓  config ✓
Secrets       .secrets ✓  .gitlab_secrets ✗644  .npmrc ✓
Kubernetes    ~/.kube ✓  config ✓  2 configs.d/
Git           credential.helper ✓osxkeychain
Cloud         AWS ○  Azure ✓  GCP ○
History       .zsh_history ✓

────────────────────────────────────────────
✗ 1 erreur(s), 2 avertissement(s)
Correction auto: zsh-env-audit-fix
```

### Légende

- `✓` : OK (permissions correctes)
- `✗` : Erreur (permissions incorrectes, affiche la valeur)
- `○` : Optionnel/Non configuré

## Correction automatique

```bash
zsh-env-audit-fix
```

Corrige automatiquement :
- Permissions SSH
- Permissions secrets
- Permissions kubeconfig
- Permissions historique

## Bonnes pratiques

1. **Ne jamais committer de secrets** dans git
2. **Utiliser SOPS/Age** pour les fichiers sensibles versionnés
3. **Vérifier régulièrement** avec `zsh-env-audit`
4. **Credential helper Git** pour éviter les tokens en clair
5. **Variables d'environnement** plutôt que fichiers pour les tokens CI/CD
