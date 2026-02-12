# shellcheck shell=zsh

Describe "auto_update.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR/.git"
    # Disable actual auto-update at source time
    export ZSH_ENV_AUTO_UPDATE=false
    # Source returns non-zero because last line is `[[ "false" == "true" ]] && ...`
    # which evaluates to false. We catch this.
    source "$SHELLSPEC_PROJECT_ROOT/functions/auto_update.zsh" || true
    # Override the update file path for tests
    ZSH_ENV_UPDATE_FILE="$ZSH_ENV_DIR/.last_update_check"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "_zsh_env_should_check_update()"
    It "returns 0 if frequency is 0"
      ZSH_ENV_UPDATE_FREQUENCY=0
      When call _zsh_env_should_check_update
      The status should equal 0
    End

    It "returns 0 if timestamp file does not exist"
      ZSH_ENV_UPDATE_FREQUENCY=7
      rm -f "$ZSH_ENV_UPDATE_FILE"
      When call _zsh_env_should_check_update
      The status should equal 0
    End

    It "returns 0 after N days"
      ZSH_ENV_UPDATE_FREQUENCY=1
      local old_ts=$(( $(date +%s) - 172800 ))
      echo "$old_ts" > "$ZSH_ENV_UPDATE_FILE"
      When call _zsh_env_should_check_update
      The status should equal 0
    End

    It "returns 1 if check is recent"
      ZSH_ENV_UPDATE_FREQUENCY=7
      date +%s > "$ZSH_ENV_UPDATE_FILE"
      When call _zsh_env_should_check_update
      The status should equal 1
    End
  End

  Describe "zsh-env-status()"
    It "displays configuration and modules"
      When call zsh-env-status
      The output should include "ZSH_ENV Status"
      The output should include "Configuration"
      The output should include "Modules"
    End
  End
End
