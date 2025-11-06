#!/bin/bash
# 001_append_all_text.sh - Test TFile.AppendAllText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "001"

# Test 1: Append to existing file
test_start "Append to existing file"
printf "initial content" > "$TEST_TMP_DIR/append.tmp"
result=$(tfile.appendAllText "$TEST_TMP_DIR/append.tmp" " appended text")
if [[ -f "$TEST_TMP_DIR/append.tmp" && "$(cat "$TEST_TMP_DIR"/append.tmp)" == "initial content appended text" ]]; then
    test_pass "Append to existing file"
else
    test_fail "Append to existing file (file content: $(cat "$TEST_TMP_DIR"/append.tmp))"
fi

# Test 2: Append to non-existing file (creates file)
test_start "Append to non-existing file"
rm -f "$TEST_TMP_DIR/nonexist.tmp"
result=$(tfile.appendAllText "$TEST_TMP_DIR/nonexist.tmp" "new content")
if [[ -f "$TEST_TMP_DIR/nonexist.tmp" && "$(cat "$TEST_TMP_DIR"/nonexist.tmp)" == "new content" ]]; then
    test_pass "Append to non-existing file"
else
    test_fail "Append to non-existing file"
fi

# Test 3: Append empty string
test_start "Append empty string"
printf "content" > "$TEST_TMP_DIR/empty.tmp"
result=$(tfile.appendAllText "$TEST_TMP_DIR/empty.tmp" "")
if [[ "$(cat "$TEST_TMP_DIR"/empty.tmp)" == "content" ]]; then
    test_pass "Append empty string"
else
    test_fail "Append empty string (expected: content, got: $(cat "$TEST_TMP_DIR"/empty.tmp))"
fi

# Test 4: Append with encoding parameter (if supported)
test_start "Append with encoding"
printf "ascii" > "$TEST_TMP_DIR/encoding.tmp"
result=$(tfile.appendAllText "$TEST_TMP_DIR/encoding.tmp" " unicode" "UTF8")
if [[ -f "$TEST_TMP_DIR/encoding.tmp" ]]; then
    test_pass "Append with encoding"
else
    test_fail "Append with encoding"
fi

# Test 5: Invalid path
test_start "Append to invalid path"
if ! result=$(tfile.appendAllText "/invalid/path/file.tmp" "content" 2>&1); then
    test_pass "Append to invalid path (correctly failed)"
else
    test_fail "Append to invalid path (should have failed)"
fi

# Test 6: Append large content
test_start "Append large content"
printf "start" > "$TEST_TMP_DIR/large.tmp"
large_content=$(printf 'a%.0s' {1..10000})
result=$(tfile.appendAllText "$TEST_TMP_DIR/large.tmp" "$large_content")
content=$(cat "$TEST_TMP_DIR"/large.tmp)
if [[ "${content:0:5}" == "start" && ${#content} -gt 10000 ]]; then
    test_pass "Append large content"
else
    test_fail "Append large content"
fi
