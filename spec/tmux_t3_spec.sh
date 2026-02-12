# shellcheck shell=zsh

Describe "tmux_manager.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    source "$SHELLSPEC_PROJECT_ROOT/functions/tmux_manager.zsh"
  }

  cleanup() {
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "_tmux_check()"
    It "is defined as a function"
      When call whence -w _tmux_check
      The output should include "function"
    End
  End

  Describe "tm()"
    It "creates 'main' session when no sessions exist"
      test_tm_no_sessions() {
        tmux() {
          case "$1" in
            list-sessions) return 1 ;;
            new-session) echo "new-session $*" ;;
            has-session) return 1 ;;
          esac
        }
        tm
      }
      When call test_tm_no_sessions
      The output should include "Creation de 'main'"
    End

    It "attaches to existing session by name"
      test_tm_attach() {
        unset TMUX
        tmux() {
          case "$1" in
            has-session) return 0 ;;
            attach-session) echo "attached to $3" ;;
          esac
        }
        tm "mysession"
      }
      When call test_tm_attach
      The output should include "attached to mysession"
    End

    It "switches client when inside tmux"
      test_tm_switch() {
        TMUX="/tmp/tmux-1000/default,12345,0"
        tmux() {
          case "$1" in
            has-session) return 0 ;;
            switch-client) echo "switched to $3" ;;
          esac
        }
        tm "other"
        unset TMUX
      }
      When call test_tm_switch
      The output should include "switched to other"
    End
  End

  Describe "tm-list()"
    It "shows message when no sessions"
      test_list_empty() {
        tmux() {
          case "$1" in
            list-sessions) return 1 ;;
          esac
        }
        tm-list
      }
      When call test_list_empty
      The output should include "Aucune session"
    End

    It "displays sessions"
      test_list_sessions() {
        tmux() {
          case "$1" in
            list-sessions)
              if [[ "$2" == "-F" ]]; then
                echo "*  main (3 fenetres, cree Mon Feb 10)"
                echo "   work (1 fenetres, cree Mon Feb 10)"
              else
                echo "main: 3 windows"
                echo "work: 1 windows"
              fi
              ;;
          esac
        }
        tm-list
      }
      When call test_list_sessions
      The output should include "Sessions tmux:"
      The output should include "session attachee"
    End
  End

  Describe "tm-kill()"
    It "fails for unknown session"
      test_kill_unknown() {
        tmux() {
          case "$1" in
            has-session) return 1 ;;
          esac
        }
        tm-kill "nonexistent"
      }
      When call test_kill_unknown
      The stderr should include "non trouvee"
      The status should equal 1
    End

    It "kills existing session"
      test_kill_ok() {
        tmux() {
          case "$1" in
            has-session) return 0 ;;
            kill-session) return 0 ;;
          esac
        }
        tm-kill "old"
      }
      When call test_kill_ok
      The output should include "terminee"
    End
  End

  Describe "tm-rename()"
    It "fails outside tmux"
      test_rename_no_tmux() {
        tmux() { :; }  # mock so _tmux_check passes
        unset TMUX
        tm-rename "newname"
      }
      When call test_rename_no_tmux
      The stderr should include "Pas dans une session tmux"
      The status should equal 1
    End

    It "renames the current session"
      test_rename_ok() {
        TMUX="/tmp/tmux-1000/default,12345,0"
        tmux() {
          case "$1" in
            rename-session) echo "renamed to $2" ;;
          esac
        }
        tm-rename "newname"
        unset TMUX
      }
      When call test_rename_ok
      The output should include "renommee"
      The output should include "newname"
    End
  End

  Describe "tm-project()"
    It "fails if directory does not exist"
      test_project_no_dir() {
        tmux() { return 0; }
        tm-project "/tmp/nonexistent_proj_dir_xyz"
      }
      When call test_project_no_dir
      The stderr should include "Dossier non trouve"
      The status should equal 1
    End

    It "creates session with 3 windows"
      test_project_layout() {
        local projdir="$TEST_HOME/my-project"
        mkdir -p "$projdir"
        local windows_created=0
        tmux() {
          case "$1" in
            has-session) return 1 ;;
            new-session) echo "tmux:new-session" ;;
            rename-window) echo "tmux:rename-window:$4" ;;
            new-window) echo "tmux:new-window:$5" ;;
            select-window) echo "tmux:select-window" ;;
            attach-session|switch-client) return 0 ;;
          esac
        }
        unset TMUX
        tm-project "$projdir"
      }
      When call test_project_layout
      The output should include "Creation de la session projet"
      The output should include "tmux:rename-window:edit"
      The output should include "tmux:new-window:term"
      The output should include "tmux:new-window:git"
    End
  End
End
