# ==============================================================================
# Mise Hooks avec Post-Installation Work
# ==============================================================================
# Intercepte les commandes mise install pour appliquer automatiquement
# les configurations Work (certificats Java, settings Maven)
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

# Ne charge que si mise est installe
command -v mise &> /dev/null || return

# --- Configuration ---
_MISE_ZSH_ENV_DIR="${ZSH_ENV_DIR:-$HOME/.zsh_env}"
_MISE_INSTALLS_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs"

# --- Hooks Post-Installation ---

# Hook pour Java: importe les certificats
_mise_hook_java() {
    local version=$1
    local java_home="$_MISE_INSTALLS_DIR/java/$version"

    local cert_script="$_MISE_ZSH_ENV_DIR/work/certificates_unix.sh"
    if [[ ! -f "$cert_script" ]]; then
        echo -e "${_ui_yellow}[mise-hook]${_ui_nc} Script de certificats non trouve: $cert_script"
        return 1
    fi

    if [[ ! -d "$java_home" ]]; then
        echo -e "${_ui_red}[mise-hook]${_ui_nc} JAVA_HOME invalide: $java_home"
        return 1
    fi

    echo -e "${_ui_blue}[mise-hook]${_ui_nc} Import des certificats Work pour Java $version..."

    (
        export JAVA_HOME="$java_home"
        bash "$cert_script"
    )

    if [[ $? -eq 0 ]]; then
        echo -e "${_ui_green}[mise-hook]${_ui_nc} Certificats importes avec succes"
    else
        echo -e "${_ui_red}[mise-hook]${_ui_nc} Erreur lors de l'import des certificats"
        return 1
    fi
}

# Hook pour Maven: copie settings.xml
_mise_hook_maven() {
    local version=$1
    local maven_home="$_MISE_INSTALLS_DIR/maven/$version"

    local settings_src="$_MISE_ZSH_ENV_DIR/work/settings.xml"
    if [[ ! -f "$settings_src" ]]; then
        echo -e "${_ui_yellow}[mise-hook]${_ui_nc} settings.xml non trouve: $settings_src"
        return 1
    fi

    if [[ ! -d "$maven_home/conf" ]]; then
        echo -e "${_ui_red}[mise-hook]${_ui_nc} Dossier conf Maven invalide: $maven_home/conf"
        return 1
    fi

    echo -e "${_ui_blue}[mise-hook]${_ui_nc} Copie de settings.xml vers Maven $version..."

    local settings_dest="$maven_home/conf/settings.xml"
    if [[ -f "$settings_dest" && ! -f "${settings_dest}.original" ]]; then
        cp "$settings_dest" "${settings_dest}.original"
    fi

    cp "$settings_src" "$settings_dest"

    if [[ $? -eq 0 ]]; then
        echo -e "${_ui_green}[mise-hook]${_ui_nc} settings.xml copie avec succes"
    else
        echo -e "${_ui_red}[mise-hook]${_ui_nc} Erreur lors de la copie de settings.xml"
        return 1
    fi
}

# --- Wrapper mise install ---

mise() {
    local cmd=$1

    # Verifier si on est en contexte Work
    local in_blg_context=false
    if typeset -f work_is_context > /dev/null 2>&1 && work_is_context; then
        in_blg_context=true
    fi

    # Appeler la commande mise originale
    command mise "$@"
    local mise_exit_code=$?

    # Si l'installation a reussi et qu'on est en contexte Work
    if [[ $mise_exit_code -eq 0 && "$cmd" == "install" && "$in_blg_context" == "true" ]]; then
        shift  # remove "install"
        for arg in "$@"; do
            case "$arg" in
                java@*)
                    _mise_hook_java "${arg#*@}"
                    ;;
                maven@*)
                    _mise_hook_maven "${arg#*@}"
                    ;;
            esac
        done
    fi

    return $mise_exit_code
}

# --- Commande manuelle pour appliquer les hooks ---

mise-configure() {
    local tool=$1
    local version=${2:-}

    if [[ -z "$tool" ]]; then
        echo "Usage: mise-configure <tool> [version]"
        echo ""
        echo "Tools supportes:"
        echo "  java    - Importe les certificats Work"
        echo "  maven   - Copie settings.xml dans conf/"
        echo ""
        echo "Exemples:"
        echo "  mise-configure java              # version active"
        echo "  mise-configure java temurin-21"
        echo "  mise-configure maven 3.9.6"
        return 1
    fi

    # Verifier que le tool est supporte
    case "$tool" in
        java|maven) ;;
        *)
            echo -e "${_ui_yellow}[mise-configure]${_ui_nc} Pas de hook configure pour: $tool"
            return 1
            ;;
    esac

    # Resoudre la version active si non specifiee
    if [[ -z "$version" ]]; then
        version=$(command mise current "$tool" 2>/dev/null)
        if [[ -z "$version" ]]; then
            echo -e "${_ui_red}[mise-configure]${_ui_nc} Aucune version de $tool n'est active"
            return 1
        fi
        echo "Version courante de $tool: $version"
    fi

    # Verifier que la version existe
    local tool_home="$_MISE_INSTALLS_DIR/$tool/$version"
    if [[ ! -d "$tool_home" ]]; then
        echo -e "${_ui_red}[mise-configure]${_ui_nc} Version non trouvee: $tool $version"
        return 1
    fi

    # Appliquer le hook
    case "$tool" in
        java)  _mise_hook_java "$version" ;;
        maven) _mise_hook_maven "$version" ;;
    esac
}

# Completion pour mise-configure
if [[ -n "$ZSH_VERSION" ]] && typeset -f compdef > /dev/null 2>&1; then
    compdef '_arguments "1:tool:(java maven)" "2:version:"' mise-configure 2>/dev/null
fi
