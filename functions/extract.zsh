# Fonction universelle d'extraction
extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar e "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *.tar.xz)    tar xJf "$1"     ;;
            *.xz)        unxz "$1"        ;;
            *.zst)       unzstd "$1"      ;;
            *)           _ui_msg_fail "'$1' : format non supporte par extract()" ;;
        esac
    else
        _ui_msg_fail "'$1' n'est pas un fichier valide"
    fi
}
