#!/bin/bash
# 033_set_last_access_time.sh - Test TFile.SetLastAccessTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "033"


# Test 1: Set last access time on existing file
test_start "Set last access time on existing file"
echo "content" > "$TEST_TMP_DIR/setaccess.tmp"
now=$(date +%s)
result=$(tfile.setLastAccessTime "$TEST_TMP_DIR/setaccess.tmp" "$now")
if [[ $? -eq 0 ]]; then
test_pass "Set last access time on existing file"
else
test_fail "Set last access time on existing file"
fi

# Test 2: Set last access time on non-existing file
test_start "Set last access time on non-existing file"
if ! result=$(tfile.setLastAccessTime "$TEST_TMP_DIR/nonexist.tmp" "$now" 2>&1); then
test_pass "Set last access time on non-existing file (correctly failed)"
else
test_fail "Set last access time on non-existing file (should have failed)"
fi
