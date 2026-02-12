# shellcheck shell=zsh

Describe "test_runner.zsh"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/test_runner.zsh"
    TEST_HOME=$(mktemp -d)
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "trun()"
    It "fails without package.json"
      cd "$TEST_HOME"
      When call trun
      The output should include "package.json"
      The status should equal 1
    End

    It "detects jest in package.json"
      mkdir -p "$TEST_HOME/jest_proj"
      echo '{"devDependencies": {"jest": "^29.0.0"}}' > "$TEST_HOME/jest_proj/package.json"
      cd "$TEST_HOME/jest_proj"
      # Just check that the runner check passes (it won't find node_modules, but verifies detection)
      When call _trun_check_runner "jest"
      The status should equal 0
    End

    It "detects vitest in package.json"
      mkdir -p "$TEST_HOME/vitest_proj"
      echo '{"devDependencies": {"vitest": "^1.0.0"}}' > "$TEST_HOME/vitest_proj/package.json"
      cd "$TEST_HOME/vitest_proj"
      When call _trun_check_runner "vitest"
      The status should equal 0
    End

    It "detects mocha in package.json"
      mkdir -p "$TEST_HOME/mocha_proj"
      echo '{"devDependencies": {"mocha": "^10.0.0"}}' > "$TEST_HOME/mocha_proj/package.json"
      cd "$TEST_HOME/mocha_proj"
      When call _trun_check_runner "mocha"
      The status should equal 0
    End
  End

  Describe "trun flags"
    It "-c includes coverage flag"
      mkdir -p "$TEST_HOME/flag_proj"
      echo '{"devDependencies": {"jest": "^29.0"}}' > "$TEST_HOME/flag_proj/package.json"
      cd "$TEST_HOME/flag_proj"
      When call _trun_build_cmd "jest" "true" ""
      The output should include "coverage"
    End

    It "-v activates verbose (help text mentions verbose)"
      When call _trun_help
      The output should include "verbose"
    End
  End
End
