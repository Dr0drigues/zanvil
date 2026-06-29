# ==============================================================================
# delta — Pager syntaxique pour git diff
# Guard: ZANVIL_MODULE_DELTA=true dans config.zsh
# ==============================================================================

[[ "${ZANVIL_MODULE_DELTA:-}" != "true" ]] && return 0

if command -v delta &>/dev/null; then
    delta_setup() {
        _ui_header "delta"
        local include_file="${HOME}/.gitconfig.d/delta"
        local gitconfig="${HOME}/.gitconfig"

        mkdir -p "${HOME}/.gitconfig.d"
        if [[ ! -f "${ZANVIL_DIR}/config/delta/gitconfig" ]]; then
            _ui_msg_fail "Source manquante: ${ZANVIL_DIR}/config/delta/gitconfig"
            return 1
        fi
        cp "${ZANVIL_DIR}/config/delta/gitconfig" "${include_file}"

        if ! grep -q "gitconfig.d/delta" "${gitconfig}" 2>/dev/null; then
            printf '\n[include]\n\tpath = %s\n' "${include_file}" >> "${gitconfig}"
            _ui_msg_ok "include ajouté dans ${gitconfig}"
        else
            _ui_msg_ok "include déjà présent"
        fi

        local lg_config="${ZANVIL_DIR}/config/lazygit/config.yml"
        if [[ -f "${lg_config}" ]]; then
            if ! grep -q "pager: delta" "${lg_config}"; then
                awk '/colorArg: always/{print; print "    pager: delta --dark --paging=never"; next}1' \
                    "${lg_config}" > "${lg_config}.tmp"
                if grep -q "pager: delta" "${lg_config}.tmp" 2>/dev/null; then
                    mv "${lg_config}.tmp" "${lg_config}"
                    _ui_msg_ok "pager delta ajouté dans lazygit/config.yml"
                else
                    rm -f "${lg_config}.tmp"
                    _ui_msg_warn "Pattern colorArg non trouvé dans lazygit/config.yml — ajout manuel requis"
                fi
            else
                _ui_msg_ok "lazygit pager déjà configuré"
            fi
        fi

        _ui_section "Version" "$(delta --version 2>/dev/null)"
        _ui_section "Config" "${include_file}"
    }
else
    echo "[zanvil] delta: module activé mais binaire absent — brew install git-delta"
fi
