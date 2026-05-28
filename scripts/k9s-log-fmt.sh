#!/usr/bin/env bash
# k9s-log-fmt.sh — Formatte les logs JSON ligne par ligne avec couleurs ANSI
# Utilise jq pour parser, codes ANSI embarqués dans les strings (TTY-indépendant)
# Usage : kubectl logs ... | k9s-log-fmt.sh | less -R +G

JQ_FILTER='
. as $line |
try (
  $line | fromjson |

  (.level // .severity // .lvl // "INFO" | ascii_upcase) as $lvl |
  (if $lvl == "ERROR" or $lvl == "FATAL" or $lvl == "CRITICAL"
   then "[1;31m"
   elif $lvl == "WARN" or $lvl == "WARNING"
   then "[1;33m"
   elif $lvl == "DEBUG" or $lvl == "TRACE"
   then "[36m"
   else "[1;32m"
   end) as $lc |

  (.["@timestamp"] // .timestamp // .time // "") as $ts |
  (.message // .msg // "") as $msg |

  (del(
    .["@timestamp"], .timestamp, .time,
    .level, .severity, .lvl,
    .message, .msg,
    .trace_id, .span_id, .trace_flags,
    .logger_name, .thread_name
  ) | to_entries | map("\(.key)=\(.value|tostring)") | join("  ")) as $extra |

  "[2m\($ts)[0m \($lc)|\($lvl)|[0m \($msg)" +
  (if $extra != "" then "\n         [2m\($extra)[0m" else "" end)

) catch $line
'

jq -Rr "$JQ_FILTER"
