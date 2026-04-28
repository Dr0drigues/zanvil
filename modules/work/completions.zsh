# ==============================================================================
# Work Completions
# ==============================================================================

(( $+functions[compdef] )) || return 0

_work_fetch_logs() {
    _arguments \
        '--app[Application a interroger]:app:' \
        '--since[Plage relative: Xm/Xh/Xd (ex: 30m, 2h, 7d)]:duration:' \
        '--from[Debut UTC+1 (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--to[Fin UTC+1 (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--target-dir[Repertoire de sortie]:directory:_directories' \
        '--format[Format de sortie]:format:(ndjson json text)' \
        '(-h --help)'{-h,--help}'[Afficher l aide]'
}
compdef _work_fetch_logs work_fetch_logs
