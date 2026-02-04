# SSH Manager

Gestion simplifiée des connexions SSH via `~/.ssh/config`.

## Commandes

| Commande | Description |
|----------|-------------|
| `ssh_select [pattern]` | Sélection interactive des hosts (fzf) |
| `ssh_list` | Liste tous les hosts configurés |
| `ssh_info <host>` | Affiche les détails d'un host |
| `ssh_add [alias]` | Ajoute un nouveau host interactivement |
| `ssh_remove [host]` | Supprime un host |
| `ssh_copy_key <host>` | Copie la clé publique vers le serveur |
| `ssh_test <host>` | Teste la connexion |
| `ssh_help` | Affiche l'aide |

## Sélection interactive

```bash
ssh_select
```

Avec fzf, affiche la liste des hosts avec prévisualisation de la config.

## Lister les hosts

```bash
ssh_list
```

Affiche :
```
Hosts SSH configurés:
──────────────────────────────────────────
  prod-server          192.168.1.100 (deploy)
  staging              staging.example.com (admin)
  dev-box              10.0.0.50
──────────────────────────────────────────
Total: 3 hosts
```

## Ajouter un host

```bash
ssh_add mon-serveur
```

Questions interactives :
- Hostname (IP ou domaine)
- Utilisateur
- Port (défaut: 22)
- Fichier de clé (défaut: ~/.ssh/id_rsa)

Résultat dans `~/.ssh/config` :

```
Host mon-serveur
    HostName 192.168.1.100
    User deploy
    Port 22
    IdentityFile ~/.ssh/id_rsa
```

## Copier la clé SSH

```bash
# Copie la clé par défaut
ssh_copy_key mon-serveur

# Copie une clé spécifique
ssh_copy_key mon-serveur ~/.ssh/id_ed25519.pub
```

## Tester une connexion

```bash
ssh_test mon-serveur
# -> Test de connexion à mon-serveur...
# -> Connexion réussie.
```

## Supprimer un host

```bash
# Interactif avec fzf
ssh_remove

# Direct
ssh_remove mon-serveur
```

Crée une backup `~/.ssh/config.bak` avant suppression.
