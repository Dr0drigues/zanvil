# ==============================================================================
# AI Completions - Completions pour ai-context et ai-tokens
# ==============================================================================

(( $+functions[compdef] )) || return 0

_ai_context() {
    local commands=(
        'detect:Affiche les informations detectees du projet'
        'init:Cree un fichier .ai-context.yml'
        'generate:Genere les fichiers de contexte'
        'templates:Liste les templates disponibles'
        'help:Affiche aide'
    )

    _arguments \
        '1:command:->command' \
        '*:args:->args'

    case $state in
        command)
            _describe 'command' commands
            ;;
        args)
            case $words[2] in
                generate|gen|g)
                    _arguments \
                        '-f[Force overwrite]' \
                        '--force[Force overwrite]' \
                        '1:directory:_files -/'
                    ;;
                detect|d|init|i)
                    _arguments '1:directory:_files -/'
                    ;;
            esac
            ;;
    esac
}
compdef _ai_context ai-context

_ai_tokens() {
    local commands=(
        'estimate:Estime les tokens (fichier, dossier ou stdin)'
        'analyze:Analyse detaillee avec suggestions'
        'compress:Compresse le contenu (supprime commentaires)'
        'select:Selectionne les fichiers pertinents'
        'export:Exporte le contexte optimise'
        'help:Affiche aide'
    )

    _arguments \
        '1:command:->command' \
        '*:args:->args'

    case $state in
        command)
            _describe 'command' commands
            ;;
        args)
            case $words[2] in
                estimate|est|e|analyze|analyse|a|select|sel|s)
                    _arguments '1:target:_files'
                    ;;
                compress|comp|c)
                    _arguments \
                        '1:file:_files' \
                        '2:language:(js ts py python go rust java c cpp sh bash zsh html)'
                    ;;
                export|exp|x)
                    _arguments \
                        '1:directory:_files -/' \
                        '--compress[Compresse le contenu]' \
                        '-c[Compresse le contenu]' \
                        '--max-tokens=[Limite de tokens]:tokens:'
                    ;;
            esac
            ;;
    esac
}
compdef _ai_tokens ai-tokens
compdef _ai_tokens ait
