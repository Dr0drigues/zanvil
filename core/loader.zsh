# ==============================================================================
# Module Loader - Chargement dynamique des modules
# ==============================================================================
# Remplace functions.zsh - charge core/*.zsh puis modules/*/init.zsh et modules/*/*/init.zsh
# ==============================================================================

# --- 0. Ajouter core/ au fpath pour les completions CLI ---
fpath=("$ZANVIL_DIR/core" $fpath)

# --- 1. Charger le systeme UI en premier ---
source "$ZANVIL_DIR/core/ui.zsh"

# --- 2. Charger les fichiers core (commandes, admin, theme, setup) ---
local _skip_core=(rc.zsh loader.zsh ui.zsh variables.zsh aliases.zsh hooks.zsh)
for _core_file in "$ZANVIL_DIR/core"/*.zsh(N) "$ZANVIL_DIR/core"/*/*.zsh(N); do
    [[ ! -f "$_core_file" ]] && continue
    local _core_name="$(basename "$_core_file")"
    (( ${_skip_core[(Ie)$_core_name]} )) && continue
    source "$_core_file"
done
unset _core_file _core_name _skip_core

# --- 3. Infrastructure lazy loading ---
_zanvil_lazy_load_module() {
    local module="$1" func="$2"
    shift 2
    local init_file="$ZANVIL_DIR/modules/$module/init.zsh"
    [[ -f "$init_file" ]] && source "$init_file"
    # Charger aussi les completions
    local comp_file="$ZANVIL_DIR/modules/$module/completions.zsh"
    [[ -f "$comp_file" ]] && source "$comp_file"
    "$func" "$@"
}

# --- 4. Charger les modules ---
for _module_dir in "$ZANVIL_DIR/modules"/*/(N) "$ZANVIL_DIR/modules"/*/*/(N); do
    [[ ! -f "$_module_dir/init.zsh" ]] && continue
    local _module_name="$(basename "$_module_dir")"
    # Chemin relatif depuis modules/ (ex: "tools/lazygit") pour les modules depth-2
    local _module_rel="${_module_dir#$ZANVIL_DIR/modules/}"

    # Module guard : ZANVIL_MODULE_<NAME> — vérifié avant tout (lazy ou non)
    local _guard_var="ZANVIL_MODULE_${(U)_module_name}"
    if [[ -n "${(P)_guard_var}" && "${(P)_guard_var}" != "true" ]]; then
        continue
    fi

    # Lazy loading : si .lazy existe, creer des stubs
    if [[ -f "$_module_dir/.lazy" ]]; then
        while IFS= read -r _fn_name; do
            [[ -z "$_fn_name" || "$_fn_name" == \#* ]] && continue
            eval "${_fn_name}() { _zanvil_lazy_load_module '${_module_rel}' '${_fn_name}' \"\$@\"; }"
        done < "$_module_dir/.lazy"
        continue
    fi

    # Verifier les dependances (.deps)
    if [[ -f "$_module_dir/.deps" ]]; then
        local _deps_ok=true
        while IFS= read -r _dep_name; do
            [[ -z "$_dep_name" || "$_dep_name" == \#* ]] && continue
            local _dep_guard="ZANVIL_MODULE_${(U)_dep_name}"
            # Un module sans guard explicite est considere comme actif (ex: git, utils)
            if [[ -n "${(P)_dep_guard}" && "${(P)_dep_guard}" != "true" ]]; then
                echo -e "${_ui_yellow}[zanvil]${_ui_nc} Module '${_module_name}' requiert '${_dep_name}' (desactive)"
                _deps_ok=false
            fi
        done < "$_module_dir/.deps"
        [[ "$_deps_ok" == "false" ]] && continue
    fi

    # Charger init.zsh
    [[ -f "$_module_dir/init.zsh" ]] && source "$_module_dir/init.zsh"

    # Charger completions.zsh (compinit deja execute dans rc.zsh)
    [[ -f "$_module_dir/completions.zsh" ]] && source "$_module_dir/completions.zsh"
done
unset _module_dir _module_name _module_rel _guard_var _fn_name _deps_ok _dep_name _dep_guard
