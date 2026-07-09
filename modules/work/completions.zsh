# ==============================================================================
# Work Completions
# ==============================================================================

(( $+functions[compdef] )) || return 0

_work_fetch_logs() {
    _arguments \
        '--app[Application a interroger]:app:' \
        '--since[Plage relative: Xs/Xm/Xh/Xd (ex: 30s, 2h, 7d)]:duration:' \
        '--from[Debut, heure locale Europe/Paris avec DST auto (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--to[Fin, heure locale Europe/Paris avec DST auto (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--search[Recherche TEXT dans .message, restreint la fenetre aux matches]:text:' \
        '--margin[Padding autour des matches --search (defaut: 1m)]:duration:' \
        '--target-dir[Repertoire de sortie]:directory:_directories' \
        '--format[Format de sortie]:format:(ndjson json text)' \
        '(-h --help)'{-h,--help}'[Afficher l aide]'
}
compdef _work_fetch_logs work_fetch_logs
