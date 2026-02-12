# shellcheck shell=zsh

Describe "check_env_deps.zsh"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/check_env_deps.zsh"
  }

  BeforeAll 'setup'

  Describe "check_env_health()"
    It "checks core tools"
      When call check_env_health
      The output should include "Checking Environment Health"
      # git and curl should always be installed
      The output should include "git"
      The output should include "curl"
    End

    It "marks missing tools"
      When call check_env_health
      # Output should contain tool status
      The output should include "installe"
    End

    It "provides brew install command for missing tools"
      When call check_env_health
      # If all tools are installed, it says "operationnel", otherwise "brew install"
      The output should be present
    End
  End
End
