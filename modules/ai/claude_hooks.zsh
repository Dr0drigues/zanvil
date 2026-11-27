# ==============================================================================
# ai_claude_hooks : sessions Claude Code en attente -> SketchyBar
# ==============================================================================
# Ajoute a ~/.claude/settings.json des hooks qui appellent scripts/claude-bar-hook.sh :
# Notification et Stop marquent la session « en attente », UserPromptSubmit et SessionEnd la
# retirent. L'element SketchyBar (dotfiles) compte les sessions en attente.
# Fusion par jq : les hooks existants restent, les notres portent le marqueur
# `# zanvil-claude-bar` qui permet de les remplacer ou de les retirer seuls.

_AI_CLAUDE_MARK="# zanvil-claude-bar"

_ai_claude_settings() { print -r -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; }

# Retire nos entrees (et les groupes devenus vides) ; les evenements vides disparaissent.
_AI_CLAUDE_JQ_STRIP='
  def strip: map(.hooks |= map(select((.command // "") | contains($mark) | not)))
             | map(select((.hooks | length) > 0));
  if .hooks then .hooks |= (with_entries(.value |= strip) | with_entries(select(.value | length > 0)))
                 | (if .hooks == {} then del(.hooks) else . end)
  else . end'

ai_claude_hooks() {
    local action="${1:-status}" file
    file=$(_ai_claude_settings)
    command -v jq &>/dev/null || { _ui_msg_fail "jq requis"; return 1; }
    case "$action" in
        install)
            local script="$ZANVIL_DIR/scripts/claude-bar-hook.sh"
            [[ -x "$script" ]] || { _ui_msg_fail "Script introuvable : $script"; return 1; }
            [[ -f "$file" ]] || { mkdir -p "${file:h}" && print '{}' > "$file"; }
            jq empty "$file" 2>/dev/null || { _ui_msg_fail "JSON invalide : $file (rien modifie)"; return 1; }
            local target="${file:A}" tmp   # lien symbolique : on ecrit sa cible, le lien reste
            tmp=$(mktemp "${target}.XXXXXX") || return 1
            if jq --arg mark "$_AI_CLAUDE_MARK" --arg s "$script" "$_AI_CLAUDE_JQ_STRIP"'
                | def h($a): {type: "command", command: ("\"" + $s + "\" " + $a + " " + $mark), timeout: 2};
                  .hooks.Notification     += [{matcher: "", hooks: [h("waiting")]}]
                | .hooks.Stop             += [{hooks: [h("waiting")]}]
                | .hooks.UserPromptSubmit += [{hooks: [h("working")]}]
                | .hooks.SessionEnd       += [{hooks: [h("end")]}]' "$file" > "$tmp"; then
                cp "$target" "$target.bak-zanvil" && mv "$tmp" "$target"
                _ui_msg_ok "Hooks installes dans $file (sauvegarde : $target.bak-zanvil)"
                _ui_msg_info "Prise en compte : nouvelles sessions Claude Code"
            else
                command rm -f "$tmp"; _ui_msg_fail "Fusion impossible, rien modifie"; return 1
            fi
            ;;
        uninstall)
            [[ -f "$file" ]] || { _ui_msg_ok "Rien a retirer"; return 0; }
            local target="${file:A}" tmp
            tmp=$(mktemp "${target}.XXXXXX") || return 1
            if jq --arg mark "$_AI_CLAUDE_MARK" "$_AI_CLAUDE_JQ_STRIP" "$file" > "$tmp"; then
                mv "$tmp" "$target"; _ui_msg_ok "Hooks zanvil retires de $file"
            else
                command rm -f "$tmp"; _ui_msg_fail "JSON invalide : $file (rien modifie)"; return 1
            fi
            ;;
        status)
            local n=0 state="${XDG_CACHE_HOME:-$HOME/.cache}/zanvil/claude"
            if [[ -f "$file" ]] && grep -qF "$_AI_CLAUDE_MARK" "$file"; then
                _ui_msg_ok "Hooks installes ($file)"
            else
                _ui_msg_warn "Hooks non installes : ai_claude_hooks install"
            fi
            local -a waiting=("$state"/*(N.mh-12))
            _ui_msg_info "Sessions en attente : ${#waiting}"
            ;;
        -h|--help|help)
            echo "Usage: ai_claude_hooks [install|uninstall|status]"
            echo "  Signale a SketchyBar les sessions Claude Code qui attendent une reponse."
            ;;
        *) _ui_msg_fail "Action inconnue : $action"; return 1 ;;
    esac
}
