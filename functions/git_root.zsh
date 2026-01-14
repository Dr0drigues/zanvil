# Se déplacer à la racine du dépôt Git actuel
# Note: unalias au cas ou un alias 'gr' existe deja (oh-my-zsh, etc.)
unalias gr 2>/dev/null
function gr() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$root" ]; then
    echo "Pas dans un depot Git."
  else
    cd "$root"
  fi
}