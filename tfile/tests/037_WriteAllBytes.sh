#!/bin/bash
# 037_write_all_bytes.sh - Test TFile.WriteAllBytes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "037"

# Test 1: Write bytes to new file
test_start "Write bytes to new file"
bytes="Hello World"
result=$(tfile.writeAllBytes "$TEST_TMP_DIR/writebytes.tmp" "$bytes")
if [[ -f "$TEST_TMP_DIR/writebytes.tmp" && "$(cat "$TEST_TMP_DIR"/writebytes.tmp)" == "$bytes" ]]; then
    test_pass "Write bytes to new file"
else
    test_fail "Write bytes to new file"
fi

# Test 2: Write bytes to existing file (overwrites)
test_start "Write bytes to existing file"
echo "old" > "$TEST_TMP_DIR/overwrite_bytes.tmp"
result=$(tfile.writeAllBytes "$TEST_TMP_DIR/overwrite_bytes.tmp" "new")
if [[ "$(cat "$TEST_TMP_DIR"/overwrite_bytes.tmp)" == "new" ]]; then
    test_pass "Write bytes to existing file"
else
    test_fail "Write bytes to existing file"
fi

# Test 3: Write empty bytes
test_start "Write empty bytes"
result=$(tfile.writeAllBytes "$TEST_TMP_DIR/empty_bytes.tmp" "")
if [[ -f "$TEST_TMP_DIR/empty_bytes.tmp" && ! -s "$TEST_TMP_DIR/empty_bytes.tmp" ]]; then
    test_pass "Write empty bytes"
else
    test_fail "Write empty bytes"
fi

# Test 4: Write to invalid path
test_start "Write bytes to invalid path"
if ! result=$(tfile.writeAllBytes "/invalid/path/file.tmp" "content" 2>&1); then
    test_pass "Write bytes to invalid path (correctly failed)"
else
    test_fail "Write bytes to invalid path (should have failed)"
fi
