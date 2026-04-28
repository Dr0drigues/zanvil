# Kubernetes Config Manager

Gestion multi-config Kubernetes avec support Azure AKS, AWS EKS et GCP GKE. En v2, ajout de commandes rapides pour le changement de contexte, de namespace et le lancement de k9s.

## Commandes

| Commande | Description |
|----------|-------------|
| `kube_init` | Initialise l'environnement, dechiffre les configs sops |
| `kube_select` | Selection interactive des configs (fzf) |
| `kube_status` | Affiche les configs actives |
| `kube_list` | Liste toutes les configs disponibles |
| `kube_add <file>` | Ajoute une config a KUBECONFIG |
| `kube_reset` | Remet uniquement la config minimale |
| `kube_encrypt <file>` | Chiffre une config avec sops/age |
| `kube_switch [context]` | Change de contexte Kubernetes |
| `kube_ns [namespace]` | Change de namespace |
| `k [alias]` | Lance k9s avec support des alias de contexte |
| `kube_help` | Affiche l'aide |

## Changement de contexte (kube_switch)

`kube_switch` permet de changer rapidement de contexte Kubernetes :

```bash
# Selection interactive (fzf)
kube_switch

# Contexte specifique
kube_switch my-cluster-dev

# Utiliser un alias de contexte
kube_switch dev
```

Sans argument, une liste interactive (fzf) des contextes disponibles est proposee.

## Changement de namespace (kube_ns)

`kube_ns` permet de changer le namespace par defaut du contexte courant :

```bash
# Selection interactive (fzf)
kube_ns

# Namespace specifique
kube_ns monitoring
```

## k9s avec alias (k)

La commande `k` lance k9s avec support des alias de contexte :

```bash
# k9s sur le contexte courant
k

# k9s sur un contexte specifique
k my-cluster-dev

# k9s via un alias de contexte
k dev
```

## Alias de contexte

Les alias sont definis dans `~/.kube/.context_aliases` :

```bash
# Format : alias=contexte-complet
dev=aks-org-cluster-dev
prd=aks-org-cluster-prd
staging=eks-staging-eu-west-1
```

Les alias sont utilises par `kube_switch` et `k` pour raccourcir les noms de contexte.

```bash
# Au lieu de :
kube_switch aks-org-cluster-dev

# Utiliser :
kube_switch dev

# Ou directement avec k9s :
k dev
```

## Azure AKS

```bash
# Selection interactive
kube_azure

# Cluster specifique
kube_azure dev

# Liste des clusters configures
kube_azure_list

# Statut de connexion Azure
kube_azure_status
```

### Clusters preconfigures

Les clusters sont definis dans la configuration du module kube :

```zsh
_KUBE_AZ_CLUSTERS=(
    "dev:my-subscription:my-rg-dev:my-aks-dev"
    "prd:my-subscription:my-rg-prd:my-aks-prd"
)
```

## AWS EKS

```bash
# Selection interactive
kube_aws

# Cluster et region specifiques
kube_aws my-cluster eu-west-1

# Liste des clusters
kube_aws_list
```

Prerequis : `aws` CLI configure (`aws configure` ou `AWS_PROFILE`).

## GCP GKE

```bash
# Selection interactive
kube_gcp

# Cluster specifique
kube_gcp my-cluster europe-west1-b my-project

# Liste des clusters
kube_gcp_list
```

Prerequis : `gcloud auth login`.

## Structure des fichiers

```
~/.kube/
├── config                    # Config par defaut kubectl
├── config.minimal.yml        # Config minimale (base)
├── .context_aliases          # Alias de contexte (nouveau v2)
└── configs.d/                # Configs additionnelles
    ├── kubeconfig-blg-dev.yml
    ├── kubeconfig-eks-prod.yml
    └── kubeconfig-gke-staging.yml
```

## Chiffrement SOPS

Pour versionner des kubeconfigs de maniere securisee :

```bash
# Chiffrer une config
kube_encrypt ~/.kube/config.minimal.yml
# -> Cree ~/.zsh_env/kube/config.minimal.sops.yml

# Dechiffrer au demarrage (automatique si sops/age installes)
kube_init
```

Configuration SOPS dans `~/.zsh_env/.sops.yaml` :

```yaml
creation_rules:
  - path_regex: \.sops\.yml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Multi-config KUBECONFIG

`kube_select` permet de selectionner plusieurs configs :

```
●/○ = etat actuel | TAB: toggle | Ctrl-A: tout | Ctrl-N: rien

● config.minimal.yml (base)
○ kubeconfig-blg-dev.yml
○ kubeconfig-eks-prod.yml
```

Le KUBECONFIG resultant est la concatenation :

```bash
echo $KUBECONFIG
# /Users/user/.kube/config.minimal.yml:/Users/user/.kube/configs.d/kubeconfig-blg-dev.yml
```
