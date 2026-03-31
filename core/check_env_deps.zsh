# Verifie les dependances recommandees et suggere l'installation

# Detect OS package manager install command
_env_pkg_install_cmd() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "brew install"
    elif command -v apt &> /dev/null; then
        echo "sudo apt install"
    elif command -v dnf &> /dev/null; then
        echo "sudo dnf install"
    elif command -v pacman &> /dev/null; then
        echo "sudo pacman -S"
    else
        echo "brew install"
    fi
}

check_env_health() {
    local dependencies=(git curl jq fzf eza starship zoxide python3 node)
    local missing=()
    local pkg_cmd
    pkg_cmd="$(_env_pkg_install_cmd)"

    _ui_header "Environment Health"

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
            echo -e "  $(_ui_fail "$dep") ${_ui_dim}($cmd_to_check)${_ui_nc}"
        else
            echo -e "  $(_ui_ok "$dep")"
        fi
    done

    echo ""
    if [[ ${#missing[@]} -gt 0 ]]; then
        _ui_msg_warn "Outils manquants : ${_ui_bold}${pkg_cmd} ${missing[*]}${_ui_nc}"
    else
        _ui_msg_ok "Tout est operationnel"
    fi
}
