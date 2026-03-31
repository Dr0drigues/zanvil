# ==============================================================================
# Utils Completions - Completions pour extract, mkcd, bak, cx, trash
# ==============================================================================

(( $+functions[compdef] )) || return 0

_extract() {
    _arguments \
        '1:archive:_files -g "*.tar.gz *.tgz *.tar.bz2 *.tbz2 *.tar.xz *.txz *.zip *.rar *.7z *.gz *.bz2 *.xz"'
}
compdef _extract extract

_mkcd() {
    _arguments \
        '1:directory:_files -/'
}
compdef _mkcd mkcd

_bak() {
    _arguments \
        '1:file:_files'
}
compdef _bak bak

_cx() {
    _arguments \
        '1:file:_files'
}
compdef _cx cx

_trash() {
    _arguments \
        '*:files:_files'
}
compdef _trash trash
