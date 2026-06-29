# ==============================================================================
# atuin — Historique shell enrichi (SQLite local, TUI fuzzy)
# Guard: ZANVIL_MODULE_ATUIN=true dans config.zsh
# Note: atuin init zsh est dans core/hooks.zsh (après fzf et keybindings)
# ==============================================================================

[[ "${ZANVIL_MODULE_ATUIN:-}" != "true" ]] && return 0

if command -v atuin &>/dev/null; then
    atuin_setup() {
        _ui_header "atuin"
        local config_src="${ZANVIL_DIR}/config/atuin/config.toml"
        local config_dst="${HOME}/.config/atuin/config.toml"

        if [[ ! -f "${config_src}" ]]; then
            _ui_msg_fail "Source manquante: ${config_src}"
            return 1
        fi

        mkdir -p "${HOME}/.config/atuin"
        cp "${config_src}" "${config_dst}"
        _ui_msg_ok "config.toml déployée"

        _ui_section "Version" "$(atuin --version 2>/dev/null)"
        _ui_section "Config" "${config_dst}"
        local db_path
        db_path="$(atuin info 2>/dev/null | grep -i 'database' | head -1 | cut -d: -f2- | xargs)"
        [[ -n "${db_path}" ]] && _ui_section "DB" "${db_path}"
    }
else
    echo "[zanvil] atuin: module activé mais binaire absent — brew install atuin"
fi
