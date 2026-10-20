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

zanvil-dotfiles() {
    _ui_header "Dotfiles"
    local sub="${1:-}" out=
    case "$sub" in
        install)
            _zanvil_dotfiles_merged || return 1
            brew bundle install --file="$REPLY"
            local rc=$?
            rm -f "$REPLY"
            return $rc
            ;;
        cleanup)
            _zanvil_dotfiles_merged || return 1
            local merged="$REPLY"
            out=$(brew bundle cleanup --file="$merged")
            [[ -n "$out" ]] && echo "$out"
            if [[ "$out" == *"Would "* ]] && _zanvil_dotfiles_confirm "Retirer ces elements ?"; then
                brew bundle cleanup --force --file="$merged"
            fi
            rm -f "$merged"
            ;;
        *)
            _ui_msg_info "Usage : zanvil-dotfiles install|cleanup"
            return 1
            ;;
    esac
}
