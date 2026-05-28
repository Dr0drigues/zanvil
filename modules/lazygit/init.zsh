# ==============================================================================
# lazygit — TUI Git ergonomique
# Guard: ZSH_ENV_MODULE_LAZYGIT=true dans config.zsh
# ==============================================================================

[[ "${ZSH_ENV_MODULE_LAZYGIT:-}" != "true" ]] && return 0

if command -v lazygit &>/dev/null; then
    export LG_CONFIG_FILE="${ZSH_ENV_DIR}/lazygit/config.yml:${HOME}/.config/lazygit/config-local.yml"
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
fi
