#!/bin/bash
# 027_read_all_lines.sh - Test TFile.ReadAllLines method
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
KK_TEST_TMPDIR=$(kk_fixture_tmpdir)


# Test 1: Read lines from existing file
kk_test_start "Read lines from existing file"
echo -e "line1\nline2\nline3" > $KK_TEST_TMPDIR/readlines.tmp
lines=$(tfile.readAllLines "$KK_TEST_TMPDIR/readlines.tmp")
if [[ $(echo "$lines" | wc -l) -eq 3 ]]; then
    kk_test_pass "Read lines from existing file"
else
    kk_test_fail "Read lines from existing file"
fi

# Test 2: Read lines with encoding
kk_test_start "Read lines with encoding"
lines=$(tfile.readAllLines "$KK_TEST_TMPDIR/readlines.tmp" "TEncoding.UTF8")
if [[ $(echo "$lines" | wc -l) -eq 3 ]]; then
    kk_test_pass "Read lines with encoding"
else
    kk_test_fail "Read lines with encoding"
fi

# Test 3: Read lines from empty file
kk_test_start "Read lines from empty file"
touch "$KK_TEST_TMPDIR/empty_lines.tmp"
lines=$(tfile.readAllLines "$KK_TEST_TMPDIR/empty_lines.tmp")
if [[ -z "$lines" ]]; then
    kk_test_pass "Read lines from empty file"
else
    kk_test_fail "Read lines from empty file"
fi

# Test 4: Read lines from non-existing file
kk_test_start "Read lines from non-existing file"
if ! lines=$(tfile.readAllLines "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Read lines from non-existing file (correctly failed)"
else
    kk_test_fail "Read lines from non-existing file (should have failed)"
fi
