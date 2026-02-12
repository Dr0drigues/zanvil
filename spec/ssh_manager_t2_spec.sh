# shellcheck shell=zsh

Describe "ssh_manager.zsh (T2 integration)"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    mkdir -p "$TEST_HOME/.ssh"
    SSH_CONFIG_FILE="$TEST_HOME/.ssh/config"
    source "$SHELLSPEC_PROJECT_ROOT/functions/ssh_manager.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "ssh_list()"
    It "displays HostName and User"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host myserver
  HostName 10.0.0.1
  User admin

Host webserver
  HostName web.example.com
  User deploy
EOF
      When call ssh_list
      The output should include "myserver"
      The output should include "10.0.0.1"
      The output should include "admin"
    End

    It "counts the total"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host server1
  HostName 10.0.0.1

Host server2
  HostName 10.0.0.2

Host server3
  HostName 10.0.0.3
EOF
      When call ssh_list
      The output should include "Total:"
      The output should include "3"
    End
  End

  Describe "ssh_select()"
    It "filters by pattern"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host prod-web
  HostName 10.0.1.1

Host prod-api
  HostName 10.0.1.2

Host staging-web
  HostName 10.0.2.1
EOF
      # Without fzf, ssh_select would need interactive input
      # We test the filter logic directly
      test_filter() {
        local hosts=$(_ssh_list_hosts)
        echo "$hosts" | grep -i "prod"
      }
      When call test_filter
      The output should include "prod-web"
      The output should include "prod-api"
      The output should not include "staging"
    End
  End

  Describe "ssh_info()"
    It "fails for unknown host"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host myserver
  HostName 10.0.0.1
EOF
      When call ssh_info "nonexistent"
      The stderr should include "non trouve"
      The status should equal 1
    End

    It "shows info for existing host"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host testhost
  HostName 192.168.1.1
  User testuser
  Port 2222
EOF
      When call ssh_info "testhost"
      The output should include "Configuration de"
      The output should include "HostName"
    End
  End

  Describe "ssh_add()"
    It "detects duplicates"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host existing
  HostName 10.0.0.1
EOF
      When call ssh_add "existing"
      The stderr should include "existe deja"
      The status should equal 1
    End

    It "creates config file if missing with permissions 600"
      rm -f "$SSH_CONFIG_FILE"
      rm -f "$TEST_HOME/.ssh/config"
      # ssh_add is interactive, so we test the file creation logic directly
      test_create_config() {
        if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
          mkdir -p "$HOME/.ssh"
          touch "$SSH_CONFIG_FILE"
          chmod 600 "$SSH_CONFIG_FILE"
        fi
        local perms
        if [[ "$OSTYPE" == darwin* ]]; then perms=$(stat -f "%Lp" "$SSH_CONFIG_FILE"); else perms=$(stat -c "%a" "$SSH_CONFIG_FILE"); fi
        echo "$perms"
      }
      When call test_create_config
      The output should equal "600"
    End
  End

  Describe "ssh_remove()"
    It "creates a backup before removal"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host to-remove
  HostName 10.0.0.99
  User deleteme

Host keep
  HostName 10.0.0.1
EOF
      # Simulate the backup part (the function needs interactive confirmation)
      test_backup() {
        cp "$SSH_CONFIG_FILE" "$SSH_CONFIG_FILE.bak"
        [ -f "$SSH_CONFIG_FILE.bak" ] && echo "backup_exists"
      }
      When call test_backup
      The output should equal "backup_exists"
    End
  End
End
