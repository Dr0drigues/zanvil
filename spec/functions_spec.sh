# shellcheck shell=zsh

Describe "functions.zsh (lazy loading)"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"
    # Some modules produce stderr (gitlab_logic.zsh warning about missing secrets)
    # Source with stderr suppressed for the setup
    source "$ZSH_ENV_DIR/functions.zsh" 2>/dev/null || true
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "Lazy files are not sourced at load time"
    It "ai_context_detect is defined as a stub function"
      run_check() { type -w ai_context_detect 2>/dev/null | cut -d' ' -f2; }
      When call run_check
      The output should equal "function"
    End

    It "ai_tokens_estimate is defined as a stub function"
      run_check() { type -w ai_tokens_estimate 2>/dev/null | cut -d' ' -f2; }
      When call run_check
      The output should equal "function"
    End
  End

  Describe "Stub functions are defined"
    It "ai_context_detect stub is defined"
      run_check() { type -w ai_context_detect 2>/dev/null | cut -d' ' -f2; }
      When call run_check
      The output should equal "function"
    End

    It "ai_tokens_estimate stub is defined"
      run_check() { type -w ai_tokens_estimate 2>/dev/null | cut -d' ' -f2; }
      When call run_check
      The output should equal "function"
    End
  End

  Describe "Non-lazy files in functions/ are sourced"
    It "utils.zsh functions are available (mkcd)"
      run_check() { type -w mkcd 2>/dev/null | cut -d' ' -f2; }
      When call run_check
      The output should equal "function"
    End

    It "extract.zsh function is available"
      run_check() { type -w extract 2>/dev/null | cut -d' ' -f2; }
      When call run_check
      The output should equal "function"
    End
  End
End
