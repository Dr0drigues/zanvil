# zanvil-dotfiles migrate : applique le depot dotfiles sur une machine deja configuree.
# Depend de core/ui.zsh et core/commands/dotfiles.zsh. Uniquement des definitions : rien ne s'execute au chargement.

# Ajoute KEY=valeur en fin de fichier, seulement si aucune ligne non commentee ne definit deja KEY.
# Une valeur existante est respectee. Cree le fichier s'il est absent.
_zanvil_dotfiles_config_key() {
    local file="$1" key="$2" value="$3"
    if [[ -f "$file" ]] && grep -Eq "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file"; then
        return 0
    fi
    case "$key" in
        ZANVIL_DOTFILES_REPO|ZANVIL_DOTFILES_DIR) value=${(qqq)value} ;;
    esac
    # fichier existant sans retour chariot final : ne pas coller la cle a la derniere ligne
    [[ -s "$file" && -n "$(tail -c1 "$file")" ]] && { echo >> "$file" || return 1; }
    echo "$key=$value" >> "$file"
}

# REPLY = pro ou perso. ZANVIL_PROFILE defini : repris sans question. Sinon 3 essais, puis code 1.
_zanvil_dotfiles_migrate_profile() {
    if [[ -n "${ZANVIL_PROFILE:-}" ]]; then
        case "$ZANVIL_PROFILE" in
            pro|perso) ;;
            *) _ui_msg_fail "ZANVIL_PROFILE doit valoir pro ou perso (actuel : '$ZANVIL_PROFILE')" >&2; return 1 ;;
        esac
        REPLY="$ZANVIL_PROFILE"
        return 0
    fi
    local default=perso
    if [[ "${ZANVIL_WORK_DETECTED:-}" == true || "${ZANVIL_BOULANGER_DETECTED:-}" == true ]] \
        || { (( $+functions[work_is_context] )) && work_is_context; }; then
        default=pro
    fi
    local answer= i=0
    for (( i = 0; i < 3; i++ )); do
        printf 'Profil de cette machine (pro/perso) [%s] ' "$default"
        answer=
        read -r answer
        [[ -n "$answer" ]] || answer=$default
        case "$answer" in
            pro|perso) REPLY=$answer; return 0 ;;
            *) _ui_msg_warn "Reponse invalide : '$answer' (pro ou perso)" ;;
        esac
    done
    _ui_msg_fail "Profil non choisi apres 3 essais" >&2
    return 1
}

# REPLY = URL du depot. Un depot avec des modifications non commitees n'est pas mis a jour.
_zanvil_dotfiles_migrate_repo() {
    local dir=$(_zanvil_dotfiles_dir)
    local url="${ZANVIL_DOTFILES_REPO:-}"
    if [[ -e "$dir/.git" ]]; then
        if [[ -n "$(command git -C "$dir" status --porcelain)" ]]; then
            _ui_msg_warn "Modifications non commitees dans $dir : pull saute, suite sur l'etat local"
        else
            _zanvil_dotfiles_pull || return 1
        fi
        [[ -n "$url" ]] || url=$(command git -C "$dir" remote get-url origin 2>/dev/null)
    else
        if [[ -z "$url" ]]; then
            printf 'URL du depot dotfiles : '
            read -r url
            [[ -n "$url" ]] || { _ui_msg_fail "URL du depot dotfiles requise" >&2; return 1; }
        fi
        ZANVIL_DOTFILES_REPO="$url" _zanvil_dotfiles_pull || return 1
    fi
    REPLY="$url"
}

_zanvil_dotfiles_migrate() {
    _ui_header "Migration dotfiles"
    if [[ ! -t 0 && "${ZANVIL_ASSUME_TTY:-}" != 1 ]]; then
        _ui_msg_fail "migrate est interactive : lancez-la depuis un terminal" >&2
        return 1
    fi
    local tool
    for tool in brew git stow; do
        command -v "$tool" &>/dev/null || { _ui_msg_fail "$tool est absent (requis par migrate)" >&2; return 1; }
    done

    _zanvil_dotfiles_migrate_profile || return 1
    local profile="$REPLY"
    export ZANVIL_PROFILE="$profile"
    [[ "$profile" == pro ]] && export ZANVIL_WORK_DETECTED=true || export ZANVIL_WORK_DETECTED=false

    _zanvil_dotfiles_migrate_repo || return 1
    [[ -n "$REPLY" ]] && export ZANVIL_DOTFILES_REPO="$REPLY"
    local dir=$(_zanvil_dotfiles_dir)
    export ZANVIL_DOTFILES_DIR="$dir"

    local cfg="${ZANVIL_DIR:-$HOME/.zanvil}/config.zsh"
    _zanvil_dotfiles_config_key "$cfg" ZANVIL_PROFILE "$profile" || return 1
    [[ -n "${ZANVIL_DOTFILES_REPO:-}" ]] && { _zanvil_dotfiles_config_key "$cfg" ZANVIL_DOTFILES_REPO "$ZANVIL_DOTFILES_REPO" || return 1; }
    _zanvil_dotfiles_config_key "$cfg" ZANVIL_DOTFILES_DIR "$dir" || return 1
    _zanvil_dotfiles_config_key "$cfg" ZANVIL_WORK_DETECTED "$ZANVIL_WORK_DETECTED" || return 1
    _ui_msg_ok "Profil $profile, depot $dir (config.zsh : seules les cles absentes sont ajoutees)"

    local f
    for f in "$dir/brew/common.Brewfile" "$dir/brew/$profile.Brewfile"; do
        if [[ ! -f "$f" ]]; then
            _ui_msg_fail "Brewfile introuvable : $f" >&2
            _ui_msg_info "Creez-le : brew bundle dump --file=$f, puis triez a la main (common, pro, perso)" >&2
            return 1
        fi
    done
}

# Affiche (un par ligne) les casks du Brewfile $1 non geres par brew dont l'.app est deja dans /Applications.
_zanvil_dotfiles_adopt_candidates() {
    command -v jq &>/dev/null || return 0
    local apps="${ZANVIL_APPLICATIONS_DIR:-/Applications}"
    local -a have=("${(@f)$(brew list --cask -1 2>/dev/null)}") want=()
    local line= name=
    for line in "${(@f)$(<"$1")}"; do
        [[ "$line" =~ '^[[:space:]]*cask[[:space:]]+"([^"]+)"' ]] || continue
        name="${match[1]}"
        (( ${have[(Ie)$name]} )) || want+=("$name")
    done
    (( ${#want} )) || return 0
    local json=$(brew info --cask --json=v2 "${want[@]}" 2>/dev/null) tok= app=
    [[ -n "$json" ]] || return 0
    # tab : un nom d'appli peut contenir des espaces, jamais de tabulation
    while IFS=$'\t' read -r tok app; do
        (( ${have[(Ie)$tok]} )) && continue
        [[ -n "$tok" && -n "$app" && -e "$apps/$app" ]] && print -r -- "$tok"
    done < <(jq -r '.casks[]? | .token as $t | (.artifacts[]? | select(type == "object" and has("app")) | .app[0] | select(type == "string")) | "\($t)\t\(.)"' <<<"$json" 2>/dev/null)
    return 0
}

# Propose d'adopter les candidats. REPLY = nombre de reussites ; echecs dans _ZANVIL_MIGRATE_FAILED_CASKS. Code 0.
_zanvil_dotfiles_migrate_casks() {
    typeset -ga _ZANVIL_MIGRATE_FAILED_CASKS=()
    REPLY=0
    local -a cands=("${(@f)$(_zanvil_dotfiles_adopt_candidates "$1")}")
    cands=("${(@)cands:#}")
    if (( ! ${#cands} )); then
        _ui_msg_info "Aucune appli installee a la main a passer sous brew"
        return 0
    fi
    _ui_msg_info "Applis deja installees, adoptables par brew : ${cands[*]}"
    _zanvil_dotfiles_confirm "Les passer sous brew (--adopt) ?" || { _ui_msg_info "Rien n a ete adopte"; return 0; }
    local c= n=0
    for c in "${cands[@]}"; do
        if brew install --cask --adopt "$c"; then
            (( n++ ))
        else
            _ZANVIL_MIGRATE_FAILED_CASKS+=("$c")
            _ui_msg_warn "Echec pour $c, a faire a la main : brew install --cask --adopt $c"
        fi
    done
    REPLY=$n
    return 0
}
