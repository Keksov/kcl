#!/bin/bash
# 027_read_all_lines.sh - Test TFile.ReadAllLines method
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
_KT_TMPDIR=$(kt_fixture_tmpdir)


# Test 1: Read lines from existing file
kt_test_start "Read lines from existing file"
echo -e "line1\nline2\nline3" > $_KT_TMPDIR/readlines.tmp
lines=$(tfile.readAllLines "$_KT_TMPDIR/readlines.tmp")
if [[ $(echo "$lines" | wc -l) -eq 3 ]]; then
    kt_test_pass "Read lines from existing file"
else
    kt_test_fail "Read lines from existing file"
fi

# Test 2: Read lines with encoding
kt_test_start "Read lines with encoding"
lines=$(tfile.readAllLines "$_KT_TMPDIR/readlines.tmp" "TEncoding.UTF8")
if [[ $(echo "$lines" | wc -l) -eq 3 ]]; then
    kt_test_pass "Read lines with encoding"
else
    kt_test_fail "Read lines with encoding"
fi

# Test 3: Read lines from empty file
kt_test_start "Read lines from empty file"
touch "$_KT_TMPDIR/empty_lines.tmp"
lines=$(tfile.readAllLines "$_KT_TMPDIR/empty_lines.tmp")
if [[ -z "$lines" ]]; then
    kt_test_pass "Read lines from empty file"
else
    kt_test_fail "Read lines from empty file"
fi

# Test 4: Read lines from non-existing file
kt_test_start "Read lines from non-existing file"
if ! lines=$(tfile.readAllLines "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Read lines from non-existing file (correctly failed)"
else
    kt_test_fail "Read lines from non-existing file (should have failed)"
fi
