# Troubleshooting

Guide de dépannage pour les problèmes courants.

## Diagnostic

```bash
# Diagnostic complet
zsh-env-doctor

# Profiler le démarrage
zsh-env-profile

# Audit de sécurité
zsh-env-audit
```

## Problèmes courants

### Le shell est lent au démarrage

1. **Profiler** :
   ```bash
   zsh-env-profile
   ```

2. **Solutions** :
   - Activer le lazy loading NVM :
     ```zsh
     # Dans config.zsh
     ZSH_ENV_NVM_LAZY=true
     ```
   - Désactiver les modules inutilisés
   - Réduire le nombre de plugins

### Erreur "no matches found"

Erreur zsh quand un glob ne matche rien.

**Solution** : Utiliser le modificateur `(N)` :
```zsh
# Mauvais
for f in *.yml; do

# Bon
for f in *.yml(N); do
```

### Commande non trouvée après installation

```bash
# Recharger le shell
ss
# ou
source ~/.zshrc
```

### NVM ne charge pas automatiquement

1. Vérifier que NVM est installé :
   ```bash
   echo $NVM_DIR
   ls $NVM_DIR
   ```

2. Vérifier le module :
   ```zsh
   # Dans config.zsh
   ZSH_ENV_MODULE_NVM=true
   ```

3. Vérifier le fichier `.nvmrc` dans le projet

### KUBECONFIG non défini

```bash
# Initialiser manuellement
kube_init

# Vérifier
echo $KUBECONFIG
kube_status
```

### fzf ne fonctionne pas

1. Vérifier l'installation :
   ```bash
   which fzf
   fzf --version
   ```

2. Réinstaller :
   ```bash
   brew install fzf  # macOS
   # ou
   sudo apt install fzf  # Debian/Ubuntu
   ```

### Erreurs de permissions

```bash
# Audit
zsh-env-audit

# Correction automatique
zsh-env-audit-fix
```

### Problème avec un plugin

```bash
# Lister les plugins
zsh-plugin-list

# Supprimer le plugin problématique
zsh-plugin-remove nom-plugin

# Réinstaller
zsh-plugin-install owner/nom-plugin
```

### Starship ne s'affiche pas

1. Vérifier l'installation :
   ```bash
   which starship
   starship --version
   ```

2. Vérifier la config :
   ```bash
   ls -la ~/.config/starship.toml
   ```

3. Réappliquer un thème :
   ```bash
   zsh-env-theme default
   ```

## Réinitialisation

### Réinitialiser la configuration

```bash
# Backup
cp ~/.zsh_env/config.zsh ~/.zsh_env/config.zsh.bak

# Recréer depuis le template
cp ~/.zsh_env/config.zsh.example ~/.zsh_env/config.zsh
```

### Réinstallation complète

```bash
# Désinstaller
~/.zsh_env/uninstall.sh --keep-dir

# Réinstaller
~/.zsh_env/install.sh
```

## Logs et debug

### Mode verbose

```bash
# Activer le debug zsh
setopt XTRACE
source ~/.zshrc
unsetopt XTRACE
```

### Tester un fichier isolément

```bash
zsh -c 'source ~/.zsh_env/functions/kube_config.zsh && kube_status'
```

## Obtenir de l'aide

1. Consulter ce wiki
2. Lancer `zsh-env-doctor`
3. Ouvrir une issue sur GitHub avec :
   - Output de `zsh-env-doctor`
   - Message d'erreur complet
   - Étapes pour reproduire
