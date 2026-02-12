# shellcheck shell=zsh

Describe "zsh_profile.zsh"
  setup() {
    export ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"
    source "$SHELLSPEC_PROJECT_ROOT/functions/zsh_profile.zsh"
  }

  BeforeAll 'setup'

  Describe "zsh-env-profile()"
    It "is defined as a function"
      check_profile() { whence -w zsh-env-profile | grep -q "function"; }
      When call check_profile
      The status should equal 0
    End
  End

  Describe "zsh-env-profile-quick()"
    It "is defined as a function"
      check_quick() { whence -w zsh-env-profile-quick | grep -q "function"; }
      When call check_quick
      The status should equal 0
    End
  End

  Describe "zsh-env-benchmark()"
    It "is defined as a function"
      check_bench() { whence -w zsh-env-benchmark | grep -q "function"; }
      When call check_bench
      The status should equal 0
    End
  End
End
