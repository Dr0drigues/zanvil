#!/usr/bin/env bash
# k9s-log-view.sh — explorateur interactif de logs, pilote par fzf.
# Consomme le format --pairs de k9s-log-fmt.sh : <texte rendu>TAB<json source>.
# Ne connait rien du format des logs : il ne manipule que deux champs.
#
# Usage : kubectl logs ... | k9s-log-fmt.sh --pairs | k9s-log-view.sh
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FMT="$SCRIPTS/k9s-log-fmt.sh"
GREP="$SCRIPTS/k9s-log-grep.sh"

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

# --- source rejouable ---------------------------------------------------------
# Jusqu ici le viewer passait son entree a fzf par le pipe. Le mode regex relance un
# filtre externe a chaque frappe et Ctrl-R rejoue kubectl : les deux ont besoin de relire
# les lignes, ce qu un pipe ne permet pas. Elles sont donc deversees dans un fichier
# temporaire, efface a la sortie — y compris sur Esc, que fzf traduit en SIGINT.
#
# Le repli sans fzf, lui, reste en amont : sans explorateur il n y a rien a rejouer, et
# le viewer y demeure un filtre pur.
#
# Le gabarit n est pas un ornement. `mktemp` NU ignore TMPDIR sur macOS — il rend un
# /var/folders/... quoi qu on lui passe — et laisse donc le fichier hors de portee de
# qui voudrait verifier qu il disparait. Il nomme aussi ce qu il cree : un fichier de
# logs de production merite mieux que « tmp.wrtDYOZyp5 » pour qui le croise.
SRC=$(mktemp "${TMPDIR:-/tmp}/k9s-log-view.XXXXXX") || {
    printf 'k9s-log-view.sh: mktemp a echoue\n' >&2; exit 2
}
trap 'rm -f "$SRC"' EXIT INT TERM
cat > "$SRC"

# --- construction des options ------------------------------------------------
strip_ansi='sed "s/\x1b\[[0-9;]*m//g"'

header="ctrl-x regex   ⏎ evenement complet   ? apercu JSON"
opts=(
    --ansi
    --multi
    --no-sort
    # exact : le matching flou de fzf n a pas de sens sur des lignes de log. Il
    # retrouve les lettres d une requete, disperses n importe ou dans la ligne, et
    # celles-ci sont longues : « contact » ramenait 486 evenements sur 500, dont aucun
    # ne contenait le mot — « InsuranceContractDatasource » satisfait c-o-n-t-a-c-t.
    # Le flou reste joignable terme par terme : sous --exact, le prefixe ' le rend.
    --exact
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

# --- mode regex ---------------------------------------------------------------
# fzf ne sait pas filtrer par expression reguliere : sa syntaxe etendue ne connait que
# l exact, les ancres ^ et $, la negation ! et le |. Ctrl-X lui retire donc la recherche
# et la confie a k9s-log-grep.sh, relance a chaque frappe.
#
# La bascule ne tient pas de drapeau a elle : elle lit FZF_INPUT_STATE, que fzf exporte a
# ses processus enfants. « enabled » signifie que fzf filtre lui-meme, « disabled » qu il
# a rendu la main au filtre externe. C est le mecanisme de l integration ripgrep que fzf
# documente, et il a l avantage de ne pas pouvoir se desynchroniser de ce qu on voit.
#
# « change » est delie au demarrage et rebranche seulement en mode regex : tant qu on
# cherche en exact, aucun sous-processus ne part a la frappe.
#
# Le \{q} echappe est voulu : la requete ne doit pas etre substituee dans la commande de
# transform, mais dans le reload que celle-ci produit — sinon une regex a parentheses,
# « gravitee/(sales|supply) », serait recopiee au milieu de la liste d actions et fzf y
# lirait des parentheses a lui.
to_regex="disable-search+change-prompt(regex > )+rebind(change)+reload(\"$GREP\" \"$SRC\" \{q})"
to_exact="enable-search+change-prompt(log > )+unbind(change)+reload(cat \"$SRC\")"
opts+=(
    --bind="start:unbind(change)"
    --bind="change:reload(\"$GREP\" \"$SRC\" {q})"
    --bind="ctrl-x:transform:[ \"\$FZF_INPUT_STATE\" = enabled ] && echo '$to_regex' || echo '$to_exact'"
)

if [[ -n "$clip" ]]; then
    header="ctrl-y copier   ctrl-o JSON   $header"
    opts+=(
        --header="$header"
        # Copie le texte rendu, codes ANSI retires (le sed ne touche pas
        # au texte lui-meme : un indicateur de stack "⤷ ..." est conserve).
        --bind="ctrl-y:execute-silent(printf '%s\n' {+1} | $strip_ansi | $clip)"
        --bind="ctrl-o:execute-silent(printf '%s\n' {+2..} | $clip)"
    )
else
    header="$header   (presse-papier indisponible)"
    opts+=(--header="$header")
fi

# --- rechargement ------------------------------------------------------------
# Le plugin k9s passe dans ZANVIL_K9S_RELOAD la commande qui a produit ces
# lignes. Le viewer n en sait rien de plus : c est une chaine opaque qu il
# rejoue, donc il continue d ignorer d ou viennent ses lignes et quel format
# elles ont. Sans la variable, aucun binding : le viewer reste un filtre pur.
# reload-sync et non reload, pour que la liste ne soit remplacee qu une fois la
# commande terminee — sinon elle se vide le temps de l appel a kubectl.
if [[ -n "${ZANVIL_K9S_RELOAD:-}" ]]; then
    header="ctrl-r recharger   $header"
    opts+=(
        --header="$header"
        # La sortie va d abord dans le fichier : sans cela le mode regex continuerait
        # de filtrer les lignes d avant le rechargement. Le mode courant est relu au
        # moment ou la touche tombe, pour que Ctrl-R ne renvoie pas en exact.
        --bind="ctrl-r:reload-sync($ZANVIL_K9S_RELOAD > \"$SRC\"; if [ \"\$FZF_INPUT_STATE\" = disabled ]; then \"$GREP\" \"$SRC\" {q}; else cat \"$SRC\"; fi)"
    )
fi

fzf "${opts[@]}" < "$SRC" >/dev/null
_exit_normal $?
