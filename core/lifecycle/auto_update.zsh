# ==============================================================================
# Auto-Update zanvil
# ==============================================================================
# ZANVIL_UPDATE_MODE :
#   auto   (defaut) au demarrage, seule la lecture de l'horodatage tourne au premier plan ;
#          quand la verification est due, _zanvil_update_background s'execute en arriere-plan
#          (verrou .update.lock, journal .update.log) et n'applique qu'une avance rapide de main.
#   prompt comportement historique : demande avant de mettre a jour.
#   off    rien (ni verification ni rechargement).
# Rechargement : a chaque invite, _zanvil_update_precmd compare la revision chargee a celle du
# depot (lecture de .git/HEAD, du ref ou de packed-refs : aucun fork) et recharge comme `ss`
# quand elle a change. ZANVIL_UPDATE_RELOAD=false le coupe (nouveaux shells seulement).
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

zmodload -F zsh/datetime p:EPOCHSECONDS

# Fichier pour stocker la date de derniere verification
ZANVIL_UPDATE_FILE="$ZANVIL_DIR/.last_update_check"
_ZANVIL_UPDATE_LOCK="$ZANVIL_DIR/.update.lock"

# Fonction pour verifier si une mise a jour est necessaire (lecture de fichier, aucun fork)
_zanvil_should_check_update() {
    local frequency="${ZANVIL_UPDATE_FREQUENCY:-1}" last=

    # Si frequence = 0, toujours verifier
    [[ "$frequency" -eq 0 ]] && return 0

    [[ -r "$ZANVIL_UPDATE_FILE" ]] && last=$(<"$ZANVIL_UPDATE_FILE")
    # Premiere fois (ou fichier illisible)
    [[ "$last" == <-> ]] || return 0

    (( (EPOCHSECONDS - last) / 86400 >= frequency ))
}

# Fonction pour verifier les mises a jour (fetch puis comparaison avec origin/main)
_zanvil_check_update() {
    [[ -d "$ZANVIL_DIR/.git" ]] || return 1
    git -C "$ZANVIL_DIR" fetch origin --quiet 2>/dev/null || return 1
    [[ "$(git -C "$ZANVIL_DIR" rev-parse HEAD 2>/dev/null)" != "$(git -C "$ZANVIL_DIR" rev-parse origin/main 2>/dev/null)" ]]
}

# Version declaree dans core/ui.zsh.
# `sed -n` et non `grep -oP` : l option -P n existe pas dans le grep de macOS —
# « grep: invalid option -- P » — donc la version ne se lisait pas et le changement
# ne s annoncait jamais. En silence, puisque la sortie vide passe le test suivant.
#
# Le defaut etait invisible ici : ugrep, installe par Homebrew, prend la place de
# grep dans le PATH et accepte -P. Il a fallu appeler /usr/bin/grep pour le voir.
_zanvil_update_version() {
    sed -n 's/.*ZANVIL_VERSION="\([^"]*\)".*/\1/p' "$ZANVIL_DIR/core/ui.zsh" 2>/dev/null | head -1
}

# _zanvil_update_apply : avance rapide de main sur origin/main (deja recupere par
# _zanvil_check_update). Logique commune a zanvil-update, au mode prompt et a l'arriere-plan.
# 0 = applique ($_zanvil_update_from -> $_zanvil_update_to), 1 = rien a appliquer,
# 2 = bloque ($REPLY = raison), 3 = echec git ($REPLY).
_zanvil_update_apply() {
    local -a g=(git -C "$ZANVIL_DIR")
    local head remote branch v0
    head=$($g rev-parse HEAD 2>/dev/null) && remote=$($g rev-parse origin/main 2>/dev/null) \
        || { REPLY="revision illisible"; return 3; }
    # origin/main deja contenu (a jour, ou commits locaux en avance) : rien a recuperer
    $g merge-base --is-ancestor "$remote" "$head" 2>/dev/null && return 1
    branch=$($g symbolic-ref --short -q HEAD 2>/dev/null)
    [[ "$branch" == main ]] || { REPLY="branche ${branch:-détachée}"; return 2; }
    # fichiers suivis seulement : non suivis et ignores (config.zsh, .current_theme...) ne bloquent pas
    $g diff --quiet HEAD -- 2>/dev/null || { REPLY="modifications locales"; return 2; }
    $g merge-base --is-ancestor "$head" "$remote" 2>/dev/null || { REPLY="historique divergé"; return 2; }
    v0=$(_zanvil_update_version)
    $g merge --ff-only --quiet origin/main >/dev/null 2>&1 || { REPLY="fusion impossible"; return 3; }
    _zanvil_update_from=$v0 _zanvil_update_to=$(_zanvil_update_version)
    if [[ -z "$v0" || "$v0" == "$_zanvil_update_to" ]]; then
        _zanvil_update_from=${head[1,7]} _zanvil_update_to=${remote[1,7]}
    fi
    return 0
}

# _zanvil_update_lock : verrou atomique (mkdir) ; un verrou de plus d'1 h est repris. Code 1 si occupe.
_zanvil_update_lock() {
    mkdir "$_ZANVIL_UPDATE_LOCK" 2>/dev/null && return 0
    local -a stale=( "$_ZANVIL_UPDATE_LOCK"(N/mm+59) )
    (( $#stale )) && rmdir "$_ZANVIL_UPDATE_LOCK" 2>/dev/null && mkdir "$_ZANVIL_UPDATE_LOCK" 2>/dev/null
}

# _zanvil_update_notify <message> : journal + notification macOS (argv : aucun echappement)
_zanvil_update_notify() {
    print -r -- "$1"
    (( $+commands[osascript] )) \
        && osascript -e 'on run a' -e 'display notification (item 1 of a) with title "zanvil"' -e 'end run' -- "$1" &>/dev/null
    return 0
}

# Le git pull amene du code Rust neuf ; sans cette reconstruction, le binaire
# installe reste celui du dernier install.sh et devient silencieusement perime.
# C'est le troisieme volet de la panne des quatre mois : le code avancait, le
# binaire non, et rien ne le disait.
#
# Garde volontaire : on ne reconstruit que si un binaire est DEJA installe.
# Quelqu'un qui n'en veut pas ne doit pas en heriter par une mise a jour.
_zanvil_update_rebuild_cli() {
    command -v cargo &>/dev/null && [[ -x "$HOME/.local/bin/zanvil" ]] || return 0
    echo -e "${_ui_blue}[zanvil]${_ui_nc} Reconstruction du binaire..."
    if (cd "$ZANVIL_DIR/cli" && cargo build --release 2>/dev/null); then
        cp "$ZANVIL_DIR/cli/target/release/zanvil" "$HOME/.local/bin/" \
            && _ui_msg_ok "binaire mis a jour"
    else
        _ui_msg_warn "reconstruction echouee — le binaire reste a sa version precedente"
    fi
}

# Code 0 si une migration de migrations/ n'est pas encore appliquee
_zanvil_update_pending_migrations() {
    local state_file="$ZANVIL_DIR/.migration_version" current_ver=0 m
    [[ -f "$state_file" ]] && current_ver=$(<"$state_file")
    for m in "$ZANVIL_DIR/migrations"/[0-9]*.zsh(N); do
        (( 10#${${m:t}%%_*} > current_ver )) && return 0
    done
    return 1
}

# Fonction pour effectuer la mise a jour (interactive : zanvil-update et mode prompt)
_zanvil_do_update() {
    echo -e "${_ui_blue}[zanvil]${_ui_nc} Mise a jour en cours..."

    _zanvil_update_lock || { echo -e "${_ui_yellow}[zanvil]${_ui_nc} Mise a jour deja en cours."; return 1; }
    {
        local old_help=""
        if (( $+functions[zanvil-help] )); then
            old_help=$(zanvil-help 2>/dev/null | grep -oE 'zanvil-[a-z-]+' | sort)
        fi

        _zanvil_update_apply
        case $? in
            0) ;;
            1) echo -e "${_ui_green}${_ui_check}${_ui_nc} Vous etes deja a jour!"; return 0 ;;
            2) echo -e "${_ui_yellow}[zanvil]${_ui_nc} Mise a jour en attente — $REPLY (seule une avance rapide de main est appliquee)."; return 1 ;;
            *) echo -e "${_ui_yellow}[zanvil]${_ui_nc} Erreur lors de la mise a jour ($REPLY)."; return 1 ;;
        esac

        rm -f "$ZANVIL_DIR/.update_blocked"
        if [[ "$ZANVIL_UPDATE_RELOAD" == false ]]; then
            echo -e "${_ui_green}[zanvil]${_ui_nc} Mise a jour terminee. Rechargez avec: ${_ui_bold}ss${_ui_nc}"
        else
            echo -e "${_ui_green}[zanvil]${_ui_nc} Mise a jour terminee. Les terminaux ouverts se rechargent a la prochaine invite."
        fi
        echo -e "  ${_ui_bold}$_zanvil_update_from ${_ui_arrow} $_zanvil_update_to${_ui_nc}"

        _zanvil_update_rebuild_cli

        # Detecter les nouvelles commandes apres reload du fichier
        local new_help_file="$ZANVIL_DIR/core/commands/commands.zsh"
        if [[ -f "$new_help_file" ]]; then
            local new_cmds=$(grep -oE 'zanvil-[a-z-]+' "$new_help_file" | sort -u)
            local added=$(comm -13 <(echo "$old_help") <(echo "$new_cmds") 2>/dev/null)
            if [[ -n "$added" ]]; then
                echo ""
                echo -e "${_ui_cyan}Nouvelles commandes:${_ui_nc}"
                echo "$added" | while read cmd; do
                    echo -e "  ${_ui_green}+${_ui_nc} $cmd"
                done
            fi
        fi

        # Appliquer les migrations en attente
        if (( $+functions[zanvil-migrate] )) && _zanvil_update_pending_migrations; then
            echo ""
            zanvil-migrate
        fi

        # Proposer migrate une seule fois (rien au demarrage du shell : seulement ici)
        (( $+functions[_zanvil_dotfiles_suggest_migrate] )) && _zanvil_dotfiles_suggest_migrate

        # Splash zanvil apres une mise a jour reussie
        _zanvil_logo
        return 0
    } always {
        rmdir "$_ZANVIL_UPDATE_LOCK" 2>/dev/null
    }
}

# Mise a jour sans terminal (mode auto) : ne pose jamais de question ; sortie dans .update.log.
# Bloquee (branche, modifications, divergence) : une notification par situation et par HEAD.
_zanvil_update_background() {
    _zanvil_update_lock || return 0
    {
        _zanvil_check_update || return 0
        _zanvil_update_apply
        case $? in
            0)
                rm -f "$ZANVIL_DIR/.update_blocked"
                _zanvil_update_rebuild_cli
                local msg="zanvil mis à jour : $_zanvil_update_from → $_zanvil_update_to"
                # une migration peut interroger : laissee a une session interactive
                _zanvil_update_pending_migrations && msg+=" — migrations en attente : lancez zanvil-migrate"
                _zanvil_update_notify "$msg"
                ;;
            2)
                local marker="$ZANVIL_DIR/.update_blocked" seen=
                local key="$REPLY $(git -C "$ZANVIL_DIR" rev-parse HEAD 2>/dev/null)"
                [[ -r "$marker" ]] && seen=$(<"$marker")
                [[ "$seen" == "$key" ]] && return 0
                print -r -- "$key" >| "$marker"
                _zanvil_update_notify "zanvil : mise à jour en attente — $REPLY"
                ;;
            3) print -r -- "zanvil : échec de la mise à jour ($REPLY)" ;;
        esac
    } always {
        rmdir "$_ZANVIL_UPDATE_LOCK" 2>/dev/null
    }
}

# Fonction pour afficher les nouveautes
_zanvil_show_changes() {
    local changes=$(git -C "$ZANVIL_DIR" log --oneline HEAD..origin/main 2>/dev/null | head -5)

    if [[ -n "$changes" ]]; then
        echo -e "${_ui_blue}Nouveautes:${_ui_nc}"
        echo "$changes" | while read line; do
            echo -e "  ${_ui_green}*${_ui_nc} $line"
        done
    fi
}

# Mode prompt : verification puis question
_zanvil_auto_update() {
    # Verifier si on doit checker
    _zanvil_should_check_update || return 0

    # Mettre a jour le timestamp
    print -r -- "$EPOCHSECONDS" >| "$ZANVIL_UPDATE_FILE"

    # Verifier les mises a jour disponibles
    if _zanvil_check_update; then
        echo ""
        echo -e "${_ui_yellow}[zanvil]${_ui_nc} Une mise a jour est disponible!"
        _zanvil_show_changes
        echo ""

        echo -n "Mettre a jour maintenant ? [y/N] "
        read -r answer
        if [[ "$answer" =~ ^[yYoO]$ ]]; then
            _zanvil_do_update
        else
            echo -e "${_ui_blue}[zanvil]${_ui_nc} Mise a jour reportee. Lancez ${_ui_bold}zanvil-update${_ui_nc} pour mettre a jour manuellement."
        fi
        echo ""
    fi
}

# Commande manuelle pour forcer la mise a jour
zanvil-update() {
    _ui_header "Zanvil Update"

    echo -e "Verification des mises a jour..."

    if _zanvil_check_update; then
        _zanvil_show_changes
        echo ""
        _zanvil_do_update
    else
        echo -e "${_ui_green}${_ui_check}${_ui_nc} Vous etes deja a jour!"
    fi
}

# _zanvil_update_rev : revision du depot dans $REPLY, sans fork (vide si illisible)
_zanvil_update_rev() {
    local g="$ZANVIL_DIR/.git" ref
    REPLY=
    [[ -r "$g/HEAD" ]] || return 0
    REPLY=$(<"$g/HEAD")
    [[ "$REPLY" == "ref: "* ]] || return 0
    ref=${REPLY#ref: } REPLY=
    if [[ -r "$g/$ref" ]]; then
        REPLY=$(<"$g/$ref")
    elif [[ -r "$g/packed-refs" ]]; then
        REPLY=${${(M)${(f)"$(<"$g/packed-refs")"}:#* $ref}%% *}
    fi
}

# Hook precmd : la revision du depot a change depuis le chargement -> recharge comme `ss`, une fois.
# Attend la fin d'une mise a jour en cours (verrou frais). `sched +0` execute `ss` au niveau
# global : sourcer .zshrc depuis une fonction rendrait locaux ses typeset (PATH, tableaux).
_zanvil_update_precmd() {
    [[ "$ZANVIL_UPDATE_RELOAD" == false || "$ZANVIL_UPDATE_MODE" == off ]] && return 0
    _zanvil_update_rev
    [[ "$REPLY" == "$_ZANVIL_LOADED_REV" ]] && return 0
    local -a busy=( "$_ZANVIL_UPDATE_LOCK"(N/mm-60) )
    (( $#busy )) && return 0
    print -r -- "zanvil mis à jour (${${_ZANVIL_LOADED_REV[1,7]}:-?} → ${${REPLY[1,7]}:-?}), rechargement…"
    # garde anti-boucle, meme si le rechargement echoue
    _ZANVIL_LOADED_REV=$REPLY
    zmodload zsh/sched 2>/dev/null && sched +0 ss
}

# Demarrage : au premier plan, seulement la lecture de l'horodatage (ni git ni fork tant que
# la verification n'est pas due).
_zanvil_update_startup() {
    case "$ZANVIL_UPDATE_MODE" in
        auto)
            _zanvil_should_check_update || return 0
            print -r -- "$EPOCHSECONDS" >| "$ZANVIL_UPDATE_FILE"
            [[ -d "$ZANVIL_DIR/.git" ]] || return 0
            # stdin hors du terminal : rien ne peut attendre de reponse (SIGTTIN invisible sinon)
            _zanvil_update_background </dev/null >|"$ZANVIL_DIR/.update.log" 2>&1 &!
            ;;
        prompt)
            # un `a && b &!` mettrait toute la liste en arriere-plan : le test reste au premier plan
            if _zanvil_should_check_update; then _zanvil_auto_update &!; fi
            ;;
    esac
}

_zanvil_update_rev
_ZANVIL_LOADED_REV=$REPLY
if [[ -o interactive ]]; then
    autoload -Uz add-zsh-hook && add-zsh-hook precmd _zanvil_update_precmd
fi
_zanvil_update_startup
