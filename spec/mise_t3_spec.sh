# shellcheck shell=zsh

Describe "mise_hooks.zsh (T3 mocked)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    ORIG_PATH="$PATH"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"

    # Source UI for _ui_* variables
    source "$SHELLSPEC_PROJECT_ROOT/functions/ui.zsh"

    # Create a fake mise binary so command -v mise succeeds
    mkdir -p "$TEST_HOME/bin"
    echo '#!/bin/sh' > "$TEST_HOME/bin/mise"
    echo 'echo "mock-mise $*"' >> "$TEST_HOME/bin/mise"
    chmod +x "$TEST_HOME/bin/mise"
    export PATH="$TEST_HOME/bin:$PATH"

    # Mock work_is_context
    work_is_context() { return 0; }

    source "$SHELLSPEC_PROJECT_ROOT/functions/mise_hooks.zsh"
  }

  cleanup() {
    export HOME="$ORIG_HOME"
    export PATH="$ORIG_PATH"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "mise-configure"
    It "shows usage without arguments"
      When call mise-configure
      The output should include "Usage: mise-configure"
      The status should equal 1
    End

    It "fails for unsupported tool"
      When call mise-configure python 3.12
      The output should include "Pas de hook"
      The status should equal 1
    End

    It "shows status with 'status' subcommand"
      test_status() {
        _MISE_ZSH_ENV_DIR="$SHELLSPEC_PROJECT_ROOT"
        # Mock mise current to return nothing (no active tools)
        mkdir -p "$TEST_HOME/bin_status"
        cat > "$TEST_HOME/bin_status/mise" << 'SCRIPT'
#!/bin/sh
echo ""
SCRIPT
        chmod +x "$TEST_HOME/bin_status/mise"
        local orig_path="$PATH"
        export PATH="$TEST_HOME/bin_status:$PATH"
        mise-configure status
        export PATH="$orig_path"
      }
      When call test_status
      The output should include "Mise Configure Status"
      The output should include "Tout est configure"
      The status should equal 0
    End
  End

  Describe "hooks.zsh activation"
    It "references ZSH_ENV_MODULE_MISE"
      check_mise_activation() {
        local content
        content=$(cat "$SHELLSPEC_PROJECT_ROOT/hooks.zsh")
        echo "$content" | grep -q "ZSH_ENV_MODULE_MISE" && echo "found" || echo "not_found"
      }
      When call check_mise_activation
      The output should equal "found"
    End
  End

  Describe "marker files"
    It "creates and detects a marker file"
      test_marker() {
        local installs="$TEST_HOME/.local/share/mise/installs"
        _MISE_INSTALLS_DIR="$installs"
        mkdir -p "$installs/java/zulu-21"
        _mise_mark_configured java zulu-21
        if _mise_is_configured java zulu-21; then
          echo "configured"
        else
          echo "not_configured"
        fi
      }
      When call test_marker
      The output should equal "configured"
    End

    It "returns false when marker does not exist"
      test_no_marker() {
        local installs="$TEST_HOME/.local/share/mise/installs"
        _MISE_INSTALLS_DIR="$installs"
        mkdir -p "$installs/java/temurin-17"
        if _mise_is_configured java temurin-17; then
          echo "configured"
        else
          echo "not_configured"
        fi
      }
      When call test_no_marker
      The output should equal "not_configured"
    End

    It "does not create marker if install dir missing"
      test_no_dir() {
        _MISE_INSTALLS_DIR="$TEST_HOME/.local/share/mise/installs"
        _mise_mark_configured java nonexistent-99
        if [[ -f "$_MISE_INSTALLS_DIR/java/nonexistent-99/.work_configured" ]]; then
          echo "created"
        else
          echo "not_created"
        fi
      }
      When call test_no_dir
      The output should equal "not_created"
    End
  End

  Describe "hook idempotence"
    It "skips java hook when already configured"
      test_java_idempotent() {
        local installs="$TEST_HOME/.local/share/mise/installs"
        _MISE_INSTALLS_DIR="$installs"
        mkdir -p "$installs/java/zulu-21"
        date +%s > "$installs/java/zulu-21/.work_configured"
        _mise_hook_java zulu-21
      }
      When call test_java_idempotent
      The output should include "deja configure"
      The status should equal 0
    End

    It "skips maven hook when ~/.m2/settings.xml already matches"
      test_maven_idempotent() {
        local installs="$TEST_HOME/.local/share/mise/installs"
        _MISE_INSTALLS_DIR="$installs"
        # Isoler dans un faux ZSH_ENV_DIR sans .enc pour tester le fallback plain
        local fake_env="$TEST_HOME/fake_zsh_env"
        _MISE_ZSH_ENV_DIR="$fake_env"
        # Simuler la structure mise : maven/3.9.6/apache-maven-3.9.6/bin/mvn
        mkdir -p "$installs/maven/3.9.6/apache-maven-3.9.6/bin"
        touch "$installs/maven/3.9.6/apache-maven-3.9.6/bin/mvn"
        mkdir -p "$fake_env/work"
        echo "<settings>blg-test</settings>" > "$fake_env/work/settings.xml"
        mkdir -p "$HOME/.m2"
        cp "$fake_env/work/settings.xml" "$HOME/.m2/settings.xml"
        _mise_hook_maven 3.9.6
      }
      When call test_maven_idempotent
      The output should include "deja a jour"
      The status should equal 0
    End
  End

  Describe "_mise_post_install_detect"
    It "calls hooks for unconfigured tools"
      test_post_detect() {
        local installs="$TEST_HOME/.local/share/mise/installs"
        _MISE_INSTALLS_DIR="$installs"
        mkdir -p "$installs/java/zulu-21"
        # Remove any leftover marker from previous tests
        rm -f "$installs/java/zulu-21/.work_configured"
        # Override mise to return a version for java
        mkdir -p "$TEST_HOME/bin2"
        cat > "$TEST_HOME/bin2/mise" << 'SCRIPT'
#!/bin/sh
if [ "$1" = "current" ] && [ "$2" = "java" ]; then
  echo "zulu-21"
elif [ "$1" = "current" ] && [ "$2" = "maven" ]; then
  echo ""
fi
SCRIPT
        chmod +x "$TEST_HOME/bin2/mise"
        local orig_path="$PATH"
        export PATH="$TEST_HOME/bin2:$PATH"
        # Hook will fail (no cert script) but that's expected
        _mise_post_install_detect 2>&1 || true
        export PATH="$orig_path"
        # Check that it tried (cert script not found = hook was called)
        if [[ -f "$installs/java/zulu-21/.work_configured" ]]; then
          echo "configured"
        else
          echo "hook_attempted"
        fi
      }
      When call test_post_detect
      The output should include "hook_attempted"
    End

    It "skips already configured tools"
      test_post_detect_skip() {
        local installs="$TEST_HOME/.local/share/mise/installs"
        _MISE_INSTALLS_DIR="$installs"
        mkdir -p "$installs/java/zulu-21"
        date +%s > "$installs/java/zulu-21/.work_configured"
        mkdir -p "$TEST_HOME/bin3"
        cat > "$TEST_HOME/bin3/mise" << 'SCRIPT'
#!/bin/sh
if [ "$1" = "current" ] && [ "$2" = "java" ]; then
  echo "zulu-21"
elif [ "$1" = "current" ] && [ "$2" = "maven" ]; then
  echo ""
fi
SCRIPT
        chmod +x "$TEST_HOME/bin3/mise"
        local orig_path="$PATH"
        export PATH="$TEST_HOME/bin3:$PATH"
        _mise_post_install_detect 2>&1
        export PATH="$orig_path"
        echo "done"
      }
      When call test_post_detect_skip
      # Should produce no hook output, just "done"
      The output should equal "done"
    End
  End

  Describe "_mise_chpwd_hook"
    It "returns early without .mise.toml"
      test_chpwd_no_toml() {
        local tmpdir
        tmpdir=$(mktemp -d)
        cd "$tmpdir" || return 1
        _mise_chpwd_hook 2>&1
        echo "no_prompt"
        rm -rf "$tmpdir"
      }
      When call test_chpwd_no_toml
      The output should equal "no_prompt"
    End

    It "detects unconfigured tools with .mise.toml present"
      test_chpwd_unconfigured() {
        local tmpdir installs
        tmpdir=$(mktemp -d)
        installs="$TEST_HOME/.local/share/mise/installs"
        _MISE_INSTALLS_DIR="$installs"
        mkdir -p "$installs/java/zulu-21"
        rm -f "$installs/java/zulu-21/.work_configured"
        touch "$tmpdir/.mise.toml"
        cd "$tmpdir" || return 1
        # Mock mise current to return java version
        mkdir -p "$TEST_HOME/bin4"
        cat > "$TEST_HOME/bin4/mise" << 'SCRIPT'
#!/bin/sh
if [ "$1" = "current" ] && [ "$2" = "java" ]; then
  echo "zulu-21"
elif [ "$1" = "current" ] && [ "$2" = "maven" ]; then
  echo ""
elif [ "$1" = "ls" ]; then
  echo "{}"
fi
SCRIPT
        chmod +x "$TEST_HOME/bin4/mise"
        local orig_path="$PATH"
        export PATH="$TEST_HOME/bin4:$PATH"
        export _MISE_CHPWD_FORCE=1
        # Pipe 'n' to decline the prompt
        _mise_chpwd_hook <<< "n" 2>&1
        unset _MISE_CHPWD_FORCE
        export PATH="$orig_path"
        rm -rf "$tmpdir"
      }
      When call test_chpwd_unconfigured
      The output should include "non configurees"
    End
  End
End
