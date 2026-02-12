# shellcheck shell=zsh

Describe "git_root.zsh"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/git_root.zsh"
  }

  BeforeAll 'setup'

  Describe "gr()"
    It "shows error when not in a git repo"
      # Run from /tmp which is not a git repo
      cd /tmp
      When call gr
      The output should include "Pas dans un depot Git"
    End

    It "navigates to git root"
      # We're in the project which is a git repo
      cd "$SHELLSPEC_PROJECT_ROOT/spec"
      When call gr
      The variable PWD should equal "$SHELLSPEC_PROJECT_ROOT"
    End
  End
End
