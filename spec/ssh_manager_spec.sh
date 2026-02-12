# shellcheck shell=zsh

Describe "ssh_manager.zsh"
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

  Describe "ssh_select()"
    It "fails without ssh config file"
      rm -f "$SSH_CONFIG_FILE"
      When call ssh_select
      The stderr should include "Aucun host"
      The status should equal 1
    End
  End

  Describe "ssh_info()"
    It "requires an argument"
      When call ssh_info
      The stderr should include "Usage:"
      The status should equal 1
    End
  End

  Describe "ssh_copy_key()"
    It "fails if the key does not exist"
      When call ssh_copy_key "myhost" "$TEST_HOME/.ssh/nonexistent.pub"
      The stderr should include "non trouvee"
      The status should equal 1
    End
  End

  Describe "_ssh_list_hosts()"
    It "parses ssh config file"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host server1
  HostName 10.0.0.1
  User admin

Host server2
  HostName 10.0.0.2
  User deploy

Host *
  ServerAliveInterval 60
EOF
      When call _ssh_list_hosts
      The output should include "server1"
      The output should include "server2"
    End

    It "ignores wildcards (* and ?)"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host server1
  HostName 10.0.0.1

Host *
  ServerAliveInterval 60

Host test?
  HostName 10.0.0.3
EOF
      When call _ssh_list_hosts
      The output should include "server1"
      The output should not include "*"
    End

    It "returns sorted hosts"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host zserver
  HostName 10.0.0.3

Host aserver
  HostName 10.0.0.1

Host mserver
  HostName 10.0.0.2
EOF
      When call _ssh_list_hosts
      The line 1 of output should equal "aserver"
    End
  End

  Describe "_ssh_get_host_info()"
    It "extracts host configuration"
      cat > "$SSH_CONFIG_FILE" << 'EOF'
Host myserver
  HostName 192.168.1.10
  User admin
  Port 2222

Host other
  HostName 10.0.0.1
EOF
      When call _ssh_get_host_info "myserver"
      The output should include "HostName"
      The status should equal 0
    End
  End
End
