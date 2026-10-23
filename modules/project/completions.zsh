# Completions du module project
(( $+functions[compdef] )) || return 0

_project() {
    _arguments '1:sous-commande:(open clean help)'
}
compdef _project project
