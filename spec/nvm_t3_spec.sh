# shellcheck shell=zsh

Describe "nvm_auto.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    export ZSH_ENV_MODULE_NVM="true"

    # Mock NVM functions before sourcing
    nvm_find_nvmrc() { echo ""; }
    nvm() { echo "mock-nvm $*"; }

    source "$SHELLSPEC_PROJECT_ROOT/functions/nvm_auto.zsh"
  }

  cleanup() {
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "module skip"
    It "skips when ZSH_ENV_MODULE_NVM != true"
      check_skip() {
        local out
        out=$(ZSH_ENV_MODULE_NVM=false zsh -c "
          nvm_find_nvmrc() { echo ''; }
          nvm() { :; }
          source '$SHELLSPEC_PROJECT_ROOT/functions/nvm_auto.zsh'
          whence -w load-nvmrc 2>/dev/null || echo 'not_found'
        ")
        echo "$out"
      }
      When call check_skip
      The output should include "not_found"
    End
  End

  Describe "load-nvmrc()"
    It "does nothing when no .nvmrc found"
      test_no_nvmrc() {
        nvm_find_nvmrc() { echo ""; }
        nvm() { echo "nvm-called"; }
        OLDPWD="$TEST_HOME"
        load-nvmrc
        echo "done"
      }
      When call test_no_nvmrc
      # Should not call nvm use/install since no nvmrc
      The output should equal "done"
    End

    It "installs version when N/A"
      test_install() {
        local nvmrc="$TEST_HOME/.nvmrc"
        echo "18" > "$nvmrc"
        nvm_find_nvmrc() { echo "$nvmrc"; }
        nvm() {
          case "$1" in
            version)
              if [[ "$2" == "18" ]]; then
                echo "N/A"
              else
                echo "v20.0.0"
              fi
              ;;
            install) echo "nvm-install-called" ;;
          esac
        }
        load-nvmrc
      }
      When call test_install
      The output should include "Installation"
      The output should include "nvm-install-called"
    End

    It "switches when version differs"
      test_switch() {
        local nvmrc="$TEST_HOME/.nvmrc"
        echo "18" > "$nvmrc"
        nvm_find_nvmrc() { echo "$nvmrc"; }
        nvm() {
          case "$1" in
            version)
              if [[ -n "$2" ]]; then
                echo "v18.0.0"
              else
                echo "v20.0.0"
              fi
              ;;
            use) echo "nvm-use-called" ;;
          esac
        }
        load-nvmrc
      }
      When call test_switch
      The output should include "Switch NVM"
      The output should include "nvm-use-called"
    End

    It "reverts to default when leaving nvmrc dir"
      test_revert() {
        # Current dir has no .nvmrc
        nvm_find_nvmrc() {
          if [[ "${PWD:-}" == "$OLDPWD" ]]; then
            echo "/some/old/.nvmrc"
          else
            echo ""
          fi
        }
        nvm() {
          case "$1" in
            version)
              if [[ "$2" == "default" ]]; then
                echo "v16.0.0"
              else
                echo "v18.0.0"
              fi
              ;;
            use) echo "nvm-use-default" ;;
          esac
        }
        OLDPWD="$TEST_HOME/olddir"
        mkdir -p "$OLDPWD"
        load-nvmrc
      }
      When call test_revert
      The output should include "Reverting"
      The output should include "nvm-use-default"
    End
  End
End
