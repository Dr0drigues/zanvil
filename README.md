# ZSH Environment & Productivity Suite

Une configuration Zsh robuste, modulaire et orientée productivité pour Développeurs (MacOS & Linux).
Ce projet automatise l'installation des outils modernes (`zoxide`, `starship`, `eza`, `nvm`) et fournit des fonctions avancées pour Git et Docker.

## Installation Rapide

1. **Cloner le repo** (Idéalement dans `~/.zsh_env`) :

    ```bash
   git clone git@github.com:Dr0drigues/zsh_env.git ~/.zsh_env
    ```

2. Lancer le script d'installation :

    ```bash
    cd ~/.zsh_env
    ./install.sh
    ```

_Ce script installe les dépendances (via brew/apt/dnf), configure NVM (avec fallback dynamique sur Linux) et modifie votre .zshrc automatiquement._

## Fonctionnalités clés

1. Navigation Intelligente
    - Auto-Jump (z) : Plus besoin de `cd`. Tapez `z front` pour aller dans .../front-toto. Le système "apprend" vos dossiers fréquents (basé sur `zoxide`).

    - Auto-CD : Tapez juste le chemin d'un dossier (`../utils`) pour y entrer.

    - mkcd : `mkcd mon_dossier` crée le dossier et rentre dedans immédiatement.

2. Gestion de Projets & Git

- Clone Intelligent (gclone) :

    ```bash
    gclone git@github.com:org/projet.git
    ```

  - Clone le projet.

  - Entre dedans automatiquement.

  - L'ajoute à l'index de navigation (z).

- GitLab Mass Clone : Des alias comme gc-frontco-ptf pour cloner/mettre à jour des groupes entiers de projets (basé sur scripts/clone-projects.sh).

1. Node.js & NVM Automatique

   - Auto-Switch : En entrant dans un dossier contenant un `.nvmrc`, l'environnement change automatiquement de version Node.

   - Installation Auto : Si la version requise n'est pas installée, il propose de l'installer.

   - Cross-Platform : Fonctionne aussi bien sur macOS (Brew) que sur Linux (Install manuelle).

2. Docker & Système

    - `dex` : Liste les conteneurs actifs et permet d'y entrer via une interface interactive (FZF).

    - `fkill` : Tuer un processus via une recherche interactive.

    - `trash` : Remplace rm pour envoyer dans la corbeille système au lieu de supprimer définitivement.

## Configuration & Personnalisation

Ne modifiez pas les fichiers du repo directement pour faciliter les mises à jour.

- Secrets : Créez `~/.secrets` ou `~/.gitlab_secrets` pour vos tokens API.

- Variables Locales : Le fichier `variables.zsh` définit vos dossiers de travail (`$WORK_DIR`).

### Structure du projet

```text
~/.zsh_env/
├── install.sh          # Bootstrapper (Install deps + Config .zshrc)
├── rc.zsh              # Point d'entrée sourcé par .zshrc
├── aliases.zsh         # Alias globaux (ls, git, ..)
├── functions/          # Fonctions chargées dynamiquement
│   ├── nvm_auto.zsh    # Logique NVM & Auto-switch
│   ├── gitlab_logic.zsh
│   └── ...
└── scripts/            # Scripts autonomes (clone-projects.sh)
```

## Astuces

- `ss` : Recharge la configuration Zsh instantanément.

- `please` : Relance la dernière commande avec sudo.

- `extract` : Décompresse n'importe quelle archive (.tar, .zip, .gz) sans se soucier de la syntaxe.
