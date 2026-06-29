# SSL/TLS — Bundle CA personnalise
# Genere par: zanvil-ssl-setup
if [[ -f "$HOME/.ssl/ca-bundle.pem" ]]; then
    export SSL_CERT_FILE="$HOME/.ssl/ca-bundle.pem"
    export CURL_CA_BUNDLE="$HOME/.ssl/ca-bundle.pem"
    export REQUESTS_CA_BUNDLE="$HOME/.ssl/ca-bundle.pem"
    export NODE_EXTRA_CA_CERTS="$HOME/.ssl/ca-bundle.pem"
fi
