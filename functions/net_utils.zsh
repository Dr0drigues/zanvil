# =======================================================
# NETWORK UTILITIES
# =======================================================

# Affiche l'IP publique et l'IP locale
myip() {
    echo "🌍 Public IP : $(curl -s ifconfig.me)"
    if [ "$(uname)" = "Darwin" ]; then
        echo "🏠 Local IP  : $(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1)"
    else
        echo "🏠 Local IP  : $(hostname -I | awk '{print $1}')"
    fi
}

# Teste si un port est ouvert sur une machine distante
# Usage: port google.com 80
port() {
    if [ $# -lt 2 ]; then
        echo "Usage: port <host> <port>"
        return 1
    fi
    
    echo "Testing connection to $1:$2..."
    if nc -z -v -w 2 "$1" "$2" 2>&1 | grep -q "succeeded"; then
        echo "Port $2 ouvert sur $1"
    else
        echo "Port $2 fermé ou inaccessible sur $1"
    fi
}