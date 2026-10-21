# zanvil-dotfiles migrate : applique le depot dotfiles sur une machine deja configuree.
# Depend de core/ui.zsh et core/commands/dotfiles.zsh. Uniquement des definitions : rien ne s'execute au chargement.

# Ajoute KEY=valeur en fin de fichier, seulement si aucune ligne non commentee ne definit deja KEY.
# Une valeur existante est respectee. Une valeur vide (KEY=, KEY="", KEY='') compte comme absente :
# la derniere ligne de ce genre est remplacee sur place, les autres octets ne bougent pas. Cree le fichier s'il est absent.
_zanvil_dotfiles_config_key() {
    local file="$1" key="$2" value="$3"
    local empty="^([[:space:]]*(export[[:space:]]+)?${key}=)(\"\"|'')?[[:space:]]*\$"
    if [[ -f "$file" ]] && grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" | grep -Evq "$empty"; then
        return 0
    fi
    case "$key" in
        ZANVIL_DOTFILES_REPO|ZANVIL_DOTFILES_DIR) value=${(qqq)value} ;;
    esac
    if [[ -f "$file" ]] && grep -Eq "$empty" "$file"; then
        # le point final garde les retours chariot de fin de fichier ; split puis join a l'identique
        local content="$(cat "$file"; echo .)" i=
        local -a lines=("${(@f)${content%.}}")
        for (( i = ${#lines}; i > 0; i-- )); do
            [[ "${lines[i]}" =~ "$empty" ]] && { lines[i]="${match[1]}$value"; break; }
        done
        print -rn -- "${(F)lines}" > "$file"
        return
    fi
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
            # cas typique : un commit local (choix l) non pousse alors que le depot distant a bouge
            _zanvil_dotfiles_pull || { _ui_msg_info "Commits locaux ? pousser ou rebaser dans $dir, puis relancer migrate" >&2; return 1; }
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

    _zanvil_dotfiles_merged || return 1
    local merged="$REPLY"
    {
        # approuver avant d'adopter : un cask de tap tiers non approuve serait refuse
        _zanvil_dotfiles_trust "$merged" || return 1
        _zanvil_dotfiles_migrate_casks "$merged"
        local adopted=$REPLY
        local -a failed=("${_ZANVIL_MIGRATE_FAILED_CASKS[@]}")
        _zanvil_dotfiles_install || { _ui_msg_fail "brew bundle install a echoue : migrate s'arrete" >&2; return 1; }
        _zanvil_dotfiles_migrate_configs || return 1
        local passed=$REPLY backup=$_ZANVIL_MIGRATE_BACKUP
        local -a ignores=("${_ZANVIL_MIGRATE_IGNORES[@]}")
        if (( passed == 0 )); then
            _zanvil_dotfiles_link || return 1
        elif (( ${#ignores} )); then
            _ui_msg_warn "$passed fichier(s) bloquent les liens : fichier d'ignores Stow (${ignores[*]}), les traiter a la main puis zanvil-dotfiles link"
        else
            _ui_msg_warn "$passed fichier(s) bloquent les liens : relancer zanvil-dotfiles migrate"
        fi
        # simulation seulement : migrate ne desinstalle jamais rien
        _zanvil_dotfiles_cleanup_preview "$merged" && _ui_msg_info "Rien n a ete desinstalle. Pour le faire : zanvil-dotfiles cleanup"

        local casks="$adopted passee(s) sous brew" files="$passed fichier(s)"
        (( ${#failed} )) && casks+=", echec(s) : ${failed[*]}"
        (( ${#ignores} )) && files+=" (fichier d'ignores Stow : ${ignores[*]})"
        echo
        _ui_section "Profil" "$profile"
        _ui_section "Depot" "$dir"
        _ui_section "Applis" "$casks"
        _ui_section "Passes" "$files"
        _ui_section "Sauvegarde" "${backup:-aucune}"
        if [[ "$(command git -C "$dir" status -sb 2>/dev/null | head -n1)" == *"[ahead "* ]]; then
            _ui_msg_warn "Commits locaux non pousses : git -C $dir push"
        fi
        _ui_msg_info "Prochaine commande : zanvil-dotfiles cleanup"
    } always {
        rm -f "$merged"
    }
}

# Apres une mise a jour reussie : propose migrate une seule fois, si aucun profil n'est defini.
_zanvil_dotfiles_suggest_migrate() {
    local state="${ZANVIL_DIR:-$HOME/.zanvil}/.dotfiles_migrate_suggested"
    [[ -n "${ZANVIL_PROFILE:-}" || -e "$state" ]] && return 0
    _ui_msg_info "Depot dotfiles : lancez zanvil-dotfiles migrate pour l'appliquer sur cette machine"
    : > "$state"
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
    local errf=$(mktemp) tok= app= json= rc=0
    json=$(brew info --cask --json=v2 "${want[@]}" 2>"$errf") || rc=$?
    if (( rc != 0 )) || ! jq -e '.casks' >/dev/null 2>&1 <<<"$json"; then
        _ui_msg_warn "brew info a echoue : impossible de verifier les applis a passer sous brew $(head -n1 "$errf")" >&2
        rm -f "$errf"
        return 2
    fi
    rm -f "$errf"
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
    local out= rc=0
    out=$(_zanvil_dotfiles_adopt_candidates "$1") || rc=$?
    (( rc == 2 )) && return 0 # avertissement deja affiche, rien n'est adopte
    local -a cands=("${(@f)out}")
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

# Deplace $1 vers $2 (dossiers crees a la volee) sans jamais ecraser. Code 1 si $1 reste en place.
_zanvil_dotfiles_migrate_stash() {
    if mkdir -p "${2:h}" && [[ ! -e "$2" && ! -L "$2" ]] && mv -n "$1" "$2" && [[ ! -e "$1" && ! -L "$1" ]]; then
        return 0
    fi
    _ui_msg_fail "Deplacement impossible vers la sauvegarde : $1 reste en place" >&2
    return 1
}

# Vrai si Stow ne lie jamais $1 (chemin relatif au paquet) : sa liste d'ignores par defaut.
# Motifs echappes : # et ~ sont speciaux sous extendedglob.
_zanvil_dotfiles_stow_ignored() {
    [[ "${1%%/*}" == (README.*|LICENSE.*|COPYING) ]] && return 0
    local part=
    for part in "${(@s:/:)1}"; do
        [[ "$part" == (.gitignore|.gitmodules|.cvsignore|.git|.svn|.hg|?*\~|?*,v|\#*\#|RCS|CVS|.\#?*|_darcs|.stow-local-ignore) ]] && return 0
    done
    return 1
}

# Resout les fichiers de $HOME qui bloqueraient Stow (stow/common et stow/$ZANVIL_PROFILE).
# REPLY = nombre de fichiers passes ; _ZANVIL_MIGRATE_BACKUP = dossier de sauvegarde, ou vide.
# Code 0, sauf deplacement ou commit impossible (code 1, fichier laisse en place). Lit les reponses sur stdin.
_zanvil_dotfiles_migrate_configs() {
    typeset -g _ZANVIL_MIGRATE_BACKUP=
    typeset -ga _ZANVIL_MIGRATE_IGNORES=()
    REPLY=0
    local dir=$(_zanvil_dotfiles_dir)
    local backup="$HOME/.zanvil-backup/$(date +%Y%m%d-%H%M%S)"
    local -a layers=("$dir/stow/common") warned=()
    [[ -n "${ZANVIL_PROFILE:-}" ]] && layers+=("$dir/stow/$ZANVIL_PROFILE")
    # chemins passes et chemins vus : un chemin n'est compte qu'une fois, meme present dans deux couches
    local -A passed=() seen=()
    local layer= src= rel= target= parent= linked= answer= tmp= custom=
    for layer in "${layers[@]}"; do
        [[ -d "$layer" ]] || continue
        # un fichier d'ignores remplace la liste par defaut de Stow (local, sinon global) : on ne sait pas l'interpreter
        custom=
        if [[ -e "$layer/.stow-local-ignore" ]]; then
            custom="$layer/.stow-local-ignore"
        elif [[ -e "$HOME/.stow-global-ignore" ]]; then
            custom="$HOME/.stow-global-ignore"
        fi
        if [[ -n "$custom" ]]; then
            _ui_msg_warn "$custom : migrate ne sait pas l'interpreter, fichiers du paquet ${layer:t} passes"
            (( ${_ZANVIL_MIGRATE_IGNORES[(Ie)$custom]} )) || _ZANVIL_MIGRATE_IGNORES+=("$custom")
        fi
        for src in "$layer"/**/*(.DN); do
            rel=${src#"$layer"/}
            if [[ -n "$custom" ]]; then
                seen[$rel]=1
                passed[$rel]=1
                continue
            fi
            _zanvil_dotfiles_stow_ignored "$rel" && continue
            if [[ -n "${seen[$rel]:-}" ]]; then
                _ui_msg_warn "$rel existe dans deux couches : passe"
                passed[$rel]=1
                continue
            fi
            seen[$rel]=1
            target="$HOME/$rel"
            # le plus haut dossier lie sous $HOME : on n'ecrit jamais a travers lui
            linked= parent=${target:h}
            while [[ "$parent" == "$HOME"/* ]]; do
                [[ -L "$parent" ]] && linked=$parent
                parent=${parent:h}
            done
            if [[ -n "$linked" ]]; then
                if (( ! ${warned[(Ie)$linked]} )); then
                    warned+=("$linked")
                    _ui_msg_warn "$linked est un lien : ses fichiers sont passes"
                fi
                passed[$rel]=1
                continue
            fi
            if [[ -L "$target" ]]; then
                [[ "${target:A}" == "${src:A}" ]] && continue
                _ui_msg_warn "$target est un lien vers ailleurs : passe"
                passed[$rel]=1
                continue
            fi
            [[ -e "$target" ]] || continue
            if [[ ! -f "$target" ]]; then
                _ui_msg_warn "$target n'est pas un fichier : passe"
                passed[$rel]=1
                continue
            fi
            if cmp -s "$src" "$target"; then
                _zanvil_dotfiles_migrate_stash "$target" "$backup/$rel" || { REPLY=${#passed}; return 1; }
                _ZANVIL_MIGRATE_BACKUP=$backup
                _ui_msg_ok "$rel identique au depot : sauvegarde"
                continue
            fi
            diff -u "$src" "$target"
            printf '%s : [d]epot / [l]ocal / [p]asser [p] ' "$rel"
            answer=
            read -r answer
            case "${answer:l}" in
                d)
                    _zanvil_dotfiles_migrate_stash "$target" "$backup/$rel" || { REPLY=${#passed}; return 1; }
                    _ZANVIL_MIGRATE_BACKUP=$backup
                    _ui_msg_ok "$rel : version du depot retenue, locale sauvegardee"
                    ;;
                l)
                    # copie du fichier du depot (modifie ou non suivi compris) pour le restaurer si le commit echoue
                    tmp=$(mktemp) && cp "$src" "$tmp" || {
                        _ui_msg_fail "Copie de secours de $src impossible : rien n'est touche" >&2
                        [[ -n "$tmp" ]] && rm -f "$tmp"
                        REPLY=${#passed}; return 1
                    }
                    # commit limite a ce fichier : rien d'autre de deja indexe n'est embarque. Jamais de push.
                    if ! cp "$target" "$src" || ! command git -C "$layer" --literal-pathspecs add -- "$rel" \
                        || ! command git -C "$layer" --literal-pathspecs commit -q -m "migrate: version locale de $rel" -- "$rel"; then
                        if cp "$tmp" "$src"; then
                            command git -C "$layer" --literal-pathspecs reset -q -- "$rel"
                            rm -f "$tmp"
                            _ui_msg_fail "Commit de $rel impossible : fichier du depot restaure, $target reste en place" >&2
                        else
                            _ui_msg_fail "Commit de $rel impossible et restauration echouee : version du depot dans $tmp, $target reste en place" >&2
                        fi
                        REPLY=${#passed}; return 1
                    fi
                    rm -f "$tmp"
                    _zanvil_dotfiles_migrate_stash "$target" "$backup/$rel" || { REPLY=${#passed}; return 1; }
                    _ZANVIL_MIGRATE_BACKUP=$backup
                    _ui_msg_ok "$rel : version locale commitee dans le depot (pensez a git push), originale sauvegardee"
                    ;;
                *)
                    _ui_msg_info "$rel passe"
                    passed[$rel]=1
                    ;;
            esac
        done
    done
    REPLY=${#passed}
    return 0
}
