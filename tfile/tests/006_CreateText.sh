#!/bin/bash
# 006_create_text.sh - Test TFile.CreateText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Create new text file
test_start "Create new text file"
rm -f test_create_text.tmp
writer=$(tfile.createText "test_create_text.tmp")
printf "text content" > "$writer"
# close_writer "$writer"
if [[ -f "test_create_text.tmp" && "$(cat test_create_text.tmp)" == "text content" ]]; then
    test_pass "Create new text file"
else
    test_fail "Create new text file"
fi

# Test 2: Create existing file (should overwrite)
test_start "Create text on existing file"
printf "old content" > test_overwrite_text.tmp
writer=$(tfile.createText "test_overwrite_text.tmp")
printf "new content" > "$writer"
# close_writer "$writer"
if [[ "$(cat test_overwrite_text.tmp)" == "new content" ]]; then
    test_pass "Create text on existing file"
else
    test_fail "Create text on existing file"
fi

# Test 3: Invalid path
test_start "Create text with invalid path"
if ! writer=$(tfile.createText "/invalid/path/file.tmp" 2>&1); then
    test_pass "Create text with invalid path (correctly failed)"
else
    test_fail "Create text with invalid path (should have failed)"
fi
