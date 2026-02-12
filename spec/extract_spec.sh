# shellcheck shell=zsh

Describe "extract.zsh"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"
    source "$SHELLSPEC_PROJECT_ROOT/functions/extract.zsh"
  }

  BeforeAll 'setup'

  Describe "extract()"
    It "fails on unsupported format"
      echo "data" > "/tmp/test_shellspec.abc"
      When call extract "/tmp/test_shellspec.abc"
      The output should include "format non supporte"
      rm -f "/tmp/test_shellspec.abc"
    End

    It "fails on nonexistent file"
      When call extract "/tmp/this_file_does_not_exist.tar.gz"
      The output should include "n'est pas un fichier valide"
    End
  End
End
