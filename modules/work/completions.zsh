# ==============================================================================
# Work Completions
# ==============================================================================

(( $+functions[compdef] )) || return 0

# Applications depuis le cache de work_es_apps — lecture fichier uniquement,
# JAMAIS d'appel reseau pendant la completion. Cache perime accepte.
_work_es_cached_apps() {
    local cache="${ZANVIL_DIR:-$HOME/.zanvil}/.work_es_apps_cache"
    if [[ -f "$cache" ]]; then
        local -a apps
        apps=(${(f)"$(tail -n +3 "$cache" 2>/dev/null | cut -f1)"})
        if (( ${#apps} )); then
            _describe -t applications 'application' apps
            return
        fi
    fi
    _message 'application (lancer work_es_apps pour alimenter la completion)'
}

_work_fetch_logs() {
    _arguments \
        '--app[Application a interroger]:app:_work_es_cached_apps' \
        '--since[Plage relative: Xs/Xm/Xh/Xd (ex: 30s, 2h, 7d)]:duration:' \
        '--from[Debut, heure locale Europe/Paris avec DST auto (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--to[Fin, heure locale Europe/Paris avec DST auto (YYYY-mm-ddTHH:MM:SS)]:date:' \
        '--search[Recherche TEXT dans .message, restreint la fenetre aux matches]:text:' \
        '--margin[Padding autour des matches --search (defaut: 1m)]:duration:' \
        '--target-dir[Repertoire de sortie]:directory:_directories' \
        '--format[Format de sortie]:format:(ndjson json text)' \
        '--yes[Passer le garde-fou volumetrique]' \
        '(-h --help)'{-h,--help}'[Afficher l aide]'
}
compdef _work_fetch_logs work_fetch_logs

_work_es_query() {
    _arguments \
        '1:methode ou chemin:(GET POST PUT DELETE HEAD)' \
        '2:chemin ES (ex es-apis-*/_search):' \
        '3:body JSON ou - pour stdin:'
}
compdef _work_es_query work_es_query

_work_es_apps() {
    _arguments \
        '--refresh[Forcer le rafraichissement du cache]' \
        '1:plage Xm/Xh/Xd (defaut 24h):(1h 6h 24h 7d)'
}
compdef _work_es_apps work_es_apps

_work_es_count() {
    _arguments \
        '--app[Application a interroger]:app:_work_es_cached_apps' \
        '--since[Plage relative: Xs/Xm/Xh/Xd]:duration:' \
        '--from[Debut, heure locale Europe/Paris avec DST auto]:date:' \
        '--to[Fin, heure locale Europe/Paris avec DST auto]:date:' \
        '--search[Phrase a chercher dans .message]:text:'
}
compdef _work_es_count work_es_count

_work_es_tail() {
    _arguments \
        '--app[Application a suivre]:app:_work_es_cached_apps' \
        '--search[Phrase a chercher dans .message]:text:' \
        '--interval[Intervalle de poll en secondes (defaut 5, min 2)]:secondes:(2 5 10 30)'
}
compdef _work_es_tail work_es_tail
