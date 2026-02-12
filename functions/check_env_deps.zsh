# Verifie les dependances recommandees et suggere l'installation
check_env_health() {
    local dependencies=(git eza starship fzf zoxide jq curl)
    local missing=()

    echo "Checking Environment Health..."
    for dep in "${dependencies[@]}"; do
        local cmd_to_check="$dep"
        if [[ "$dep" == "trash" && "$(uname)" == "Linux" ]]; then
            cmd_to_check="trash-put"
        fi

        if [[ "$dep" == "bat" && "$(uname)" == "Linux" ]]; then
            if command -v batcat &> /dev/null; then cmd_to_check="batcat"; fi
        fi

        if ! command -v "$cmd_to_check" &> /dev/null; then
            missing+=("$dep")
            echo "  $dep ($cmd_to_check) est manquant"
        else
            echo "  $dep est installe"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo "Outils manquants pour une experience optimale :"
        echo "   brew install ${missing[*]}"
    else
        echo ""
        echo "Tout est operationnel !"
    fi
}
