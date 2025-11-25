#!/bin/bash
# 007_decrypt.sh - Test TFile.Decrypt method
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test

# Test 1: Decrypt encrypted file
kk_test_start "Decrypt encrypted file"
echo "content" > "$KK_TEST_TMPDIR/encrypt.tmp"
tfile.encrypt "$KK_TEST_TMPDIR/encrypt.tmp"  # Assume this works
result=$(tfile.decrypt "$KK_TEST_TMPDIR/encrypt.tmp")
if [[ $? -eq 0 ]]; then
    kk_test_pass "Decrypt encrypted file"
else
    kk_test_fail "Decrypt encrypted file"
fi

# Test 2: Decrypt non-encrypted file
kk_test_start "Decrypt non-encrypted file"
echo "plain" > "$KK_TEST_TMPDIR/plain.tmp"
result=$(tfile.decrypt "$KK_TEST_TMPDIR/plain.tmp")
if [[ $? -ne 0 ]]; then
kk_test_pass "Decrypt non-encrypted file"
else
kk_test_fail "Decrypt non-encrypted file"
fi

# Test 3: Decrypt non-existing file
kk_test_start "Decrypt non-existing file"
if ! result=$(tfile.decrypt "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Decrypt non-existing file (correctly failed)"
else
    kk_test_fail "Decrypt non-existing file (should have failed)"
fi
