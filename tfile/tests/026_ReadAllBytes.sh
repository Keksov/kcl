#!/bin/bash
# 026_read_all_bytes.sh - Test TFile.ReadAllBytes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "026"

# Test 1: Read bytes from existing file
test_start "Read bytes from existing file"
echo "content" > "$TEST_TMP_DIR/readbytes.tmp"
bytes=$(tfile.readAllBytes "$TEST_TMP_DIR/readbytes.tmp")
if [[ -n "$bytes" ]]; then
    test_pass "Read bytes from existing file"
else
    test_fail "Read bytes from existing file"
fi

# Test 2: Read bytes from empty file
test_start "Read bytes from empty file"
touch "$TEST_TMP_DIR/empty_bytes.tmp"
bytes=$(tfile.readAllBytes "$TEST_TMP_DIR/empty_bytes.tmp")
if [[ ${#bytes} -eq 0 ]]; then
    test_pass "Read bytes from empty file"
else
    test_fail "Read bytes from empty file"
fi

# Test 3: Read bytes from non-existing file
test_start "Read bytes from non-existing file"
if ! bytes=$(tfile.readAllBytes "$TEST_TMP_DIR/nonexist.tmp" 2>&1); then
    test_pass "Read bytes from non-existing file (correctly failed)"
else
    test_fail "Read bytes from non-existing file (should have failed)"
fi
