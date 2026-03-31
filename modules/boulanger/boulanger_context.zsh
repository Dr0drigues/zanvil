# ==============================================================================
# Boulanger Context Detection
# ==============================================================================
# Detection automatique du contexte professionnel Boulanger
# Test d'acces au Nexus interne avec cache de 5 minutes
# Utilise les fonctions UI de ui.zsh
# ==============================================================================

# --- Configuration (surchargeable via config.zsh) ---
_BLG_NEXUS_URL="${ZSH_ENV_BLG_NEXUS_URL:-https://nexus.forge.tsc.azr.intranet}"
_BLG_CACHE_FILE="${ZSH_ENV_DIR:-$HOME/.zsh_env}/.boulanger_context_cache"
_BLG_CACHE_TTL="${ZSH_ENV_BLG_CACHE_TTL:-300}"       # 5 minutes en secondes
_BLG_TIMEOUT="${ZSH_ENV_BLG_TIMEOUT:-2}"              # Timeout en secondes pour le test

# --- Fonctions internes ---

# Retourne le timestamp actuel en secondes
_blg_timestamp() {
    date +%s
}

# Verifie si le cache est encore valide
_blg_cache_valid() {
    [[ ! -f "$_BLG_CACHE_FILE" ]] && return 1

    local cached_time cached_value
    cached_time=$(head -1 "$_BLG_CACHE_FILE" 2>/dev/null)
    cached_value=$(tail -1 "$_BLG_CACHE_FILE" 2>/dev/null)

    [[ -z "$cached_time" ]] && return 1

    local now=$(_blg_timestamp)
    local age=$((now - cached_time))

    if (( age < _BLG_CACHE_TTL )); then
        # Cache valide, retourne la valeur cachee
        [[ "$cached_value" == "true" ]] && return 0 || return 1
    fi

    return 1  # Cache expire
}

# Met a jour le cache
_blg_cache_write() {
    local value=$1
    echo "$(_blg_timestamp)" > "$_BLG_CACHE_FILE"
    echo "$value" >> "$_BLG_CACHE_FILE"
}

# Test reel d'acces au Nexus
_blg_test_nexus() {
    if command -v curl &>/dev/null; then
        local _curl_opts="-s --connect-timeout $_BLG_TIMEOUT --max-time $_BLG_TIMEOUT"
        [[ -n "$SSL_CERT_FILE" ]] && _curl_opts+=" --cacert $SSL_CERT_FILE"
        curl $_curl_opts -o /dev/null -w "%{http_code}" \
            "$_BLG_NEXUS_URL" 2>/dev/null | grep -q "^[23]"
        return $?
    elif command -v wget &>/dev/null; then
        wget -q --spider --timeout="$_BLG_TIMEOUT" "$_BLG_NEXUS_URL" 2>/dev/null
        return $?
    fi
    return 1
}

# --- Fonctions publiques ---

# Teste si on est dans le contexte Boulanger (avec cache)
blg_is_context() {
    # Verifier le cache d'abord
    if _blg_cache_valid; then
        return 0
    fi

    # Verifier si le cache existe mais est "false"
    if [[ -f "$_BLG_CACHE_FILE" ]]; then
        local cached_time cached_value
        cached_time=$(head -1 "$_BLG_CACHE_FILE" 2>/dev/null)
        cached_value=$(tail -1 "$_BLG_CACHE_FILE" 2>/dev/null)
        local now=$(_blg_timestamp)
        local age=$((now - cached_time))

        if (( age < _BLG_CACHE_TTL )) && [[ "$cached_value" == "false" ]]; then
            return 1
        fi
    fi

    # Test reel
    if _blg_test_nexus; then
        _blg_cache_write "true"
        return 0
    else
        _blg_cache_write "false"
        return 1
    fi
}

# Force la re-detection (invalide le cache)
blg_refresh() {
    rm -f "$_BLG_CACHE_FILE"
    if blg_is_context; then
        echo "Contexte Boulanger detecte - fichiers dechiffres"
        blg_init
    else
        echo "Hors contexte Boulanger"
    fi
}

# Initialise le contexte Boulanger (dechiffre les fichiers si necessaire)
blg_init() {
    local zsh_env_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}"
    local decrypted_count=0

    # Verifier que sops est disponible
    if ! command -v sops &>/dev/null; then
        return 1
    fi

    local blg_dir="$zsh_env_dir/boulanger"

    # Dechiffrer settings.xml.enc si existe et pas deja dechiffre
    if [[ -f "$blg_dir/settings.xml.enc" && ! -f "$blg_dir/settings.xml" ]]; then
        if sops -d "$blg_dir/settings.xml.enc" > "$blg_dir/settings.xml" 2>/dev/null; then
            ((decrypted_count++))
        fi
    fi

    # Dechiffrer certificates_unix.sh.enc si existe et pas deja dechiffre
    if [[ -f "$blg_dir/certificates_unix.sh.enc" && ! -f "$blg_dir/certificates_unix.sh" ]]; then
        if sops -d "$blg_dir/certificates_unix.sh.enc" > "$blg_dir/certificates_unix.sh" 2>/dev/null; then
            chmod +x "$blg_dir/certificates_unix.sh"
            ((decrypted_count++))
        fi
    fi

    # Activer le module GitLab si en contexte
    export ZSH_ENV_MODULE_GITLAB=true

    return 0
}

# Affiche l'etat du contexte Boulanger
blg_status() {
    local zsh_env_dir="${ZSH_ENV_DIR:-$HOME/.zsh_env}"

    _ui_header "Contexte Boulanger"

    # Statut de la detection
    if blg_is_context; then
        _ui_section "Reseau" "${_ui_green}Connecte (Nexus accessible)${_ui_nc}"
    else
        _ui_section "Reseau" "${_ui_red}Non connecte${_ui_nc}"
    fi

    # Statut du cache
    if [[ -f "$_BLG_CACHE_FILE" ]]; then
        local cached_time cached_value
        cached_time=$(head -1 "$_BLG_CACHE_FILE" 2>/dev/null)
        cached_value=$(tail -1 "$_BLG_CACHE_FILE" 2>/dev/null)
        local now=$(_blg_timestamp)
        local age=$((now - cached_time))
        local remaining=$((_BLG_CACHE_TTL - age))

        if (( remaining > 0 )); then
            _ui_section "Cache" "Valide (expire dans ${remaining}s)"
        else
            _ui_section "Cache" "Expire"
        fi
    else
        _ui_section "Cache" "Non initialise"
    fi

    echo ""
    echo -e "${_ui_bold}Fichiers${_ui_nc}"
    _ui_separator 44

    # Statut des fichiers chiffres/dechiffres
    local blg_dir="$zsh_env_dir/boulanger"
    local files=("settings.xml" "certificates_unix.sh")
    for file in "${files[@]}"; do
        local enc_file="$blg_dir/${file}.enc"
        local dec_file="$blg_dir/$file"

        if [[ -f "$dec_file" && -f "$enc_file" ]]; then
            echo -e "  $file: ${_ui_green}Dechiffre${_ui_nc}"
        elif [[ -f "$enc_file" ]]; then
            echo -e "  $file: ${_ui_yellow}Chiffre (non dechiffre)${_ui_nc}"
        elif [[ -f "$dec_file" ]]; then
            echo -e "  $file: ${_ui_yellow}En clair (non chiffre)${_ui_nc}"
        else
            echo -e "  $file: ${_ui_red}Absent${_ui_nc}"
        fi
    done

    echo ""
    echo -e "${_ui_bold}Modules${_ui_nc}"
    _ui_separator 44
    _ui_section "GitLab" "${ZSH_ENV_MODULE_GITLAB:-false}"

    # Mise
    if command -v mise &> /dev/null; then
        _ui_section "Mise" "Installe ($(mise --version 2>/dev/null | awk '{print $1}'))"
    else
        _ui_section "Mise" "Non installe"
    fi
}

# --- Auto-initialisation au chargement ---
# Ne s'execute que si on detecte le contexte Boulanger (test rapide via cache ou reseau)
if blg_is_context; then
    blg_init
fi
