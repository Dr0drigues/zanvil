# Skip si module desactive
[ "$ZSH_ENV_MODULE_NVM" != "true" ] && return

# =======================================================
# NVM AUTOMATION
# =======================================================

# Fonction de chargement intelligent de la version Node
load-nvmrc() {
  local nvmrc_path
  nvmrc_path="$(nvm_find_nvmrc)"

  if [ -n "$nvmrc_path" ]; then
    local nvmrc_node_version
    nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

    if [ "$nvmrc_node_version" = "N/A" ]; then
      echo "⚠️ Version Node requise non installée. Installation..."
      nvm install
    elif [ "$nvmrc_node_version" != "$(nvm version)" ]; then
      echo "🔄 Switch NVM : $(nvm version) -> $nvmrc_node_version"
      nvm use
    fi
  elif [ -n "$(PWD=$OLDPWD nvm_find_nvmrc)" ] && [ "$(nvm version)" != "$(nvm version default)" ]; then
    echo "Reverting to nvm default version"
    nvm use default
  fi
}