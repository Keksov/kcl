#!/bin/bash
# 017_get_last_write_time.sh - Test TFile.GetLastWriteTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "017"


# Test 1: Get last write time of existing file
test_start "Get last write time of existing file"
echo "content" > "$TEST_TMP_DIR/write.tmp"
result=$(tfile.getLastWriteTime "$TEST_TMP_DIR/write.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get last write time of existing file"
else
    test_fail "Get last write time of existing file"
fi

# Test 2: Get last write time of non-existing file
test_start "Get last write time of non-existing file"
if ! result=$(tfile.getLastWriteTime "$TEST_TMP_DIR/nonexist.tmp" 2>&1); then
    test_pass "Get last write time of non-existing file (correctly failed)"
else
    test_fail "Get last write time of non-existing file (should have failed)"
fi
