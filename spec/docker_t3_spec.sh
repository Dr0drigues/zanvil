# shellcheck shell=zsh

Describe "docker_utils.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    export ZSH_ENV_MODULE_DOCKER="true"
    source "$SHELLSPEC_PROJECT_ROOT/functions/docker_utils.zsh"
  }

  cleanup() {
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "module skip"
    It "skips when ZSH_ENV_MODULE_DOCKER != true"
      check_skip() {
        local out
        out=$(ZSH_ENV_MODULE_DOCKER=false zsh -c "source '$SHELLSPEC_PROJECT_ROOT/functions/docker_utils.zsh'; whence -w dex 2>/dev/null || echo 'not_found'")
        echo "$out"
      }
      When call check_skip
      The output should include "not_found"
    End
  End

  Describe "dex()"
    It "fails when Docker is not running"
      test_dex_no_docker() {
        docker() { return 1; }
        dex
      }
      When call test_dex_no_docker
      The output should include "Docker n'est pas"
      The status should equal 1
    End
  End

  Describe "dstop()"
    It "fails when Docker is not accessible"
      test_dstop_no_docker() {
        docker() { return 1; }
        dstop
      }
      When call test_dstop_no_docker
      The output should include "Docker n'est pas"
      The status should equal 1
    End

    It "returns 0 if no containers running"
      test_dstop_empty() {
        docker() {
          case "$1" in
            ps)
              if [[ "$2" == "-q" ]]; then
                echo ""
              else
                return 0
              fi
              ;;
          esac
        }
        dstop
      }
      When call test_dstop_empty
      The output should include "Aucun conteneur"
      The status should equal 0
    End

    It "displays container count"
      test_dstop_count() {
        docker() {
          case "$1" in
            ps)
              if [[ "$2" == "-q" ]]; then
                printf "abc123\ndef456\n"
              elif [[ "$2" == "--format" ]]; then
                echo "  web (nginx) - Up 5m"
                echo "  api (node) - Up 10m"
              else
                return 0
              fi
              ;;
            stop) echo "stopped" ;;
          esac
        }
        # Non-interactive mode: skip read -q prompt
        dstop < /dev/null
      }
      When call test_dstop_count
      The output should include "2 conteneur(s)"
    End
  End
End
