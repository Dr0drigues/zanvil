# Plan : Migration NVM + SDKMAN → mise

## Contexte

NVM et SDKMAN gèrent respectivement Node.js et Java/Maven avec ~400 lignes de code custom (lazy loading, auto-switch chpwd, sdk-sync, wrapper avec hooks Work). **mise** (https://mise.jdx.dev/) est un gestionnaire polyglotte qui remplace les deux avec :
- Auto-switch natif (.nvmrc, .sdkmanrc, .tool-versions, .mise.toml)
- Activation ultra-rapide (~2ms, pas besoin de lazy loading)
- Hooks postinstall par outil
- Support Node, Java (temurin, openjdk, zulu, corretto), Maven, Python, Go, etc.

**Résultat attendu** : suppression de ~350 lignes de code custom, un seul outil, startup plus rapide.

---

## Fichiers à SUPPRIMER (3)

| Fichier | Raison |
|---------|--------|
| `functions/nvm_auto.zsh` | Auto-switch géré nativement par mise |
| `functions/sdk_sync.zsh` | `mise install` lit .sdkmanrc/.tool-versions nativement |
| `spec/nvm_t3_spec.sh` | Tests obsolètes (load-nvmrc n'existe plus) |

## Fichiers à CRÉER (1)

| Fichier | Rôle |
|---------|------|
| `functions/mise_hooks.zsh` | Hooks Work pour mise (certificats Java, settings Maven) + commande `mise-configure` |

## Fichiers à MODIFIER (11)

| Fichier | Changements |
|---------|------------|
| `install.sh` | Ajouter mise via `install_tool` + fallback Linux, supprimer blocs NVM/SDKMAN, MAJ config interactive |
| `hooks.zsh` | Supprimer sections NVM (42-103) et SDKMAN (105-111), ajouter `eval "$(mise activate zsh)"` |
| `rc.zsh` | `ZSH_ENV_MODULE_MISE` remplace `ZSH_ENV_MODULE_NVM`, supprimer `ZSH_ENV_NVM_LAZY`, ajouter shim de rétrocompatibilité |
| `functions/sdk_wrapper.zsh` | Supprimer (remplacé par `mise_hooks.zsh`) |
| `functions/project_switcher.zsh` | Remplacer `nvm use/install` par `mise use/install` (lignes 85-100) |
| `functions/zsh_env_commands.zsh` | MAJ zsh-env-list, zsh-env-doctor, zsh-env-status : mise au lieu de NVM/SDKMAN |
| `functions/work_context.zsh` | MAJ blg_status() : mise au lieu de SDKMAN (lignes 199-204) |
| `config.zsh.example` | `ZSH_ENV_MODULE_MISE`, supprimer `ZSH_ENV_NVM_LAZY`, nouvelle section Mise |
| `spec/rc_spec.sh` | Remplacer `ZSH_ENV_MODULE_NVM`/`ZSH_ENV_NVM_LAZY` par `ZSH_ENV_MODULE_MISE` |
| `spec/TODO.md` | Remplacer section NVM par section Mise |
| `CLAUDE.md` | MAJ architecture, flux de chargement, description |

---

## Étapes d'implémentation

### Étape 1 : `install.sh` — Installation de mise

**1a.** Ajouter mise dans la section `install_tool` (après ligne 157) :
```bash
# 5. Gestionnaire de versions (mise - remplace NVM + SDKMAN)
install_tool "mise" "mise" "" ""
```
→ macOS : `brew install mise`. apt/dnf : vide (fallback ci-dessous).

**1b.** Ajouter fallback Linux (même pattern que starship, après ligne 175) :
```bash
if ! command -v mise &> /dev/null; then
    log_info "Installation manuelle de mise..."
    log_warn "Le script d'installation est telecharge depuis mise.jdx.dev (HTTPS)"
    curl -sS --proto '=https' --tlsv1.2 https://mise.jdx.dev/install.sh | sh
fi
```

**1c.** Configurer mise pour supporter `.nvmrc` et `.sdkmanrc` :
```bash
if command -v mise &> /dev/null; then
    mise settings set idiomatic_version_file true 2>/dev/null
fi
```

**1d.** Supprimer bloc NVM (lignes 177-201) et bloc SDKMAN (lignes 224-237).

**1e.** MAJ config interactive — remplacer :
```bash
MODULE_NVM=$(ask_module "NVM" "Auto-switch Node.js via .nvmrc" "true")
NVM_LAZY="true"
if [ "$MODULE_NVM" = "true" ]; then
    NVM_LAZY=$(ask_module "NVM Lazy" ...)
fi
```
Par :
```bash
MODULE_MISE=$(ask_module "Mise" "Gestionnaire de versions (Node, Java, Maven, etc.)" "true")
```

**1f.** MAJ mode `--default` : `MODULE_MISE="true"`, supprimer `NVM_LAZY`.

**1g.** MAJ config.zsh générée : `ZSH_ENV_MODULE_MISE=$MODULE_MISE`, supprimer lignes NVM_LAZY.

**1h.** MAJ résumé d'installation : remplacer le bloc NVM par Mise.

### Étape 2 : `hooks.zsh` — Activation

Supprimer sections NVM (lignes 42-103) et SDKMAN (lignes 105-111). Remplacer par :
```zsh
# =======================================================
# MISE (Gestionnaire de versions: Node, Java, Maven, etc.)
# =======================================================
if [ "$ZSH_ENV_MODULE_MISE" = "true" ]; then
    if command -v mise &> /dev/null; then
        eval "$(mise activate zsh)"
    fi
fi
```

### Étape 3 : `rc.zsh` — Module system

**3a.** Remplacer `ZSH_ENV_MODULE_NVM` par `ZSH_ENV_MODULE_MISE` (ligne 26).

**3b.** Supprimer `ZSH_ENV_NVM_LAZY` (ligne 35).

**3c.** Ajouter shim de rétrocompatibilité (après ligne 38, après sourcing config.zsh) :
```zsh
# Backward compat: NVM -> mise
if [[ -n "$ZSH_ENV_MODULE_NVM" && -z "$ZSH_ENV_MODULE_MISE" ]]; then
    ZSH_ENV_MODULE_MISE="$ZSH_ENV_MODULE_NVM"
    unset ZSH_ENV_MODULE_NVM ZSH_ENV_NVM_LAZY
fi
```

**3d.** MAJ commentaire ligne 13 : remplacer `nvm, sdkman` par `mise`.

### Étape 4 : Supprimer `functions/nvm_auto.zsh`

Fichier entier remplacé par l'auto-switch natif de mise.

### Étape 5 : `functions/sdk_wrapper.zsh` → Supprimer + Créer `functions/mise_hooks.zsh`

Nouveau fichier `mise_hooks.zsh` qui :
- Garde les hooks Work (`_mise_hook_java`, `_mise_hook_maven`) adaptés aux chemins mise (`~/.local/share/mise/installs/<tool>/<version>/`)
- Wrappe `mise install` pour appliquer les hooks en contexte Work (même pattern que l'ancien wrapper sdk)
- Fournit `mise-configure <tool> [version]` (remplace `sdk-configure`)
- Completion zsh pour `mise-configure`

### Étape 6 : Supprimer `functions/sdk_sync.zsh`

`mise install` lit nativement `.tool-versions`/`.mise.toml`/`.sdkmanrc`.

### Étape 7 : `functions/project_switcher.zsh` — Node switching

Remplacer lignes 85-100 : `nvm use/install` → `mise use node@<version>`.
Aussi détecter `.tool-versions` et `.mise.toml` en plus de `.nvmrc`.
MAJ help et template `proj_init`.

### Étape 8 : `functions/zsh_env_commands.zsh`

- `zsh-env-list()` : remplacer entrées "nvm"/"sdk" par "mise", MAJ version detection
- `zsh-env-doctor()` : remplacer bloc NVM (lignes 441-461) par bloc Mise avec versions actives
- `zsh-env-status()` : remplacer NVM par Mise (lignes 543-552)

### Étape 9 : `functions/work_context.zsh`

`blg_status()` lignes 199-204 : remplacer SDKMAN par mise.

### Étape 10 : `config.zsh.example`

Remplacer `ZSH_ENV_MODULE_NVM` par `ZSH_ENV_MODULE_MISE`, supprimer section NVM Lazy, ajouter section Mise avec commentaire vers la doc.

### Étape 11 : Tests

- Supprimer `spec/nvm_t3_spec.sh`
- Créer `spec/mise_t3_spec.sh` : tests mockés pour mise-configure (usage, unsupported tool), vérification que hooks.zsh référence `ZSH_ENV_MODULE_MISE`
- MAJ `spec/rc_spec.sh` : `ZSH_ENV_MODULE_NVM` → `ZSH_ENV_MODULE_MISE`, supprimer tests `ZSH_ENV_NVM_LAZY`
- MAJ `spec/TODO.md` : section NVM → section Mise

### Étape 12 : `CLAUDE.md`

MAJ description, architecture (nvm_auto.zsh → mise_hooks.zsh), flux de chargement, supprimer références sdk_wrapper/sdk_sync.

---

## Rétrocompatibilité

Les utilisateurs existants avec `config.zsh` contenant `ZSH_ENV_MODULE_NVM=true` sont couverts par le shim dans `rc.zsh` (Étape 3c). Au prochain `install.sh`, le nouveau `config.zsh` sera généré avec `ZSH_ENV_MODULE_MISE`.

---

## Vérification

1. **Tests unitaires** : `shellspec` doit passer avec les nouveaux/modifiés specs
2. **install.sh --default** : vérifier que mise est installé, config.zsh contient `ZSH_ENV_MODULE_MISE=true`
3. **Shell reload** : `source ~/.zshrc` sans erreur, `mise --version` disponible
4. **Auto-switch** : créer un dossier avec `.nvmrc` contenant `20`, y entrer → `node -v` = v20.x
5. **Work hooks** : en contexte BLG, `mise install java@temurin-21` déclenche l'import de certificats
6. **mise-configure** : `mise-configure java` applique les certificats sur la version active
7. **Commandes status** : `zsh-env-doctor`, `zsh-env-list`, `zsh-env-status` affichent mise correctement
8. **Rétrocompat** : avec un ancien `config.zsh` (ZSH_ENV_MODULE_NVM=true), le module mise s'active quand même
