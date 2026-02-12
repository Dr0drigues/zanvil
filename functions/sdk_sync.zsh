# ==============================================================================
# sdk-sync : Installe les versions manquantes définies dans .sdkmanrc
# ==============================================================================
# Usage: sdk-sync [chemin/vers/.sdkmanrc]
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

sdk-sync() {
    local rc_file="${1:-.sdkmanrc}"

    # Vérifications préalables
    if ! command -v sdk &> /dev/null; then
        echo "Erreur: SDKMAN n'est pas installé ou initialisé."
        return 1
    fi

    if [[ ! -f "$rc_file" ]]; then
        echo "Erreur: Fichier '$rc_file' introuvable."
        return 1
    fi

    local missing=()
    local installed=()

    # Lecture du .sdkmanrc
    while IFS='=' read -r candidate version || [[ -n "$candidate" ]]; do
        # Ignorer les lignes vides et commentaires
        [[ -z "$candidate" || "$candidate" =~ ^# ]] && continue

        # Nettoyer les espaces
        candidate="${candidate// /}"
        version="${version// /}"

        local install_path="$SDKMAN_DIR/candidates/$candidate/$version"

        if [[ -d "$install_path" ]]; then
            installed+=("$candidate $version")
        else
            missing+=("$candidate=$version")
        fi
    done < "$rc_file"

    # Affichage du statut
    if [[ ${#installed[@]} -gt 0 ]]; then
        echo "Déjà installés:"
        for item in "${installed[@]}"; do
            echo -e "  ${_ui_green}${_ui_check}${_ui_nc} $item"
        done
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "\nToutes les versions sont déjà installées."
        return 0
    fi

    echo -e "\nVersions manquantes:"
    for item in "${missing[@]}"; do
        echo -e "  ${_ui_red}${_ui_cross}${_ui_nc} $item"
    done

    # Demande de confirmation
    echo ""
    read -q "response?Installer les ${#missing[@]} version(s) manquante(s)? [y/N] "
    echo ""

    if [[ "$response" != "y" ]]; then
        echo "Installation annulée."
        return 0
    fi

    # Installation
    echo ""
    for item in "${missing[@]}"; do
        local candidate="${item%=*}"
        local version="${item#*=}"
        echo "Installation de $candidate $version..."
        sdk install "$candidate" "$version" || echo "Echec: $candidate $version"
    done

    echo -e "\nTerminé. Exécute 'sdk env' pour activer les versions."
}

# Hook chpwd : rappel si des versions sont manquantes
_sdk_sync_check() {
    # Ne rien faire si SDKMAN n'est pas dispo ou pas de .sdkmanrc
    [[ ! -f ".sdkmanrc" ]] && return
    command -v sdk &> /dev/null || return

    local missing=0

    while IFS='=' read -r candidate version || [[ -n "$candidate" ]]; do
        [[ -z "$candidate" || "$candidate" =~ ^# ]] && continue
        candidate="${candidate// /}"
        version="${version// /}"

        if [[ ! -d "$SDKMAN_DIR/candidates/$candidate/$version" ]]; then
            ((missing++))
        fi
    done < .sdkmanrc

    if [[ $missing -gt 0 ]]; then
        echo -e "${_ui_yellow}${_ui_warn} .sdkmanrc: $missing version(s) manquante(s) - lance 'sdk-sync' pour installer${_ui_nc}"
    fi
}

# Enregistrement du hook
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _sdk_sync_check
