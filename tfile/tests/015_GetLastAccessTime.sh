#!/bin/bash
# 015_get_last_access_time.sh - Test TFile.GetLastAccessTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "015"


# Test 1: Get last access time of existing file
test_start "Get last access time of existing file"
echo "content" > "$TEST_TMP_DIR/access.tmp"
result=$(tfile.getLastAccessTime "$TEST_TMP_DIR/access.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get last access time of existing file"
else
    test_fail "Get last access time of existing file"
fi

# Test 2: Get last access time of non-existing file
test_start "Get last access time of non-existing file"
if ! result=$(tfile.getLastAccessTime "$TEST_TMP_DIR/nonexist.tmp" 2>&1); then
    test_pass "Get last access time of non-existing file (correctly failed)"
else
    test_fail "Get last access time of non-existing file (should have failed)"
fi
