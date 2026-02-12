# shellcheck shell=zsh

Describe "plugins.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"
    # Avoid auto-loading plugins at source time
    export ZSH_ENV_PLUGINS=()
    # Source the file (skips loading since ZSH_ENV_PLUGINS is empty)
    source "$SHELLSPEC_PROJECT_ROOT/plugins.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "plugins.zsh sources without error"
    It "loads successfully"
      The variable ZSH_ENV_PLUGINS_DIR should be present
    End
  End

  Describe "ZSH_ENV_PLUGINS=() empty causes no error"
    It "handles empty plugins array"
      The variable ZSH_ENV_PLUGINS should be defined
    End
  End

  Describe "_zsh_env_plugin_name()"
    It "extracts name from owner/repo"
      When call _zsh_env_plugin_name "zsh-users/zsh-autosuggestions"
      The output should equal "zsh-autosuggestions"
    End

    It "extracts name from full URL"
      When call _zsh_env_plugin_name "https://github.com/Aloxaf/fzf-tab.git"
      The output should equal "fzf-tab"
    End

    It "extracts name from simple name"
      When call _zsh_env_plugin_name "zsh-autosuggestions"
      The output should equal "zsh-autosuggestions"
    End
  End

  Describe "_zsh_env_plugin_url()"
    It "generates GitHub URL from owner/repo"
      When call _zsh_env_plugin_url "zsh-users/zsh-autosuggestions"
      The output should equal "https://github.com/zsh-users/zsh-autosuggestions.git"
    End

    It "prefixes with ZSH_ENV_PLUGINS_ORG if no slash"
      ZSH_ENV_PLUGINS_ORG="zsh-users"
      When call _zsh_env_plugin_url "zsh-autosuggestions"
      The output should equal "https://github.com/zsh-users/zsh-autosuggestions.git"
    End

    It "returns URL as-is if https://"
      When call _zsh_env_plugin_url "https://github.com/custom/plugin.git"
      The output should equal "https://github.com/custom/plugin.git"
    End

    It "returns URL as-is if git@"
      When call _zsh_env_plugin_url "git@github.com:custom/plugin.git"
      The output should equal "git@github.com:custom/plugin.git"
    End
  End

  Describe "_zsh_env_find_plugin_file()"
    It "detects *.plugin.zsh"
      local dir="$TEST_HOME/test-plugin1"
      mkdir -p "$dir"
      touch "$dir/myplugin.plugin.zsh"
      When call _zsh_env_find_plugin_file "$dir"
      The output should end with "myplugin.plugin.zsh"
      The status should equal 0
    End

    It "detects init.zsh"
      local dir="$TEST_HOME/test-plugin2"
      mkdir -p "$dir"
      touch "$dir/init.zsh"
      When call _zsh_env_find_plugin_file "$dir"
      The output should end with "init.zsh"
      The status should equal 0
    End

    It "detects <name>.zsh"
      local dir="$TEST_HOME/test-plugin3"
      mkdir -p "$dir"
      touch "$dir/test-plugin3.zsh"
      When call _zsh_env_find_plugin_file "$dir"
      The output should end with "test-plugin3.zsh"
      The status should equal 0
    End
  End

  Describe "zsh-plugin-install()"
    It "shows usage without arguments"
      When call zsh-plugin-install
      The output should include "Usage:"
      The status should equal 1
    End
  End

  Describe "zsh-plugin-remove()"
    It "shows usage without arguments"
      When call zsh-plugin-remove
      The output should include "Usage:"
      The status should equal 1
    End
  End
End
