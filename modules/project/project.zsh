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
    [[ "${f[4]}" == <-> && "${f[5]}" == <-> ]] || { _project_notify "MR !$iid : projets source/cible illisibles"; return 1; }
    [[ "${f[4]}" == "${f[5]}" ]] || { _project_notify "MR d'un fork : non prise en charge"; return 1; }
    # la branche vient de GitLab : refuser tout nom que git n'accepterait pas (option, '..', etc.)
    [[ -n "$branch" && "$branch" != null ]] && git check-ref-format --branch "$branch" &>/dev/null \
        || { _project_notify "MR !$iid : branche source illisible"; return 1; }

    local repo wt; local -a created
    repo=$(_project_repo_dir "$mr_path")
    wt=$(_project_worktree_dir "$mr_path" "$branch")
    if [[ ! -d "$repo" ]]; then
        created=("$(_project_first_missing "$repo")")
        mkdir -p "${repo:h}" && GITLAB_HOST="$mr_host" glab repo clone "$mr_path" "$repo" &>/dev/null \
            || { _project_abort "Clone de $mr_path impossible" $created; return; }
    fi
    # refs completes partout : un tag, ou une branche locale 'origin/x', du meme nom ne masque rien
    local remote="refs/remotes/origin/$branch" local_ref="refs/heads/$branch"
    local before_fetch=$(git -C "$repo" rev-parse -q --verify "$remote")
    git -C "$repo" fetch --quiet origin "+$local_ref:$remote" &>/dev/null \
        || { _project_abort "Branche $branch introuvable sur origin (MR $state)" $created; return; }
    [[ "$(git -C "$repo" symbolic-ref -q HEAD)" == "$local_ref" ]] \
        && { _project_abort "$branch est extraite dans $repo : rien n'est touche" $created; return; }

    if [[ ! -e "$wt" ]]; then
        # branche locale existante : seulement si elle avance en avance rapide (-B l'y amene)
        if git -C "$repo" show-ref -q --verify "$local_ref"; then
            git -C "$repo" merge-base --is-ancestor "$local_ref" "$remote" \
                || { _project_abort "Branche locale $branch divergente de origin : rien n'est touche" $created; return; }
        fi
        created+=("$(_project_first_missing "$wt")")
        # un worktree efface a la main reste enregistre et bloquerait `worktree add`
        git -C "$repo" worktree prune &>/dev/null
        git -C "$repo" worktree add --quiet --track -B "$branch" "$wt" "$remote" &>/dev/null \
            || { _project_abort "Worktree $wt impossible" $created; return; }
    else
        # ici $created vaut au plus $repo : $wt existe, donc ses ancetres aussi
        local wt_common repo_common
        wt_common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        repo_common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        [[ -e "$wt/.git" && -n "$wt_common" && "${wt_common:A}" == "${repo_common:A}" ]] \
            || { _project_abort "$wt n'est pas un worktree de $repo : rien n'est touche" $created; return; }
        [[ "$(git -C "$wt" symbolic-ref -q HEAD)" == "$local_ref" ]] \
            || { _project_abort "$wt n'est pas sur $branch : rien n'est touche" $created; return; }
        [[ -z "$(git -C "$wt" status --porcelain)" ]] \
            || { _project_abort "Modifications en cours dans $wt : rien n'est touche" $created; return; }
        _project_pushed "$repo" "$branch" "$(git -C "$wt" rev-parse HEAD)" "$before_fetch" \
            || { _project_abort "Commits non pousses dans $wt : rien n'est touche" $created; return; }
        git -C "$wt" reset --quiet --hard "$remote" &>/dev/null \
            || { _project_abort "Mise a jour de $wt impossible" $created; return; }
    fi

    if [[ -f "$repo/.zanvil.local" && ! -e "$wt/.zanvil.local" ]]; then
        # meme contenu, meme hash : la confiance accordee a l'original vaut pour la copie
        cp -p "$repo/.zanvil.local" "$wt/.zanvil.local"
        if ! git -C "$wt" check-ignore -q .zanvil.local; then
            local exclude="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
            mkdir -p "${exclude:h}" && print -r -- .zanvil.local >> "$exclude"
        fi
    fi

    # Orca est un confort : sans lui (CLI absente ou en echec), on notifie et on ouvre IDEA quand meme
    # la CLI d'Orca n'est sur aucun PATH par defaut : repli sur celle de l'appli
    local orca=$(command -v orca) orca_app="${ZANVIL_ORCA_BIN:-/Applications/Orca.app/Contents/Resources/bin/orca}"
    [[ -z "$orca" && -x "$orca_app" ]] && orca="$orca_app"
    if [[ -z "$orca" ]]; then
        _project_notify "orca introuvable ; worktree pret : $wt"
    else
        "$orca" repo add --path "$repo" &>/dev/null  # deja present : erreur sans consequence
        "$orca" repo set --repo "path:$repo" --external-worktree-visibility show &>/dev/null
        if "$orca" terminal create --worktree "path:$wt" --title "!$iid" --focus &>/dev/null; then
            "$orca" reference add "$url" --worktree "path:$wt" &>/dev/null \
                || _project_notify "Lien de la MR non attache dans Orca"
        else
            _project_notify "Onglet Orca impossible ; worktree pret : $wt"
        fi
    fi

    if command -v idea &>/dev/null; then
        idea "$wt" &>/dev/null
    else
        open -a "IntelliJ IDEA" "$wt" &>/dev/null
    fi || { _project_notify "IntelliJ IDEA impossible a lancer ; worktree pret : $wt"; return 1; }
    _ui_msg_ok "MR !$iid ouverte : $wt"
}

# _project_remote_host <url-de-remote> : hote d'une URL https, ssh:// ou scp (git@hote:chemin)
_project_remote_host() {
    [[ "$1" =~ '^[a-z+]+://([^@/]+@)?([^/:]+)' ]] && { print -r -- "${match[2]}"; return; }
    [[ "$1" =~ '^([^@/]+@)?([^/:]+):' ]] && { print -r -- "${match[2]}"; return; }
    return 1
}

# _project_clean_reason <depot> <worktree> <branche> <HEAD> <sha-de-la-MR> : rien si le worktree
# peut etre supprime, sinon la raison de le garder
_project_clean_reason() {
    local repo="$1" wt="$2" branch="$3" head="$4" sha="$5" line
    [[ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]] || { print modifications en cours; return; }
    # stash commun au depot : seules comptent les entrees faites sur cette branche
    for line in ${(f)"$(git -C "$repo" stash list --format=%gs 2>/dev/null)"}; do
        [[ "$line" == "WIP on $branch:"* || "$line" == "On $branch:"* ]] && { print stash en cours; return; }
    done
    # shortcut: pas de fetch ; un sha de MR absent en local se rabat sur les refs distantes connues
    [[ "$sha" =~ '^[0-9a-f]{40,64}$' ]] && git -C "$repo" merge-base --is-ancestor "$head" "$sha" 2>/dev/null && return
    [[ -n "$(git -C "$repo" for-each-ref --count=1 --contains "$head" refs/remotes 2>/dev/null)" ]] && return
    print commits non pousses
}

# _project_clean [--quiet] : supprime les worktrees sous $WORK_DIR dont la MR est mergee ou fermee
# et qui ne portent aucun travail non pousse ; notifie un resume (rien si rien a faire).
_project_clean() {
    local quiet=0
    [[ "$1" == --quiet ]] && quiet=1
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] || { _project_notify "WORK_DIR absent : ${WORK_DIR:-non defini}"; return 1; }
    command -v glab &>/dev/null || { _project_notify "glab introuvable"; return 1; }
    command -v jq &>/dev/null || { _project_notify "jq introuvable"; return 1; }

    # un seul menage a la fois (deux shells ouverts ensemble) ; verrou de plus d'1 h repris
    local lock="$ZANVIL_DIR/.project_clean.lock"
    local -a mtime
    if ! mkdir "$lock" 2>/dev/null; then
        zmodload -F zsh/stat b:zstat; zmodload -F zsh/datetime p:EPOCHSECONDS
        zstat -A mtime +mtime "$lock" 2>/dev/null && (( EPOCHSECONDS - mtime[1] > 3600 )) \
            && rmdir "$lock" 2>/dev/null && mkdir "$lock" 2>/dev/null \
            || { (( quiet )) || _ui_msg_warn "Menage deja en cours"; return 0; }
    fi
    trap "rmdir ${(q)lock} 2>/dev/null" EXIT  # zsh : trap EXIT d'une fonction = a son retour

    local wt repo rel mr_path ref branch host head json state sha reason
    local -a f removed kept detached
    for wt in "$WORK_DIR"/**/.worktrees/*/*(/N); do
        repo="${wt:h:h:h}/${wt:h:t}"
        rel="${wt#"$WORK_DIR"/}"
        mr_path="${repo#"$WORK_DIR"/}"
        # seulement les worktrees de ce depot ; le reste sous .worktrees n'est pas a nous
        [[ -e "$wt/.git" && -d "$repo" ]] || continue
        [[ "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
            == "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]] || continue
        # vraie branche lue dans le worktree : feat/x -> feat-x ne se defait pas
        # HEAD detache : ignore sans notification (pas de rappel quotidien), signale a la main
        ref=$(git -C "$wt" symbolic-ref -q HEAD) || { detached+=("$rel"); continue; }
        branch="${ref#refs/heads/}"
        head=$(git -C "$wt" rev-parse -q --verify HEAD) || continue
        host=$(_project_remote_host "$(git -C "$repo" remote get-url origin 2>/dev/null)") || continue
        # alias ~/.ssh/config (git@gitlab:...) : le vrai nom d'hote vient de ssh -G
        # shortcut: non teste (pas de faux ssh), a couvrir si un alias pose probleme
        [[ "$host" == *.* ]] || host=$(ssh -G -- "$host" 2>/dev/null | awk '/^hostname /{print $2}')
        [[ -n "$host" ]] || continue
        json=$(GLAB_NO_PROMPT=1 GITLAB_HOST="$host" glab mr view "$branch" -R "$mr_path" -F json 2>/dev/null) || continue
        f=("${(@f)$(print -r -- "$json" | jq -r '.state, .sha' 2>/dev/null)}")
        state="${f[1]}" sha="${f[2]}"
        [[ "$state" == (merged|closed) ]] || continue
        # nom de branche reutilise : une MR ouverte sur la meme branche source garde le worktree
        json=$(GLAB_NO_PROMPT=1 GITLAB_HOST="$host" glab mr list --source-branch "$branch" -R "$mr_path" -F json 2>/dev/null) || continue
        [[ "$(print -r -- "$json" | jq 'length' 2>/dev/null)" == 0 ]] || continue
        reason=$(_project_clean_reason "$repo" "$wt" "$branch" "$head" "$sha")
        [[ -z "$reason" ]] || { kept+=("$rel : $reason"); continue; }
        # sans --force : git refuse encore si le worktree a change entre-temps
        git -C "$repo" worktree remove "$wt" &>/dev/null || { kept+=("$rel : suppression refusee par git"); continue; }
        rmdir "${wt:h}" "${wt:h:h}" 2>/dev/null
        # branche supprimee seulement si elle pointe encore sur le HEAD verifie
        git -C "$repo" update-ref -d "$ref" "$head" &>/dev/null \
            || { kept+=("$rel : branche $branch gardee, elle a bouge"); continue; }
        removed+=("$rel")
    done

    local k
    if (( ! quiet )); then
        _ui_header "project clean"
        for k in $removed; do _ui_msg_ok "supprime $k"; done
        for k in $kept; do _ui_msg_warn "garde $k"; done
        for k in $detached; do _ui_msg_info "ignore $k : HEAD detache"; done
        (( ${#removed} + ${#kept} + ${#detached} )) || _ui_msg_info "Rien a faire"
    fi
    (( ${#removed} + ${#kept} )) || return 0
    local -a parts
    (( ${#removed} )) && parts+=("${#removed} worktree$( (( ${#removed} > 1 )) && print s) supprime$( (( ${#removed} > 1 )) && print s)")
    for k in $kept; do parts+=("garde $k"); done
    # le resume est deja affiche : la notification ne le repete pas au terminal
    _project_notify "${(j: ; :)parts}" >/dev/null
}

# _project_clean_daily : _project_clean --quiet en arriere-plan, au plus une fois par 24 h
_project_clean_daily() {
    local stamp="$ZANVIL_DIR/.last_project_clean" last
    zmodload -F zsh/datetime p:EPOCHSECONDS
    [[ -r "$stamp" ]] && last=$(<"$stamp")
    [[ "$last" == <-> ]] && (( EPOCHSECONDS - last < 86400 )) && return 0
    print -r -- "$EPOCHSECONDS" > "$stamp"
    # stdin hors du terminal : une invite glab arreterait le job (SIGTTIN), invisible
    _project_clean --quiet </dev/null &>/dev/null &!
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
        open|clean) "_project_$sub" "$@" ;;
        help|-h|--help) _project_help ;;
        *) _ui_msg_fail "sous-commande inconnue : $sub"; _project_help; return 1 ;;
    esac
}
