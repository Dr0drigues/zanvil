# Skip si module desactive
[ "$ZSH_ENV_MODULE_GITLAB" != "true" ] && return

### SECURITY & CONFIGURATION ###

# 1. Chargement sécurisé du token
# Créez un fichier ~/.gitlab_secrets contenant : export GITLAB_TOKEN='votre_token'
if [ -f "$HOME/.gitlab_secrets" ]; then
    source "$HOME/.gitlab_secrets"
else
    echo "WARNING: $HOME/.gitlab_secrets introuvable. Le token GitLab est manquant."
fi

# 2. Configuration des Group IDs (Modèle de données)
# Structure : [environnement-composant]=ID
typeset -A GITLAB_PROJECTS
GITLAB_PROJECTS=(
    # PTF Environment
    [ptf-frontco]="35621"
    [ptf-backcaisse]="35617"
    [ptf-controlpanel]="35366"
    [ptf-liveperf]="35624"

    # CaaS BLG Environment
    [blg-front]="36963"        
    #[blg-backcaisse]="00000"   
    #[blg-controlpanel]="00000" 
    #[blg-liveperf]="00000"     

    # CaaS ED Environment
    #[ed-front]="00000"
    #[ed-backcaisse]="00000"
    #[ed-controlpanel]="00000"
    #[ed-liveperf]="00000"
)

### LOGIC & ALIAS GENERATION ###

###
# Génère les alias de clonage basés sur la configuration GITLAB_PROJECTS.
# Crée des alias sous la forme : gc-<composant>-<env>
#
# Itère sur le tableau associatif pour respecter le principe DRY.
###
function load_gitlab_aliases() {
    local key id parts env component alias_name

    for key id in "${(@kv)GITLAB_PROJECTS}"; do
        # Parsing de la clé "env-composant"
        # On suppose le format 'env-composant' dans la clé du tableau
        parts=("${(@s/-/)key}")
        env=$parts[1]
        component=$parts[2]

        # Construction du nom de l'alias : gc-composant-env (pour matcher votre format actuel)
        # Ex: ptf-frontco devient gc-frontco-ptf
        alias_name="gc-${component}-${env}"

        # Création de l'alias
        alias "$alias_name"="cd $WORK_DIR && clone-projects.sh $id $GITLAB_TOKEN"
    done
}

# Exécution de la génération
load_gitlab_aliases

# Fonction utilitaire pour lister les alias générés
function list-gitlab-cmds() {
    echo "\033[1;34mCommandes GitLab disponibles :\033[0m"
    for key in "${(@k)GITLAB_PROJECTS}"; do
        # On refait le parsing pour l'affichage
        parts=("${(@s/-/)key}")
        echo "  \033[0;32mgc-${parts[2]}-${parts[1]}\033[0m -> Clone le groupe ${GITLAB_PROJECTS[$key]}"
    done | sort
}

# Un alias court pour lister les commandes
alias help-clone="list-gitlab-cmds"

# Nettoyage de la fonction pour ne pas polluer l'espace de noms global
unfunction load_gitlab_aliases