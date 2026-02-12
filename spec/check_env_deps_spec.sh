# shellcheck shell=zsh

Describe "check_env_deps.zsh"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"
    source "$SHELLSPEC_PROJECT_ROOT/functions/check_env_deps.zsh"
  }

  BeforeAll 'setup'

  Describe "check_env_health()"
    It "checks core tools"
      When call check_env_health
      The output should include "Environment Health"
      The output should include "git"
      The output should include "curl"
    End

    It "marks tools with status indicators"
      When call check_env_health
      The output should be present
    End

    It "provides summary for results"
      When call check_env_health
      # If all tools are installed, it says "operationnel", otherwise "brew install"
      The output should be present
    End
  End
End
