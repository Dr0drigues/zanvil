# shellcheck shell=zsh

Describe "GitLab scripts"
  Describe "trigger-jobs.sh"
    It "--help displays help and exits 0"
      When run script "$SHELLSPEC_PROJECT_ROOT/scripts/trigger-jobs.sh" --help
      The output should include "USAGE"
      The status should equal 0
    End

    It "fails without GITLAB_TOKEN (exit 1)"
      unset GITLAB_TOKEN
      When run script "$SHELLSPEC_PROJECT_ROOT/scripts/trigger-jobs.sh" -j "deploy" -p "group/project"
      # log_error writes to stdout (echo -e)
      The output should include "GITLAB_TOKEN"
      The status should equal 1
    End

    It "fails without -j argument (exit 1)"
      export GITLAB_TOKEN="fake-token"
      When run script "$SHELLSPEC_PROJECT_ROOT/scripts/trigger-jobs.sh" -p "group/project"
      The output should include "job"
      The status should equal 1
    End

    It "fails without target (-p/-P/-g) (exit 1)"
      export GITLAB_TOKEN="fake-token"
      When run script "$SHELLSPEC_PROJECT_ROOT/scripts/trigger-jobs.sh" -j "deploy"
      The output should include "cible"
      The status should equal 1
    End
  End

  Describe "clone-projects.sh"
    It "--help displays help and exits 0"
      When run script "$SHELLSPEC_PROJECT_ROOT/scripts/clone-projects.sh" --help
      The output should include "USAGE"
      The status should equal 0
    End

    It "fails with less than 2 arguments (exit 1)"
      When run script "$SHELLSPEC_PROJECT_ROOT/scripts/clone-projects.sh" "12345"
      The output should include "Erreur"
      The status should equal 1
    End
  End
End
