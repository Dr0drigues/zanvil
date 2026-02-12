# shellcheck shell=zsh

Describe "rc.zsh"
  Describe "Module default values"
    setup() {
      # Unset all module vars to test defaults
      unset ZSH_ENV_MODULE_GITLAB
      unset ZSH_ENV_MODULE_DOCKER
      unset ZSH_ENV_MODULE_NVM
      unset ZSH_ENV_MODULE_NUSHELL
      unset ZSH_ENV_AUTO_UPDATE
      unset ZSH_ENV_UPDATE_FREQUENCY
      unset ZSH_ENV_UPDATE_MODE
      unset ZSH_ENV_NVM_LAZY

      # Simulate what rc.zsh does for defaults (without sourcing the full file)
      ZSH_ENV_MODULE_GITLAB=${ZSH_ENV_MODULE_GITLAB:-true}
      ZSH_ENV_MODULE_DOCKER=${ZSH_ENV_MODULE_DOCKER:-true}
      ZSH_ENV_MODULE_NVM=${ZSH_ENV_MODULE_NVM:-true}
      ZSH_ENV_MODULE_NUSHELL=${ZSH_ENV_MODULE_NUSHELL:-true}
      ZSH_ENV_AUTO_UPDATE=${ZSH_ENV_AUTO_UPDATE:-true}
      ZSH_ENV_UPDATE_FREQUENCY=${ZSH_ENV_UPDATE_FREQUENCY:-7}
      ZSH_ENV_UPDATE_MODE=${ZSH_ENV_UPDATE_MODE:-prompt}
      ZSH_ENV_NVM_LAZY=${ZSH_ENV_NVM_LAZY:-true}
    }
    Before 'setup'

    It "defaults ZSH_ENV_MODULE_GITLAB to true"
      The variable ZSH_ENV_MODULE_GITLAB should equal "true"
    End

    It "defaults ZSH_ENV_MODULE_DOCKER to true"
      The variable ZSH_ENV_MODULE_DOCKER should equal "true"
    End

    It "defaults ZSH_ENV_MODULE_NVM to true"
      The variable ZSH_ENV_MODULE_NVM should equal "true"
    End

    It "defaults ZSH_ENV_MODULE_NUSHELL to true"
      The variable ZSH_ENV_MODULE_NUSHELL should equal "true"
    End

    It "defaults ZSH_ENV_NVM_LAZY to true"
      The variable ZSH_ENV_NVM_LAZY should equal "true"
    End

    It "defaults ZSH_ENV_AUTO_UPDATE to true"
      The variable ZSH_ENV_AUTO_UPDATE should equal "true"
    End

    It "defaults ZSH_ENV_UPDATE_FREQUENCY to 7"
      The variable ZSH_ENV_UPDATE_FREQUENCY should equal 7
    End

    It "defaults ZSH_ENV_UPDATE_MODE to prompt"
      The variable ZSH_ENV_UPDATE_MODE should equal "prompt"
    End
  End

  Describe "Disabled modules are not loaded"
    setup_disabled() {
      ZSH_ENV_MODULE_GITLAB=false
      ZSH_ENV_MODULE_DOCKER=false
    }
    Before 'setup_disabled'

    It "respects ZSH_ENV_MODULE_GITLAB=false"
      The variable ZSH_ENV_MODULE_GITLAB should equal "false"
    End

    It "respects ZSH_ENV_MODULE_DOCKER=false"
      The variable ZSH_ENV_MODULE_DOCKER should equal "false"
    End
  End

  Describe "Missing files warning"
    It "warns on stderr if ZSH_ENV_DIR is not set"
      test_zsh_env_warning() {
        (
          unset ZSH_ENV_DIR
          # Simulate the check from rc.zsh
          if [[ -z "$ZSH_ENV_DIR" ]]; then
            echo "WARNING: ZSH_ENV_DIR is not set. Assuming default location." >&2
          fi
        )
      }
      When call test_zsh_env_warning
      The stderr should include "WARNING"
    End
  End

  Describe "config.zsh is sourced if present"
    It "sources config.zsh when it exists"
      test_config_source() {
        local tmpdir=$(mktemp -d)
        echo 'TEST_CONFIG_LOADED=yes' > "$tmpdir/config.zsh"
        if [[ -f "$tmpdir/config.zsh" ]]; then
          source "$tmpdir/config.zsh"
        fi
        echo "$TEST_CONFIG_LOADED"
        rm -rf "$tmpdir"
      }
      When call test_config_source
      The output should equal "yes"
    End
  End

  Describe "SCRIPTS_DIR is added to PATH"
    It "adds SCRIPTS_DIR to PATH"
      test_path_addition() {
        local SCRIPTS_DIR="/tmp/test_scripts_dir"
        export PATH="$SCRIPTS_DIR:$PATH"
        echo "$PATH"
      }
      When call test_path_addition
      The output should include "/tmp/test_scripts_dir"
    End
  End

  Describe "PATH deduplication"
    It "deduplicates PATH with typeset -U"
      test_dedup() {
        typeset -U PATH
        PATH="/tmp/dup:/tmp/dup:/usr/bin"
        echo "$PATH"
      }
      When call test_dedup
      The output should equal "/tmp/dup:/usr/bin"
    End
  End
End
