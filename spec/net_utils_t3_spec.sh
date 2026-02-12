# shellcheck shell=zsh

Describe "net_utils.zsh (T3 mocked)"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/net_utils.zsh"
  }

  BeforeAll 'setup'

  Describe "myip()"
    It "displays public and local IP"
      test_myip() {
        curl() { echo "1.2.3.4"; }
        uname() { echo "Darwin"; }
        ipconfig() { echo "192.168.1.100"; }
        myip
        unfunction curl uname ipconfig 2>/dev/null
      }
      When call test_myip
      The output should include "Public IP : 1.2.3.4"
      The output should include "Local IP  : 192.168.1.100"
    End

    It "handles curl timeout"
      test_myip_timeout() {
        curl() { return 1; }
        uname() { echo "Darwin"; }
        ipconfig() { echo "10.0.0.1"; }
        myip
        unfunction curl uname ipconfig 2>/dev/null
      }
      When call test_myip_timeout
      The output should include "Public IP : timeout"
    End

    It "handles Linux IP detection"
      test_myip_linux() {
        curl() { echo "5.6.7.8"; }
        uname() { echo "Linux"; }
        hostname() { echo "10.0.0.5 172.17.0.1"; }
        myip
        unfunction curl uname hostname 2>/dev/null
      }
      When call test_myip_linux
      The output should include "Public IP : 5.6.7.8"
      The output should include "Local IP  : 10.0.0.5"
    End
  End

  Describe "port() with mocked nc"
    It "detects open port"
      test_port_open() {
        nc() { echo "Connection to host port 80 [tcp/http] succeeded!"; return 0; }
        port "host" "80"
        unfunction nc 2>/dev/null
      }
      When call test_port_open
      The output should include "Port 80 ouvert"
    End

    It "detects closed port"
      test_port_closed() {
        nc() { echo "Connection refused"; return 1; }
        port "host" "443"
        unfunction nc 2>/dev/null
      }
      When call test_port_closed
      The output should include "ferme ou inaccessible"
    End
  End
End
