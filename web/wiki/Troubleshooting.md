# Troubleshooting

Guide de dépannage pour les problèmes courants.

## Diagnostic

```bash
# Diagnostic complet
zanvil-doctor

# Profiler le démarrage
zanvil-bench

# Audit de sécurité
zanvil-audit
```

## Problèmes courants

### Le shell est lent au démarrage

1. **Profiler** :
   ```bash
   zanvil-bench
   ```

2. **Solutions** :
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

### La version de Node ne change pas au `cd`

1. Vérifier que mise est installé et activé :
   ```bash
   mise --version
   mise current
   ```

2. Vérifier le module :
   ```zsh
   # Dans config.zsh
   ZANVIL_MODULE_MISE=true
   ```

3. Vérifier le fichier `.nvmrc`, `.tool-versions` ou `.mise.toml` dans le projet

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
   echo $STARSHIP_CONFIG    # ~/.config/zanvil/theme/starship.toml
   ls -la ~/.config/zanvil/theme/starship.toml
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
