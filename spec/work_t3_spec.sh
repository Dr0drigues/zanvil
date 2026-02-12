# shellcheck shell=zsh

Describe "work_context.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"

    # Source only function definitions, skip auto-init block
    eval "$(sed '/^# --- Auto-initialisation/,$ d' "$SHELLSPEC_PROJECT_ROOT/functions/work_context.zsh")"
  }

  cleanup() {
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "_blg_test_nexus()"
    It "returns 0 when curl gets HTTP 2xx"
      test_nexus_ok() {
        curl() { echo "200"; return 0; }
        _blg_test_nexus
      }
      When call test_nexus_ok
      The status should equal 0
    End

    It "returns 1 when curl fails (timeout)"
      test_nexus_fail() {
        curl() { return 1; }
        # Also ensure wget is not found
        wget() { return 1; }
        _blg_test_nexus
      }
      When call test_nexus_fail
      The status should equal 1
    End

    It "uses wget as fallback"
      test_nexus_wget() {
        curl() { return 127; }  # curl not found
        wget() { return 0; }    # wget succeeds
        command() {
          if [[ "$2" == "curl" ]]; then return 1; fi
          if [[ "$2" == "wget" ]]; then return 0; fi
          builtin command "$@"
        }
        _blg_test_nexus
        unfunction command 2>/dev/null
      }
      When call test_nexus_wget
      The status should equal 0
    End
  End

  Describe "work_is_context()"
    It "uses cached value when cache is valid"
      test_cache_hit() {
        local cache_file="$TEST_HOME/.cache/zsh_env/blg_context"
        mkdir -p "$(dirname "$cache_file")"
        _WORK_CACHE_FILE="$cache_file"
        _WORK_CACHE_TTL=3600
        # Write recent cache (timestamp = now, value = true)
        local now=$(date +%s)
        echo "$now" > "$cache_file"
        echo "true" >> "$cache_file"
        work_is_context
      }
      When call test_cache_hit
      The status should equal 0
    End

    It "returns 1 when cache says false"
      test_cache_false() {
        local cache_file="$TEST_HOME/.cache/zsh_env/blg_context_false"
        mkdir -p "$(dirname "$cache_file")"
        _WORK_CACHE_FILE="$cache_file"
        _WORK_CACHE_TTL=3600
        local now=$(date +%s)
        echo "$now" > "$cache_file"
        echo "false" >> "$cache_file"
        work_is_context
      }
      When call test_cache_false
      The status should equal 1
    End

    It "falls back to live test when cache expired"
      test_cache_miss() {
        local cache_file="$TEST_HOME/.cache/zsh_env/blg_context_expired"
        mkdir -p "$(dirname "$cache_file")"
        _WORK_CACHE_FILE="$cache_file"
        _WORK_CACHE_TTL=3600
        # Write old cache (expired)
        echo "1000000000" > "$cache_file"
        echo "true" >> "$cache_file"
        # Mock _blg_test_nexus to succeed
        _blg_test_nexus() { return 0; }
        work_is_context
      }
      When call test_cache_miss
      The status should equal 0
    End
  End
End
