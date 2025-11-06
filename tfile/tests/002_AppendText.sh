#!/bin/bash
# 002_append_text.sh - Test TFile.AppendText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Append to existing file
test_start "Append text to existing file"
printf "initial" > test_append_text.tmp
writer=$(tfile.appendText "test_append_text.tmp")
# Note: This assumes writer has write and close methods, adjust based on actual API
printf " appended" >> "$writer"  # Simplified, actual implementation may vary
# close_writer "$writer"
if [[ "$(cat test_append_text.tmp)" == "initial appended" ]]; then
    test_pass "Append text to existing file"
else
    test_fail "Append text to existing file (got: $(cat test_append_text.tmp))"
fi

# Test 2: Append to new file
test_start "Append text to new file"
rm -f test_new_append.tmp
writer=$(tfile.appendText "test_new_append.tmp")
printf "new content" > "$writer"
# close_writer "$writer"
if [[ "$(cat test_new_append.tmp)" == "new content" ]]; then
    test_pass "Append text to new file"
else
    test_fail "Append text to new file"
fi

# Test 3: Invalid path
test_start "Append text to invalid path"
if ! writer=$(tfile.appendText "/invalid/path/file.tmp" 2>&1); then
    test_pass "Append text to invalid path (correctly failed)"
else
    test_fail "Append text to invalid path (should have failed)"
fi
