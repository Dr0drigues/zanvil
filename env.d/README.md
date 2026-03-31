# env.d/ — Variables d'environnement dynamiques

Placez ici des fichiers `.zsh` avec vos variables d'environnement.
Ils sont sourcés automatiquement au démarrage du shell.

## Fichiers en clair
```
env.d/java.zsh        # export JAVA_HOME=...
env.d/proxy.zsh       # export HTTP_PROXY=...
```

## Fichiers chiffrés (sops/age)
```
env.d/secrets.sops.zsh   # Déchiffré automatiquement si sops est installé
```

Pour chiffrer un fichier :
```bash
sops -e env.d/secrets.zsh > env.d/secrets.sops.zsh
rm env.d/secrets.zsh
```

## Gitignore
Les fichiers en clair contenant des secrets doivent être dans `.gitignore`.
Les fichiers `.sops.zsh` peuvent être versionnés (chiffrés).
