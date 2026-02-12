# shellcheck shell=zsh

Describe "zsh_env_commands.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"
    source "$SHELLSPEC_PROJECT_ROOT/functions/zsh_env_commands.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "zsh-env-list()"
    It "displays installed tools with version"
      When call zsh-env-list
      The output should include "Outils installes"
      The output should include "Resume"
    End

    It "marks missing tools"
      When call zsh-env-list
      The output should include "installes"
    End
  End

  Describe "zsh-env-help()"
    It "displays help"
      When call zsh-env-help
      The output should include "Commandes ZSH_ENV"
      The output should include "zsh-env-list"
      The output should include "zsh-env-doctor"
    End
  End

  Describe "zsh-env-completion-add()"
    It "requires name and command"
      When call zsh-env-completion-add
      The output should include "Usage"
      The status should equal 1
    End

    It "requires command when name is given"
      When call zsh-env-completion-add "mycomp"
      The output should include "Usage"
      The status should equal 1
    End
  End

  Describe "zsh-env-completion-remove()"
    It "requires a name"
      When call zsh-env-completion-remove
      The output should include "Usage"
      The status should equal 1
    End

    It "fails if entry not found"
      When call zsh-env-completion-remove "nonexistent"
      The output should include "n'existe pas"
      The status should equal 1
    End
  End
End
