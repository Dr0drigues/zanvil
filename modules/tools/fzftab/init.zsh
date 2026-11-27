# ==============================================================================
# fzf-tab — apercus pendant la completion
# Guard: ZANVIL_MODULE_FZFTAB=true dans config.zsh
# Le plugin lui-meme vient de ZANVIL_PLUGINS (Aloxaf/fzf-tab, AVANT zsh-autosuggestions) ;
# ce module ne pose que des reglages zstyle, sans effet si le plugin n'est pas charge.
# ==============================================================================

[[ "${ZANVIL_MODULE_FZFTAB:-}" != "true" ]] && return 0

# fzf-tab remplace le menu de completion : celui de zsh ne doit pas s'ouvrir en plus.
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
# Options fzf du theme (FZF_DEFAULT_OPTS_FILE, ecrit par zanvil-theme) : memes couleurs.
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'

# Dossiers : cd est un alias de z (zoxide), les deux sont couverts.
if (( $+commands[eza] )); then
    zstyle ':fzf-tab:complete:(cd|z|__zoxide_z):*' fzf-preview 'eza -1 --color=always --icons=auto -- $realpath'
else
    zstyle ':fzf-tab:complete:(cd|z|__zoxide_z):*' fzf-preview 'command ls -1 -- $realpath'
fi
# git : diff du fichier, ou historique de la branche/du commit
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview 'git diff --color=always -- $word'
zstyle ':fzf-tab:complete:git-(checkout|switch|log|show):*' fzf-preview \
    'git log --oneline --graph --color=always -20 $word 2>/dev/null'
# Processus : ligne de commande complete
zstyle ':fzf-tab:complete:(kill|pkill):argument-rest' fzf-preview \
    '[[ $group == "[process ID]" ]] && command ps -p $word -o command= -ww'
zstyle ':fzf-tab:complete:(kill|pkill):argument-rest' fzf-flags --preview-window=down:3:wrap
