# ==============================================================================
# Explorateur de projets : work_explore
# ==============================================================================
# Delegue au CLI Rust (`zanvil explore`) ; le dossier choisi revient par un fichier,
# parce qu un sous-processus ne peut pas changer le repertoire du shell appelant.

work_explore() {
    if ! command -v zanvil &>/dev/null; then
        _ui_msg_fail "L'explorateur demande le CLI zanvil (introuvable)"
        _ui_msg_info "Reconstruire : relancer install.sh ou gclone puis cargo build --release dans cli/"
        return 1
    fi

    # Index GitLab perime (> 24 h) ou absent : rafraichi en arriere-plan (~50 s)
    local cache="$HOME/.cache/zanvil/projects.json"
    setopt localoptions extendedglob
    [[ -n $cache(#qN.mh-24) ]] || zanvil explore --refresh &>/dev/null &!

    local tmp=$(mktemp) dir=
    zanvil explore --out "$tmp"
    dir=$(<"$tmp")
    rm -f "$tmp"
    [[ -n "$dir" && -d "$dir" ]] && cd "$dir"
    return 0
}
