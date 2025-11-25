#!/bin/bash
# 026_read_all_bytes.sh - Test TFile.ReadAllBytes method
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

# Test 1: Read bytes from existing file
kk_test_start "Read bytes from existing file"
echo "content" > "$KK_TEST_TMPDIR/readbytes.tmp"
bytes=$(tfile.readAllBytes "$KK_TEST_TMPDIR/readbytes.tmp")
if [[ -n "$bytes" ]]; then
    kk_test_pass "Read bytes from existing file"
else
    kk_test_fail "Read bytes from existing file"
fi

# Test 2: Read bytes from empty file
kk_test_start "Read bytes from empty file"
touch "$KK_TEST_TMPDIR/empty_bytes.tmp"
bytes=$(tfile.readAllBytes "$KK_TEST_TMPDIR/empty_bytes.tmp")
if [[ ${#bytes} -eq 0 ]]; then
    kk_test_pass "Read bytes from empty file"
else
    kk_test_fail "Read bytes from empty file"
fi

# Test 3: Read bytes from non-existing file
kk_test_start "Read bytes from non-existing file"
if ! bytes=$(tfile.readAllBytes "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Read bytes from non-existing file (correctly failed)"
else
    kk_test_fail "Read bytes from non-existing file (should have failed)"
fi
