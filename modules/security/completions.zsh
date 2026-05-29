(( $+functions[compdef] )) || return 0

_zsh_env_audit() {
    local -a subcmds
    subcmds=(
        'perms:Vérifie les permissions des fichiers sensibles'
        'secrets:Recherche des secrets dans les configs'
        'all:Lance tous les checks'
    )
    _describe 'subcommand' subcmds
}

compdef _zsh_env_audit zsh-env-audit
compdef _zsh_env_audit zsh-env-audit-fix

_zsh_env_secrets_scan() {
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

compdef _zsh_env_secrets_scan zsh-env-secrets-scan
