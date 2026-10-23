# ==============================================================================
# Module project : ouvre une MR GitLab dans un worktree sous $WORK_DIR
# ==============================================================================

# _project_parse_mr <url> : reply=(hote chemin-projet iid), code 1 si pas un lien de MR
_project_parse_mr() {
    reply=()
    [[ "$1" =~ '^https?://([^/]+)/(.+)/-/merge_requests/([0-9]+)' ]] || return 1
    # le chemin devient un dossier sous $WORK_DIR : aucun segment vide, '.' ou '..'
    [[ "/${match[2]}/" == *(//|/./|/../)* ]] && return 1
    reply=("${match[1]}" "${match[2]}" "${match[3]}")
}

_project_repo_dir() { print -r -- "$WORK_DIR/$1"; }

# _project_worktree_dir <chemin-projet> <branche>
_project_worktree_dir() {
    local parent="${1%/*}" repo="${1##*/}"
    print -r -- "$WORK_DIR/$parent/.worktrees/$repo/${2//\//-}"
}

_project_notify() {
    command -v osascript &>/dev/null \
        && osascript -e 'on run a' -e 'display notification (item 1 of a) with title "zanvil project"' -e 'end run' -- "$1" &>/dev/null
    [[ -t 1 ]] && _ui_msg_warn "$1"
    return 0
}

# _project_first_missing <dossier> : premier ancetre (ou lui-meme) a creer ; code 1 s'il existe deja
_project_first_missing() {
    local d="$1"
    [[ -e "$d" ]] && return 1
    while [[ ! -e "${d:h}" ]]; do d="${d:h}"; done
    print -r -- "$d"
}

# _project_abort <message> [dossier-cree...] : retire ce que cet appel a cree, notifie, code 1
_project_abort() {
    (( $# > 1 )) && rm -rf -- "${@:2}"
    _project_notify "$1"
    return 1
}

# _project_pushed <depot> <branche> <commit> [valeur-avant-fetch] : le commit est dans une valeur
# connue de origin/<branche> (avant le fetch ou dans son reflog), donc deja dans la MR meme si la
# branche a ete reecrite depuis.
# shortcut: le clone n'ecrit pas de reflog ; si un fetch externe a suivi un force-push, la valeur
# d'origine est perdue et l'on s'arrete (sur) au lieu d'aligner ; garder un fichier d'etat si ca gene.
_project_pushed() {
    local h
    for h in ${4:+"$4"} ${(f)"$(git -C "$1" reflog show --format=%H "refs/remotes/origin/$2" 2>/dev/null)"}; do
        git -C "$1" merge-base --is-ancestor "$3" "$h" 2>/dev/null && return 0
    done
    return 1
}

# _project_open <lien-de-MR> : worktree sur la branche de la MR, onglet Orca, IDEA.
# Code 1 apres une notification ; rien n'est laisse sous $WORK_DIR si le worktree n'existe pas.
_project_open() {
    local url="$1" mr_host mr_path iid
    _project_parse_mr "$url" || { _project_notify "Pas un lien de MR GitLab : $url"; return 1; }
    mr_host="${reply[1]}" mr_path="${reply[2]}" iid="${reply[3]}"
    url="https://$mr_host/$mr_path/-/merge_requests/$iid"
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] || { _project_notify "WORK_DIR absent : ${WORK_DIR:-non defini}"; return 1; }
    command -v glab &>/dev/null || { _project_notify "glab introuvable"; return 1; }
    command -v jq &>/dev/null || { _project_notify "jq introuvable"; return 1; }

    local json f
    json=$(GITLAB_HOST="$mr_host" glab mr view "$iid" -R "$mr_path" -F json 2>/dev/null) \
        || { _project_notify "MR !$iid introuvable sur $mr_host ($mr_path)"; return 1; }
    f=("${(@f)$(print -r -- "$json" | jq -r '.state, .source_branch, .sha, .source_project_id, .target_project_id' 2>/dev/null)}")
    local state="${f[1]}" branch="${f[2]}"
    [[ "${f[4]}" == "${f[5]}" ]] || { _project_notify "MR d'un fork : non prise en charge"; return 1; }
    # la branche vient de GitLab : refuser tout nom que git n'accepterait pas (option, '..', etc.)
    [[ -n "$branch" && "$branch" != null ]] && git check-ref-format --branch "$branch" &>/dev/null \
        || { _project_notify "MR !$iid : branche source illisible"; return 1; }

    local repo wt; local -a created
    repo=$(_project_repo_dir "$mr_path")
    wt=$(_project_worktree_dir "$mr_path" "$branch")
    if [[ ! -d "$repo" ]]; then
        created=("$(_project_first_missing "$repo")")
        mkdir -p "${repo:h}" && glab repo clone "$mr_path" "$repo" &>/dev/null \
            || { _project_abort "Clone de $mr_path impossible" $created; return; }
    fi
    local before_fetch=$(git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$branch")
    git -C "$repo" fetch --quiet origin "$branch" &>/dev/null \
        || { _project_abort "Branche $branch introuvable sur origin (MR $state)" $created; return; }
    [[ "$(git -C "$repo" symbolic-ref -q --short HEAD)" == "$branch" ]] \
        && { _project_abort "$branch est extraite dans $repo : rien n'est touche" $created; return; }

    local remote="origin/$branch"
    if [[ ! -e "$wt" ]]; then
        if git -C "$repo" show-ref -q --verify "refs/heads/$branch"; then
            git -C "$repo" merge-base --is-ancestor "$branch" "$remote" \
                || { _project_abort "Branche locale $branch divergente de $remote : rien n'est touche" $created; return; }
            git -C "$repo" branch -f "$branch" "$remote" &>/dev/null \
                || { _project_abort "Branche locale $branch impossible a avancer" $created; return; }
        fi
        created+=("$(_project_first_missing "$wt")")
        git -C "$repo" worktree add --quiet "$wt" "$branch" &>/dev/null \
            || { _project_abort "Worktree $wt impossible" $created; return; }
    else
        [[ -e "$wt/.git" && "$(git -C "$wt" symbolic-ref -q --short HEAD)" == "$branch" ]] \
            || { _project_notify "$wt n'est pas un worktree sur $branch : rien n'est touche"; return 1; }
        [[ -z "$(git -C "$wt" status --porcelain)" ]] \
            || { _project_notify "Modifications en cours dans $wt : rien n'est touche"; return 1; }
        _project_pushed "$repo" "$branch" "$(git -C "$wt" rev-parse HEAD)" "$before_fetch" \
            || { _project_notify "Commits non pousses dans $wt : rien n'est touche"; return 1; }
        git -C "$wt" reset --quiet --hard "$remote" &>/dev/null \
            || { _project_notify "Mise a jour de $wt impossible"; return 1; }
    fi

    if [[ -f "$repo/.zanvil.local" && ! -e "$wt/.zanvil.local" ]]; then
        # meme contenu, meme hash : la confiance accordee a l'original vaut pour la copie
        cp -p "$repo/.zanvil.local" "$wt/.zanvil.local"
        if ! git -C "$wt" check-ignore -q .zanvil.local; then
            local exclude="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
            mkdir -p "${exclude:h}" && print -r -- .zanvil.local >> "$exclude"
        fi
    fi

    command -v orca &>/dev/null || { _project_notify "orca introuvable ; worktree pret : $wt"; return 1; }
    orca repo add --path "$repo" &>/dev/null  # deja present : erreur sans consequence
    orca repo set --repo "path:$repo" --external-worktree-visibility show &>/dev/null
    orca terminal create --worktree "path:$wt" --title "!$iid" --focus &>/dev/null \
        || { _project_notify "Onglet Orca impossible ; worktree pret : $wt"; return 1; }
    orca reference add "$url" --worktree "path:$wt" &>/dev/null \
        || _project_notify "Lien de la MR non attache dans Orca"

    if command -v idea &>/dev/null; then
        idea "$wt" &>/dev/null
    else
        open -a "IntelliJ IDEA" "$wt" &>/dev/null
    fi || { _project_notify "IntelliJ IDEA impossible a lancer ; worktree pret : $wt"; return 1; }
    _ui_msg_ok "MR !$iid ouverte : $wt"
}

_project_help() {
    _ui_header "project"
    print "  project open <lien-de-MR>   ouvre la MR dans un worktree sous \$WORK_DIR"
    print "  project clean               supprime les worktrees des MR terminees"
    print "  project help                cette aide"
}

project() {
    local sub="${1:-help}"
    (( $# )) && shift
    case "$sub" in
        open|clean)
            if (( $+functions[_project_$sub] )); then
                "_project_$sub" "$@"
            else
                _ui_msg_fail "project $sub : pas encore disponible"
                return 1
            fi ;;
        help|-h|--help) _project_help ;;
        *) _ui_msg_fail "sous-commande inconnue : $sub"; _project_help; return 1 ;;
    esac
}
