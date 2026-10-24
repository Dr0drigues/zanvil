#!/usr/bin/env bash
# Verifie les scripts Raycast zanvil-theme, kube-context et project-clean : argument transmis
# sans interpretation, confirmation des contextes de production, bascule seulement sur accord.
# Faux osascript/kubectl/glab/jq ; HOME et ZANVIL_DIR jetables. Usage : scripts/tests/raycast-commands.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
has() { grep -q -- "$2" "$T/calls.log" && ok "$1" || { bad "$1 (attendu : $2)"; cat "$T/calls.log"; }; }
hasnt() { grep -q -- "$2" "$T/calls.log" && { bad "$1 (inattendu : $2)"; cat "$T/calls.log"; } || ok "$1"; }

# ZANVIL_DIR jetable : zanvil-theme y ecrit .current_theme
Z="$T/zanvil"; H="$T/home"; B="$T/bin"; S="$T/sysbin"
mkdir -p "$Z" "$H/.kube" "$H/work" "$B" "$S"
# PATH isole : symlinks vers les seuls utilitaires requis (la CI a de vrais kubectl, bat, tmux... dans /usr/bin)
for u in zsh sh bash env cat cp mv rm ln mkdir rmdir touch chmod ls find sort uniq tr sed awk grep head tail cut wc cmp diff date stat dirname basename readlink realpath mktemp printf tee uname sleep id whoami hostname; do
    p=$(command -v "$u" 2>/dev/null) && [[ "$p" == /* ]] && ln -sf "$p" "$S/$u"
done
cp -R "$ROOT/core" "$ROOT/config" "$ROOT/modules" "$ROOT/scripts" "$Z/"
printf 'ctx-dev=full-cluster-dev\nctx-prd=full-cluster-prd\n' > "$H/.kube/.context_aliases"

# faux osascript : enregistre ses arguments ; reponse du dialogue dans $T/dialog (ou echec)
cat > "$B/osascript" <<EOF
#!/bin/sh
echo "osascript \$*" >> "$T/calls.log"
case "\$*" in *"display dialog"*) cat "$T/dialog"; exit \$(cat "$T/dialog.rc") ;; esac
EOF
# faux kubectl : seuls ctx-dev/full-cluster-* existent
cat > "$B/kubectl" <<EOF
#!/bin/sh
echo "kubectl \$*" >> "$T/calls.log"
case "\$*" in
  "config use-context full-cluster-"*) exit 0 ;;
  "config use-context"*) exit 1 ;;
esac
exit 0
EOF
printf "#!/bin/sh\nexit 0\n" > "$B/starship"  # zanvil-theme le demande pour appliquer un theme
for b in glab jq open sketchybar borders; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\nexit 1\n' "$b" "$T" > "$B/$b"
done
chmod +x "$B"/*
touch "$T/calls.log"
for b in osascript kubectl glab jq open sketchybar borders; do
    [[ "$(PATH="$B:$S" command -v $b)" == "$B/$b" ]] || { echo "$b reel atteignable : abandon" >&2; exit 2; }
done
[[ -z "$(PATH="$B:$S" command -v zanvil)" ]] || { echo "zanvil reel atteignable : abandon" >&2; exit 2; }

run() {  # run <script> [arg]
    : > "$T/calls.log"
    env -i HOME="$H" XDG_CONFIG_HOME="$H/.config" PATH="$B:$S" ZANVIL_DIR="$Z" \
        "$Z/scripts/raycast/$1" "${@:2}" >"$T/out" 2>&1
}
nostdout() { [[ ! -s "$T/out" ]] && ok "$1 : rien sur stdout" || { bad "$1 : sortie parasite"; cat "$T/out"; }; }

echo "zanvil-theme"
run zanvil-theme.sh forge
[[ "$(cat "$Z/.current_theme" 2>/dev/null)" == forge ]] && ok "le theme du dropdown atteint zanvil-theme" || { bad "theme non applique"; cat "$T/out"; }
nostdout zanvil-theme
run zanvil-theme.sh inexistant
has "theme inconnu : notification" 'osascript.*Thème non appliqué : inexistant'

echo "kube-context"
printf 'button returned:Basculer\n' > "$T/dialog"; echo 0 > "$T/dialog.rc"
run kube-context.sh ctx-dev
has "non-prod : bascule" 'use-context full-cluster-dev'
hasnt "non-prod : pas de dialogue" 'display dialog'
has "non-prod : notification" 'osascript.*Contexte : ctx-dev'
nostdout kube-context

printf 'button returned:Annuler\n' > "$T/dialog"
run kube-context.sh ctx-prd
has "prod : dialogue" 'frontmost application.*display dialog.*icon caution'
hasnt "prod + Annuler : pas de bascule" 'use-context'

echo 1 > "$T/dialog.rc"; echo "User canceled. (-128)" > "$T/dialog"  # annulation reelle d'osascript
run kube-context.sh ctx-prd
hasnt "annulation : pas de bascule" 'use-context'
has "annulation : notification" 'osascript.*Bascule annulée'

: > "$T/dialog"
run kube-context.sh ctx-prd
hasnt "dialogue en echec : pas de bascule" 'use-context'
has "dialogue en echec : notification" 'osascript.*Confirmation impossible'

printf 'button returned:Basculer\n' > "$T/dialog"; echo 0 > "$T/dialog.rc"
run kube-context.sh ctx-prd
has "prod + Basculer : bascule" 'use-context full-cluster-prd'
run kube-context.sh other-prod
has "nom en -prod : dialogue" 'display dialog'
run kube-context.sh aks-x-prd-common-001
has "segment -prd au milieu : dialogue" 'display dialog'
run kube-context.sh aks-x-PROD
has "-PROD en majuscules : dialogue" 'display dialog'
run kube-context.sh aks-x-prdx-dev
hasnt "-prdx n'est pas prod : pas de dialogue" 'display dialog'
printf 'ctx-new=aks-y-prd-001\n' >> "$H/.kube/.context_aliases"
run kube-context.sh ctx-new
has "alias dont le contexte est prod : dialogue" 'display dialog'
printf 'ctx-old=full-cluster-dev\nsafe-prd=full-cluster-dev\n' >> "$H/.kube/.context_aliases"
run kube-context.sh full-cluster-dev
has "alias -prd pointant le contexte : dialogue" 'display dialog'

run kube-context.sh "x\"; touch $T/pwned; \""
[[ -e "$T/pwned" ]] && bad "argument interprete" || ok "argument avec guillemets non interprete"
has "argument transmis tel quel" 'use-context x"; touch'

echo "kubectl absent"
# le script ajoute les chemins Homebrew a PATH : impossible de masquer un kubectl installe la
if [[ -x /opt/homebrew/bin/kubectl || -x /usr/local/bin/kubectl ]]; then echo "  skip kubectl reel dans un chemin Homebrew"; else
    mv "$B/kubectl" "$T/kubectl.off"
    run kube-context.sh ctx-old
    has "kubectl absent : notification" 'osascript.*kubectl introuvable'
    mv "$T/kubectl.off" "$B/kubectl"
fi

echo "project-clean"
rmdir "$H/work"  # WORK_DIR absent : project clean s'arrete avec sa propre notification
run project-clean.sh
has "project clean execute (sa notification)" 'osascript.*WORK_DIR absent'
nostdout project-clean
mkdir "$H/work"  # rien a retirer
run project-clean.sh
has "rien a faire : notification" 'osascript.*Aucun worktree à retirer'
exit $fail
