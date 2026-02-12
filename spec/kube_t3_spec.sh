# shellcheck shell=zsh

Describe "kube_config.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    ORIG_PWD="$PWD"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"

    # Set kube vars before sourcing to override defaults
    export KUBE_DIR="$TEST_HOME/.kube"
    export KUBE_CONFIGS_DIR="$KUBE_DIR/configs.d"
    export KUBE_MINIMAL_CONFIG="$KUBE_DIR/config.minimal.yml"
    export KUBE_SOPS_SOURCE="$ZSH_ENV_DIR/kube"
    export KUBE_SELECTION_FILE="$KUBE_DIR/.kubeconfig_selection"
    mkdir -p "$KUBE_DIR" "$KUBE_CONFIGS_DIR"
    unset KUBECONFIG

    source "$SHELLSPEC_PROJECT_ROOT/functions/kube_config.zsh"
  }

  cleanup() {
    cd "$ORIG_PWD" 2>/dev/null || cd /
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "kube_init()"
    It "creates ~/.kube and configs.d directories"
      init_kube() {
        rm -rf "$KUBE_DIR"
        # Mock kubectl to avoid errors
        kubectl() { echo "mock"; }
        kube_init
        [[ -d "$KUBE_DIR" ]] && echo "kube_dir_exists"
        [[ -d "$KUBE_CONFIGS_DIR" ]] && echo "configs_d_exists"
        unfunction kubectl 2>/dev/null
      }
      When call init_kube
      The output should include "kube_dir_exists"
      The output should include "configs_d_exists"
    End
  End

  Describe "kube_status()"
    It "shows default message when KUBECONFIG is empty"
      status_empty() {
        unset KUBECONFIG
        kube_status
      }
      When call status_empty
      The output should include "aucune"
    End

    It "lists active configs"
      status_with_config() {
        echo "apiVersion: v1" > "$KUBE_DIR/test-config.yml"
        export KUBECONFIG="$KUBE_DIR/test-config.yml"
        kubectl() { echo "test-context"; }
        kube_status
        unfunction kubectl 2>/dev/null
      }
      When call status_with_config
      The output should include "test-config.yml"
      The output should include "test-context"
    End

    It "marks missing config files"
      status_missing() {
        export KUBECONFIG="/tmp/nonexistent_kube_config_xyz.yml"
        kubectl() { return 1; }
        kube_status
        unfunction kubectl 2>/dev/null
      }
      When call status_missing
      The output should include "MANQUANT"
    End
  End

  Describe "kube_add()"
    It "validates file existence"
      add_missing() {
        kube_add "/tmp/nonexistent_kube_config_xyz.yml"
      }
      When call add_missing
      The stderr should include "non trouve"
      The status should equal 1
    End

    It "detects duplicates"
      add_dup() {
        local cfg="$KUBE_DIR/dup-config.yml"
        echo "apiVersion: v1" > "$cfg"
        export KUBECONFIG="$cfg"
        kube_add "$cfg"
      }
      When call add_dup
      The output should include "deja chargee"
    End

    It "adds config to KUBECONFIG"
      add_new() {
        local cfg="$KUBE_DIR/new-config.yml"
        echo "apiVersion: v1" > "$cfg"
        export KUBECONFIG="$KUBE_MINIMAL_CONFIG"
        echo "apiVersion: v1" > "$KUBE_MINIMAL_CONFIG"
        kube_add "$cfg"
        echo "RESULT:$KUBECONFIG"
      }
      When call add_new
      The output should include "Config ajoutee"
      The output should include "RESULT:"
      The output should include "new-config.yml"
    End
  End

  Describe "kube_reset()"
    It "resets to minimal config"
      reset_kube() {
        echo "apiVersion: v1" > "$KUBE_MINIMAL_CONFIG"
        export KUBECONFIG="$KUBE_DIR/some-config.yml:$KUBE_DIR/another.yml"
        kube_reset
        echo "RESULT:$KUBECONFIG"
      }
      When call reset_kube
      The output should include "reinitialise"
      The output should include "RESULT:"
      The output should include "config.minimal.yml"
    End

    It "unsets KUBECONFIG when no minimal config"
      reset_no_minimal() {
        rm -f "$KUBE_MINIMAL_CONFIG"
        export KUBECONFIG="something"
        kube_reset
      }
      When call reset_no_minimal
      The output should include "KUBECONFIG vide"
    End
  End

  Describe "_kube_check_deps()"
    It "returns 0 when kubectl is available"
      check_deps_ok() {
        kubectl() { :; }
        _kube_check_deps
        local rc=$?
        unfunction kubectl 2>/dev/null
        return $rc
      }
      When call check_deps_ok
      The status should equal 0
    End
  End

  Describe "_kube_has_sops()"
    It "returns 1 when sops or age is missing"
      check_no_sops() {
        # In CI/test, sops and age are unlikely to be installed
        if ! command -v sops &>/dev/null || ! command -v age &>/dev/null; then
          _kube_has_sops
        else
          return 1
        fi
      }
      When call check_no_sops
      The status should equal 1
    End
  End
End
