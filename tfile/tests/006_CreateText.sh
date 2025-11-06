#!/bin/bash
# 006_create_text.sh - Test TFile.CreateText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=006
mkdir -p ".tmp/$TEST_ID"

# Test 1: Create new text file
test_start "Create new text file"
writer=$(tfile.createText ".tmp/$TEST_ID/create_text.tmp")
printf "text content" > "$writer"
if [[ -f ".tmp/$TEST_ID/create_text.tmp" && "$(cat .tmp/$TEST_ID/create_text.tmp)" == "text content" ]]; then
    test_pass "Create new text file"
else
    test_fail "Create new text file"
fi

# Test 2: Create existing file (should overwrite)
test_start "Create text on existing file"
printf "old content" > ".tmp/$TEST_ID/overwrite_text.tmp"
writer=$(tfile.createText ".tmp/$TEST_ID/overwrite_text.tmp")
printf "new content" > "$writer"
if [[ "$(cat .tmp/$TEST_ID/overwrite_text.tmp)" == "new content" ]]; then
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
