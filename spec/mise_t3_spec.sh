# shellcheck shell=zsh

Describe "mise_hooks.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    ORIG_PATH="$PATH"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"

    # Source UI for _ui_* variables
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"

    # Create a fake mise binary so command -v mise succeeds
    mkdir -p "$TEST_HOME/bin"
    echo '#!/bin/sh' > "$TEST_HOME/bin/mise"
    echo 'echo "mock-mise $*"' >> "$TEST_HOME/bin/mise"
    chmod +x "$TEST_HOME/bin/mise"
    export PATH="$TEST_HOME/bin:$PATH"

    # Mock work_is_context
    work_is_context() { return 0; }

    source "$SHELLSPEC_PROJECT_ROOT/functions/mise_hooks.zsh"
  }

  cleanup() {
    export HOME="$ORIG_HOME"
    export PATH="$ORIG_PATH"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "mise-configure"
    It "shows usage without arguments"
      When call mise-configure
      The output should include "Usage: mise-configure"
      The status should equal 1
    End

    It "fails for unsupported tool"
      When call mise-configure python 3.12
      The output should include "Pas de hook"
      The status should equal 1
    End
  End

  Describe "hooks.zsh activation"
    It "references ZSH_ENV_MODULE_MISE"
      check_mise_activation() {
        local content
        content=$(cat "$SHELLSPEC_PROJECT_ROOT/hooks.zsh")
        echo "$content" | grep -q "ZSH_ENV_MODULE_MISE" && echo "found" || echo "not_found"
      }
      When call check_mise_activation
      The output should equal "found"
    End
  End
End
