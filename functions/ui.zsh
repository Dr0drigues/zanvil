# ==============================================================================
# ZSH_ENV UI - Fonctions utilitaires d'affichage
# ==============================================================================
# Ce fichier centralise toutes les fonctions de formatage et d'affichage
# pour garantir un style cohérent dans toutes les commandes zsh-env-*.
#
# Usage dans les autres fichiers:
#   Les fonctions sont automatiquement disponibles car ui.zsh est chargé
#   en premier par functions.zsh (ordre alphabétique inversé ou explicite)
# ==============================================================================

# ==============================================================================
# Version ZSH_ENV
# ==============================================================================
export ZSH_ENV_VERSION="v1.3.0"

# ==============================================================================
# Couleurs ANSI
# ==============================================================================
# Couleurs de base
_ui_black=$'\033[0;30m'
_ui_red=$'\033[0;31m'
_ui_green=$'\033[0;32m'
_ui_yellow=$'\033[1;33m'
_ui_blue=$'\033[0;34m'
_ui_magenta=$'\033[0;35m'
_ui_cyan=$'\033[0;36m'
_ui_white=$'\033[0;37m'

# Styles
_ui_bold=$'\033[1m'
_ui_dim=$'\033[2m'
_ui_italic=$'\033[3m'
_ui_underline=$'\033[4m'
_ui_nc=$'\033[0m'  # No Color / Reset

# Aliases pour compatibilité (utilisés dans zsh_env_commands.zsh)
_zsh_cmd_green=$_ui_green
_zsh_cmd_red=$_ui_red
_zsh_cmd_yellow=$_ui_yellow
_zsh_cmd_blue=$_ui_blue
_zsh_cmd_cyan=$_ui_cyan
_zsh_cmd_bold=$_ui_bold
_zsh_cmd_dim=$_ui_dim
_zsh_cmd_nc=$_ui_nc

# ==============================================================================
# Symboles Unicode
# ==============================================================================
_ui_check="✓"
_ui_cross="✗"
_ui_circle="○"
_ui_bullet="•"
_ui_arrow="→"
_ui_info="ℹ"
_ui_warn="⚠"

# Box drawing
_ui_box_tl="╭"
_ui_box_tr="╮"
_ui_box_bl="╰"
_ui_box_br="╯"
_ui_box_h="─"
_ui_box_v="│"

# ==============================================================================
# Fonctions de formatage - Header
# ==============================================================================

# Affiche un header boxed avec titre et version
# Usage: _ui_header "Titre" [largeur]
# Exemple:
#   ╭──────────────────────────────────────────╮
#   │  Mon Titre                       v1.2.0  │
#   ╰──────────────────────────────────────────╯
_ui_header() {
    local title="$1"
    local width="${2:-44}"
    local inner=$((width - 2))
    local version="$ZSH_ENV_VERSION"
    local content="  $title"
    local padding=$((inner - ${#content} - ${#version} - 2))
    local spaces=$(printf '%*s' $padding '')

    echo -e "${_ui_cyan}"
    printf "${_ui_box_tl}%s${_ui_box_tr}\n" "$(printf "${_ui_box_h}%.0s" $(seq 1 $inner))"
    printf "${_ui_box_v}%s%s${_ui_dim}%s${_ui_cyan}  ${_ui_box_v}\n" "$content" "$spaces" "$version"
    printf "${_ui_box_bl}%s${_ui_box_br}\n" "$(printf "${_ui_box_h}%.0s" $(seq 1 $inner))"
    echo -e "${_ui_nc}"
}

# Alias pour compatibilité
_zsh_header() { _ui_header "$@"; }

# ==============================================================================
# Fonctions de formatage - Sections et lignes
# ==============================================================================

# Affiche un label de section aligné (14 caractères par défaut)
# Usage: _ui_section "Label" contenu...
_ui_section() {
    local label="$1"
    shift
    printf "${_ui_bold}%-14s${_ui_nc} %s\n" "$label" "$*"
}

# Alias pour compatibilité
_zsh_section() { _ui_section "$@"; }

# Affiche une ligne de séparation
# Usage: _ui_separator [largeur]
_ui_separator() {
    local width="${1:-44}"
    printf "${_ui_dim}"
    printf "${_ui_box_h}%.0s" $(seq 1 $width)
    printf "${_ui_nc}\n"
}

# Alias pour compatibilité
_zsh_separator() { _ui_separator "$@"; }

# ==============================================================================
# Fonctions de formatage - Indicateurs de statut
# ==============================================================================

# Affiche un indicateur de succès inline
# Usage: _ui_ok "texte" [version]
# Output: "texte ✓" ou "texte ✓ version"
_ui_ok() {
    local text="$1"
    local version="$2"
    if [[ -n "$version" ]]; then
        printf "%s ${_ui_green}${_ui_check}${_ui_nc}${_ui_dim}%s${_ui_nc}  " "$text" "$version"
    else
        printf "%s ${_ui_green}${_ui_check}${_ui_nc}  " "$text"
    fi
}

# Affiche un indicateur d'erreur inline
# Usage: _ui_fail "texte" [détail]
# Output: "texte ✗" ou "texte ✗ détail"
_ui_fail() {
    local text="$1"
    local detail="$2"
    if [[ -n "$detail" ]]; then
        printf "%s ${_ui_red}${_ui_cross}${_ui_nc}${_ui_dim}%s${_ui_nc}  " "$text" "$detail"
    else
        printf "%s ${_ui_red}${_ui_cross}${_ui_nc}  " "$text"
    fi
}

# Affiche un indicateur d'avertissement inline
# Usage: _ui_warn "texte" [détail]
_ui_warn() {
    local text="$1"
    local detail="$2"
    if [[ -n "$detail" ]]; then
        printf "%s ${_ui_yellow}${_ui_circle}${_ui_nc}${_ui_dim}%s${_ui_nc}  " "$text" "$detail"
    else
        printf "%s ${_ui_yellow}${_ui_circle}${_ui_nc}  " "$text"
    fi
}

# Affiche un indicateur optionnel/désactivé inline
# Usage: _ui_skip "texte"
_ui_skip() {
    local text="$1"
    printf "${_ui_dim}%s ${_ui_circle}${_ui_nc}  " "$text"
}

# Affiche un indicateur d'info inline
# Usage: _ui_info "texte"
_ui_info() {
    local text="$1"
    printf "${_ui_dim}%s${_ui_nc}  " "$text"
}

# ==============================================================================
# Fonctions de formatage - Messages
# ==============================================================================

# Affiche un message de succès sur une ligne
# Usage: _ui_msg_ok "message"
_ui_msg_ok() {
    echo -e "${_ui_green}${_ui_check}${_ui_nc} $1"
}

# Affiche un message d'erreur sur une ligne
# Usage: _ui_msg_fail "message"
_ui_msg_fail() {
    echo -e "${_ui_red}${_ui_cross}${_ui_nc} $1"
}

# Affiche un message d'avertissement sur une ligne
# Usage: _ui_msg_warn "message"
_ui_msg_warn() {
    echo -e "${_ui_yellow}${_ui_warn}${_ui_nc} $1"
}

# Affiche un message d'info sur une ligne
# Usage: _ui_msg_info "message"
_ui_msg_info() {
    echo -e "${_ui_blue}${_ui_info}${_ui_nc} $1"
}

# ==============================================================================
# Fonctions de formatage - Préfixes [TAG]
# ==============================================================================

# Affiche [OK] message
_ui_tag_ok() {
    echo -e "${_ui_green}[OK]${_ui_nc} $1"
}

# Affiche [FAIL] message
_ui_tag_fail() {
    echo -e "${_ui_red}[FAIL]${_ui_nc} $1"
}

# Affiche [WARN] message
_ui_tag_warn() {
    echo -e "${_ui_yellow}[WARN]${_ui_nc} $1"
}

# Affiche [INFO] message
_ui_tag_info() {
    echo -e "${_ui_blue}[INFO]${_ui_nc} $1"
}

# Affiche [SKIP] message
_ui_tag_skip() {
    echo -e "${_ui_dim}[SKIP]${_ui_nc} $1"
}

# ==============================================================================
# Fonctions de formatage - Tableaux
# ==============================================================================

# Affiche un header de tableau
# Usage: _ui_table_header "Col1" "Col2" "Col3" [largeurs...]
# Par défaut: 14 12 reste
_ui_table_header() {
    local col1="$1"
    local col2="$2"
    local col3="$3"
    local w1="${4:-14}"
    local w2="${5:-12}"

    printf "${_ui_bold}%-${w1}s %-${w2}s %s${_ui_nc}\n" "$col1" "$col2" "$col3"
}

# ==============================================================================
# Fonctions de formatage - Résumés
# ==============================================================================

# Affiche un résumé final avec compteurs
# Usage: _ui_summary $issues $warnings
_ui_summary() {
    local issues="${1:-0}"
    local warnings="${2:-0}"

    _ui_separator 44

    if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${_ui_green}${_ui_check} Tout est OK${_ui_nc}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "${_ui_green}${_ui_check} OK${_ui_nc} ${_ui_dim}($warnings avertissement(s))${_ui_nc}"
    else
        echo -e "${_ui_red}${_ui_cross} $issues erreur(s)${_ui_nc}, ${_ui_yellow}$warnings avertissement(s)${_ui_nc}"
    fi
}

# ==============================================================================
# Fonctions utilitaires
# ==============================================================================

# Retourne les permissions d'un fichier (cross-platform)
# Usage: perms=$(_ui_get_perms "/path/to/file")
_ui_get_perms() {
    stat -f "%Lp" "$1" 2>/dev/null || stat -c "%a" "$1" 2>/dev/null
}

# Tronque une chaîne à N caractères avec ...
# Usage: _ui_truncate "long string" 20
_ui_truncate() {
    local str="$1"
    local max="${2:-20}"
    if [[ ${#str} -gt $max ]]; then
        echo "${str:0:$((max-3))}..."
    else
        echo "$str"
    fi
}
