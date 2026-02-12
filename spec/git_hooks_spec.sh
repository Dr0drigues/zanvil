# shellcheck shell=zsh

Describe "git_hooks.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    ORIG_PWD="$PWD"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"
    source "$SHELLSPEC_PROJECT_ROOT/functions/git_hooks.zsh"

    # Create a temporary git repo for tests
    TEST_REPO="$TEST_HOME/test-repo"
    mkdir -p "$TEST_REPO"
    git -C "$TEST_REPO" init --quiet
  }

  cleanup() {
    cd "$ORIG_PWD" 2>/dev/null || cd /
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "hooks_list()"
    It "fails outside a git repo"
      test_outside() {
        cd "$TEST_HOME"
        hooks_list
      }
      When call test_outside
      The stderr should include "Pas dans un depot Git"
      The status should equal 1
    End

    It "works inside a git repo"
      test_inside() {
        cd "$TEST_REPO"
        hooks_list
      }
      When call test_inside
      The output should include "Hooks Git installes"
    End
  End

  Describe "hooks_install_precommit()"
    It "creates the pre-commit file"
      install_precommit() {
        cd "$TEST_REPO"
        hooks_install_precommit
      }
      When call install_precommit
      The output should include "pre-commit installe"
      The path "$TEST_REPO/.git/hooks/pre-commit" should be file
    End

    It "makes the hook executable"
      # File already created by previous test
      The path "$TEST_REPO/.git/hooks/pre-commit" should be executable
    End
  End

  Describe "hooks_install_commitmsg()"
    It "creates the commit-msg file"
      install_commitmsg() {
        cd "$TEST_REPO"
        hooks_install_commitmsg
      }
      When call install_commitmsg
      The output should include "commit-msg installe"
      The path "$TEST_REPO/.git/hooks/commit-msg" should be file
    End
  End

  Describe "hooks_install_prepush()"
    It "creates the pre-push file"
      install_prepush() {
        cd "$TEST_REPO"
        hooks_install_prepush
      }
      When call install_prepush
      The output should include "pre-push installe"
      The path "$TEST_REPO/.git/hooks/pre-push" should be file
    End
  End

  Describe "_hooks_check_repo()"
    It "returns 0 inside a git repo"
      check_inside() {
        cd "$TEST_REPO"
        _hooks_check_repo
      }
      When call check_inside
      The status should equal 0
    End

    It "returns 1 outside a git repo"
      check_outside() {
        cd /tmp
        _hooks_check_repo
      }
      When call check_outside
      The stderr should include "Pas dans un depot Git"
      The status should equal 1
    End
  End
End
