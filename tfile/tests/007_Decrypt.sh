#!/bin/bash
# 007_decrypt.sh - Test TFile.Decrypt method
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

# Test 1: Decrypt encrypted file
kt_test_start "Decrypt encrypted file"
echo "content" > "$_KT_TMPDIR/encrypt.tmp"
tfile.encrypt "$_KT_TMPDIR/encrypt.tmp"  # Assume this works
result=$(tfile.decrypt "$_KT_TMPDIR/encrypt.tmp")
if [[ $? -eq 0 ]]; then
    kt_test_pass "Decrypt encrypted file"
else
    kt_test_fail "Decrypt encrypted file"
fi

# Test 2: Decrypt non-encrypted file
kt_test_start "Decrypt non-encrypted file"
echo "plain" > "$_KT_TMPDIR/plain.tmp"
result=$(tfile.decrypt "$_KT_TMPDIR/plain.tmp")
if [[ $? -ne 0 ]]; then
kt_test_pass "Decrypt non-encrypted file"
else
kt_test_fail "Decrypt non-encrypted file"
fi

# Test 3: Decrypt non-existing file
kt_test_start "Decrypt non-existing file"
if ! result=$(tfile.decrypt "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Decrypt non-existing file (correctly failed)"
else
    kt_test_fail "Decrypt non-existing file (should have failed)"
fi
