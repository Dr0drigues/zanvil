# ==============================================================================
# Security Audit - Verification de la securite des configs
# ==============================================================================
# Verifie les permissions, detecte les problemes potentiels
# ==============================================================================

# Couleurs
_audit_ok() { echo "\033[32m[OK]\033[0m $1"; }
_audit_warn() { echo "\033[33m[WARN]\033[0m $1"; }
_audit_fail() { echo "\033[31m[FAIL]\033[0m $1"; }
_audit_info() { echo "\033[34m[INFO]\033[0m $1"; }

# Verifie les permissions d'un fichier
_audit_check_perms() {
    local file="$1"
    local expected="$2"
    local desc="$3"

    if [[ ! -e "$file" ]]; then
        return 1
    fi

    local perms=$(stat -f "%Lp" "$file" 2>/dev/null || stat -c "%a" "$file" 2>/dev/null)

    if [[ "$perms" == "$expected" ]]; then
        _audit_ok "$desc ($file) - permissions $perms"
        return 0
    else
        _audit_fail "$desc ($file) - permissions $perms (attendu: $expected)"
        return 1
    fi
}

# Audit principal
zsh-env-audit() {
    local issues=0
    local warnings=0

    echo "Audit de securite zsh_env"
    echo "══════════════════════════════════════════════════════════════"
    echo ""

    # --- Section: Dossier SSH ---
    echo "SSH"
    echo "──────────────────────────────────────────"

    if [[ -d "$HOME/.ssh" ]]; then
        _audit_check_perms "$HOME/.ssh" "700" "Dossier SSH" || ((issues++))

        # Cles privees
        for key in "$HOME/.ssh"/id_* "$HOME/.ssh"/*.pem; do
            [[ ! -f "$key" ]] && continue
            [[ "$key" == *.pub ]] && continue

            local perms=$(stat -f "%Lp" "$key" 2>/dev/null || stat -c "%a" "$key" 2>/dev/null)
            if [[ "$perms" != "600" && "$perms" != "400" ]]; then
                _audit_fail "Cle privee $key - permissions $perms (attendu: 600)"
                ((issues++))
            else
                _audit_ok "Cle privee $(basename "$key") - permissions $perms"
            fi
        done

        # Config SSH
        [[ -f "$HOME/.ssh/config" ]] && {
            _audit_check_perms "$HOME/.ssh/config" "600" "Config SSH" || ((issues++))
        }

        # Known hosts
        [[ -f "$HOME/.ssh/known_hosts" ]] && {
            _audit_check_perms "$HOME/.ssh/known_hosts" "644" "Known hosts" || true
        }
    else
        _audit_info "Dossier ~/.ssh non present"
    fi

    echo ""

    # --- Section: Secrets ---
    echo "Fichiers secrets"
    echo "──────────────────────────────────────────"

    local secret_files=(
        "$HOME/.secrets"
        "$HOME/.gitlab_secrets"
        "$HOME/.env"
        "$HOME/.netrc"
        "$HOME/.npmrc"
        "$HOME/.pypirc"
    )

    for secret in "${secret_files[@]}"; do
        if [[ -f "$secret" ]]; then
            local perms=$(stat -f "%Lp" "$secret" 2>/dev/null || stat -c "%a" "$secret" 2>/dev/null)
            if [[ "$perms" != "600" && "$perms" != "400" ]]; then
                _audit_fail "$(basename "$secret") - permissions $perms (attendu: 600)"
                ((issues++))
            else
                _audit_ok "$(basename "$secret") - permissions $perms"
            fi

            # Verifier si contient des tokens/passwords en clair
            if grep -qiE "(password|token|secret|key)[[:space:]]*=" "$secret" 2>/dev/null; then
                _audit_info "$(basename "$secret") contient des credentials (normal si chiffre ou protected)"
            fi
        fi
    done

    echo ""

    # --- Section: Kubeconfig ---
    echo "Kubernetes configs"
    echo "──────────────────────────────────────────"

    if [[ -d "$HOME/.kube" ]]; then
        _audit_check_perms "$HOME/.kube" "700" "Dossier .kube" || ((warnings++))

        for kube in "$HOME/.kube"/config* "$HOME/.kube"/kubeconfig* "$HOME/.kube/configs.d"/*; do
            [[ ! -f "$kube" ]] && continue

            local perms=$(stat -f "%Lp" "$kube" 2>/dev/null || stat -c "%a" "$kube" 2>/dev/null)
            local name=$(basename "$kube")

            if [[ "$perms" != "600" && "$perms" != "400" ]]; then
                _audit_warn "$name - permissions $perms (recommande: 600)"
                ((warnings++))
            else
                _audit_ok "$name - permissions $perms"
            fi

            # Verifier si contient des tokens en clair (pas de certificat)
            if grep -q "client-certificate-data\|client-key-data\|token:" "$kube" 2>/dev/null; then
                _audit_info "$name contient des credentials inline"
            fi
        done
    else
        _audit_info "Dossier ~/.kube non present"
    fi

    echo ""

    # --- Section: Git ---
    echo "Git"
    echo "──────────────────────────────────────────"

    if [[ -f "$HOME/.gitconfig" ]]; then
        # Verifier si credential helper est configure
        if grep -qi "helper" "$HOME/.gitconfig" 2>/dev/null; then
            local helper=$(git config --global credential.helper 2>/dev/null)
            _audit_ok "Credential helper configure: $helper"
        else
            _audit_warn "Pas de credential helper configure"
            ((warnings++))
        fi
    fi

    # Verifier les fichiers credentials en clair
    if [[ -f "$HOME/.git-credentials" ]]; then
        _audit_warn "Fichier .git-credentials present (credentials en clair)"
        _audit_check_perms "$HOME/.git-credentials" "600" "Git credentials" || ((issues++))
        ((warnings++))
    fi

    echo ""

    # --- Section: AWS ---
    echo "Cloud credentials"
    echo "──────────────────────────────────────────"

    if [[ -d "$HOME/.aws" ]]; then
        [[ -f "$HOME/.aws/credentials" ]] && {
            _audit_check_perms "$HOME/.aws/credentials" "600" "AWS credentials" || ((issues++))
        }
    fi

    if [[ -d "$HOME/.azure" ]]; then
        _audit_info "Azure CLI configure (~/.azure)"
    fi

    if [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
        _audit_check_perms "$HOME/.config/gcloud/application_default_credentials.json" "600" "GCP credentials" || ((issues++))
    fi

    echo ""

    # --- Section: History ---
    echo "Historique shell"
    echo "──────────────────────────────────────────"

    local history_files=(
        "$HOME/.zsh_history"
        "$HOME/.bash_history"
        "$HOME/.node_repl_history"
        "$HOME/.python_history"
    )

    for hist in "${history_files[@]}"; do
        if [[ -f "$hist" ]]; then
            local perms=$(stat -f "%Lp" "$hist" 2>/dev/null || stat -c "%a" "$hist" 2>/dev/null)
            if [[ "$perms" != "600" ]]; then
                _audit_warn "$(basename "$hist") - permissions $perms (recommande: 600)"
                ((warnings++))
            else
                _audit_ok "$(basename "$hist") - permissions $perms"
            fi

            # Verifier si contient des secrets potentiels
            if grep -qiE "(password|secret|token|api.?key)=" "$hist" 2>/dev/null; then
                _audit_warn "$(basename "$hist") pourrait contenir des secrets"
                ((warnings++))
            fi
        fi
    done

    echo ""

    # --- Resume ---
    echo "══════════════════════════════════════════════════════════════"
    echo "Resume:"

    if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
        _audit_ok "Aucun probleme detecte"
    else
        [[ $issues -gt 0 ]] && _audit_fail "$issues probleme(s) critique(s)"
        [[ $warnings -gt 0 ]] && _audit_warn "$warnings avertissement(s)"
    fi

    echo ""

    # --- Actions correctives ---
    if [[ $issues -gt 0 ]]; then
        echo "Actions recommandees:"
        echo "  chmod 700 ~/.ssh"
        echo "  chmod 600 ~/.ssh/id_* ~/.ssh/config"
        echo "  chmod 600 ~/.secrets ~/.kube/config*"
    fi

    return $issues
}

# Corrige automatiquement les permissions
zsh-env-audit-fix() {
    echo "Correction automatique des permissions..."
    echo ""

    local fixed=0

    # SSH
    [[ -d "$HOME/.ssh" ]] && chmod 700 "$HOME/.ssh" && ((fixed++))
    for key in "$HOME/.ssh"/id_*; do
        [[ -f "$key" && ! "$key" == *.pub ]] && chmod 600 "$key" && ((fixed++))
    done
    [[ -f "$HOME/.ssh/config" ]] && chmod 600 "$HOME/.ssh/config" && ((fixed++))

    # Secrets
    [[ -f "$HOME/.secrets" ]] && chmod 600 "$HOME/.secrets" && ((fixed++))
    [[ -f "$HOME/.gitlab_secrets" ]] && chmod 600 "$HOME/.gitlab_secrets" && ((fixed++))

    # Kube
    [[ -d "$HOME/.kube" ]] && chmod 700 "$HOME/.kube" && ((fixed++))
    for kube in "$HOME/.kube"/config* "$HOME/.kube/configs.d"/*; do
        [[ -f "$kube" ]] && chmod 600 "$kube" && ((fixed++))
    done

    # AWS
    [[ -f "$HOME/.aws/credentials" ]] && chmod 600 "$HOME/.aws/credentials" && ((fixed++))

    # History
    [[ -f "$HOME/.zsh_history" ]] && chmod 600 "$HOME/.zsh_history" && ((fixed++))

    echo "$fixed fichier(s) corrige(s)."
    echo ""
    echo "Relancez 'zsh-env-audit' pour verifier."
}
