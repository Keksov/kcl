#!/bin/bash
# 036_set_last_write_time_utc.sh - Test TFile.SetLastWriteTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "036"


# Test 1: Set last write time UTC on existing file
test_start "Set last write time UTC on existing file"
echo "content" > "$TEST_TMP_DIR/setwrite_utc.tmp"
now=$(date +%s)
result=$(tfile.setLastWriteTimeUtc "$TEST_TMP_DIR/setwrite_utc.tmp" "$now")
if [[ $? -eq 0 ]]; then
test_pass "Set last write time UTC on existing file"
else
test_fail "Set last write time UTC on existing file"
fi

# Test 2: Set last write time UTC on non-existing file
test_start "Set last write time UTC on non-existing file"
if ! result=$(tfile.setLastWriteTimeUtc "$TEST_TMP_DIR/nonexist.tmp" "$now" 2>&1); then
test_pass "Set last write time UTC on non-existing file (correctly failed)"
else
test_fail "Set last write time UTC on non-existing file (should have failed)"
fi
