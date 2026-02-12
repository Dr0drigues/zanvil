# shellcheck shell=zsh

Describe "git_change_author.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    ORIG_PWD="$PWD"
    export HOME="$TEST_HOME"
    # Configure git for temp HOME (needed for git commit)
    git config --global user.email "test@test.com"
    git config --global user.name "Test User"
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"
    source "$SHELLSPEC_PROJECT_ROOT/functions/git_change_author.zsh"
  }

  cleanup() {
    cd "$ORIG_PWD" 2>/dev/null || cd /
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "gc-author()"
    It "prefers git-filter-repo when available"
      test_filter_repo() {
        local repo="$TEST_HOME/test-repo"
        mkdir -p "$repo" && cd "$repo"
        git init --quiet
        git commit --allow-empty -m "init" --quiet

        # Store original git path
        local orig_git="$(which git)"
        # Override command -v to find git-filter-repo
        command() {
          if [[ "$1" == "-v" && "$2" == "git-filter-repo" ]]; then
            echo "git-filter-repo"
            return 0
          fi
          builtin command "$@"
        }
        # Override git to handle filter-repo subcommand
        git() {
          case "$1" in
            tag) $orig_git tag "$2" HEAD 2>/dev/null ;;
            filter-repo) echo "filter-repo-executed"; return 0 ;;
            *) $orig_git "$@" ;;
          esac
        }
        date() { echo "20260212-120000"; }
        read() { eval "${2%%\?*}=y"; }

        gc-author "old@email.com" "New Name" "new@email.com"
        local rc=$?

        unfunction command git date read 2>/dev/null
        return $rc
      }
      When call test_filter_repo
      The output should include "filter-repo"
      The status should equal 0
    End

    It "creates backup tag before rewrite"
      test_backup_tag() {
        local repo="$TEST_HOME/test-repo2"
        mkdir -p "$repo" && cd "$repo"
        git init --quiet
        git commit --allow-empty -m "init" --quiet

        local tag_created=""
        local orig_git="$(which git)"
        git() {
          case "$1" in
            tag) tag_created="$2"; $orig_git tag "$2" HEAD 2>/dev/null ;;
            filter-branch) return 0 ;;
            *) $orig_git "$@" ;;
          esac
        }
        command() {
          if [[ "$1" == "-v" && "$2" == "git-filter-repo" ]]; then
            return 1  # not available, use filter-branch
          fi
          builtin command "$@"
        }
        date() { echo "20260212-143000"; }
        read() { eval "${2%%\?*}=y"; }

        gc-author "old@email.com" "New" "new@email.com"
        echo "TAG:$tag_created"

        unfunction git command date read 2>/dev/null
      }
      When call test_backup_tag
      The output should include "TAG:backup/before-author-change-20260212-143000"
    End
  End
End
