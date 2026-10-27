# ==============================================================================
# fastfetch — fiche systeme aux couleurs du theme zanvil
# Guard: ZANVIL_MODULE_FASTFETCH=true dans config.zsh
# ==============================================================================

[[ "${ZANVIL_MODULE_FASTFETCH:-}" != "true" ]] && return 0
command -v fastfetch &>/dev/null || return 0

# zfetch [full|work|minimal|palette|banner] [theme] : fastfetch avec un preset de config/fastfetch/.
# Couleurs et logo viennent du theme actif a chaque appel ; `fastfetch` seul garde la config de l'utilisateur.
zfetch() {
    local preset="${1:-full}"
    local cfg="$ZANVIL_DIR/config/fastfetch/$preset.jsonc"
    if [[ ! -f "$cfg" ]]; then
        _ui_msg_fail "preset inconnu : $preset (full, work, minimal, palette, banner)"
        return 1
    fi
    local cur=""
    [[ -f "$ZANVIL_DIR/.current_theme" ]] && cur=$(<"$ZANVIL_DIR/.current_theme")
    local theme="${2:-$cur}" l wp ext
    local -A p
    for l in ${(f)"$(_zanvil_theme_palette_hex "$theme")"}; do p[${l%%=*}]=${l#*=}; done

    local -a args=(-c "$cfg" --color-keys "#$p[blue]" --color-title "#$p[cyan]")
    if [[ "$preset" == (full|work) ]]; then
        # Logo : l'enclume de config/fastfetch/logo.txt ; ZANVIL_FETCH_LOGO=wallpaper rend le fond d'ecran du theme par chafa
        # (le terminal doit donner sa taille en pixels, sinon fastfetch affiche son logo par defaut)
        wp=""
        [[ "${ZANVIL_FETCH_LOGO:-}" == wallpaper && -n "$cur" ]] && for ext in jpg jpeg png heic; do
            wp="${XDG_CONFIG_HOME:-$HOME/.config}/zanvil/wallpapers/$cur.$ext"
            [[ -f "$wp" ]] && break
            wp=""
        done
        if [[ -n "$wp" ]] && fastfetch --list-features 2>/dev/null | grep -qx chafa; then
            args+=(--chafa "$wp" --logo-width 30)
        else
            # $1 corps, $2 face du dessus, $3 etincelles
            args+=(--file "$ZANVIL_DIR/config/fastfetch/logo.txt" --logo-color-1 "#$p[blue]" --logo-color-2 "#$p[cyan]" --logo-color-3 "#$p[yellow]")
        fi
    fi

    # Valeurs zanvil lues par les modules "command" des presets (une variable par ligne)
    local kube="" update="" kubeconfigs="" palette="" k
    if [[ "$preset" == (full|work) ]]; then
        if command -v zanvil &>/dev/null; then kube=$(zanvil context 2>/dev/null)
        elif command -v kubectl &>/dev/null; then kube=$(kubectl config current-context 2>/dev/null); fi
        kubeconfigs="${#${(s.:.)KUBECONFIG}} fichier(s)"
        if [[ -f "$ZANVIL_DIR/.update_blocked" ]]; then
            update="bloquee (zanvil-update)"
        elif [[ -f "$ZANVIL_DIR/.last_update_check" ]]; then
            zmodload -F zsh/datetime p:EPOCHSECONDS
            local last=$(<"$ZANVIL_DIR/.last_update_check")
            [[ "$last" == <-> ]] && update="${ZANVIL_UPDATE_MODE:-auto}, verifiee il y a $(( (EPOCHSECONDS - last) / 3600 )) h"
        fi
    fi
    if [[ "$preset" == palette ]]; then
        for k in fg dim blue cyan green yellow red magenta; do
            palette+="\033[38;2;$((16#${p[$k][1,2]}));$((16#${p[$k][3,4]}));$((16#${p[$k][5,6]}))m███\033[0m "
        done
    fi
    local -a on=()
    for k in ${(o)${(k)parameters[(I)ZANVIL_MODULE_*]}}; do [[ "${(P)k}" == true ]] && on+=(${(L)k#ZANVIL_MODULE_}); done

    ZF_VERSION="$ZANVIL_VERSION" ZF_THEME="${theme:-aucun}" ZF_PROFILE="${ZANVIL_PROFILE:-?}" \
    ZF_KUBE="${kube:-aucun contexte}" ZF_KUBECONFIGS="$kubeconfigs" ZF_UPDATE="${update:-inconnue}" \
    ZF_MODULES="${(j:, :)on}" ZF_PALETTE="$palette" \
        fastfetch "${args[@]}"
}
