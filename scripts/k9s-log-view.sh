#!/usr/bin/env bash
# k9s-log-view.sh — explorateur interactif de logs, pilote par fzf.
# Consomme le format --pairs de k9s-log-fmt.sh : <texte rendu>TAB<json source>.
# Ne connait rien du format des logs : il ne manipule que deux champs.
#
# Usage : kubectl logs ... | k9s-log-fmt.sh --pairs | k9s-log-view.sh
set -uo pipefail

FMT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/k9s-log-fmt.sh"

# --- presse-papier -----------------------------------------------------------
# Resolu une fois : les bindings fzf ne sont construits qu ensuite.
clip=""
if command -v pbcopy >/dev/null 2>&1; then
    clip="pbcopy"
elif command -v wl-copy >/dev/null 2>&1; then
    clip="wl-copy"
elif command -v xclip >/dev/null 2>&1; then
    clip="xclip -selection clipboard"
fi

# --- normalisation du code de sortie -----------------------------------------
# Quitter l explorateur est une sortie normale, pas un echec : fzf rend 130
# (128 + SIGINT) sur Esc / Ctrl-C et 1 quand aucune ligne ne correspond au
# filtre. k9s affiche une popup d erreur des que le plugin sort non nul
# ("command failed ... exit status 130"), donc ces deux codes deviennent 0.
# Le code 2 (vraie erreur fzf) et tout autre code sont conserves.
_exit_normal() {
    case "$1" in
        130|1) exit 0 ;;
        *)     exit "$1" ;;
    esac
}

# --- repli sans fzf ----------------------------------------------------------
# Seul le premier champ est affiche : le JSON source n a d interet qu en
# interactif. sed retire tout ce qui suit la premiere tabulation.
if ! command -v fzf >/dev/null 2>&1; then
    sed 's/\t.*$//' | less -R
    _exit_normal $?
fi

# --- construction des options ------------------------------------------------
strip_ansi='sed "s/\x1b\[[0-9;]*m//g"'

header="⏎ evenement complet   ? apercu JSON"
opts=(
    --ansi
    --multi
    --no-sort
    --delimiter=$'\t'
    --with-nth=1
    --prompt="log > "
    --header="$header"
    --preview="printf '%s' {2..} | jq -C . 2>/dev/null || printf '%s' {2..}"
    # hidden : le panneau demarre replie, la liste occupe toute la largeur.
    # Les lignes rendues sont longues (heure, niveau, thread, logger, message) et
    # le JSON source ne sert qu a l inspection ponctuelle. "?" le deplie.
    --preview-window="right:50%:wrap:hidden"
    --bind="?:toggle-preview"
    --bind="enter:execute(printf '%s' {2..} | \"$FMT\" | less -R)"
)

if [[ -n "$clip" ]]; then
    header="ctrl-y copier   ctrl-o JSON   ⏎ evenement complet   ? apercu JSON"
    opts+=(
        --header="$header"
        # Copie le texte rendu, codes ANSI retires (le sed ne touche pas
        # au texte lui-meme : un indicateur de stack "⤷ ..." est conserve).
        --bind="ctrl-y:execute-silent(printf '%s\n' {+1} | $strip_ansi | $clip)"
        --bind="ctrl-o:execute-silent(printf '%s\n' {+2..} | $clip)"
    )
else
    opts+=(--header="$header   (presse-papier indisponible)")
fi

fzf "${opts[@]}" >/dev/null
_exit_normal $?
