# ==============================================================================
# SDKMAN Wrapper avec Hooks Post-Installation
# ==============================================================================
# Intercepte les commandes sdk install pour appliquer automatiquement
# les configurations Work (certificats Java, settings Maven)
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

# Ne charge ce wrapper que si SDKMAN est installe
[[ -z "$SDKMAN_DIR" || ! -d "$SDKMAN_DIR" ]] && return

# --- Configuration ---
_SDK_ZSH_ENV_DIR="${ZSH_ENV_DIR:-$HOME/.zsh_env}"

# --- Hooks Post-Installation ---

# Hook pour Java: importe les certificats
_sdk_hook_java() {
    local version=$1
    local java_home="$SDKMAN_DIR/candidates/java/$version"

    # Verifier que le certificat script existe
    local cert_script="$_SDK_ZSH_ENV_DIR/work/certificates_unix.sh"
    if [[ ! -f "$cert_script" ]]; then
        echo -e "${_ui_yellow}[sdk-hook]${_ui_nc} Script de certificats non trouve: $cert_script"
        return 1
    fi

    # Verifier que JAVA_HOME est valide
    if [[ ! -d "$java_home" ]]; then
        echo -e "${_ui_red}[sdk-hook]${_ui_nc} JAVA_HOME invalide: $java_home"
        return 1
    fi

    echo -e "${_ui_blue}[sdk-hook]${_ui_nc} Import des certificats Work pour Java $version..."

    # Exporter JAVA_HOME temporairement pour le script
    (
        export JAVA_HOME="$java_home"
        bash "$cert_script"
    )

    if [[ $? -eq 0 ]]; then
        echo -e "${_ui_green}[sdk-hook]${_ui_nc} Certificats importes avec succes"
    else
        echo -e "${_ui_red}[sdk-hook]${_ui_nc} Erreur lors de l'import des certificats"
        return 1
    fi
}

# Hook pour Maven: copie settings.xml
_sdk_hook_maven() {
    local version=$1
    local maven_home="$SDKMAN_DIR/candidates/maven/$version"

    # Verifier que settings.xml existe
    local settings_src="$_SDK_ZSH_ENV_DIR/work/settings.xml"
    if [[ ! -f "$settings_src" ]]; then
        echo -e "${_ui_yellow}[sdk-hook]${_ui_nc} settings.xml non trouve: $settings_src"
        return 1
    fi

    # Verifier que le dossier conf existe
    local settings_dest="$maven_home/conf/settings.xml"
    if [[ ! -d "$maven_home/conf" ]]; then
        echo -e "${_ui_red}[sdk-hook]${_ui_nc} Dossier conf Maven invalide: $maven_home/conf"
        return 1
    fi

    echo -e "${_ui_blue}[sdk-hook]${_ui_nc} Copie de settings.xml vers Maven $version..."

    # Backup de l'original si existe
    if [[ -f "$settings_dest" && ! -f "${settings_dest}.original" ]]; then
        cp "$settings_dest" "${settings_dest}.original"
    fi

    cp "$settings_src" "$settings_dest"

    if [[ $? -eq 0 ]]; then
        echo -e "${_ui_green}[sdk-hook]${_ui_nc} settings.xml copie avec succes"
    else
        echo -e "${_ui_red}[sdk-hook]${_ui_nc} Erreur lors de la copie de settings.xml"
        return 1
    fi
}

# --- Wrapper SDK ---

# Sauvegarde la fonction sdk originale si elle existe
if typeset -f sdk > /dev/null 2>&1; then
    # sdk est deja une fonction (chargee par SDKMAN)
    functions[_sdk_original]=$functions[sdk]
elif [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
    # SDKMAN pas encore charge, on cree un wrapper qui le charge d'abord
    _sdk_original() {
        source "$SDKMAN_DIR/bin/sdkman-init.sh"
        sdk "$@"
    }
fi

# Fonction sdk avec hooks
sdk() {
    local cmd=$1
    local candidate=$2
    local version=$3

    # Verifier si on est en contexte Work
    local in_blg_context=false
    if typeset -f work_is_context > /dev/null 2>&1 && work_is_context; then
        in_blg_context=true
    fi

    # Appeler la commande SDK originale
    if typeset -f _sdk_original > /dev/null 2>&1; then
        _sdk_original "$@"
    else
        # Charger SDKMAN si pas encore fait
        if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
            source "$SDKMAN_DIR/bin/sdkman-init.sh"
            command sdk "$@"
        else
            echo "SDKMAN non initialise"
            return 1
        fi
    fi

    local sdk_exit_code=$?

    # Si l'installation a reussi et qu'on est en contexte Work
    if [[ $sdk_exit_code -eq 0 && "$cmd" == "install" && "$in_blg_context" == "true" ]]; then
        # Determiner la version installee si non specifiee
        if [[ -z "$version" || "$version" == "current" ]]; then
            version=$(sdk current "$candidate" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[^ ]*' | head -1)
        fi

        [[ -z "$version" ]] && return $sdk_exit_code

        # Appliquer les hooks selon le candidate
        case "$candidate" in
            java)
                _sdk_hook_java "$version"
                ;;
            maven)
                _sdk_hook_maven "$version"
                ;;
        esac
    fi

    return $sdk_exit_code
}

# --- Commande manuelle pour appliquer les hooks ---

# Applique manuellement les hooks sur une version existante
sdk-configure() {
    local candidate=$1
    local version=${2:-current}

    if [[ -z "$candidate" ]]; then
        echo "Usage: sdk-configure <candidate> [version]"
        echo ""
        echo "Candidates supportes:"
        echo "  java    - Importe les certificats Work"
        echo "  maven   - Copie settings.xml dans conf/"
        echo ""
        echo "Exemples:"
        echo "  sdk-configure java current"
        echo "  sdk-configure maven 3.9.6"
        return 1
    fi

    # Resoudre "current" vers la version reelle
    if [[ "$version" == "current" ]]; then
        version=$(sdk current "$candidate" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[^ ]*' | head -1)
        if [[ -z "$version" ]]; then
            echo -e "${_ui_red}[sdk-configure]${_ui_nc} Aucune version de $candidate n'est active"
            return 1
        fi
        echo "Version courante de $candidate: $version"
    fi

    # Verifier que la version existe
    local candidate_home="$SDKMAN_DIR/candidates/$candidate/$version"
    if [[ ! -d "$candidate_home" ]]; then
        echo -e "${_ui_red}[sdk-configure]${_ui_nc} Version non trouvee: $candidate $version"
        return 1
    fi

    # Appliquer le hook
    case "$candidate" in
        java)
            _sdk_hook_java "$version"
            ;;
        maven)
            _sdk_hook_maven "$version"
            ;;
        *)
            echo -e "${_ui_yellow}[sdk-configure]${_ui_nc} Pas de hook configure pour: $candidate"
            return 1
            ;;
    esac
}

# Completion pour sdk-configure
_sdk_configure_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ $COMP_CWORD -eq 1 ]]; then
        # Completer les candidates
        COMPREPLY=($(compgen -W "java maven" -- "$cur"))
    elif [[ $COMP_CWORD -eq 2 ]]; then
        # Completer les versions installees
        local candidate="$prev"
        local versions_dir="$SDKMAN_DIR/candidates/$candidate"
        if [[ -d "$versions_dir" ]]; then
            local versions=$(ls "$versions_dir" 2>/dev/null | grep -v current)
            COMPREPLY=($(compgen -W "current $versions" -- "$cur"))
        fi
    fi
}

# Activer la completion si disponible
if [[ -n "$BASH_VERSION" ]]; then
    complete -F _sdk_configure_completion sdk-configure
elif [[ -n "$ZSH_VERSION" ]]; then
    # Pour zsh, utiliser compdef
    compdef '_arguments "1:candidate:(java maven)" "2:version:_files -W $SDKMAN_DIR/candidates/$words[2]"' sdk-configure 2>/dev/null
fi
