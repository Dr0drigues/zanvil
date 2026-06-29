[[ "${ZANVIL_MODULE_POSTING:-}" != "true" ]] && return 0

if command -v posting &>/dev/null; then
    posting_setup() {
        _ui_header "posting"
        local config_src="${ZANVIL_DIR}/config/posting/config.yaml"
        local config_dst="${HOME}/.config/posting/config.yaml"

        if [[ ! -f "${config_src}" ]]; then
            _ui_msg_fail "Source manquante: ${config_src}"
            return 1
        fi

        mkdir -p "${HOME}/.config/posting"
        cp "${config_src}" "${config_dst}"
        _ui_msg_ok "config.yaml déployée"

        _ui_section "Version" "$(posting --version 2>/dev/null)"
        _ui_section "Config" "${config_dst}"
    }

    alias po='posting'
else
    echo "[zanvil] posting: module activé mais binaire absent — brew install posting"
fi
