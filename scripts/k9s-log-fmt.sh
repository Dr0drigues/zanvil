#!/usr/bin/env bash
# k9s-log-fmt.sh — rend des logs JSON au format d'une console logback.
# Filtre pur stdin -> stdout : pas d'etat, pas de fichier temporaire.
# Les codes ANSI sont embarques par jq (\u001b) : le rendu ne depend pas d'un TTY,
# ce qui est necessaire puisque k9s execute le plugin derriere deux pipes.
#
# Usage : kubectl logs ... | k9s-log-fmt.sh [--pairs]
#   (defaut)  rendu multi-ligne : stack trace indentee, champs extra sur 2e ligne
#   --pairs   une ligne par entree : texte, TAB, JSON source (pour k9s-log-view.sh)
set -uo pipefail

pairs=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pairs) pairs=true; shift ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            printf 'k9s-log-fmt.sh: option inconnue : %s\n' "$1" >&2
            exit 2 ;;
    esac
done

JQ_FILTER='
# --- helpers -----------------------------------------------------------------
def c($code; $s): "\u001b[" + $code + "m" + $s + "\u001b[0m";
def pad($n): if length >= $n then . else . + (" " * ($n - length)) end;
def trunc($n): if length > $n then .[0:$n-1] + "…" else . end;

# "2026-07-28T08:00:00.123456Z" -> "08:00:00.123". Chaine vide -> 12 espaces,
# pour que la colonne du niveau reste alignee.
def hhmmss:
  if . == "" then "            "
  else (if test("T") then split("T")[1] else . end) as $t
    | ($t | sub("(Z|[+-][0-9:]+)$"; "")) as $u
    | (if ($u | test("\\."))
       then (($u | split("."))[0] + "." + (($u | split("."))[1][0:3]))
       else $u + ".000" end)
  end;

def level_color:
  if . == "ERROR" or . == "FATAL" or . == "CRITICAL" then "1;31"
  elif . == "WARN" or . == "WARNING" then "1;33"
  elif . == "DEBUG" or . == "TRACE" then "36"
  else "1;32" end;

# Regle logback %logger{36} : au-dela de $max caracteres, chaque segment de
# package est reduit a son initiale, la classe finale etant preservee.
# "com.boulanger.foo.FooService" -> "c.b.f.FooService"
def abbrev_logger($max):
  if length <= $max then .
  else (split(".")) as $p
    | (if ($p | length) > 1
       then (($p[0:-1] | map(.[0:1])) + [$p[-1]]) | join(".")
       else . end)
  end;

# --- rendu -------------------------------------------------------------------
. as $line |
try (
  $line | fromjson |

  (.level // .severity // .lvl // "INFO" | ascii_upcase) as $lvl |
  (.["@timestamp"] // .timestamp // .time // "" | tostring | hhmmss) as $hh |
  (.message // .msg // "" | tostring) as $msg |
  (.thread_name // "" | tostring) as $thr |
  (.logger_name // "" | tostring) as $log |

  (if $thr == "" then "" else "[" + ($thr | trunc(20)) + "] " end) as $thr_plain |
  (if $log == "" then "" else ($log | abbrev_logger(36)) + " " end) as $log_plain |
  (if $thr == "" and $log == "" then "" else "- " end) as $sep |

  # Prefixe sans ANSI : sert a calculer l indentation de la 2e ligne (Task 4).
  ($hh + " " + ($lvl | pad(5)) + " " + $thr_plain + $log_plain + $sep) as $pre_plain |

  (c("2"; $hh) + " " + c($lvl | level_color; $lvl | pad(5)) + " "
   + (if $thr == "" then "" else c("2"; "[" + ($thr | trunc(20)) + "]") + " " end)
   + (if $log == "" then "" else c("36"; ($log | abbrev_logger(36))) + " " end)
   + $sep + $msg) as $head |

  $head

) catch $line
'

jq -Rr --argjson pairs "$pairs" "$JQ_FILTER"
