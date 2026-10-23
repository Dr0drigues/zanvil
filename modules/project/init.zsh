[[ "${ZANVIL_MODULE_PROJECT:-true}" == true ]] || return 0

source "$ZANVIL_DIR/modules/project/project.zsh"

# menage quotidien des worktrees de MR terminees : en arriere-plan, rien au premier plan
if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && (( $+commands[glab] )); then _project_clean_daily; fi
