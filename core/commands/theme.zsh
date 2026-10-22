# ==============================================================================
# core/theme.zsh — Gestion des themes (Starship et Ghostty)
# ==============================================================================
# Fonctions : zanvil-theme, zanvil-ghostty
# Utilise les fonctions UI de ui.zsh (charge automatiquement avant ce fichier)
# ==============================================================================

# ==============================================================================
# zanvil-theme : Gestion des themes Starship
# ==============================================================================

# Retourne le dossier de config k9s selon la plateforme.
_k9s_config_dir() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "$HOME/Library/Application Support/k9s"
    else
        echo "${XDG_CONFIG_HOME:-$HOME/.config}/k9s"
    fi
}

# Applique le skin k9s correspondant au theme active.
# Silent si k9s absent, ZANVIL_K9S_AUTO_THEME=false, ou pas de skin pour ce theme.
_zanvil_k9s_apply_skin() {
    local theme="$1"
    [[ "${ZANVIL_K9S_AUTO_THEME:-true}" == "false" ]] && return 0
    command -v k9s &>/dev/null || return 0
    local skin_src="$ZANVIL_DIR/config/themes/$theme/k9s-skin.yaml"
    [[ -f "$skin_src" ]] || return 0

    local k9s_skins_dir="$(_k9s_config_dir)/skins"
    mkdir -p "$k9s_skins_dir"
    cp "$skin_src" "$k9s_skins_dir/${theme}.yaml"
    # k9s lit K9S_SKIN avant config.yaml (verifie sur k9s 0.51 : « Loading env skin »).
    # config.yaml n est donc plus edite : il peut etre un lien Stow vers le depot dotfiles.
    # core/ui.zsh exporte la meme variable au demarrage pour les shells suivants.
    export K9S_SKIN="$theme"
}

# Dossier des fichiers generes pour le theme courant. Les configs (souvent des liens
# Stow vers le depot dotfiles) incluent ces fichiers ; zanvil n ecrit jamais dans les configs.
_zanvil_theme_dir() {
    print -r -- "${XDG_CONFIG_HOME:-$HOME/.config}/zanvil/theme"
}

# Une seule fois, a la premiere ecriture dans <theme_dir> : signaler un starship.toml ecrit
# par l ancien systeme, sans le supprimer.
_zanvil_theme_legacy_notice() {
    local legacy="$HOME/.config/starship.toml" first=""
    [[ -f "$(_zanvil_theme_dir)/starship.toml" || ! -f "$legacy" ]] && return 0
    IFS= read -r first < "$legacy"
    [[ "$first" == "# Starship Theme:"* ]] || return 0
    _ui_msg_info "$legacy (ancien theme zanvil) n est plus utilise : supprimez-le avec ${_ui_bold}rm $legacy${_ui_nc}"
}

# Affiche RRGGBB pour une sequence ANSI \033[38;2;R;G;Bm, rien si elle n est pas reconnue.
_zanvil_theme_hex() {
    [[ "$1" =~ '38;2;([0-9]+);([0-9]+);([0-9]+)' ]] || return 0
    printf '%02x%02x%02x' "${match[1]}" "${match[2]}" "${match[3]}"
}

# Ecrit <theme_dir>/colors.sh (SketchyBar, JankyBorders : 0xAARRGGBB) depuis la palette du
# theme, puis recharge la barre et les bordures si elles tournent. Ne les demarre jamais.
_zanvil_theme_colors() {
    local palette="$ZANVIL_DIR/config/themes/$1/palette.zsh" dir="$(_zanvil_theme_dir)"
    # Sous-shell : les _ui_* de la session restent ceux du code appelant ; les unset evitent
    # qu une variable absente de cette palette reprenne celle du theme precedent.
    local -a c
    c=( ${=$(
        unset _ui_blue _ui_white _ui_dim _theme_bg
        [[ -f "$palette" ]] && source "$palette"
        local v
        for v in "${_theme_bg#\#}" "$(_zanvil_theme_hex "$_ui_white")" "$(_zanvil_theme_hex "$_ui_dim")" "$(_zanvil_theme_hex "$_ui_blue")"; do
            print -rn -- "${v:--} "
        done
    )} )
    [[ "${c[1]}" == - ]] && c[1]=e1e2e7
    [[ "${c[2]}" == - ]] && c[2]=383e5d
    [[ "${c[3]}" == - ]] && c[3]=969cb4
    [[ "${c[4]}" == - ]] && c[4]=2e7de9

    mkdir -p "$dir"
    printf 'export ZANVIL_BAR_BG=0xe6%s\nexport ZANVIL_BAR_TEXT=0xff%s\nexport ZANVIL_BAR_DIM=0xff%s\nexport ZANVIL_ACCENT=0xff%s\n' \
        "${c[@]}" > "$dir/colors.sh"

    if pgrep -x sketchybar &>/dev/null; then sketchybar --reload &>/dev/null; fi
    if pgrep -x borders &>/dev/null && [[ -x "$HOME/.config/borders/bordersrc" ]]; then
        "$HOME/.config/borders/bordersrc" &>/dev/null
    fi
    return 0
}

# Pose ~/.config/zanvil/wallpapers/<theme>.{jpg,jpeg,png,heic} sur tous les ecrans, s il existe (macOS).
# NSWorkspace ne demande aucune autorisation, contrairement a System Events.
_zanvil_theme_wallpaper() {
    [[ "$OSTYPE" == darwin* ]] || return 0
    local f
    for f in "${XDG_CONFIG_HOME:-$HOME/.config}/zanvil/wallpapers/$1".{jpg,jpeg,png,heic}(N); do
        osascript -l JavaScript -e 'function run(argv) {
            ObjC.import("AppKit");
            var url = $.NSURL.fileURLWithPath(argv[0]), ws = $.NSWorkspace.sharedWorkspace, s = $.NSScreen.screens;
            for (var i = 0; i < s.count; i++) ws.setDesktopImageURLForScreenOptionsError(url, s.objectAtIndex(i), $({}), null);
        }' "$f" &>/dev/null || _ui_msg_warn "Fond d ecran non applique : $f"
        return 0
    done
}

zanvil-theme() {
    # Intercepter preview et auto avant delegation CLI
    if [[ "$1" == "preview" ]]; then
        shift
        _zanvil_theme_preview "$@"
        return $?
    fi
    if [[ "$1" == "auto" ]]; then
        _zanvil_theme_auto
        return $?
    fi

    local _noticed=false

    # Delegation au CLI Rust si disponible. Pas si ~/.config/starship.toml est un lien :
    # un CLI obsolete ecrirait a travers, dans le depot dotfiles.
    if command -v zanvil &>/dev/null && [[ ! -L "$HOME/.config/starship.toml" ]]; then
        local cli_args=("$@")
        # Mapper l'ancien usage: zanvil-theme <name> -> zanvil theme apply <name>
        if [[ -n "$1" && "$1" != "list" && "$1" != "current" && "$1" != "apply" ]]; then
            cli_args=(apply "$@")
        fi
        if [[ "${cli_args[1]}" != "apply" ]]; then
            zanvil theme "${cli_args[@]}"
            return $?
        fi

        _zanvil_theme_legacy_notice
        _noticed=true
        zanvil theme "${cli_args[@]}"
        local rc=$?
        (( rc == 0 )) || return $rc
        local _theme_name="${cli_args[-1]}"
        local _src="$ZANVIL_DIR/config/themes/$_theme_name/prompt.toml"
        [[ -f "$_src" ]] || _src="$ZANVIL_DIR/config/themes/$_theme_name.toml"
        if cmp -s "$_src" "$(_zanvil_theme_dir)/starship.toml"; then
            [[ -z "$STARSHIP_CONFIG" ]] && export STARSHIP_CONFIG="$(_zanvil_theme_dir)/starship.toml"
            # Sourcer la palette pour la session courante apres apply
            local _p="$ZANVIL_DIR/config/themes/$_theme_name/palette.zsh"
            [[ -f "$_p" ]] && source "$_p"
            _zanvil_k9s_apply_skin "$_theme_name"
            _zanvil_theme_colors "$_theme_name"
            _zanvil_theme_wallpaper "$_theme_name"
            return 0
        fi
        # CLI d avant ~/.config/zanvil/theme : le repli zsh ecrit le bon fichier
        _ui_msg_warn "CLI zanvil obsolete : reconstruisez-le (${_ui_bold}cd \$ZANVIL_DIR/cli && cargo build --release${_ui_nc})"
        set -- "$_theme_name"
    fi

    # --- Fallback zsh ---
    local themes_dir="$ZANVIL_DIR/config/themes"
    local starship_config="$(_zanvil_theme_dir)/starship.toml"
    local state_file="$ZANVIL_DIR/.current_theme"
    local theme="$1"

    # La garde ne couvre que ce qui a besoin de starship : APPLIQUER un theme ecrit une
    # configuration que starship seul relit. Lister les themes versionnes sous
    # config/themes/ et dire lequel est courant n en demande rien — ce sont des fichiers
    # du depot et une ligne dans .current_theme.
    #
    # L ancienne garde refusait tout en tete de fonction, ce qui rendait le repli
    # dependant d un outil dont il n avait pas besoin. Trouve en CI : le cas de
    # delegation echouait sur les deux runners avec « Starship n'est pas installe », parce
    # qu il demandait simplement la liste.
    if [[ -n "$theme" && "$theme" != "list" && "$theme" != "current" ]] \
        && ! command -v starship &> /dev/null; then
        _ui_msg_fail "Starship n'est pas installe."
        return 1
    fi

    # Sans argument ou "list" : afficher les themes disponibles
    if [[ -z "$theme" ]] || [[ "$theme" = "list" ]]; then
        _ui_header "Themes Starship"

        # Theme actuel depuis le fichier d'etat
        local current=""
        [[ -f "$state_file" ]] && current=$(<"$state_file")

        # Collecter les noms de themes (directory + flat, sans doublons)
        local -a theme_names=()
        # Directory themes
        for d in "$themes_dir"/*/prompt.toml(N); do
            theme_names+=($(basename $(dirname "$d")))
        done
        # Flat themes (skip si version directory existe)
        for f in "$themes_dir"/*.toml(N); do
            local name=$(basename "$f" .toml)
            (( ${theme_names[(Ie)$name]} )) || theme_names+=($name)
        done

        for name in ${(o)theme_names}; do
            local desc="" toml_file=""
            if [[ -f "$themes_dir/$name/prompt.toml" ]]; then
                toml_file="$themes_dir/$name/prompt.toml"
            else
                toml_file="$themes_dir/$name.toml"
            fi
            desc=$(grep -m1 "^# Starship Theme:" "$toml_file" 2>/dev/null | sed 's/^# Starship Theme: //')

            # Indicateur palette
            local palette_tag=""
            [[ -f "$themes_dir/$name/palette.zsh" ]] && palette_tag=" ${_ui_magenta}[palette]${_ui_nc}"

            if [[ "$name" = "$current" ]]; then
                echo -e "  ${_ui_green}*${_ui_nc} ${_ui_bold}$name${_ui_nc} - $desc ${_ui_cyan}(actif)${_ui_nc}$palette_tag"
            else
                echo -e "  ${_ui_cyan}${_ui_circle}${_ui_nc} $name - $desc$palette_tag"
            fi
        done

        echo ""
        echo -e "  ${_ui_dim}Usage: zanvil-theme <nom>          Appliquer un theme${_ui_nc}"
        echo -e "  ${_ui_dim}       zanvil-theme preview <nom>  Apercu sans appliquer${_ui_nc}"
        echo -e "  ${_ui_dim}       zanvil-theme auto            Auto dark/light${_ui_nc}"
        return 0
    fi

    # Resoudre le theme (directory > flat)
    local toml_source=""
    if [[ -f "$themes_dir/$theme/prompt.toml" ]]; then
        toml_source="$themes_dir/$theme/prompt.toml"
    elif [[ -f "$themes_dir/$theme.toml" ]]; then
        toml_source="$themes_dir/$theme.toml"
    else
        _ui_msg_fail "Theme '$theme' non trouve."
        return 1
    fi

    [[ "$_noticed" == true ]] || _zanvil_theme_legacy_notice
    mkdir -p "${starship_config:h}"

    # Appliquer : core/hooks.zsh exporte STARSHIP_CONFIG vers ce fichier au demarrage
    cp "$toml_source" "$starship_config"
    [[ -z "$STARSHIP_CONFIG" ]] && export STARSHIP_CONFIG="$starship_config"
    echo "$theme" > "$state_file"

    # Sourcer la palette si disponible
    local palette="$themes_dir/$theme/palette.zsh"
    if [[ -f "$palette" ]]; then
        source "$palette"
        _ui_tag_ok "Theme '$theme' applique (prompt + palette)"
    else
        _ui_tag_ok "Theme '$theme' applique"
    fi
    _zanvil_k9s_apply_skin "$theme"
    _zanvil_theme_colors "$theme"
    _zanvil_theme_wallpaper "$theme"
    _ui_msg_info "Rechargez avec ${_ui_bold}ss${_ui_nc} pour voir les changements."
}

# ==============================================================================
# Theme Preview : apercu sans appliquer
# ==============================================================================
_zanvil_theme_preview() {
    local theme="$1"
    local themes_dir="$ZANVIL_DIR/config/themes"

    if [[ -z "$theme" ]]; then
        _ui_msg_fail "Usage: zanvil-theme preview <nom>"
        return 1
    fi

    # Resoudre le fichier toml
    local toml_source=""
    if [[ -f "$themes_dir/$theme/prompt.toml" ]]; then
        toml_source="$themes_dir/$theme/prompt.toml"
    elif [[ -f "$themes_dir/$theme.toml" ]]; then
        toml_source="$themes_dir/$theme.toml"
    else
        _ui_msg_fail "Theme '$theme' non trouve."
        return 1
    fi

    _ui_header "Theme Preview: $theme"

    # Description
    local desc=$(grep -m1 "^# Starship Theme:" "$toml_source" 2>/dev/null | sed 's/^# Starship Theme: //')
    [[ -n "$desc" ]] && _ui_section "Description" "$desc"

    # Palette
    local palette="$themes_dir/$theme/palette.zsh"
    if [[ -f "$palette" ]]; then
        _ui_section "Palette" "oui"
        echo ""
        echo "  ${_ui_bold}Couleurs:${_ui_nc}"
        # Sourcer la palette dans un scope local pour evaluer les variables
        local _pv_red _pv_green _pv_yellow _pv_blue _pv_magenta _pv_cyan _pv_white _pv_dim
        # Lire le fichier et extraire var=hex
        grep -E '^_ui_\w+=' "$palette" 2>/dev/null | while IFS= read -r line; do
            local var_name=$(echo "$line" | cut -d= -f1 | tr -d ' ')
            # Extraire le commentaire hex (#rrggbb)
            local hex=$(echo "$line" | grep -oE '#[0-9a-fA-F]{6}' 2>/dev/null | head -1)
            # Evaluer la variable pour obtenir le code ANSI
            eval "local color_code=$line" 2>/dev/null
            local color_val="${(P)var_name}"
            printf "    %-20s %b████████%b  ${_ui_dim}%s${_ui_nc}\n" "$var_name" "$color_val" "${_ui_nc}" "$hex"
        done
    else
        _ui_section "Palette" "non (couleurs par defaut)"
    fi

    # Generer un prompt de demo avec starship
    if command -v starship &>/dev/null; then
        echo ""
        _ui_section "Prompt" "apercu"
        echo ""
        # starship prompt genere des %{...%} (zsh prompt escapes)
        # On les convertit en codes ANSI bruts pour l'affichage hors prompt
        local prompt_ok prompt_err
        prompt_ok=$(STARSHIP_CONFIG="$toml_source" starship prompt \
            --status=0 --jobs=0 --cmd-duration=1234 2>/dev/null)
        prompt_err=$(STARSHIP_CONFIG="$toml_source" starship prompt \
            --status=1 --jobs=0 --cmd-duration=0 2>/dev/null)

        # Nettoyer les %{...%} -> garder le contenu entre %{ et %}
        prompt_ok=$(echo "$prompt_ok" | sed 's/%{//g; s/%}//g')
        prompt_err=$(echo "$prompt_err" | sed 's/%{//g; s/%}//g')

        printf "  %b\n" "$prompt_ok"
        printf "  %b\n" "$prompt_err"
    fi

    echo ""
    _ui_msg_info "Appliquer: zanvil-theme $theme"
}

# ==============================================================================
# Auto dark/light : detection du mode systeme
# ==============================================================================
# Config dans config.zsh :
#   ZANVIL_THEME_LIGHT=tokyo-light-pro
#   ZANVIL_THEME_DARK=tokyo-night-pro
# ==============================================================================
_zanvil_detect_appearance() {
    # macOS : lire le mode systeme
    if [[ "$OSTYPE" == darwin* ]]; then
        if defaults read -g AppleInterfaceStyle &>/dev/null 2>&1; then
            echo "dark"
        else
            echo "light"
        fi
        return
    fi

    # Linux : essayer via dbus (GNOME/KDE)
    if command -v gsettings &>/dev/null; then
        local gtk_theme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)
        if [[ "$gtk_theme" == *"dark"* ]]; then
            echo "dark"
            return
        fi
    fi

    # Fallback : dark par defaut
    echo "dark"
}

_zanvil_theme_auto() {
    local light_theme="${ZANVIL_THEME_LIGHT:-}"
    local dark_theme="${ZANVIL_THEME_DARK:-}"

    if [[ -z "$light_theme" || -z "$dark_theme" ]]; then
        _ui_msg_fail "Configurez ZANVIL_THEME_LIGHT et ZANVIL_THEME_DARK dans config.zsh"
        echo ""
        echo "  Exemple:"
        echo "    ZANVIL_THEME_LIGHT=tokyo-light-pro"
        echo "    ZANVIL_THEME_DARK=tokyo-night-pro"
        return 1
    fi

    local appearance=$(_zanvil_detect_appearance)
    local target_theme=""

    if [[ "$appearance" == "dark" ]]; then
        target_theme="$dark_theme"
    else
        target_theme="$light_theme"
    fi

    # Verifier si deja sur le bon theme
    local state_file="$ZANVIL_DIR/.current_theme"
    local current=""
    [[ -f "$state_file" ]] && current=$(<"$state_file")

    if [[ "$current" == "$target_theme" ]]; then
        _ui_msg_ok "Deja sur le theme $target_theme ($appearance)"
        return 0
    fi

    _ui_msg_info "Mode detecte: $appearance -> theme $target_theme"
    zanvil-theme "$target_theme"
}

# Hook auto dark/light au startup (silencieux)
if [[ -n "${ZANVIL_THEME_LIGHT}" && -n "${ZANVIL_THEME_DARK}" ]]; then
    _zanvil_theme_auto_startup() {
        local appearance=$(_zanvil_detect_appearance)
        local target=""
        [[ "$appearance" == "dark" ]] && target="$ZANVIL_THEME_DARK" || target="$ZANVIL_THEME_LIGHT"

        local current=""
        [[ -f "$ZANVIL_DIR/.current_theme" ]] && current=$(<"$ZANVIL_DIR/.current_theme")

        if [[ "$current" != "$target" ]]; then
            zanvil-theme "$target" &>/dev/null
        fi
    }
    _zanvil_theme_auto_startup
    unfunction _zanvil_theme_auto_startup 2>/dev/null
fi

# ==============================================================================
# zanvil-ghostty : Gestion des themes Ghostty
# ==============================================================================
zanvil-ghostty() {
    local themes_dir="$ZANVIL_DIR/config/ghostty/themes"
    local ghostty_config="$HOME/.config/ghostty/config"
    local generated="$(_zanvil_theme_dir)/ghostty"
    local theme="$1"

    # Sans argument ou "list" : afficher les themes disponibles
    if [[ -z "$theme" ]] || [[ "$theme" = "list" ]]; then
        _ui_header "Themes Ghostty"

        if [[ ! -d "$themes_dir" ]]; then
            echo -e "${_ui_yellow}Aucun theme trouve dans $themes_dir${_ui_nc}"
            return 1
        fi

        for theme_file in "$themes_dir"/*; do
            [[ -f "$theme_file" ]] || continue
            local name=$(basename "$theme_file")
            local desc=$(grep -m1 "^# Ghostty Theme:" "$theme_file" 2>/dev/null | sed 's/^# Ghostty Theme: //' || echo "")

            # Theme actuel : celui dont le fichier genere est la copie
            if cmp -s "$theme_file" "$generated"; then
                echo -e "  ${_ui_green}*${_ui_nc} ${_ui_bold}$name${_ui_nc} - $desc ${_ui_cyan}(actif)${_ui_nc}"
            else
                echo -e "  ${_ui_cyan}○${_ui_nc} $name - $desc"
            fi
        done

        grep -q '^theme = light:' "$generated" 2>/dev/null && \
            echo -e "  ${_ui_green}*${_ui_nc} ${_ui_bold}auto${_ui_nc} - suit l'apparence de macOS ${_ui_cyan}(actif)${_ui_nc}"
        echo ""
        echo -e "${_ui_dim}Usage: zanvil-ghostty <nom>|auto${_ui_nc}"
        echo -e "${_ui_dim}Sync:  zanvil-ghostty sync${_ui_nc}"
        return 0
    fi

    # Commande "sync" : déployer la config de zanvil vers ~/.config/ghostty
    if [[ "$theme" = "sync" ]]; then
        local src_config="$ZANVIL_DIR/config/ghostty/config"
        local dest_dir="$HOME/.config/ghostty"

        if [[ ! -f "$src_config" ]]; then
            echo -e "${_ui_red}[ERROR]${_ui_nc} Config source non trouvee: $src_config"
            return 1
        fi

        # La config (zanvil ou dotfiles) inclut le fichier genere : sans lui, pas de theme
        if [[ ! -f "$generated" ]]; then
            mkdir -p "${generated:h}"
            cp "$themes_dir/tokyo-light-storm" "$generated" && _ui_msg_ok "Theme par defaut (tokyo-light-storm) ecrit dans $generated"
        fi

        # Une config liee (Stow) appartient au depot dotfiles : ne pas l ecraser
        if [[ -L "$ghostty_config" ]]; then
            _ui_msg_info "Config Ghostty fournie par les dotfiles ($ghostty_config) : rien a synchroniser"
            return 0
        fi

        mkdir -p "$dest_dir"

        # Backup si existe et différent
        if [[ -f "$ghostty_config" ]] && ! diff -q "$src_config" "$ghostty_config" &>/dev/null; then
            cp "$ghostty_config" "$ghostty_config.backup"
            echo -e "${_ui_cyan}[INFO]${_ui_nc} Backup: $ghostty_config.backup"
        fi

        # Les themes ne sont plus copies : la config inclut le fichier genere
        cp "$src_config" "$ghostty_config"

        echo -e "${_ui_green}[OK]${_ui_nc} Config Ghostty synchronisee vers $dest_dir"
        echo -e "${_ui_cyan}[INFO]${_ui_nc} Redemarrez Ghostty pour appliquer les changements."
        return 0
    fi

    # "auto" : Ghostty suit lui-meme l'apparence de macOS (theme = light:...,dark:...), sans rechargement
    if [[ "$theme" = "auto" ]]; then
        local light="${ZANVIL_GHOSTTY_LIGHT:-tokyo-light-storm}" dark="${ZANVIL_GHOSTTY_DARK:-tokyo-night-storm}" t
        for t in "$light" "$dark"; do
            [[ -f "$themes_dir/$t" ]] || { _ui_msg_fail "Theme Ghostty '$t' non trouve dans $themes_dir"; return 1; }
        done
        mkdir -p "${generated:h}"
        print -r -- "theme = light:$themes_dir/$light,dark:$themes_dir/$dark" > "$generated"
        _ui_msg_ok "Ghostty suit l'apparence de macOS : $light (clair), $dark (sombre)"
        _ui_msg_info "Rechargez la config Ghostty (cmd+shift+,) une fois pour l'activer"
        return 0
    fi

    # Appliquer un theme
    local theme_file="$themes_dir/$theme"

    if [[ ! -f "$theme_file" ]]; then
        echo -e "${_ui_red}[ERROR]${_ui_nc} Theme '$theme' non trouve."
        echo -e "Themes disponibles: $(ls "$themes_dir" 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    # La config Ghostty inclut ce fichier (config-file = ?~/.config/zanvil/theme/ghostty)
    mkdir -p "${generated:h}"
    cp "$theme_file" "$generated"

    _ui_msg_ok "Theme '$theme' ecrit dans $generated"
    if ! grep -q "zanvil/theme/ghostty" "$ghostty_config" 2>/dev/null; then
        _ui_msg_warn "$ghostty_config n inclut pas $generated : lancez zanvil-ghostty sync (ou ajoutez 'config-file = ?$generated' dans vos dotfiles)"
        return 0
    fi
    _ui_msg_info "Rechargez la config Ghostty (cmd+shift+,) pour l appliquer"
}
