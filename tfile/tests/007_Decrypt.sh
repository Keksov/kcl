#!/bin/bash
# 007_decrypt.sh - Test TFile.Decrypt method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Decrypt encrypted file
test_start "Decrypt encrypted file"
echo "content" > test_encrypt.tmp
tfile.encrypt "test_encrypt.tmp"  # Assume this works
result=$(tfile.decrypt "test_encrypt.tmp")
if [[ $? -eq 0 ]]; then
    test_pass "Decrypt encrypted file"
else
    test_fail "Decrypt encrypted file"
fi

# Test 2: Decrypt non-encrypted file
test_start "Decrypt non-encrypted file"
echo "plain" > test_plain.tmp
result=$(tfile.decrypt "test_plain.tmp")
if [[ $? -eq 0 ]]; then
    test_pass "Decrypt non-encrypted file"
else
    test_fail "Decrypt non-encrypted file"
fi

# Test 3: Decrypt non-existing file
test_start "Decrypt non-existing file"
if ! result=$(tfile.decrypt "nonexist.tmp" 2>&1); then
    test_pass "Decrypt non-existing file (correctly failed)"
else
    test_fail "Decrypt non-existing file (should have failed)"
fi
