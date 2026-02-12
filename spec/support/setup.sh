# shellcheck shell=sh

# ==============================================================================
# Common test setup for ZSH_ENV
# ==============================================================================

# Resolve the real project root (parent of spec/)
ZSH_ENV_PROJECT_ROOT="${SHELLSPEC_PROJECT_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Setup a temporary test environment
setup_test_env() {
  TEST_HOME=$(mktemp -d)
  TEST_ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
  mkdir -p "$TEST_ZSH_ENV_DIR/functions"
  mkdir -p "$TEST_ZSH_ENV_DIR/scripts"
  mkdir -p "$TEST_HOME/.config"
  mkdir -p "$TEST_HOME/.ssh"

  # Save originals
  ORIG_HOME="$HOME"
  ORIG_ZSH_ENV_DIR="${ZSH_ENV_DIR:-}"

  # Override for tests
  export HOME="$TEST_HOME"
  export ZSH_ENV_DIR="$TEST_ZSH_ENV_DIR"
}

# Cleanup the temporary test environment
cleanup_test_env() {
  # Restore originals
  export HOME="$ORIG_HOME"
  [ -n "$ORIG_ZSH_ENV_DIR" ] && export ZSH_ENV_DIR="$ORIG_ZSH_ENV_DIR" || unset ZSH_ENV_DIR
  # Remove temp dir
  [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}
