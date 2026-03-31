# ==============================================================================
# Mise Hooks avec Post-Installation Boulanger
# ==============================================================================
# Intercepte les commandes mise install pour appliquer automatiquement
# les configurations Boulanger (certificats Java, settings Maven)
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

# Ne charge que si mise est installe
command -v mise &> /dev/null || return

# --- Configuration ---
_MISE_ZSH_ENV_DIR="${ZSH_ENV_DIR:-$HOME/.zsh_env}"
_MISE_INSTALLS_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs"

# --- Marker Files (idempotence) ---

# Verifie si un tool@version est deja configure Boulanger
# Usage: _mise_is_configured java zulu-21
_mise_is_configured() {
    local tool=$1 version=$2
    [[ -f "$_MISE_INSTALLS_DIR/$tool/$version/.blg_configured" ]]
}

# Marque un tool@version comme configure
# Usage: _mise_mark_configured java zulu-21
_mise_mark_configured() {
    local tool=$1 version=$2
    local marker="$_MISE_INSTALLS_DIR/$tool/$version/.blg_configured"
    [[ -d "$_MISE_INSTALLS_DIR/$tool/$version" ]] && date +%s > "$marker"
}

# --- Utilitaires ---

# Resout le vrai MAVEN_HOME (mise niche dans un sous-dossier apache-maven-*)
# Usage: local home=$(_mise_resolve_maven_home "3.9.6")
_mise_resolve_maven_home() {
    local version=$1
    local install_dir="$_MISE_INSTALLS_DIR/maven/$version"
    if [[ -f "$install_dir/bin/mvn" ]]; then
        echo "$install_dir"
    elif [[ -d "$install_dir" ]]; then
        local subdir subdirs=()
        subdirs=("$install_dir"/*(N/))
        for subdir in "${subdirs[@]}"; do
            if [[ -f "$subdir/bin/mvn" ]]; then
                echo "$subdir"
                return
            fi
        done
    fi
}

# --- Export MAVEN_HOME au chargement du shell ---
_mise_export_maven_home() {
    local version
    version=$(command mise current maven 2>/dev/null)
    [[ -z "$version" ]] && return
    local resolved
    resolved=$(_mise_resolve_maven_home "$version")
    if [[ -n "$resolved" && -d "$resolved/bin" ]]; then
        export MAVEN_HOME="$resolved"
        export M2_HOME="$resolved"
    fi
}
_mise_export_maven_home

# --- Hooks Post-Installation ---

# Hook pour Java: importe les certificats
_mise_hook_java() {
    local version=$1
    local java_home="$_MISE_INSTALLS_DIR/java/$version"

    if _mise_is_configured java "$version"; then
        _ui_msg_info "Java $version deja configure Boulanger"
        return 0
    fi

    local cert_script="$_MISE_ZSH_ENV_DIR/boulanger/certificates_unix.sh"
    if [[ ! -f "$cert_script" ]]; then
        echo -e "${_ui_yellow}[mise-hook]${_ui_nc} Script de certificats non trouve: $cert_script"
        return 1
    fi

    if [[ ! -d "$java_home" ]]; then
        echo -e "${_ui_red}[mise-hook]${_ui_nc} JAVA_HOME invalide: $java_home"
        return 1
    fi

    echo -e "${_ui_blue}[mise-hook]${_ui_nc} Import des certificats Boulanger pour Java $version..."

    (
        export JAVA_HOME="$java_home"
        bash "$cert_script"
    )

    if [[ $? -eq 0 ]]; then
        echo -e "${_ui_green}[mise-hook]${_ui_nc} Certificats importes avec succes"
        _mise_mark_configured java "$version"
    else
        echo -e "${_ui_red}[mise-hook]${_ui_nc} Erreur lors de l'import des certificats"
        return 1
    fi
}

# Hook pour Maven: deploie settings.xml dans ~/.m2/ et exporte MAVEN_HOME
_mise_hook_maven() {
    local version=$1
    local settings_enc="$_MISE_ZSH_ENV_DIR/boulanger/settings.xml.enc"
    local settings_plain="$_MISE_ZSH_ENV_DIR/boulanger/settings.xml"
    local settings_dest="$HOME/.m2/settings.xml"

    # Resoudre la source : decrypter le .enc si disponible, sinon le .xml en clair
    local settings_src=""
    if [[ -f "$settings_enc" ]] && command -v sops &>/dev/null; then
        local decrypted
        decrypted=$(sops -d "$settings_enc" 2>/dev/null)
        if [[ $? -eq 0 && -n "$decrypted" ]]; then
            settings_src=$(mktemp)
            echo "$decrypted" > "$settings_src"
            local _cleanup_src=true
        else
            echo -e "${_ui_yellow}[mise-hook]${_ui_nc} Echec du decryptage sops, fallback sur settings.xml"
        fi
    fi
    if [[ -z "$settings_src" ]]; then
        if [[ -f "$settings_plain" ]]; then
            settings_src="$settings_plain"
        else
            echo -e "${_ui_yellow}[mise-hook]${_ui_nc} settings.xml non trouve"
            return 1
        fi
    fi

    # Resoudre et exporter MAVEN_HOME
    local maven_home
    maven_home=$(_mise_resolve_maven_home "$version")
    if [[ -n "$maven_home" && -d "$maven_home/bin" ]]; then
        export MAVEN_HOME="$maven_home"
        export M2_HOME="$maven_home"
    else
        echo -e "${_ui_red}[mise-hook]${_ui_nc} Impossible de resoudre MAVEN_HOME pour maven/$version"
        [[ "$_cleanup_src" == "true" ]] && rm -f "$settings_src"
        return 1
    fi

    # Idempotence par diff reel
    if [[ -f "$settings_dest" ]] && diff -q "$settings_src" "$settings_dest" &>/dev/null; then
        _ui_msg_info "Maven ~/.m2/settings.xml deja a jour (MAVEN_HOME=$MAVEN_HOME)"
        _mise_mark_configured maven "$version"
        [[ "$_cleanup_src" == "true" ]] && rm -f "$settings_src"
        return 0
    fi

    echo -e "${_ui_blue}[mise-hook]${_ui_nc} Deploiement de settings.xml vers ~/.m2/..."

    mkdir -p "$HOME/.m2"

    # Backup de l'existant si different
    if [[ -f "$settings_dest" && ! -f "${settings_dest}.original" ]]; then
        cp "$settings_dest" "${settings_dest}.original"
    fi

    cp "$settings_src" "$settings_dest"

    # Verification post-copie par diff
    if diff -q "$settings_src" "$settings_dest" &>/dev/null; then
        echo -e "${_ui_green}[mise-hook]${_ui_nc} settings.xml deploye et verifie dans ~/.m2/"
        [[ -n "$MAVEN_HOME" ]] && echo -e "${_ui_green}[mise-hook]${_ui_nc} MAVEN_HOME=$MAVEN_HOME"
        _mise_mark_configured maven "$version"
    else
        echo -e "${_ui_red}[mise-hook]${_ui_nc} Erreur: settings.xml ne correspond pas apres copie"
        [[ "$_cleanup_src" == "true" ]] && rm -f "$settings_src"
        return 1
    fi

    [[ "$_cleanup_src" == "true" ]] && rm -f "$settings_src"
}

# --- Detection post-install ---

# Detecte les outils installes via mise current et applique les hooks manquants
_mise_post_install_detect() {
    local tool version
    for tool in java maven; do
        version=$(command mise current "$tool" 2>/dev/null)
        [[ -z "$version" ]] && continue
        if ! _mise_is_configured "$tool" "$version"; then
            case "$tool" in
                java)  _mise_hook_java "$version" ;;
                maven) _mise_hook_maven "$version" ;;
            esac
        fi
    done
}

# --- Wrapper mise install ---

mise() {
    local cmd=$1

    # Verifier si on est en contexte Boulanger
    local in_blg_context=false
    if typeset -f blg_is_context > /dev/null 2>&1 && blg_is_context; then
        in_blg_context=true
    fi

    # Appeler la commande mise originale
    command mise "$@"
    local mise_exit_code=$?

    # Si l'installation a reussi et qu'on est en contexte Boulanger
    if [[ $mise_exit_code -eq 0 && "$cmd" == "install" && "$in_blg_context" == "true" ]]; then
        local has_tool_args=false
        local args=("$@")
        shift  # remove "install"
        for arg in "$@"; do
            case "$arg" in
                java@*)
                    _mise_hook_java "${arg#*@}"
                    has_tool_args=true
                    ;;
                maven@*)
                    _mise_hook_maven "${arg#*@}"
                    has_tool_args=true
                    ;;
            esac
        done
        # Si pas d'args tool@version (mise install nu ou --missing), auto-detect
        if [[ "$has_tool_args" == "false" ]]; then
            _mise_post_install_detect
        fi
    fi

    return $mise_exit_code
}

# --- Commande manuelle pour appliquer les hooks ---

mise-configure() {
    local tool=$1
    local version=${2:-}

    if [[ -z "$tool" ]]; then
        echo "Usage: mise-configure <tool|status> [version]"
        echo ""
        echo "Tools supportes:"
        echo "  java    - Importe les certificats Boulanger"
        echo "  maven   - Deploie settings.xml dans ~/.m2/"
        echo "  status  - Affiche l'etat de la config Boulanger"
        echo ""
        echo "Exemples:"
        echo "  mise-configure status"
        echo "  mise-configure java              # version active"
        echo "  mise-configure java temurin-21"
        echo "  mise-configure maven 3.9.6"
        return 1
    fi

    # Sous-commande status
    if [[ "$tool" == "status" ]]; then
        _mise_configure_status
        return $?
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

# --- Status Boulanger ---

_mise_configure_status() {
    _ui_header "Mise Configure Status"

    local issues=0 tool version

    # --- Java ---
    version=$(command mise current java 2>/dev/null)
    if [[ -n "$version" ]]; then
        if _mise_is_configured java "$version"; then
            _ui_section "Java" "$(_ui_ok "$version" "configure")"
        else
            _ui_section "Java" "$(_ui_fail "$version" "non configure")"
            ((issues++))
        fi
    else
        _ui_section "Java" "$(_ui_skip "aucune version active")"
    fi

    # --- Maven ---
    version=$(command mise current maven 2>/dev/null)
    local settings_enc="$_MISE_ZSH_ENV_DIR/boulanger/settings.xml.enc"
    local settings_dest="$HOME/.m2/settings.xml"

    if [[ -n "$version" ]]; then
        if [[ ! -f "$settings_dest" ]]; then
            _ui_section "Maven" "$(_ui_fail "$version" "~/.m2/settings.xml absent")"
            ((issues++))
        elif [[ -f "$settings_enc" ]] && command -v sops &>/dev/null; then
            local ref_content
            ref_content=$(sops -d "$settings_enc" 2>/dev/null)
            if [[ $? -eq 0 ]] && echo "$ref_content" | diff -q - "$settings_dest" &>/dev/null; then
                _ui_section "Maven" "$(_ui_ok "$version" "~/.m2/settings.xml OK")"
            else
                _ui_section "Maven" "$(_ui_fail "$version" "~/.m2/settings.xml differe du .enc")"
                ((issues++))
            fi
        elif grep -q "activeProfile" "$settings_dest" 2>/dev/null; then
            _ui_section "Maven" "$(_ui_ok "$version" "~/.m2/settings.xml present")"
        else
            _ui_section "Maven" "$(_ui_fail "$version" "~/.m2/settings.xml semble invalide")"
            ((issues++))
        fi
        # MAVEN_HOME pour IDE
        if [[ -n "$MAVEN_HOME" && -d "$MAVEN_HOME" ]]; then
            _ui_section "MAVEN_HOME" "$(_ui_ok "$MAVEN_HOME")"
        else
            _ui_section "MAVEN_HOME" "$(_ui_fail "non defini")"
            ((issues++))
        fi
    else
        _ui_section "Maven" "$(_ui_skip "aucune version active")"
    fi

    echo ""
    if [[ $issues -gt 0 ]]; then
        _ui_msg_warn "$issues outil(s) non configure(s) — lancer ${_ui_bold}mise-configure <tool>${_ui_nc}"
    else
        _ui_msg_ok "Tout est configure"
    fi
}

# --- Hook chpwd (auto-detection au cd) ---

# Propose d'installer les outils manquants
_mise_prompt_install() {
    local tools_list=$1
    _ui_msg_info "Nouvelles versions mise detectees : $tools_list"
    echo -n "Installer et configurer ? [y/N] "
    local reply
    read -r reply
    if [[ "$reply" =~ ^[yY]$ ]]; then
        command mise install
        _mise_post_install_detect
    fi
}

# Propose de configurer les outils non configures
_mise_prompt_configure() {
    local tools_list=$1
    _ui_msg_info "Versions non configurees : $tools_list"
    echo -n "Appliquer la config Boulanger ? [y/N] "
    local reply
    read -r reply
    if [[ "$reply" =~ ^[yY]$ ]]; then
        local tool version
        for tool in java maven; do
            version=$(command mise current "$tool" 2>/dev/null)
            [[ -z "$version" ]] && continue
            if ! _mise_is_configured "$tool" "$version"; then
                case "$tool" in
                    java)  _mise_hook_java "$version" ;;
                    maven) _mise_hook_maven "$version" ;;
                esac
            fi
        done
    fi
}

# Hook appele a chaque changement de repertoire
_mise_chpwd_hook() {
    # Early returns
    [[ -t 0 || -n "$_MISE_CHPWD_FORCE" ]] || return
    typeset -f blg_is_context > /dev/null 2>&1 && blg_is_context || return
    [[ -f ".mise.toml" ]] || return

    local missing_tools="" unconfigured_tools=""
    local tool version

    # Detecter les outils manquants (non installes)
    local missing_json
    missing_json=$(command mise ls --missing --json 2>/dev/null)
    if [[ -n "$missing_json" && "$missing_json" != "{}" && "$missing_json" != "[]" ]]; then
        for tool in java maven; do
            version=$(command mise current "$tool" 2>/dev/null)
            if [[ -z "$version" ]]; then
                local requested
                requested=$(command mise ls --missing "$tool" 2>/dev/null | head -1 | awk '{print $2}')
                if [[ -n "$requested" ]]; then
                    missing_tools="${missing_tools:+$missing_tools, }${tool}@${requested}"
                fi
            fi
        done
    fi

    if [[ -n "$missing_tools" ]]; then
        _mise_prompt_install "$missing_tools"
        return
    fi

    # Detecter les outils installes mais non configures
    for tool in java maven; do
        version=$(command mise current "$tool" 2>/dev/null)
        [[ -z "$version" ]] && continue
        if ! _mise_is_configured "$tool" "$version"; then
            unconfigured_tools="${unconfigured_tools:+$unconfigured_tools, }${tool}@${version}"
        fi
    done

    if [[ -n "$unconfigured_tools" ]]; then
        _mise_prompt_configure "$unconfigured_tools"
    fi
}

# Enregistrer le hook chpwd
if [[ -n "$ZSH_VERSION" ]]; then
    chpwd_functions+=(_mise_chpwd_hook)
fi

# Completion pour mise-configure
if [[ -n "$ZSH_VERSION" ]] && typeset -f compdef > /dev/null 2>&1; then
    compdef '_arguments "1:tool:(status java maven)" "2:version:"' mise-configure 2>/dev/null
fi
