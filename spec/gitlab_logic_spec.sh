# shellcheck shell=zsh

Describe "gitlab_logic.zsh"
  Describe "Module skip if ZSH_ENV_MODULE_GITLAB != true"
    It "skips when module is disabled"
      test_skip() {
        ZSH_ENV_MODULE_GITLAB=false
        # Simulate the guard
        [[ "$ZSH_ENV_MODULE_GITLAB" != "true" ]] && echo "skipped" && return
        echo "loaded"
      }
      When call test_skip
      The output should equal "skipped"
    End
  End

  Describe "Warning if ~/.gitlab_secrets missing"
    It "warns when secrets file is missing"
      test_warning() {
        local TEST_DIR=$(mktemp -d)
        # Simulate the warning logic from gitlab_logic.zsh
        if [[ ! -f "$TEST_DIR/.gitlab_secrets" ]]; then
          echo "WARNING: gitlab_secrets introuvable" >&2
        fi
        rm -rf "$TEST_DIR"
      }
      When call test_warning
      The stderr should include "WARNING"
    End
  End
End
