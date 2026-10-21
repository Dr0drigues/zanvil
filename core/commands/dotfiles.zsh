# zanvil-dotfiles : Brewfiles par couches (base zanvil + common + profil) et nettoyage confirme.
# Ne depend que de core/ui.zsh. Uniquement des definitions : rien ne s'execute au chargement.

_zanvil_dotfiles_dir() {
    echo "${ZANVIL_DOTFILES_DIR:-$HOME/.dotfiles}"
}

# Une ligne par Brewfile : base, common, profil. Echec si profil invalide ou fichier absent.
_zanvil_dotfiles_brewfiles() {
    case "${ZANVIL_PROFILE:-}" in
        pro|perso) ;;
        *) _ui_msg_fail "ZANVIL_PROFILE doit valoir pro ou perso (actuel : '${ZANVIL_PROFILE:-}')" >&2; return 1 ;;
    esac
    local dir=$(_zanvil_dotfiles_dir)
    local f
    local -a files=("${ZANVIL_DIR:-$HOME/.zanvil}/brew/base.Brewfile" "$dir/brew/common.Brewfile" "$dir/brew/$ZANVIL_PROFILE.Brewfile")
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || { _ui_msg_fail "Brewfile introuvable : $f" >&2; return 1; }
    done
    printf '%s\n' "${files[@]}"
}

# REPLY = fichier temporaire qui concatene les trois Brewfiles
_zanvil_dotfiles_merged() {
    local list
    list=$(_zanvil_dotfiles_brewfiles) || return 1
    REPLY=$(mktemp "${TMPDIR:-/tmp}/zanvil-brewfile.XXXXXX") || return 1
    cat "${(@f)list}" > "$REPLY"
}

# Retour 0 seulement sur un terminal avec une reponse o/oui/y/yes
_zanvil_dotfiles_confirm() {
    [[ -t 0 || "${ZANVIL_ASSUME_TTY:-}" == 1 ]] || return 1
    local answer=
    printf '%s [o/N] ' "$1"
    read -r answer
    case "${(L)answer}" in
        o|oui|y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

_zanvil_dotfiles_install() {
    _zanvil_dotfiles_merged || return 1
    # installe ce qui manque, sans tout mettre a jour
    brew bundle install --no-upgrade --file="$REPLY"
    local rc=$?
    rm -f "$REPLY"
    return $rc
}

_zanvil_dotfiles_pull() {
    local dir=$(_zanvil_dotfiles_dir)
    # Premier passage : clone depuis ZANVIL_DOTFILES_REPO (dossier temporaire puis mv)
    if [[ ! -e "$dir" && -n "${ZANVIL_DOTFILES_REPO:-}" ]]; then
        local tmp="$dir.tmp.$$"
        if command git clone "$ZANVIL_DOTFILES_REPO" "$tmp" && mv "$tmp" "$dir"; then
            _ui_msg_ok "Depot dotfiles clone dans $dir"
            return 0
        fi
        rm -rf "$tmp"
        _ui_msg_fail "Clone impossible depuis $ZANVIL_DOTFILES_REPO (cle SSH ou acces au depot ?)" >&2
        return 1
    fi
    if [[ ! -e "$dir/.git" ]]; then
        _ui_msg_fail "Depot dotfiles absent ou sans versionnage : $dir" >&2
        return 1
    fi
    command git -C "$dir" pull --ff-only || { _ui_msg_fail "pull echoue dans $dir" >&2; return 1; }
}

# Stow --no-folding : les dossiers restent reels, seuls les fichiers sont des liens.
# Un conflit (fichier reel a la place d'un lien) est affiche et bloque, rien n'est ecrase.
_zanvil_dotfiles_link() {
    setopt localoptions extendedglob
    case "${ZANVIL_PROFILE:-}" in
        pro|perso) ;;
        *) _ui_msg_fail "ZANVIL_PROFILE doit valoir pro ou perso (actuel : '${ZANVIL_PROFILE:-}')" >&2; return 1 ;;
    esac
    command -v stow &>/dev/null || { _ui_msg_fail "stow est absent (brew install stow)" >&2; return 1; }
    local dir=$(_zanvil_dotfiles_dir)
    local out= rc=0 line= p=
    # git ne garde pas de dossier vide : stow/perso manque souvent, ne passer que les paquets presents
    local -a pkgs=()
    for p in common "$ZANVIL_PROFILE"; do
        [[ -d "$dir/stow/$p" ]] && pkgs+=("$p")
    done
    if (( ! ${#pkgs} )); then
        _ui_msg_info "Aucun paquet dans $dir/stow (common, $ZANVIL_PROFILE) : rien a lier"
        return 0
    fi
    out=$(stow --no-folding -n -v -d "$dir/stow" -t "$HOME" "${pkgs[@]}" 2>&1) || rc=$?
    if (( rc != 0 )); then
        # stow 2.4 : "  * cannot stow <src> over existing target <cible> since ..."
        # stow 2.3 : "  * existing target is neither a link nor a directory: <cible>"
        local -a conflicts=("${(@M)${(@f)out}:#[[:space:]]#\** *}")
        if (( ${#conflicts} )); then
            for line in "${conflicts[@]}"; do
                _ui_fail "${line##[[:space:]]#\* }" >&2; echo >&2
            done
        else
            _ui_msg_fail "stow a echoue : $out" >&2
        fi
        return 1
    fi
    stow --no-folding -v -d "$dir/stow" -t "$HOME" "${pkgs[@]}"
}

# Deplace un fichier reel de $HOME dans la couche du depot, puis le relie
_zanvil_dotfiles_adopt() {
    local target="${1:-}" layer="${2:-common}"
    [[ -n "$target" ]] || { _ui_msg_fail "Usage : zanvil-dotfiles adopt <chemin> [common|pro|perso]" >&2; return 1; }
    case "$layer" in common|pro|perso) ;; *) _ui_msg_fail "Couche inconnue : $layer" >&2; return 1 ;; esac
    [[ "$target" == /* ]] || target="$HOME/$target"
    local rel="${target#$HOME/}"
    if [[ "$target" != "$HOME/"* || "$rel" == *..* ]]; then
        _ui_msg_fail "Hors de \$HOME : $target" >&2; return 1
    fi
    # segments vides et "." retires : "./.zshrc" ou ".//.ssh/config" ne doivent pas echapper a la liste
    local -a segs=("${(@s:/:)rel}"); segs=("${(@)segs:#(|.)}"); rel="${(j:/:)segs}"
    [[ -n "$rel" ]] || { _ui_msg_fail "Chemin invalide" >&2; return 1; }
    target="$HOME/$rel"
    # casse ignoree : APFS ne la distingue pas (.ZSHRC, .SSH/config)
    case "${(L)rel}" in
        */gh/hosts.yml|*/glab-cli/*|*/sops/*|*/gcloud/*|.ssh/*|.zshrc)
            _ui_msg_fail "Secret ou fichier gere par install.sh, refuse : $rel" >&2; return 1 ;;
    esac
    [[ -L "$target" ]] && { _ui_msg_fail "Deja un lien : $target" >&2; return 1; }
    [[ -f "$target" ]] || { _ui_msg_fail "Fichier introuvable : $target" >&2; return 1; }
    command -v stow &>/dev/null || { _ui_msg_fail "stow est absent (brew install stow)" >&2; return 1; }
    local dir=$(_zanvil_dotfiles_dir)
    local dest="$dir/stow/$layer/$rel"
    if [[ -e "$dest" ]] && ! cmp -s "$target" "$dest"; then
        _ui_msg_fail "Le depot contient deja une autre version : $dest (locale : $target). Comparer : diff $target $dest" >&2
        return 1
    fi
    mkdir -p "${dest:h}" && mv "$target" "$dest" || return 1
    if ! stow --no-folding -v -d "$dir/stow" -t "$HOME" "$layer"; then
        mv "$dest" "$target"
        _ui_msg_fail "stow a echoue, fichier remis en place : $target" >&2
        return 1
    fi
    _ui_msg_ok "Adopte : $rel -> $layer"
}

# Liste ce que brew retirerait, puis ne retire qu'apres confirmation.
# Types limites a brew : sans filtre, brew 7 nettoie aussi vscode, npm, uv, cargo...
_zanvil_dotfiles_cleanup() {
    _zanvil_dotfiles_merged || return 1
    local merged="$REPLY" out= rc=0
    local -a types=(--formula --cask --tap)
    # brew sort 1 en simulation quand il y a quoi retirer ; </dev/null : jamais sa propre question
    out=$(brew bundle cleanup "${types[@]}" --file="$merged" 2>&1 </dev/null) || rc=$?
    if [[ "$out" == *"Would uninstall"* || "$out" == *"Would untap"* ]]; then
        # brew liste aussi des dizaines de dossiers vides qui noient la vraie liste
        print -r -- "${(F)${(@)${(@f)out}:#Would remove \(empty directory\)*}}"
        rc=0
        if _zanvil_dotfiles_confirm "Retirer ces elements ?"; then
            brew bundle cleanup "${types[@]}" --force --file="$merged" || rc=$?
        else
            _ui_msg_info "Rien n a ete desinstalle"
        fi
    elif (( rc != 0 )); then
        _ui_msg_fail "brew bundle cleanup a echoue (code $rc) : $out" >&2
    else
        _ui_msg_info "Rien a desinstaller"
    fi
    rm -f "$merged"
    return $rc
}

zanvil-dotfiles() {
    _ui_header "Dotfiles"
    local sub="${1:-status}" out=
    case "$sub" in
        install) _zanvil_dotfiles_install ;;
        link) _zanvil_dotfiles_link ;;
        pull) _zanvil_dotfiles_pull ;;
        adopt) shift; _zanvil_dotfiles_adopt "$@" ;;
        apply) _zanvil_dotfiles_pull && _zanvil_dotfiles_install && _zanvil_dotfiles_link && _zanvil_dotfiles_cleanup ;;
        status)
            local dir=$(_zanvil_dotfiles_dir)
            _ui_section "Profil" "${ZANVIL_PROFILE:-non defini}"
            _ui_section "Depot" "$dir"
            if [[ -e "$dir/.git" ]]; then
                out=$(command git -C "$dir" status --short)
                _ui_section "Etat" "${out:-propre}"
            else
                _ui_section "Etat" "depot absent"
            fi
            _zanvil_dotfiles_brewfiles | sed 's/^/  /'
            ;;
        cleanup) _zanvil_dotfiles_cleanup ;;
        *)
            _ui_msg_info "Usage : zanvil-dotfiles status|install|cleanup|link|adopt|pull|apply"
            return 1
            ;;
    esac
}
