#!/bin/bash
# ==============================================================================
# Script : ssl-setup.sh
# Description : Detection automatique des certificats entreprise et creation
#               d'un CA bundle unifie pour les outils CLI
# Support : macOS (Keychain), Linux (cert stores), WSL (Windows cert store)
# Usage : ./ssl-setup.sh [--quiet] [--force]
# Commande : zsh-env-ssl-setup
# ==============================================================================

# --- Couleurs & UI ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

QUIET=false
FORCE=false

log_info()    { $QUIET || echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { $QUIET || echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { $QUIET || echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quiet) QUIET=true; shift ;;
        -f|--force) FORCE=true; shift ;;
        -h|--help)
            echo -e "${BOLD}USAGE${NC}"
            echo "    $(basename "$0") [OPTIONS]"
            echo ""
            echo -e "${BOLD}DESCRIPTION${NC}"
            echo "    Detecte les certificats entreprise dans le store systeme"
            echo "    et cree un CA bundle unifie dans ~/.ssl/ca-bundle.pem"
            echo ""
            echo -e "${BOLD}OPTIONS${NC}"
            echo "    -q, --quiet    Mode silencieux (erreurs uniquement)"
            echo "    -f, --force    Recreer le bundle meme s'il existe deja"
            echo "    -h, --help     Affiche cette aide"
            echo ""
            echo -e "${BOLD}CERTIFICATS DETECTES${NC}"
            echo "    - UnitedB-Root-CA  (DC=com, DC=htm-group)"
            echo "    - Unitedb-Sub-CA   (DC=com, DC=htm-group)"
            exit 0
            ;;
        *) log_error "Option inconnue: $1"; exit 1 ;;
    esac
done

# --- Configuration ---
SSL_DIR="$HOME/.ssl"
BUNDLE_FILE="$SSL_DIR/ca-bundle.pem"
ENTERPRISE_DIR="$SSL_DIR/enterprise"

# Issuers entreprise a rechercher (CN exact)
ENTERPRISE_ISSUERS=(
    "UnitedB-Root-CA"
    "Unitedb-Sub-CA"
)

# --- Fonctions de detection ---

# Detecte la plateforme
detect_platform() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

# Localise le CA bundle systeme
find_system_ca_bundle() {
    local candidates=(
        # macOS Homebrew OpenSSL
        "/opt/homebrew/etc/openssl@3/cert.pem"
        "/usr/local/etc/openssl@3/cert.pem"
        # macOS systeme
        "/etc/ssl/cert.pem"
        # Linux distributions
        "/etc/ssl/certs/ca-certificates.crt"
        "/etc/pki/tls/certs/ca-bundle.crt"
        "/etc/ssl/ca-bundle.pem"
        "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
        # Alpine
        "/etc/ssl/certs/ca-certificates.crt"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

# macOS : extraire les certificats entreprise du Keychain
extract_from_keychain() {
    local target_cn="$1"
    local output_file="$2"

    if ! command -v security &>/dev/null; then
        return 1
    fi

    # Chercher dans tous les keychains (System, Login, System Roots)
    local keychains=(
        "/Library/Keychains/System.keychain"
        "$HOME/Library/Keychains/login.keychain-db"
        "/System/Library/Keychains/SystemRootCertificates.keychain"
    )

    for keychain in "${keychains[@]}"; do
        [[ ! -f "$keychain" ]] && continue

        # Extraire les certificats correspondant au CN
        local cert_pem
        cert_pem=$(security find-certificate -c "$target_cn" -p "$keychain" 2>/dev/null)

        if [[ -n "$cert_pem" ]]; then
            echo "$cert_pem" > "$output_file"

            # Verifier que c'est un certificat valide
            if openssl x509 -in "$output_file" -noout 2>/dev/null; then
                return 0
            fi

            # Essayer en DER si PEM echoue
            rm -f "$output_file"
        fi
    done

    return 1
}

# Linux : chercher les certificats dans les stores systeme
extract_from_linux_store() {
    local target_cn="$1"
    local output_file="$2"

    local search_dirs=(
        "/etc/ssl/certs"
        "/usr/local/share/ca-certificates"
        "/usr/share/ca-certificates"
        "/etc/pki/ca-trust/source/anchors"
        "/etc/pki/tls/certs"
    )

    for dir in "${search_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue

        # Chercher dans les fichiers .pem et .crt
        while IFS= read -r cert_file; do
            [[ ! -f "$cert_file" ]] && continue

            # Verifier si le sujet contient le CN recherche
            local subject
            subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null)

            if echo "$subject" | grep -q "CN.*=.*${target_cn}"; then
                # Extraire en PEM
                openssl x509 -in "$cert_file" -out "$output_file" -outform PEM 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    return 0
                fi
            fi
        done < <(find "$dir" -maxdepth 2 -type f \( -name "*.pem" -o -name "*.crt" -o -name "*.cer" \) 2>/dev/null)
    done

    return 1
}

# WSL : extraire depuis le store Windows via PowerShell
extract_from_windows_store() {
    local target_cn="$1"
    local output_file="$2"

    # Verifier que PowerShell est accessible
    local ps_cmd=""
    if command -v powershell.exe &>/dev/null; then
        ps_cmd="powershell.exe"
    elif command -v /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe &>/dev/null; then
        ps_cmd="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    else
        return 1
    fi

    # Script PowerShell pour exporter le certificat en Base64
    local ps_script="
\$cert = Get-ChildItem -Path Cert:\\LocalMachine\\Root, Cert:\\LocalMachine\\CA -Recurse |
    Where-Object { \$_.Subject -match '${target_cn}' } |
    Select-Object -First 1

if (\$cert) {
    \$base64 = [Convert]::ToBase64String(\$cert.RawData, 'InsertLineBreaks')
    Write-Output '-----BEGIN CERTIFICATE-----'
    Write-Output \$base64
    Write-Output '-----END CERTIFICATE-----'
}
"

    local cert_pem
    cert_pem=$($ps_cmd -NoProfile -NonInteractive -Command "$ps_script" 2>/dev/null)

    if [[ -n "$cert_pem" ]] && echo "$cert_pem" | grep -q "BEGIN CERTIFICATE"; then
        # Convertir les retours chariot Windows
        echo "$cert_pem" | tr -d '\r' > "$output_file"

        if openssl x509 -in "$output_file" -noout 2>/dev/null; then
            return 0
        fi
        rm -f "$output_file"
    fi

    return 1
}

# Chercher dans des fichiers locaux (~/Downloads, etc.)
extract_from_local_files() {
    local target_cn="$1"
    local output_file="$2"

    local search_dirs=(
        "$HOME/Downloads"
        "$HOME/Desktop"
        "$HOME/Documents"
        "$SSL_DIR"
    )

    for dir in "${search_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue

        while IFS= read -r cert_file; do
            [[ ! -f "$cert_file" ]] && continue

            local subject=""

            # Essayer en PEM
            subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null)

            # Essayer en DER si PEM echoue
            if [[ -z "$subject" ]]; then
                subject=$(openssl x509 -in "$cert_file" -inform DER -noout -subject 2>/dev/null)
                if echo "$subject" | grep -q "CN.*=.*${target_cn}"; then
                    openssl x509 -in "$cert_file" -inform DER -out "$output_file" -outform PEM 2>/dev/null
                    if [[ $? -eq 0 ]]; then
                        return 0
                    fi
                fi
                continue
            fi

            if echo "$subject" | grep -q "CN.*=.*${target_cn}"; then
                openssl x509 -in "$cert_file" -out "$output_file" -outform PEM 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    return 0
                fi
            fi
        done < <(find "$dir" -maxdepth 1 -type f \( -name "*.pem" -o -name "*.crt" -o -name "*.cer" -o -name "*.der" \) 2>/dev/null)
    done

    return 1
}

# --- Fonction principale ---

main() {
    local platform
    platform=$(detect_platform)

    $QUIET || echo -e "\n${BOLD}=== Configuration SSL/TLS ===${NC}"
    log_info "Plateforme detectee : $platform"

    # Verifier qu'openssl est disponible
    if ! command -v openssl &>/dev/null; then
        log_error "openssl est requis mais non installe"
        return 1
    fi

    # Verifier si le bundle existe deja
    if [[ -f "$BUNDLE_FILE" ]] && ! $FORCE; then
        log_success "CA bundle existant : $BUNDLE_FILE ($(wc -l < "$BUNDLE_FILE" | tr -d ' ') lignes)"
        log_info "Utilisez --force pour recreer le bundle"
        return 0
    fi

    # Creer les repertoires
    mkdir -p "$SSL_DIR" "$ENTERPRISE_DIR"

    # --- Etape 1 : Detecter les certificats entreprise ---
    log_info "Recherche des certificats entreprise..."

    local found_count=0
    local enterprise_certs=()

    for issuer_cn in "${ENTERPRISE_ISSUERS[@]}"; do
        local cert_file="$ENTERPRISE_DIR/${issuer_cn}.pem"
        local found=false

        # Strategie de recherche par plateforme
        case "$platform" in
            macos)
                if extract_from_keychain "$issuer_cn" "$cert_file"; then
                    found=true
                fi
                ;;
            wsl)
                if extract_from_windows_store "$issuer_cn" "$cert_file"; then
                    found=true
                elif extract_from_linux_store "$issuer_cn" "$cert_file"; then
                    found=true
                fi
                ;;
            linux)
                if extract_from_linux_store "$issuer_cn" "$cert_file"; then
                    found=true
                fi
                ;;
        esac

        # Fallback : chercher dans les fichiers locaux
        if ! $found; then
            if extract_from_local_files "$issuer_cn" "$cert_file"; then
                found=true
            fi
        fi

        if $found; then
            ((found_count++))
            enterprise_certs+=("$cert_file")
            local cert_subject
            cert_subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
            log_success "Trouve : ${issuer_cn} ${DIM}(${cert_subject})${NC}"
        else
            log_warn "Non trouve : ${issuer_cn}"
        fi
    done

    if [[ $found_count -eq 0 ]]; then
        log_warn "Aucun certificat entreprise detecte"
        log_info "Les certificats seront recherches au prochain lancement"
        return 0
    fi

    # --- Etape 2 : Localiser le CA bundle systeme ---
    log_info "Recherche du CA bundle systeme..."

    local system_bundle
    system_bundle=$(find_system_ca_bundle)

    if [[ -z "$system_bundle" ]]; then
        log_error "Impossible de trouver le CA bundle systeme"
        log_info "Vous pouvez specifier le chemin avec: SSL_SYSTEM_CA_BUNDLE=/path/to/ca-bundle.pem"
        return 1
    fi

    log_success "CA bundle systeme : $system_bundle"

    # --- Etape 3 : Assembler le bundle ---
    log_info "Creation du CA bundle unifie..."

    # Commencer avec le bundle systeme
    cp "$system_bundle" "$BUNDLE_FILE.tmp"

    # Ajouter les certificats entreprise
    for cert in "${enterprise_certs[@]}"; do
        local cn
        cn=$(basename "$cert" .pem)
        echo "" >> "$BUNDLE_FILE.tmp"
        echo "# === Enterprise CA: ${cn} ===" >> "$BUNDLE_FILE.tmp"
        cat "$cert" >> "$BUNDLE_FILE.tmp"
    done

    # Remplacer atomiquement
    mv "$BUNDLE_FILE.tmp" "$BUNDLE_FILE"

    local total_certs
    total_certs=$(grep -c "BEGIN CERTIFICATE" "$BUNDLE_FILE")
    local line_count
    line_count=$(wc -l < "$BUNDLE_FILE" | tr -d ' ')

    log_success "CA bundle cree : $BUNDLE_FILE"
    log_info "  Certificats : ${total_certs} (dont ${found_count} entreprise)"
    log_info "  Taille : ${line_count} lignes"

    # --- Etape 4 : Rappel des variables d'environnement ---
    $QUIET || echo ""
    $QUIET || echo -e "${BOLD}Variables d'environnement (configurees par variables.zsh) :${NC}"
    $QUIET || echo -e "  ${DIM}SSL_CERT_FILE=$BUNDLE_FILE${NC}"
    $QUIET || echo -e "  ${DIM}CURL_CA_BUNDLE=$BUNDLE_FILE${NC}"
    $QUIET || echo -e "  ${DIM}REQUESTS_CA_BUNDLE=$BUNDLE_FILE${NC}"
    $QUIET || echo -e "  ${DIM}NODE_EXTRA_CA_CERTS=$BUNDLE_FILE${NC}"

    return 0
}

main "$@"
