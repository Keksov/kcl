#!/bin/bash
# 007_decrypt.sh - Test TFile.Decrypt method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "007"

# Test 1: Decrypt encrypted file
test_start "Decrypt encrypted file"
echo "content" > "$TEST_TMP_DIR/encrypt.tmp"
tfile.encrypt "$TEST_TMP_DIR/encrypt.tmp"  # Assume this works
result=$(tfile.decrypt "$TEST_TMP_DIR/encrypt.tmp")
if [[ $? -eq 0 ]]; then
    test_pass "Decrypt encrypted file"
else
    test_fail "Decrypt encrypted file"
fi

# Test 2: Decrypt non-encrypted file
test_start "Decrypt non-encrypted file"
echo "plain" > "$TEST_TMP_DIR/plain.tmp"
result=$(tfile.decrypt "$TEST_TMP_DIR/plain.tmp")
if [[ $? -ne 0 ]]; then
test_pass "Decrypt non-encrypted file"
else
test_fail "Decrypt non-encrypted file"
fi

# Test 3: Decrypt non-existing file
test_start "Decrypt non-existing file"
if ! result=$(tfile.decrypt "$TEST_TMP_DIR/nonexist.tmp" 2>&1); then
    test_pass "Decrypt non-existing file (correctly failed)"
else
    test_fail "Decrypt non-existing file (should have failed)"
fi
