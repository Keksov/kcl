#!/bin/bash
# 009_encrypt.sh - Test TFile.Encrypt method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Encrypt file
test_start "Encrypt file"
echo "content" > test_encrypt.tmp
result=$(tfile.encrypt "test_encrypt.tmp")
if [[ $? -eq 0 ]]; then
    test_pass "Encrypt file"
else
    test_fail "Encrypt file"
fi

# Test 2: Encrypt already encrypted file
test_start "Encrypt already encrypted file"
result=$(tfile.encrypt "test_encrypt.tmp")
if [[ $? -eq 0 ]]; then
    test_pass "Encrypt already encrypted file"
else
    test_fail "Encrypt already encrypted file"
fi

# Test 3: Encrypt non-existing file
test_start "Encrypt non-existing file"
if ! result=$(tfile.encrypt "nonexist.tmp" 2>&1); then
    test_pass "Encrypt non-existing file (correctly failed)"
else
    test_fail "Encrypt non-existing file (should have failed)"
fi
