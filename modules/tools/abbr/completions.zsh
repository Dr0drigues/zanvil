(( $+functions[compdef] )) || return 0
_zanvil_abbr() { _arguments "1:action:(import help)" "2:option:(--apply)" }
compdef _zanvil_abbr zanvil-abbr
