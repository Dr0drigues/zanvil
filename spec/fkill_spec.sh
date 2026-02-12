# shellcheck shell=zsh

Describe "fkill.zsh"
  setup() {
    export ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"
    source "$SHELLSPEC_PROJECT_ROOT/functions/fkill.zsh"
  }

  BeforeAll 'setup'

  Describe "fkill()"
    It "is defined as a function"
      check_fkill_defined() {
        whence -w fkill | grep -q "function"
      }
      When call check_fkill_defined
      The status should equal 0
    End
  End
End
