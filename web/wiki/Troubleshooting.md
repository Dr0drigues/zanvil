# Troubleshooting

Guide de dépannage pour les problèmes courants.

## Diagnostic

```bash
# Diagnostic complet
zanvil-doctor

# Profiler le démarrage
zanvil-profile

# Audit de sécurité
zanvil-audit
```

## Problèmes courants

### Le shell est lent au démarrage

1. **Profiler** :
   ```bash
   zanvil-profile
   ```

2. **Solutions** :
   - Activer le lazy loading NVM :
     ```zsh
     # Dans config.zsh
     ZANVIL_NVM_LAZY=true
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
   ZANVIL_MODULE_NVM=true
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
zanvil-audit

# Correction automatique
zanvil-audit-fix
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
   zanvil-theme default
   ```

## Réinitialisation

### Réinitialiser la configuration

```bash
# Backup
cp ~/.zanvil/config.zsh ~/.zanvil/config.zsh.bak

# Recréer depuis le template
cp ~/.zanvil/config.zsh.example ~/.zanvil/config.zsh
```

### Réinstallation complète

```bash
# Désinstaller
~/.zanvil/uninstall.sh --keep-dir

# Réinstaller
~/.zanvil/install.sh
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
zsh -c 'source ~/.zanvil/functions/kube_config.zsh && kube_status'
```

## Obtenir de l'aide

1. Consulter ce wiki
2. Lancer `zanvil-doctor`
3. Ouvrir une issue sur GitHub avec :
   - Output de `zanvil-doctor`
   - Message d'erreur complet
   - Étapes pour reproduire
