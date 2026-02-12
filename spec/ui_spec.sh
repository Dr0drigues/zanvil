# shellcheck shell=zsh

Describe "ui.zsh"
  setup() {
    export ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"
  }

  BeforeAll 'setup'

  Describe "variables"
    It "defines ZSH_ENV_VERSION"
      The variable ZSH_ENV_VERSION should be present
      The variable ZSH_ENV_VERSION should start with "v"
    End

    It "defines color variables"
      The variable _ui_red should be present
      The variable _ui_green should be present
      The variable _ui_yellow should be present
      The variable _ui_blue should be present
      The variable _ui_cyan should be present
      The variable _ui_nc should be present
    End

    It "defines style variables"
      The variable _ui_bold should be present
      The variable _ui_dim should be present
    End

    It "defines symbol variables"
      The variable _ui_check should equal "✓"
      The variable _ui_cross should equal "✗"
      The variable _ui_circle should equal "○"
    End

    It "defines compatibility aliases"
      The variable _zsh_cmd_green should equal "$_ui_green"
      The variable _zsh_cmd_red should equal "$_ui_red"
      The variable _zsh_cmd_bold should equal "$_ui_bold"
      The variable _zsh_cmd_nc should equal "$_ui_nc"
    End
  End

  Describe "_ui_header()"
    It "renders a boxed header"
      When call _ui_header "Test Title"
      The output should include "Test Title"
      The output should include "$ZSH_ENV_VERSION"
    End
  End

  Describe "_ui_section()"
    It "formats a label-value pair"
      When call _ui_section "Label" "Value"
      The output should include "Label"
      The output should include "Value"
    End
  End

  Describe "_ui_separator()"
    It "renders a separator line"
      When call _ui_separator 10
      The output should include "─"
    End
  End

  Describe "_ui_ok()"
    It "renders success indicator"
      When call _ui_ok "tool"
      The output should include "tool"
      The output should include "✓"
    End

    It "includes version when provided"
      When call _ui_ok "tool" "1.0"
      The output should include "tool"
      The output should include "1.0"
    End
  End

  Describe "_ui_fail()"
    It "renders failure indicator"
      When call _ui_fail "tool"
      The output should include "tool"
      The output should include "✗"
    End
  End

  Describe "_ui_warn()"
    It "renders warning indicator"
      When call _ui_warn "tool"
      The output should include "tool"
      The output should include "○"
    End
  End

  Describe "_ui_msg_ok()"
    It "renders success message"
      When call _ui_msg_ok "all good"
      The output should include "✓"
      The output should include "all good"
    End
  End

  Describe "_ui_msg_fail()"
    It "renders failure message"
      When call _ui_msg_fail "something failed"
      The output should include "✗"
      The output should include "something failed"
    End
  End

  Describe "_ui_msg_warn()"
    It "renders warning message"
      When call _ui_msg_warn "be careful"
      The output should include "be careful"
    End
  End

  Describe "_ui_tag_ok()"
    It "renders [OK] tag"
      When call _ui_tag_ok "done"
      The output should include "[OK]"
      The output should include "done"
    End
  End

  Describe "_ui_tag_fail()"
    It "renders [FAIL] tag"
      When call _ui_tag_fail "error"
      The output should include "[FAIL]"
    End
  End

  Describe "_ui_summary()"
    It "shows all OK with no issues"
      When call _ui_summary 0 0
      The output should include "Tout est OK"
    End

    It "shows warnings count"
      When call _ui_summary 0 3
      The output should include "3 avertissement"
    End

    It "shows issues and warnings"
      When call _ui_summary 2 1
      The output should include "2 erreur"
      The output should include "1 avertissement"
    End
  End

  Describe "_ui_get_perms()"
    It "returns permissions for a file"
      local tmpfile=$(mktemp)
      chmod 644 "$tmpfile"
      When call _ui_get_perms "$tmpfile"
      The output should equal "644"
      rm -f "$tmpfile"
    End
  End

  Describe "_ui_truncate()"
    It "does not truncate short strings"
      When call _ui_truncate "short" 20
      The output should equal "short"
    End

    It "truncates long strings with ellipsis"
      When call _ui_truncate "this is a very long string" 10
      The output should equal "this is..."
    End
  End

  Describe "_zsh_header() alias"
    It "delegates to _ui_header"
      When call _zsh_header "Alias Test"
      The output should include "Alias Test"
    End
  End

  Describe "_zsh_section() alias"
    It "delegates to _ui_section"
      When call _zsh_section "Key" "Val"
      The output should include "Key"
      The output should include "Val"
    End
  End
End
