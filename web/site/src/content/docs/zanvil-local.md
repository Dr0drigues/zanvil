---
title: Variables par dossier (.zanvil.local)
description: Un fichier .zanvil.local par dossier, chargé au cd, hérité par les sous-dossiers, approuvé une fois et retiré proprement en sortant.
---

Un fichier `.zanvil.local` porte les variables et les fonctions propres à un dossier : le
`KUBECONFIG` d'un projet, l'URL d'une API de recette, un `PATH` enrichi, un utilitaire de
connexion. Il est chargé en entrant dans le dossier, comme avec direnv, et tout ce qu'il a
changé est défait en sortant.

## Le cycle de vie

1. **Premier `cd`** : zanvil affiche le fichier **en entier** et demande « Autoriser ce
   fichier ? ». C'est exactement ce texte, lu une seule fois, qui est ensuite haché et exécuté.
2. **Fichier autorisé** : son empreinte SHA-256 est notée dans `$ZANVIL_DIR/.trusted/`. Les
   `cd` suivants le chargent sans rien demander.
3. **Fichier modifié** : l'empreinte change, la question revient. Un `git pull` qui modifie le
   fichier ne passe donc jamais en silence.
4. **Refus** : rien n'est chargé, et la question n'est plus posée de la session pour ce contenu.
   `zanvil-trust [chemin]` l'autorise plus tard (par défaut, le fichier du dossier courant) et
   recharge aussitôt.
5. **Sortie du dossier** : les variables exportées reprennent leur valeur d'avant (une variable
   ajoutée est retirée, une variable modifiée comme `PATH` est restaurée) et les fonctions
   définies par le fichier sont supprimées.

## L'héritage

En entrant dans un dossier, zanvil applique **toute la chaîne** des `.zanvil.local` présents
entre `$HOME` (exclu) et ce dossier, du plus haut au plus bas : l'enfant l'emporte sur le parent.

```
~/ctf/otw/.zanvil.local            OTW_HOST, OTW_PORT, otw-ssh, otw-next
~/ctf/otw/bandit0/.zanvil.local    OTW_USER=bandit0, OTW_PASSWORD
~/ctf/otw/bandit1/.zanvil.local    OTW_USER=bandit1, OTW_PASSWORD
```

- Dans `bandit0/` : `OTW_HOST` vient du parent, `OTW_USER` de l'enfant.
- Dans un sous-dossier sans fichier (`bandit0/notes/`) : la même chaîne reste en place.
- De `bandit0/` à `bandit1/` : la chaîne est déchargée puis rechargée, `OTW_USER` vaut `bandit1`.
- Un dossier voisin au nom proche (`otw-old/` à côté de `otw/`) n'hérite de rien.
- **Refuser un parent coupe l'héritage** : les fichiers en dessous ne sont pas chargés, même
  s'ils sont autorisés. Le parent est souvent ce qui donne leur sens aux enfants.

Le fichier d'exemple complet, avec la fonction `otw-next` qui crée le dossier du niveau suivant
et son `.zanvil.local`, est dans
[`examples/zanvil.local.overthewire.example`](https://github.com/Dr0drigues/zanvil/blob/main/examples/zanvil.local.overthewire.example).

## Limites

- **Seuls les variables exportées et les fonctions sont défaites.** Une variable non exportée,
  un alias ou une option `setopt` posés par le fichier restent après la sortie.
- **`$HOME` n'est pas couvert** : un `~/.zanvil.local` ne serait jamais chargé. Pour du global,
  utiliser `config.zsh` ou `env.d/`.
- **Le fichier s'exécute** : c'est du zsh, avec les droits de l'utilisateur. Relire ce que
  l'invite affiche avant d'accepter, surtout dans un dépôt cloné.
- `project open` copie le `.zanvil.local` du dépôt dans le worktree de la MR ; `project clean`
  ne le compte pas comme un travail local à garder.
