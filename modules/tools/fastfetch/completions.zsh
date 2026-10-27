# Completions zfetch
(( $+functions[compdef] )) || return 0

_zfetch() {
    _arguments '1:preset:(full work minimal palette banner)' '2:theme:_files -W "$ZANVIL_DIR/config/themes" -/'
}
compdef _zfetch zfetch
