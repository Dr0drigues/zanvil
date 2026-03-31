# =======================================================
# NETWORK UTILITIES
# =======================================================

# Affiche l'IP publique et l'IP locale
myip() {
    local public_ip
    public_ip=$(curl -s --max-time 5 ifconfig.me) || public_ip="timeout"
    _ui_section "Public IP" "$public_ip"
    if [[ "$(uname)" == "Darwin" ]]; then
        _ui_section "Local IP" "$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "N/A")"
    else
        _ui_section "Local IP" "$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
}

# Teste si un port est ouvert sur une machine distante
# Usage: port google.com 80
port() {
    if [[ $# -lt 2 ]]; then
        echo -e "${_ui_bold}Usage:${_ui_nc} port <host> <port>"
        return 1
    fi

    echo -e "${_ui_dim}Testing connection to $1:$2...${_ui_nc}"
    if nc -z -v -w 2 "$1" "$2" 2>&1 | grep -q "succeeded"; then
        _ui_msg_ok "Port $2 ouvert sur $1"
    else
        _ui_msg_fail "Port $2 ferme ou inaccessible sur $1"
    fi
}
