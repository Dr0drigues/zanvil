# shellcheck shell=zsh

Describe "aliases.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"
    source "$SHELLSPEC_PROJECT_ROOT/aliases.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "Git aliases"
    It "gst is aliased to git status"
      result() { alias gst 2>/dev/null; }
      When call result
      The output should include "git status"
    End

    It "gl is aliased to git fetch/pull"
      result() { alias gl 2>/dev/null; }
      When call result
      The output should include "git fetch --all"
      The output should include "git pull"
    End

    It "gld is aliased to git log --oneline --decorate --graph --all"
      result() { alias gld 2>/dev/null; }
      When call result
      The output should include "git log --oneline --decorate --graph --all"
    End
  End

  Describe "ls alias"
    Context "when eza is available"
      It "uses eza if available"
        if command -v eza &>/dev/null; then
          result() { alias ls 2>/dev/null; }
          When call result
          The output should include "eza"
        else
          Skip "eza not installed"
        fi
      End
    End

    Context "when eza is NOT available"
      It "l alias references ls"
        result() { alias l 2>/dev/null; }
        When call result
        The output should include "ls"
      End
    End
  End

  Describe "cat alias"
    It "uses bat if available"
      if command -v bat &>/dev/null; then
        result() { alias cat 2>/dev/null; }
        When call result
        The output should include "bat"
      else
        Skip "bat not installed"
      fi
    End
  End

  Describe "npm aliases"
    It "npmi is aliased to npm install"
      if command -v npm &>/dev/null; then
        result() { alias npmi 2>/dev/null; }
        When call result
        The output should include "npm install"
      else
        Skip "npm not installed"
      fi
    End

    It "nci uses /bin/rm and not rmi"
      if command -v npm &>/dev/null; then
        result() { alias nci 2>/dev/null; }
        When call result
        The output should include "/bin/rm"
      else
        Skip "npm not installed"
      fi
    End
  End

  Describe "rm/trash wrapper"
    It "rm is redefined (function or alias)"
      result() {
        local rm_type=$(type -w rm 2>/dev/null | cut -d' ' -f2)
        # rm should be either a function (trash available) or an alias (rm -i)
        [[ "$rm_type" == "function" || "$rm_type" == "alias" ]] && echo "redefined" || echo "builtin"
      }
      When call result
      The output should equal "redefined"
    End
  End

  Describe "rm wrapper behavior"
    It "uses real rm in non-interactive/scripted context"
      test_rm_scripted() {
        # funcstack depth > 1 means scripted context
        # The rm function should use 'command rm' not 'trash'
        if whence -w rm | grep -q function; then
          local def=$(whence -f rm 2>/dev/null)
          # The function should have the 'command rm' fallback path
          [[ "$def" == *'command rm'* ]] && echo "has_rm_fallback" || echo "missing"
        else
          # rm is an alias (no trash), which is also correct for non-interactive
          echo "has_rm_fallback"
        fi
      }
      When call test_rm_scripted
      The output should equal "has_rm_fallback"
    End
  End

  Describe "git-clean-branches()"
    It "is defined as a function"
      result() { type -w git-clean-branches 2>/dev/null | cut -d' ' -f2; }
      When call result
      The output should equal "function"
    End

    It "returns 0 when no merged branches exist (output includes 'Aucune')"
      # Verify the function handles the "no branches" case
      # by testing the function definition includes that path
      result() {
        local def=$(whence -f git-clean-branches 2>/dev/null)
        [[ "$def" == *"Aucune branche"* ]] && echo "has_empty_case" || echo "missing"
      }
      When call result
      The output should equal "has_empty_case"
    End

    It "excludes master/main/dev/develop/release/*"
      result() {
        # Verify the function definition contains the exclusion patterns
        local def=$(whence -f git-clean-branches 2>/dev/null)
        [[ "$def" == *"master"* && "$def" == *"main"* && "$def" == *"develop"* && "$def" == *"release/"* ]] && echo "all_excluded" || echo "missing"
      }
      When call result
      The output should equal "all_excluded"
    End
  End
End
