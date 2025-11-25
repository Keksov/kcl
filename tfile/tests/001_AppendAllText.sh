#!/bin/bash
# 001_append_all_text.sh - Test TFile.AppendAllText method
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

# Test 1: Append to existing file
kk_test_start "Append to existing file"
printf "initial content" > "$KK_TEST_TMPDIR/append.tmp"
result=$(tfile.appendAllText "$KK_TEST_TMPDIR/append.tmp" " appended text")
if [[ -f "$KK_TEST_TMPDIR/append.tmp" && "$(cat "$KK_TEST_TMPDIR"/append.tmp)" == "initial content appended text" ]]; then
    kk_test_pass "Append to existing file"
else
    kk_test_fail "Append to existing file (file content: $(cat "$KK_TEST_TMPDIR"/append.tmp))"
fi

# Test 2: Append to non-existing file (creates file)
kk_test_start "Append to non-existing file"
rm -f "$KK_TEST_TMPDIR/nonexist.tmp"
result=$(tfile.appendAllText "$KK_TEST_TMPDIR/nonexist.tmp" "new content")
if [[ -f "$KK_TEST_TMPDIR/nonexist.tmp" && "$(cat "$KK_TEST_TMPDIR"/nonexist.tmp)" == "new content" ]]; then
    kk_test_pass "Append to non-existing file"
else
    kk_test_fail "Append to non-existing file"
fi

# Test 3: Append empty string
kk_test_start "Append empty string"
printf "content" > "$KK_TEST_TMPDIR/empty.tmp"
result=$(tfile.appendAllText "$KK_TEST_TMPDIR/empty.tmp" "")
if [[ "$(cat "$KK_TEST_TMPDIR"/empty.tmp)" == "content" ]]; then
    kk_test_pass "Append empty string"
else
    kk_test_fail "Append empty string (expected: content, got: $(cat "$KK_TEST_TMPDIR"/empty.tmp))"
fi

# Test 4: Append with encoding parameter (if supported)
kk_test_start "Append with encoding"
printf "ascii" > "$KK_TEST_TMPDIR/encoding.tmp"
result=$(tfile.appendAllText "$KK_TEST_TMPDIR/encoding.tmp" " unicode" "UTF8")
if [[ -f "$KK_TEST_TMPDIR/encoding.tmp" ]]; then
    kk_test_pass "Append with encoding"
else
    kk_test_fail "Append with encoding"
fi

# Test 5: Invalid path
kk_test_start "Append to invalid path"
if ! result=$(tfile.appendAllText "/invalid/path/file.tmp" "content" 2>&1); then
    kk_test_pass "Append to invalid path (correctly failed)"
else
    kk_test_fail "Append to invalid path (should have failed)"
fi

# Test 6: Append large content
kk_test_start "Append large content"
printf "start" > "$KK_TEST_TMPDIR/large.tmp"
large_content=$(printf 'a%.0s' {1..10000})
result=$(tfile.appendAllText "$KK_TEST_TMPDIR/large.tmp" "$large_content")
content=$(cat "$KK_TEST_TMPDIR"/large.tmp)
if [[ "${content:0:5}" == "start" && ${#content} -gt 10000 ]]; then
    kk_test_pass "Append large content"
else
    kk_test_fail "Append large content"
fi
