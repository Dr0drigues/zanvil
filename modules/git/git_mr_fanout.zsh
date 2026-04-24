# ==============================================================================
# Git MR Fanout - Propage un changement (commit, range, patch worktree) en MR/PR
# sur plusieurs branches d'environnement, en une commande.
# ==============================================================================
# Usage:
#   zsh-env-mr-fanout [--mode cherry|range|patch] [--target <br>]... [--all]
#                     [--title "..."] [--description "..."] [--draft]
#                     [--no-push|--no-mr|--dry-run|--strict]
#                     [--from <ref>] [--pattern <regex>] [--branch-prefix <s>]
#
# Detecte automatiquement gh (GitHub) ou glab (GitLab) selon l'URL du remote.
# La selection des branches cibles utilise fzf si dispo, sinon prompt textuel.
# ==============================================================================

zsh-env-mr-fanout() {
    if ! command -v zsh-env-cli &>/dev/null; then
        _ui_msg_fail "zsh-env-cli requis (cd ~/.zsh_env/cli && cargo install --path .)"
        return 1
    fi
    zsh-env-cli mr-fanout "$@"
}

# Alias courts
alias mrfan='zsh-env-mr-fanout'
alias mrfo='zsh-env-mr-fanout'
