#!/bin/bash
# 017_get_last_write_time.sh - Test TFile.GetLastWriteTime method
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


# Test 1: Get last write time of existing file
kk_test_start "Get last write time of existing file"
echo "content" > "$KK_TEST_TMPDIR/write.tmp"
result=$(tfile.getLastWriteTime "$KK_TEST_TMPDIR/write.tmp")
if [[ -n "$result" ]]; then
    kk_test_pass "Get last write time of existing file"
else
    kk_test_fail "Get last write time of existing file"
fi

# Test 2: Get last write time of non-existing file
kk_test_start "Get last write time of non-existing file"
if ! result=$(tfile.getLastWriteTime "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Get last write time of non-existing file (correctly failed)"
else
    kk_test_fail "Get last write time of non-existing file (should have failed)"
fi
