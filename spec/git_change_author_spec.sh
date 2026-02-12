# shellcheck shell=zsh

Describe "git_change_author.zsh"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/git_change_author.zsh"
  }

  BeforeAll 'setup'

  Describe "gc-author()"
    It "shows usage without arguments"
      When call gc-author
      The output should include "Usage: gc-author"
      The status should equal 1
    End

    It "requires 3 arguments minimum"
      When call gc-author "old@email.com"
      The output should include "Usage: gc-author"
      The status should equal 1
    End

    It "shows usage with only 2 arguments"
      When call gc-author "old@email.com" "New Name"
      The output should include "Usage: gc-author"
      The status should equal 1
    End

    It "uses HEAD~10..HEAD as default range (shown in usage)"
      When call gc-author
      The output should include "HEAD~10..HEAD"
      The status should equal 1
    End

    It "shows ATTENTION warning in usage"
      When call gc-author
      The output should include "ATTENTION"
      The status should equal 1
    End

    It "mentions custom range in usage"
      When call gc-author
      The output should include "RANGE"
      The status should equal 1
    End
  End
End
