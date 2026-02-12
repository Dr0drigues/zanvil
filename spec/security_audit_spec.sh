# shellcheck shell=zsh

Describe "security_audit.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"
    setopt NULL_GLOB NO_NOMATCH
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"
    source "$SHELLSPEC_PROJECT_ROOT/functions/security_audit.zsh"
  }

  cleanup() {
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "zsh-env-audit()"
    It "checks ~/.ssh permissions (700) - OK"
      mkdir -p "$TEST_HOME/.ssh"
      chmod 700 "$TEST_HOME/.ssh"
      When call zsh-env-audit
      The output should include "SSH"
    End

    It "detects bad permissions on ~/.ssh"
      chmod 755 "$TEST_HOME/.ssh"
      When call zsh-env-audit
      The output should include "erreur"
      The status should not equal 0
    End

    It "checks private key permissions (600)"
      chmod 700 "$TEST_HOME/.ssh"
      echo "fake_key" > "$TEST_HOME/.ssh/id_rsa"
      chmod 600 "$TEST_HOME/.ssh/id_rsa"
      When call zsh-env-audit
      The output should include "id_rsa"
    End

    It "detects bad private key permissions"
      echo "fake_key" > "$TEST_HOME/.ssh/id_ed25519"
      chmod 644 "$TEST_HOME/.ssh/id_ed25519"
      When call zsh-env-audit
      The output should include "id_ed25519"
      The status should not equal 0
    End

    It "checks ~/.ssh/config (600)"
      chmod 600 "$TEST_HOME/.ssh/id_ed25519"
      echo "Host test" > "$TEST_HOME/.ssh/config"
      chmod 600 "$TEST_HOME/.ssh/config"
      When call zsh-env-audit
      The output should include "config"
      The status should equal 0
    End

    It "checks ~/.secrets (600)"
      echo "export SECRET=test" > "$TEST_HOME/.secrets"
      chmod 600 "$TEST_HOME/.secrets"
      When call zsh-env-audit
      The output should include "Secrets"
    End

    It "checks ~/.kube (700)"
      mkdir -p "$TEST_HOME/.kube"
      chmod 700 "$TEST_HOME/.kube"
      When call zsh-env-audit
      The output should include "Kubernetes"
    End

    It "detects credentials in history"
      echo "password=secret123" > "$TEST_HOME/.zsh_history"
      chmod 600 "$TEST_HOME/.zsh_history"
      When call zsh-env-audit
      The output should include "History"
      The output should include "secrets"
    End

    It "returns the number of issues (0 = ok)"
      chmod 700 "$TEST_HOME/.ssh"
      chmod 600 "$TEST_HOME/.ssh/id_rsa"
      chmod 600 "$TEST_HOME/.ssh/id_ed25519"
      chmod 600 "$TEST_HOME/.ssh/config"
      chmod 600 "$TEST_HOME/.secrets"
      rm -f "$TEST_HOME/.zsh_history"
      When call zsh-env-audit
      The output should include "Security Audit"
      The status should equal 0
    End

    It "returns non-zero with issues"
      chmod 755 "$TEST_HOME/.ssh"
      When call zsh-env-audit
      The output should include "erreur"
      The status should not equal 0
    End
  End

  Describe "zsh-env-audit-fix()"
    It "corrects SSH permissions"
      chmod 755 "$TEST_HOME/.ssh"
      chmod 644 "$TEST_HOME/.ssh/id_rsa"
      chmod 644 "$TEST_HOME/.ssh/config"
      When call zsh-env-audit-fix
      The output should include "corrige"
    End

    It "SSH dir is 700 after fix"
      chmod 755 "$TEST_HOME/.ssh"
      check_and_fix() {
        setopt NULL_GLOB NO_NOMATCH
        zsh-env-audit-fix > /dev/null 2>&1
        if [[ "$OSTYPE" == darwin* ]]; then stat -f "%Lp" "$TEST_HOME/.ssh"; else stat -c "%a" "$TEST_HOME/.ssh"; fi
      }
      When call check_and_fix
      The output should equal "700"
    End

    It "corrects secrets permissions"
      chmod 644 "$TEST_HOME/.secrets"
      When call zsh-env-audit-fix
      The output should include "corrige"
    End

    It "secrets file is 600 after fix"
      chmod 644 "$TEST_HOME/.secrets"
      check_and_fix() {
        setopt NULL_GLOB NO_NOMATCH
        zsh-env-audit-fix > /dev/null 2>&1
        if [[ "$OSTYPE" == darwin* ]]; then stat -f "%Lp" "$TEST_HOME/.secrets"; else stat -c "%a" "$TEST_HOME/.secrets"; fi
      }
      When call check_and_fix
      The output should equal "600"
    End
  End
End
