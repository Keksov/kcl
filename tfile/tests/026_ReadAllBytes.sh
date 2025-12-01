#!/bin/bash
# 026_read_all_bytes.sh - Test TFile.ReadAllBytes method
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

# Test 1: Read bytes from existing file
kt_test_start "Read bytes from existing file"
echo "content" > "$_KT_TMPDIR/readbytes.tmp"
bytes=$(tfile.readAllBytes "$_KT_TMPDIR/readbytes.tmp")
if [[ -n "$bytes" ]]; then
    kt_test_pass "Read bytes from existing file"
else
    kt_test_fail "Read bytes from existing file"
fi

# Test 2: Read bytes from empty file
kt_test_start "Read bytes from empty file"
touch "$_KT_TMPDIR/empty_bytes.tmp"
bytes=$(tfile.readAllBytes "$_KT_TMPDIR/empty_bytes.tmp")
if [[ ${#bytes} -eq 0 ]]; then
    kt_test_pass "Read bytes from empty file"
else
    kt_test_fail "Read bytes from empty file"
fi

# Test 3: Read bytes from non-existing file
kt_test_start "Read bytes from non-existing file"
if ! bytes=$(tfile.readAllBytes "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Read bytes from non-existing file (correctly failed)"
else
    kt_test_fail "Read bytes from non-existing file (should have failed)"
fi
