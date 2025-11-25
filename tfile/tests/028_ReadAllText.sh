#!/bin/bash
# 028_read_all_text.sh - Test TFile.ReadAllText method
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


# Test 1: Read text from existing file
kk_test_start "Read text from existing file"
echo "text content" > $KK_TEST_TMPDIR/readtext.tmp
text=$(tfile.readAllText "$KK_TEST_TMPDIR/readtext.tmp")
if [[ "$text" == "text content" ]]; then
    kk_test_pass "Read text from existing file"
else
    kk_test_fail "Read text from existing file (got: $text)"
fi

# Test 2: Read text with encoding
kk_test_start "Read text with encoding"
text=$(tfile.readAllText "$KK_TEST_TMPDIR/readtext.tmp" "TEncoding.UTF8")
if [[ "$text" == "text content" ]]; then
    kk_test_pass "Read text with encoding"
else
    kk_test_fail "Read text with encoding"
fi

# Test 3: Read text from empty file
kk_test_start "Read text from empty file"
touch "$KK_TEST_TMPDIR/empty_text.tmp"
text=$(tfile.readAllText "$KK_TEST_TMPDIR/empty_text.tmp")
if [[ -z "$text" ]]; then
    kk_test_pass "Read text from empty file"
else
    kk_test_fail "Read text from empty file"
fi

# Test 4: Read text from non-existing file
kk_test_start "Read text from non-existing file"
if ! text=$(tfile.readAllText "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Read text from non-existing file (correctly failed)"
else
    kk_test_fail "Read text from non-existing file (should have failed)"
fi
