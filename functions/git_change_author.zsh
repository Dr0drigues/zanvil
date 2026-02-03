# Permet de changer en masse un auteur de commit par un autre
function gc-author() {
  local old_email=$1
  local new_name=$2
  local new_email=$3

  if [ -z "$old_email" ] || [ -z "$new_name" ] || [ -z "$new_email" ]; then
    echo "Usage: gc-author <OLD_EMAIL> <NEW_NAME> <NEW_EMAIL>"
    return 1
  fi

  git filter-branch --env-filter '
    if [ "$GIT_COMMITTER_EMAIL" = "'"$old_email"'" ]; then
        export GIT_COMMITTER_NAME="'"$new_name"'"
        export GIT_COMMITTER_EMAIL="'"$new_email"'"
    fi
    if [ "$GIT_AUTHOR_EMAIL" = "'"$old_email"'" ]; then
        export GIT_AUTHOR_NAME="'"$new_name"'"
        export GIT_AUTHOR_EMAIL="'"$new_email"'"
    fi
    ' --tag-name-filter cat -- develop..HEAD
}
