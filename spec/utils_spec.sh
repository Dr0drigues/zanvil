# shellcheck shell=zsh

Describe "utils.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"
    source "$SHELLSPEC_PROJECT_ROOT/functions/utils.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "mkcd()"
    It "creates a directory and enters it"
      When call mkcd "$TEST_HOME/testdir"
      The path "$TEST_HOME/testdir" should be directory
      The variable PWD should equal "$TEST_HOME/testdir"
    End

    It "creates nested directories"
      When call mkcd "$TEST_HOME/a/b/c"
      The path "$TEST_HOME/a/b/c" should be directory
      The variable PWD should equal "$TEST_HOME/a/b/c"
    End
  End

  Describe "bak()"
    It "requires an argument"
      When call bak
      The output should include "Usage:"
      The status should equal 1
    End

    It "creates a timestamped backup"
      echo "content" > "$TEST_HOME/file.txt"
      When call bak "$TEST_HOME/file.txt"
      The output should include "Backup cree"
      The status should equal 0
    End
  End

  Describe "cx()"
    It "requires an argument"
      When call cx
      The output should include "Usage:"
      The status should equal 1
    End

    It "fails if file does not exist"
      When call cx "$TEST_HOME/nonexistent"
      The output should include "n'est pas un fichier valide"
      The status should equal 1
    End

    It "makes a file executable"
      echo "#!/bin/sh" > "$TEST_HOME/script.sh"
      When call cx "$TEST_HOME/script.sh"
      The output should include "executable"
      The status should equal 0
      The path "$TEST_HOME/script.sh" should be executable
    End
  End

  Describe "trash()"
    It "returns 1 if no trash command is available"
      # Mock: hide all trash commands
      command() { return 1; }
      When call trash "file"
      The output should include "Erreur"
      The status should equal 1
      unfunction command 2>/dev/null
    End
  End
End
