#!/bin/bash
# 037_write_all_bytes.sh - Test TFile.WriteAllBytes method
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test

# Test 1: Write bytes to new file
kk_test_start "Write bytes to new file"
bytes="Hello World"
result=$(tfile.writeAllBytes "$KK_TEST_TMPDIR/writebytes.tmp" "$bytes")
if [[ -f "$KK_TEST_TMPDIR/writebytes.tmp" && "$(cat "$KK_TEST_TMPDIR"/writebytes.tmp)" == "$bytes" ]]; then
    kk_test_pass "Write bytes to new file"
else
    kk_test_fail "Write bytes to new file"
fi

# Test 2: Write bytes to existing file (overwrites)
kk_test_start "Write bytes to existing file"
echo "old" > "$KK_TEST_TMPDIR/overwrite_bytes.tmp"
result=$(tfile.writeAllBytes "$KK_TEST_TMPDIR/overwrite_bytes.tmp" "new")
if [[ "$(cat "$KK_TEST_TMPDIR"/overwrite_bytes.tmp)" == "new" ]]; then
    kk_test_pass "Write bytes to existing file"
else
    kk_test_fail "Write bytes to existing file"
fi

# Test 3: Write empty bytes
kk_test_start "Write empty bytes"
result=$(tfile.writeAllBytes "$KK_TEST_TMPDIR/empty_bytes.tmp" "")
if [[ -f "$KK_TEST_TMPDIR/empty_bytes.tmp" && ! -s "$KK_TEST_TMPDIR/empty_bytes.tmp" ]]; then
    kk_test_pass "Write empty bytes"
else
    kk_test_fail "Write empty bytes"
fi

# Test 4: Write to invalid path
kk_test_start "Write bytes to invalid path"
if ! result=$(tfile.writeAllBytes "/invalid/path/file.tmp" "content" 2>&1); then
    kk_test_pass "Write bytes to invalid path (correctly failed)"
else
    kk_test_fail "Write bytes to invalid path (should have failed)"
fi
