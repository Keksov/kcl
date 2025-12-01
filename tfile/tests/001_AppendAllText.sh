#!/bin/bash
# 001_append_all_text.sh - Test TFile.AppendAllText method
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

# Test 1: Append to existing file
kt_test_start "Append to existing file"
printf "initial content" > "$_KT_TMPDIR/append.tmp"
result=$(tfile.appendAllText "$_KT_TMPDIR/append.tmp" " appended text")
if [[ -f "$_KT_TMPDIR/append.tmp" && "$(cat "$_KT_TMPDIR"/append.tmp)" == "initial content appended text" ]]; then
    kt_test_pass "Append to existing file"
else
    kt_test_fail "Append to existing file (file content: $(cat "$_KT_TMPDIR"/append.tmp))"
fi

# Test 2: Append to non-existing file (creates file)
kt_test_start "Append to non-existing file"
rm -f "$_KT_TMPDIR/nonexist.tmp"
result=$(tfile.appendAllText "$_KT_TMPDIR/nonexist.tmp" "new content")
if [[ -f "$_KT_TMPDIR/nonexist.tmp" && "$(cat "$_KT_TMPDIR"/nonexist.tmp)" == "new content" ]]; then
    kt_test_pass "Append to non-existing file"
else
    kt_test_fail "Append to non-existing file"
fi

# Test 3: Append empty string
kt_test_start "Append empty string"
printf "content" > "$_KT_TMPDIR/empty.tmp"
result=$(tfile.appendAllText "$_KT_TMPDIR/empty.tmp" "")
if [[ "$(cat "$_KT_TMPDIR"/empty.tmp)" == "content" ]]; then
    kt_test_pass "Append empty string"
else
    kt_test_fail "Append empty string (expected: content, got: $(cat "$_KT_TMPDIR"/empty.tmp))"
fi

# Test 4: Append with encoding parameter (if supported)
kt_test_start "Append with encoding"
printf "ascii" > "$_KT_TMPDIR/encoding.tmp"
result=$(tfile.appendAllText "$_KT_TMPDIR/encoding.tmp" " unicode" "UTF8")
if [[ -f "$_KT_TMPDIR/encoding.tmp" ]]; then
    kt_test_pass "Append with encoding"
else
    kt_test_fail "Append with encoding"
fi

# Test 5: Invalid path
kt_test_start "Append to invalid path"
if ! result=$(tfile.appendAllText "/invalid/path/file.tmp" "content" 2>&1); then
    kt_test_pass "Append to invalid path (correctly failed)"
else
    kt_test_fail "Append to invalid path (should have failed)"
fi

# Test 6: Append large content
kt_test_start "Append large content"
printf "start" > "$_KT_TMPDIR/large.tmp"
large_content=$(printf 'a%.0s' {1..10000})
result=$(tfile.appendAllText "$_KT_TMPDIR/large.tmp" "$large_content")
content=$(cat "$_KT_TMPDIR"/large.tmp)
if [[ "${content:0:5}" == "start" && ${#content} -gt 10000 ]]; then
    kt_test_pass "Append large content"
else
    kt_test_fail "Append large content"
fi
