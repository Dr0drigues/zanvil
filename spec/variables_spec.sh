# shellcheck shell=zsh

Describe "variables.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    TEST_ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$TEST_ZSH_ENV_DIR/scripts"
    mkdir -p "$TEST_HOME/.config"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_ZSH_ENV_DIR"
    source "$SHELLSPEC_PROJECT_ROOT/variables.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "Exported variables"
    It "exports WORK_DIR"
      The variable WORK_DIR should be exported
      The variable WORK_DIR should end with "/work"
    End

    It "exports SCRIPTS_DIR"
      The variable SCRIPTS_DIR should be exported
      The variable SCRIPTS_DIR should end with "/scripts"
    End

    It "exports HISTFILE as ~/.zsh_history"
      The variable HISTFILE should be exported
      The variable HISTFILE should end with "/.zsh_history"
    End

    It "sets HISTSIZE to 50000"
      The variable HISTSIZE should equal 50000
    End

    It "sets SAVEHIST to 50000"
      The variable SAVEHIST should equal 50000
    End

    It "exports SOPS_AGE_KEY_FILE"
      The variable SOPS_AGE_KEY_FILE should be exported
      The variable SOPS_AGE_KEY_FILE should end with "/.config/sops/age/keys.txt"
    End
  End

  Describe "Directory creation"
    It "creates WORK_DIR if missing"
      The path "$WORK_DIR" should be directory
    End

    It "creates SCRIPTS_DIR if missing"
      The path "$SCRIPTS_DIR" should be directory
    End
  End
End
