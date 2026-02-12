# shellcheck shell=sh

# ==============================================================================
# ShellSpec Helper - ZSH_ENV Test Suite
# ==============================================================================

spec_helper_precheck() {
  minimum_version "0.28.1"
}

spec_helper_loaded() {
  :
}

spec_helper_configure() {
  # Available functions: import, before_each, after_each, before_all, after_all
  import 'support/setup'
}
