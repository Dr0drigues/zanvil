# shellcheck shell=zsh

Describe "net_utils.zsh"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/net_utils.zsh"
  }

  BeforeAll 'setup'

  Describe "port()"
    It "requires 2 arguments (host and port)"
      When call port
      The output should include "Usage: port"
      The status should equal 1
    End

    It "requires 2 arguments (only host given)"
      When call port "localhost"
      The output should include "Usage: port"
      The status should equal 1
    End
  End
End
