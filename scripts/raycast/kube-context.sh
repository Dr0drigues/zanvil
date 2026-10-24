#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Contexte kube
# @raycast.mode silent
# @raycast.packageName zanvil
# @raycast.argument1 { "type": "text", "placeholder": "Alias ou contexte" }

PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; export PATH
ZANVIL_DIR="${ZANVIL_DIR:-$HOME/.zanvil}"; export ZANVIL_DIR

# l'argument passe en $1, jamais dans le code zsh ; un contexte de production demande une
# confirmation (dialogue sur l'appli au premier plan) : annuler ou echec du dialogue = pas de bascule.
exec zsh -f -c '
    notify() {
        osascript -e "on run a" -e "display notification (item 1 of a) with title \"zanvil\"" -e "end run" \
            -- "$1" &>/dev/null
        return 0
    }
    [[ -f "$ZANVIL_DIR/config.zsh" ]] && source "$ZANVIL_DIR/config.zsh"
    export ZANVIL_MODULE_KUBE=true
    source "$ZANVIL_DIR/core/ui.zsh"
    source "$ZANVIL_DIR/modules/kube/kube_config.zsh"
    setopt extendedglob
    target="${${1##[[:space:]]#}%%[[:space:]]#}"
    [[ -n "$target" ]] || { notify "Contexte kube : argument vide"; exit 1; }
    command -v kubectl >/dev/null || { notify "kubectl introuvable"; exit 1; }
    resolved=$(_kube_resolve_alias "$target")
    # prod : la cible, le contexte complet ou un alias de ce contexte porte un segment -prd/-prod
    # shortcut: regle propre a ce script, aucune autre dans zanvil ; segments separes par - seulement
    names=("$target" "$resolved")
    if [[ -f "$KUBE_ALIASES_FILE" ]]; then
        while IFS= read -r line; do
            [[ "${line#*=}" == "$resolved" ]] && names+=("${line%%=*}")
        done < "$KUBE_ALIASES_FILE"
    fi
    for n in "${names[@]}"; do
        if [[ "$n" == (#i)*-(prd|prod)(|-*) ]]; then
            answer=$(osascript -e "on run a" \
                -e "tell application (path to frontmost application as text) to display dialog (item 1 of a) with title \"zanvil\" with icon caution buttons {\"Annuler\", \"Basculer\"} default button \"Annuler\"" \
                -e "end run" -- "Basculer sur le contexte de production : $target ?" 2>&1)
            case "$answer" in
                *"button returned:Basculer"*) ;;
                *"button returned:Annuler"*|*"-128"*) notify "Bascule annulée"; exit 1 ;;
                *) notify "Confirmation impossible"; exit 1 ;;
            esac
            break
        fi
    done
    if kube_switch "$target" &>/dev/null; then
        notify "Contexte : $(_kube_get_alias "$resolved")"
    else
        notify "Contexte kube introuvable : $target"
        exit 1
    fi
' zanvil-raycast "$1" >/dev/null
