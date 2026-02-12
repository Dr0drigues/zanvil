# shellcheck shell=zsh

Describe "extract.zsh (T2 decompression)"
  setup() {
    source "$SHELLSPEC_PROJECT_ROOT/functions/extract.zsh"
    TEST_DIR=$(mktemp -d)
    # Create a test file to compress
    echo "test content for extract" > "$TEST_DIR/testfile.txt"
  }

  cleanup() {
    [ -d "${TEST_DIR:-}" ] && rm -rf "$TEST_DIR"
  }

  BeforeAll 'setup'
  AfterAll 'cleanup'

  Describe "extract decompresses .tar.gz"
    It "extracts tar.gz archive"
      cd "$TEST_DIR"
      tar czf test.tar.gz testfile.txt
      rm -f testfile.txt
      When call extract test.tar.gz
      The path "$TEST_DIR/testfile.txt" should be file
      The status should equal 0
    End
  End

  Describe "extract decompresses .zip"
    It "extracts zip archive"
      if ! command -v zip &>/dev/null; then
        Skip "zip not installed"
      fi
      cd "$TEST_DIR"
      echo "zip content" > zipfile.txt
      zip -q test.zip zipfile.txt
      rm -f zipfile.txt
      When call extract test.zip
      The output should be present
      The path "$TEST_DIR/zipfile.txt" should be file
    End
  End

  Describe "extract decompresses .tar.bz2"
    It "extracts tar.bz2 archive"
      cd "$TEST_DIR"
      echo "bz2 content" > bz2file.txt
      tar cjf test.tar.bz2 bz2file.txt
      rm -f bz2file.txt
      When call extract test.tar.bz2
      The path "$TEST_DIR/bz2file.txt" should be file
    End
  End

  Describe "extract decompresses .tar.xz"
    It "extracts tar.xz archive"
      if ! command -v xz &>/dev/null; then
        Skip "xz not installed"
      fi
      cd "$TEST_DIR"
      echo "xz content" > xzfile.txt
      tar cJf test.tar.xz xzfile.txt
      rm -f xzfile.txt
      When call extract test.tar.xz
      The path "$TEST_DIR/xzfile.txt" should be file
    End
  End

  Describe "extract decompresses .gz"
    It "extracts gz file"
      cd "$TEST_DIR"
      echo "gz content" > gzfile.txt
      gzip gzfile.txt
      When call extract gzfile.txt.gz
      The path "$TEST_DIR/gzfile.txt" should be file
    End
  End
End
