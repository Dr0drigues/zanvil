# Kubernetes — Clusters Azure AKS preconfigures
# Format : "label:subscription:resource-group:cluster-name"
# Utilise par les fonctions kube_azure / kube_azure_list du module kube
_KUBE_AZ_CLUSTERS=(
    # "dev:my-subscription:my-rg-dev:my-aks-dev"
    # "prd:my-subscription:my-rg-prd:my-aks-prd"
)
export _KUBE_AZ_CLUSTERS
