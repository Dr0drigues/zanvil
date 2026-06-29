[[ "${ZANVIL_MODULE_KUBE:-}" != "true" ]] && return 0

if command -v stern &>/dev/null; then
    ks() {
        stern --timestamps --color always --tail 50 "$@"
    }
else
    echo "[zanvil] stern: module kube actif mais binaire absent — brew install stern"
fi
