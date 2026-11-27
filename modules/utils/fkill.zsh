# Chercher et tuer un processus
fkill() {
    local pid
    if [[ "$UID" != "0" ]]; then
        pid=$(command ps -f -u "$UID" | sed 1d | fzf -m | awk '{print $2}')
    else
        pid=$(command ps -ef | sed 1d | fzf -m | awk '{print $2}')
    fi

    if [[ -n "$pid" ]]; then
        echo "$pid" | xargs kill -"${1:-9}"
    fi
}
