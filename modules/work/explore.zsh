# ==============================================================================
# Explorateur de projets : work_explore
# ==============================================================================
# Delegue au CLI Rust (`zanvil explore`) ; le dossier choisi revient par un fichier,
# parce qu un sous-processus ne peut pas changer le repertoire du shell appelant.

work_explore() {
    if ! command -v zanvil &>/dev/null; then
        _ui_msg_fail "zanvil CLI absent : l'explorateur demande le binaire (install.sh)"
        _ui_msg_info "En attendant : gclone, zoxide"
        return 1
    fi

    # Index GitLab perime (> 24 h) ou absent : rafraichi en arriere-plan (~50 s), un seul a la fois.
    # Verrou atomique (mkdir) ; un verrou de plus d'une heure vient d'un rafraichissement mort.
    local cdir="${XDG_CACHE_HOME:-$HOME/.cache}/zanvil"
    local cache="$cdir/projects.json" lock="$cdir/refresh.lock"
    setopt localoptions extendedglob
    if [[ -z $cache(#qN.mh-24) ]] && mkdir -p "$cdir" 2>/dev/null; then
        [[ -n $lock(#qN/mm+59) ]] && rm -rf "$lock"
        if mkdir "$lock" 2>/dev/null; then
            { zanvil explore --refresh &>/dev/null; rm -rf "$lock" } &!
        fi
    fi

    local tmp dir= rc
    tmp=$(mktemp 2>/dev/null) || { _ui_msg_fail "work_explore : fichier temporaire impossible"; return 1 }
    {
        zanvil explore --out "$tmp"
        rc=$?
        dir=$(<"$tmp")
        [[ $rc -eq 0 && -n "$dir" && -d "$dir" ]] && cd "$dir"
    } always {
        rm -f "$tmp"
    }
    return $rc
}
