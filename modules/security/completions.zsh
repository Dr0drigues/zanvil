(( $+functions[compdef] )) || return 0

_zanvil_audit() {
    local -a subcmds
    subcmds=(
        'perms:Vérifie les permissions des fichiers sensibles'
        'secrets:Recherche des secrets dans les configs'
        'all:Lance tous les checks'
    )
    _describe 'subcommand' subcmds
}

compdef _zanvil_audit zanvil-audit
compdef _zanvil_audit zanvil-audit-fix

_zanvil_secrets_scan() {
    local -a subcmds
    subcmds=(
        'repo:Scanner le repo courant'
        'working-tree:Scanner les fichiers non commités'
        'history:Scanner l'\''historique git'
        'bulk:Scanner plusieurs repos'
        'help:Afficher l'\''aide'
    )
    _describe 'subcommand' subcmds
}

compdef _zanvil_secrets_scan zanvil-secrets-scan
