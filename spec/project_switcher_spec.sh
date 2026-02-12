# shellcheck shell=zsh

Describe "project_switcher.zsh"
  setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export ZSH_ENV_DIR="$TEST_HOME/.zsh_env"
    mkdir -p "$ZSH_ENV_DIR"
    PROJ_REGISTRY_FILE="$TEST_HOME/.config/zsh_env/projects.yml"
    mkdir -p "$(dirname "$PROJ_REGISTRY_FILE")"
    source "$SHELLSPEC_PROJECT_ROOT/functions/project_switcher.zsh"
  }

  cleanup() {
    [ -d "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "_proj_find_config()"
    It "detects .proj file"
      local dir="$TEST_HOME/proj1"
      mkdir -p "$dir"
      touch "$dir/.proj"
      When call _proj_find_config "$dir"
      The output should end with "/.proj"
      The status should equal 0
    End

    It "detects .project.yml file"
      local dir="$TEST_HOME/proj2"
      mkdir -p "$dir"
      touch "$dir/.project.yml"
      When call _proj_find_config "$dir"
      The output should end with "/.project.yml"
      The status should equal 0
    End

    It "detects .project.yaml file"
      local dir="$TEST_HOME/proj3"
      mkdir -p "$dir"
      touch "$dir/.project.yaml"
      When call _proj_find_config "$dir"
      The output should end with "/.project.yaml"
      The status should equal 0
    End

    It "returns 1 if no config file found"
      local dir="$TEST_HOME/proj_empty"
      mkdir -p "$dir"
      When call _proj_find_config "$dir"
      The status should equal 1
    End
  End

  Describe "_proj_get_value()"
    setup_yaml() {
      cat > "$TEST_HOME/test.proj" << 'YAML'
name: my-project
kube_context: my-cluster
node_version: "18"
env_file: '.env.local'
YAML
    }
    Before 'setup_yaml'

    It "parses a simple YAML key"
      When call _proj_get_value "$TEST_HOME/test.proj" "name"
      The output should equal "my-project"
    End

    It "removes double quotes"
      When call _proj_get_value "$TEST_HOME/test.proj" "node_version"
      The output should equal "18"
    End

    It "removes single quotes"
      When call _proj_get_value "$TEST_HOME/test.proj" "env_file"
      The output should equal ".env.local"
    End
  End

  Describe "_proj_load_by_path()"
    It "skips post_cmd in non-interactive mode"
      local dir="$TEST_HOME/proj_postcmd"
      mkdir -p "$dir"
      cat > "$dir/.proj" << 'EOF'
name: test
post_cmd: echo "should not run"
EOF
      When call _proj_load_by_path "$dir"
      The output should include "Projet:"
      The stderr should include "non-interactif"
    End
  End

  Describe "proj_init()"
    It "fails if .proj already exists"
      mkdir -p "$TEST_HOME/proj_exists"
      touch "$TEST_HOME/proj_exists/.proj"
      cd "$TEST_HOME/proj_exists"
      When call proj_init
      The output should include "existe deja"
      The status should equal 1
    End
  End
End
