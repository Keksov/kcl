#!/bin/bash
# 009_encrypt.sh - Test TFile.Encrypt method
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test

# Test 1: Encrypt file
kt_test_start "Encrypt file"
echo "content" > "$_KT_TMPDIR/encrypt.tmp"
result=$(tfile.encrypt "$_KT_TMPDIR/encrypt.tmp")
if [[ $? -eq 0 ]]; then
    kt_test_pass "Encrypt file"
else
    kt_test_fail "Encrypt file"
fi

# Test 2: Encrypt already encrypted file
kt_test_start "Encrypt already encrypted file"
result=$(tfile.encrypt "$_KT_TMPDIR/encrypt.tmp")
if [[ $? -eq 0 ]]; then
    kt_test_pass "Encrypt already encrypted file"
else
    kt_test_fail "Encrypt already encrypted file"
fi

# Test 3: Encrypt non-existing file
kt_test_start "Encrypt non-existing file"
if ! result=$(tfile.encrypt "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Encrypt non-existing file (correctly failed)"
else
    kt_test_fail "Encrypt non-existing file (should have failed)"
fi
