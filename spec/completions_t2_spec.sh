# shellcheck shell=zsh

Describe "completions (T2 integration)"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"
    # Create a completions.zsh file
    cat > "$ZSH_ENV_DIR/completions.zsh" << 'EOF'
ZSH_ENV_COMPLETIONS=(
    "existing:existing completions"
)
EOF
    source "$SHELLSPEC_PROJECT_ROOT/functions/zsh_env_commands.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "zsh-env-completion-add()"
    It "adds an entry to completions.zsh"
      When call zsh-env-completion-add "testcomp" "test completions"
      The output should include "OK"
      The output should include "testcomp"
    End

    It "detects duplicate entries"
      zsh-env-completion-add "mydup" "dup completions" > /dev/null 2>&1
      When call zsh-env-completion-add "mydup" "dup completions"
      The output should include "existe deja"
      The status should equal 1
    End
  End

  Describe "zsh-env-completion-remove()"
    It "removes an entry from completions.zsh"
      zsh-env-completion-add "removeme" "remove completions" > /dev/null 2>&1
      When call zsh-env-completion-remove "removeme"
      The output should include "OK"
      The output should include "removeme"
    End

    It "fails if entry not found"
      When call zsh-env-completion-remove "doesnotexist"
      The output should include "n'existe pas"
      The status should equal 1
    End
  End
End
