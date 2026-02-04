# Kubernetes Config Manager

Gestion multi-config Kubernetes avec support Azure AKS, AWS EKS et GCP GKE.

## Commandes

| Commande | Description |
|----------|-------------|
| `kube_init` | Initialise l'environnement, déchiffre les configs sops |
| `kube_select` | Sélection interactive des configs (fzf) |
| `kube_status` | Affiche les configs actives |
| `kube_list` | Liste toutes les configs disponibles |
| `kube_add <file>` | Ajoute une config à KUBECONFIG |
| `kube_reset` | Remet uniquement la config minimale |
| `kube_encrypt <file>` | Chiffre une config avec sops/age |
| `kube_help` | Affiche l'aide |

## Azure AKS

```bash
# Sélection interactive
kube_azure

# Cluster spécifique
kube_azure blg-dev

# Liste des clusters configurés
kube_azure_list

# Statut de connexion Azure
kube_azure_status
```

### Clusters préconfigurés

Les clusters sont définis dans `kube_config.zsh` :

```zsh
_KUBE_AZ_CLUSTERS=(
    "blg-dev:sub-org:rg-org-cluster-dev:aks-org-cluster-dev"
    "blg-prd:sub-org:rg-org-cluster-prd:aks-org-cluster-prd"
)
```

## AWS EKS

```bash
# Sélection interactive
kube_aws

# Cluster et région spécifiques
kube_aws my-cluster eu-west-1

# Liste des clusters
kube_aws_list
```

Prérequis : `aws` CLI configuré (`aws configure` ou `AWS_PROFILE`).

## GCP GKE

```bash
# Sélection interactive
kube_gcp

# Cluster spécifique
kube_gcp my-cluster europe-west1-b my-project

# Liste des clusters
kube_gcp_list
```

Prérequis : `gcloud auth login`.

## Structure des fichiers

```
~/.kube/
├── config                    # Config par défaut kubectl
├── config.minimal.yml        # Config minimale (base)
└── configs.d/                # Configs additionnelles
    ├── kubeconfig-blg-dev.yml
    ├── kubeconfig-eks-prod.yml
    └── kubeconfig-gke-staging.yml
```

## Chiffrement SOPS

Pour versionner des kubeconfigs de manière sécurisée :

```bash
# Chiffrer une config
kube_encrypt ~/.kube/config.minimal.yml
# -> Crée ~/.zsh_env/kube/config.minimal.sops.yml

# Déchiffrer au démarrage (automatique si sops/age installés)
kube_init
```

Configuration SOPS dans `~/.zsh_env/.sops.yaml` :

```yaml
creation_rules:
  - path_regex: \.sops\.yml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Multi-config KUBECONFIG

`kube_select` permet de sélectionner plusieurs configs :

```
●/○ = état actuel | TAB: toggle | Ctrl-A: tout | Ctrl-N: rien

● config.minimal.yml (base)
○ kubeconfig-blg-dev.yml
○ kubeconfig-eks-prod.yml
```

Le KUBECONFIG résultant est la concaténation :

```bash
echo $KUBECONFIG
# /Users/user/.kube/config.minimal.yml:/Users/user/.kube/configs.d/kubeconfig-blg-dev.yml
```
