# ==============================================================================
# lazygit — TUI Git ergonomique
# Guard: ZANVIL_MODULE_LAZYGIT=true dans config.zsh
# ==============================================================================

[[ "${ZANVIL_MODULE_LAZYGIT:-}" != "true" ]] && return 0

if command -v lazygit &>/dev/null; then
    local _lg_config="${ZANVIL_DIR}/lazygit/config.yml"
    local _lg_local="${HOME}/.config/lazygit/config-local.yml"
    if [[ -f "$_lg_local" ]]; then
        export LG_CONFIG_FILE="${_lg_config},${_lg_local}"
    else
        export LG_CONFIG_FILE="${_lg_config}"
    fi
    unset _lg_config _lg_local
    export LAZYGIT_NEW_DIR_FILE="${HOME}/.lazygit/newdir"
    mkdir -p "${HOME}/.lazygit"

    lg() {
        lazygit "$@"
        if [[ -f "${LAZYGIT_NEW_DIR_FILE}" ]]; then
            local newdir
            newdir="$(cat "${LAZYGIT_NEW_DIR_FILE}")"
            rm -f "${LAZYGIT_NEW_DIR_FILE}"
            [[ -d "${newdir}" ]] && cd "${newdir}"
        fi
    }

    lazygit_setup() {
        _ui_header "lazygit"
        _ui_section "Version" "$(lazygit --version 2>/dev/null | head -1)"
        _ui_section "Config" "${LG_CONFIG_FILE}"
        echo ""
        local local_cfg="${HOME}/.config/lazygit/config-local.yml"
        if [[ -f "${local_cfg}" ]]; then
            _ui_ok "config-local.yml"
            echo ""
        else
            _ui_warn "config-local.yml"
            echo ""
            _ui_section "Créer" "touch ${local_cfg}"
        fi
    }
else
    echo "[zanvil] lazygit: module activé mais binaire absent — brew install lazygit"
fi
