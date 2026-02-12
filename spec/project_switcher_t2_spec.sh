# shellcheck shell=zsh

Describe "project_switcher.zsh (T2 integration)"
  setup() {
    TEST_HOME=$(mktemp -d)
    ORIG_HOME="$HOME"
    ORIG_PWD="$PWD"
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    export WORK_DIR="$TEST_HOME/work"
    mkdir -p "$ZSH_ENV_DIR" "$WORK_DIR"
    mkdir -p "$TEST_HOME/.config/zsh_env"
    source "$SHELLSPEC_PROJECT_ROOT/functions/project_switcher.zsh"
  }

  cleanup() {
    cd "$ORIG_PWD" 2>/dev/null || cd /
    export HOME="$ORIG_HOME"
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "_proj_load_by_path()"
    It "changes the current directory"
      load_proj() {
        local dir="$TEST_HOME/proj_cd"
        mkdir -p "$dir"
        _proj_load_by_path "$dir"
      }
      When call load_proj
      The output should include "Projet:"
      The status should equal 0
    End
  End

  Describe "proj_add()"
    It "creates the registry file"
      add_new_proj() {
        rm -f "$PROJ_REGISTRY_FILE"
        local dir="$TEST_HOME/newproj"
        mkdir -p "$dir"
        proj_add -n "testproj" -p "$dir" -f
      }
      When call add_new_proj
      The path "$TEST_HOME/.config/zsh_env/projects.yml" should be file
      The output should include "enregistre"
    End

    It "detects duplicate paths"
      add_dup_path() {
        rm -f "$PROJ_REGISTRY_FILE"
        local dir="$TEST_HOME/duppath"
        mkdir -p "$dir"
        proj_add -n "proj1" -p "$dir" -f > /dev/null 2>&1
        proj_add -n "proj2" -p "$dir" -f
      }
      When call add_dup_path
      The output should include "deja enregistre"
    End

    It "detects duplicate names"
      add_dup_name() {
        rm -f "$PROJ_REGISTRY_FILE"
        local dir1="$TEST_HOME/dup1"
        local dir2="$TEST_HOME/dup2"
        mkdir -p "$dir1" "$dir2"
        proj_add -n "samename" -p "$dir1" -f > /dev/null 2>&1
        proj_add -n "samename" -p "$dir2" -f
      }
      When call add_dup_name
      The output should include "existe deja"
      The status should equal 0
    End
  End

  Describe "proj_list()"
    It "displays registered projects"
      list_projects() {
        rm -f "$PROJ_REGISTRY_FILE"
        local dir="$TEST_HOME/listproj"
        mkdir -p "$dir"
        proj_add -n "listed" -p "$dir" -f > /dev/null 2>&1
        proj_list
      }
      When call list_projects
      The output should include "listed"
    End

    It "marks missing directories"
      list_missing() {
        rm -f "$PROJ_REGISTRY_FILE"
        echo 'gone: "/tmp/nonexistent_proj_test_abc"' >> "$PROJ_REGISTRY_FILE"
        proj_list
      }
      When call list_missing
      The output should include "manquant"
    End
  End

  Describe "proj_remove()"
    It "removes entry from registry"
      remove_proj() {
        rm -f "$PROJ_REGISTRY_FILE"
        local dir="$TEST_HOME/removeproj"
        mkdir -p "$dir"
        proj_add -n "toremove" -p "$dir" -f > /dev/null 2>&1
        proj_remove "toremove"
      }
      When call remove_proj
      The output should include "supprime"
    End

    It "fails for nonexistent project"
      remove_nonexistent() {
        rm -f "$PROJ_REGISTRY_FILE"
        # Create a registry with at least one entry so we don't get "Aucun projet"
        local dir="$TEST_HOME/someproj"
        mkdir -p "$dir"
        proj_add -n "someproj" -p "$dir" -f > /dev/null 2>&1
        proj_remove "nonexistent_project_xyz"
      }
      When call remove_nonexistent
      The stderr should include "non trouve"
      The status should equal 1
    End
  End

  Describe "proj_init()"
    It "creates a .proj template file"
      init_proj() {
        local dir="$TEST_HOME/initproj"
        mkdir -p "$dir"
        cd "$dir"
        proj_init
      }
      When call init_proj
      The output should include "cree"
    End
  End

  Describe "proj_scan()"
    It "detects .git directories"
      scan_git() {
        local scandir="$TEST_HOME/scan"
        mkdir -p "$scandir/project-a/.git"
        mkdir -p "$scandir/project-b/.git"
        rm -f "$PROJ_REGISTRY_FILE"
        # Mock fzf and disable interactive prompts
        fzf() { cat > /dev/null; return 1; }
        proj_scan "$scandir" 2 < /dev/null
        unfunction fzf 2>/dev/null
      }
      When call scan_git
      The output should include "project-a"
      The output should include "project-b"
    End

    It "detects package.json, Cargo.toml, go.mod"
      scan_markers() {
        local scandir="$TEST_HOME/scan2"
        mkdir -p "$scandir/node-proj"
        echo '{}' > "$scandir/node-proj/package.json"
        mkdir -p "$scandir/rust-proj"
        echo '[package]' > "$scandir/rust-proj/Cargo.toml"
        mkdir -p "$scandir/go-proj"
        echo 'module test' > "$scandir/go-proj/go.mod"
        rm -f "$PROJ_REGISTRY_FILE"
        fzf() { cat > /dev/null; return 1; }
        proj_scan "$scandir" 2 < /dev/null
        unfunction fzf 2>/dev/null
      }
      When call scan_markers
      The output should include "node"
      The output should include "rust"
      The output should include "go"
    End

    It "respects depth limit"
      scan_depth() {
        local scandir="$TEST_HOME/scan3"
        mkdir -p "$scandir/level1/level2/level3/.git"
        rm -f "$PROJ_REGISTRY_FILE"
        fzf() { cat > /dev/null; return 1; }
        proj_scan "$scandir" 1 < /dev/null
        unfunction fzf 2>/dev/null
      }
      When call scan_depth
      The output should not include "level3"
    End
  End

  Describe "_proj_load_by_path() env file"
    It "loads env file owned by current user"
      load_env() {
        local dir="$TEST_HOME/envproj"
        mkdir -p "$dir"
        cat > "$dir/.proj" << 'PROJEOF'
name: envtest
env_file: .env.test
PROJEOF
        echo "TEST_VAR=hello" > "$dir/.env.test"
        _proj_load_by_path "$dir"
      }
      When call load_env
      The output should include "Projet:"
    End

    It "refuses env file with wrong owner"
      load_env_bad_owner() {
        local dir="$TEST_HOME/envproj_bad"
        mkdir -p "$dir"
        cat > "$dir/.proj" << 'PROJEOF'
name: badowner
env_file: .env.secret
PROJEOF
        echo "SECRET=nope" > "$dir/.env.secret"
        # Override stat to return a different UID
        stat() { echo "99999"; }
        _proj_load_by_path "$dir"
        unfunction stat 2>/dev/null
      }
      When call load_env_bad_owner
      The output should include "Projet:"
      The stderr should include "proprietaire different"
    End
  End
End
