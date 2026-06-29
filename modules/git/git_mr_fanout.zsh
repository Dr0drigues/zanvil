# ==============================================================================
# Git MR Fanout - Propage un changement (commit, range, patch worktree) en MR/PR
# sur plusieurs branches d'environnement, en une commande.
# ==============================================================================
# Usage:
#   zanvil-mr-fanout [--mode cherry|range|patch] [--target <br>]... [--all]
#                     [--title "..."] [--description "..."] [--draft]
#                     [--no-push|--no-mr|--dry-run|--strict]
#                     [--from <ref>] [--pattern <regex>] [--branch-prefix <s>]
#
# Detecte automatiquement gh (GitHub) ou glab (GitLab) selon l'URL du remote.
# La selection des branches cibles utilise fzf si dispo, sinon prompt textuel.
# ==============================================================================

zanvil-mr-fanout() {
    if ! command -v zanvil &>/dev/null; then
        _ui_msg_fail "zanvil requis (cd ~/.zanvil/cli && cargo install --path .)"
        return 1
    fi
    zanvil mr-fanout "$@"
}

# Alias courts
alias mrfan='zanvil-mr-fanout'
alias mrfo='zanvil-mr-fanout'
