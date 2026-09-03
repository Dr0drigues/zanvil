#!/usr/bin/env bash
# k9s-log-grep.sh — filtre par expression reguliere les paires produites par
# k9s-log-fmt.sh --pairs, pour le mode regex de k9s-log-view.sh.
#
# Usage : k9s-log-grep.sh <fichier de paires> <motif ERE>
#
# Il existe plutot que d etre un `grep -E` ecrit dans le binding fzf, parce que la
# comparaison ne porte pas sur la ligne telle qu elle est stockee :
#
#   - Seul le TEXTE RENDU compte, soit le champ avant la tabulation. Le champ suivant
#     porte le JSON source, qui repete les memes mots sous d autres noms : un grep sur la
#     ligne entiere ramenerait une ligne pour « level » ou « msg », que l utilisateur ne
#     lit nulle part a l ecran.
#   - Les codes ANSI sont retires avant comparaison. Le rendu est colore, donc une ligne
#     commence par un code de couleur, pas par son heure : sans cela « ^06:49 » ne
#     matcherait jamais, et « 31m » matcherait tout ce qui est rouge.
#
# La ligne, elle, sort entiere : fzf a besoin du JSON source pour l apercu et pour Ctrl-O.
set -uo pipefail

if [[ $# -ne 2 ]]; then
    printf 'k9s-log-grep.sh: usage : %s <fichier> <motif>\n' "${0##*/}" >&2
    exit 2
fi

file="$1"
pattern="$2"

if [[ ! -r "$file" ]]; then
    printf 'k9s-log-grep.sh: fichier illisible : %s\n' "$file" >&2
    exit 2
fi

# Motif vide : tout passe. Sans ce cas, basculer en mode regex viderait l ecran tant que
# rien n est tape, alors que l utilisateur attend la liste entiere.
if [[ -z "$pattern" ]]; then
    cat -- "$file"
    exit 0
fi

# Le motif transite par l environnement, jamais par `awk -v` : celui-ci developpe les
# echappements de la valeur qu il recoit, si bien que « 46\.865 » lui arriverait deja
# reduit a « 46.865 » — le point litteral redevenu joker, en silence.
if ! PAT="$pattern" awk -F'\t' '
    BEGIN { pat = ENVIRON["PAT"] }
    {
        rendered = $1
        gsub(/\033\[[0-9;]*m/, "", rendered)
        if (rendered ~ pat) print
    }
' < "$file" 2>/dev/null; then
    # awk refuse de compiler le motif : il est invalide. C est l etat normal d une regex
    # a moitie tapee (« ERROR.*[ »), pas une panne du viewer. Aucune ligne, aucun bruit,
    # et un code nul : fzf affiche 0 resultat et la frappe continue.
    exit 0
fi
