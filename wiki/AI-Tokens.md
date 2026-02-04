# AI Tokens Optimizer

Estimation et optimisation des tokens envoyes aux LLMs (Claude, GPT, etc.).

## Presentation

Le module `ai-tokens` (alias `ait`) permet de:
- Estimer le nombre de tokens avant envoi
- Analyser un projet avec details et suggestions
- Compresser le contexte (supprimer commentaires, espaces)
- Selectionner intelligemment les fichiers pertinents
- Exporter un contexte optimise

## Commandes

### Estimation de tokens

```bash
# Estimer un fichier
ai-tokens estimate src/index.ts

# Estimer un dossier
ai-tokens estimate src/

# Estimer depuis stdin (pipe)
cat package.json | ai-tokens estimate

# Alias court
ait estimate .
```

Sortie:
```
Estimation: src/index.ts
===================
  Caracteres: 2450
  Tokens:     ~612

Cout estime (input):
--------------------
  claude-3.5-sonnet:   $0.0018
  claude-3-haiku:      $0.0002
  gpt-4-turbo:         $0.0061
  gpt-3.5-turbo:       $0.0003
```

### Analyse de projet

```bash
# Analyse complete du projet courant
ai-tokens analyze

# Analyser un dossier specifique
ai-tokens analyze ~/projects/mon-app
```

Sortie:
```
Analyse: /home/user/mon-app
==========================================

Resume:
-------
  Fichiers analyses: 45
  Caracteres total:  125,000
  Tokens estimes:    ~31,250

Top 10 fichiers (par tokens):
-----------------------------
     5,234 tokens  src/components/Dashboard.tsx
     3,891 tokens  src/services/api.ts
     2,456 tokens  src/utils/helpers.ts
     ...

Cout estime (input):
--------------------
  claude-3.5-sonnet:   $0.0938
  claude-3-haiku:      $0.0078
  gpt-4-turbo:         $0.3125
  gpt-3.5-turbo:       $0.0156

Suggestions d'optimisation:
---------------------------
  - 3 fichier(s) > 5000 tokens: envisagez de les resumer ou exclure
  - Excluez les fichiers lock (package-lock.json, yarn.lock)
```

### Compression de contenu

```bash
# Compresser un fichier (supprime commentaires et espaces excessifs)
ai-tokens compress src/utils.ts

# Compresser et sauvegarder
ai-tokens compress src/utils.ts > src/utils.compressed.ts

# Specifier le langage
ai-tokens compress script.txt python
```

La compression:
- Supprime les commentaires (`//`, `/* */`, `#`, `<!-- -->`)
- Supprime les docstrings Python
- Reduit les lignes vides multiples
- Supprime les espaces en fin de ligne
- Reduit l'indentation excessive

### Selection intelligente

```bash
# Selectionner les fichiers pertinents pour une tache
ai-tokens select . "authentication"

# Limiter le nombre de tokens
ai-tokens select . "database" --max-tokens=50000
```

Le scoring prend en compte:
- Extension du fichier (priorite aux fichiers code)
- Position (fichiers racine bonus)
- Fichiers de config importants (README, package.json)
- Correspondance avec la query
- Malus pour les fichiers de test (sauf si query contient "test")

### Export de contexte

```bash
# Exporter le contexte du projet
ai-tokens export . > context.txt

# Exporter avec compression
ai-tokens export . --compress > context.txt

# Limiter a 50000 tokens
ai-tokens export . --max-tokens=50000 > context.txt

# Combiner les options
ai-tokens export . --compress --max-tokens=30000 > context.txt
```

## Fichiers ignores

Par defaut, ces dossiers sont exclus:
- `node_modules`, `.git`, `dist`, `build`, `target`
- `__pycache__`, `.pytest_cache`, `vendor`
- `.idea`, `.vscode`, `coverage`
- `tmp`, `temp`, `cache`

Et ces fichiers:
- `*.min.js`, `*.min.css`, `*.map`
- `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- Images, videos, archives, binaires

## Modeles supportes

Les estimations de cout sont calculees pour:

| Modele | Prix / 1M tokens (input) |
|--------|--------------------------|
| Claude 3.5 Sonnet | $3.00 |
| Claude 3 Opus | $15.00 |
| Claude 3 Haiku | $0.25 |
| GPT-4 Turbo | $10.00 |
| GPT-3.5 Turbo | $0.50 |

## Algorithme d'estimation

L'estimation utilise l'approximation:
- ~4 caracteres = 1 token (moyenne pour code/anglais)
- Ajustement pour les retours a la ligne

Cette estimation est approximative. Pour une precision exacte, utilisez les tokenizers officiels (tiktoken pour OpenAI, etc.).

## Cas d'usage

### Preparer un contexte pour Claude Code

```bash
# Analyser le projet
ai-tokens analyze .

# Selectionner les fichiers pertinents
ai-tokens select . "feature-to-implement"

# Exporter un contexte optimise
ai-tokens export . --compress --max-tokens=80000 > context.md
```

### Reduire les couts

```bash
# Identifier les fichiers volumineux
ai-tokens analyze .

# Compresser les fichiers critiques
for f in src/large/*.ts; do
  ai-tokens compress "$f" > "${f%.ts}.min.ts"
done
```

### Integration CI/CD

```bash
# Verifier que le contexte ne depasse pas une limite
tokens=$(ai-tokens estimate . | grep "Tokens:" | awk '{print $2}')
if [[ $tokens -gt 100000 ]]; then
  echo "Warning: context too large ($tokens tokens)"
fi
```

## Voir aussi

- [AI Context](AI-Context) - Generation de fichiers de contexte IA
- [Project Switcher](Project-Switcher) - Gestion des contextes projet
