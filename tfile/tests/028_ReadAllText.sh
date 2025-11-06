#!/bin/bash
# 028_read_all_text.sh - Test TFile.ReadAllText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Read text from existing file
test_start "Read text from existing file"
echo "text content" > test_readtext.tmp
text=$(tfile.readAllText "test_readtext.tmp")
if [[ "$text" == "text content" ]]; then
    test_pass "Read text from existing file"
else
    test_fail "Read text from existing file (got: $text)"
fi

# Test 2: Read text with encoding
test_start "Read text with encoding"
text=$(tfile.readAllText "test_readtext.tmp" "TEncoding.UTF8")
if [[ "$text" == "text content" ]]; then
    test_pass "Read text with encoding"
else
    test_fail "Read text with encoding"
fi

# Test 3: Read text from empty file
test_start "Read text from empty file"
touch test_empty_text.tmp
text=$(tfile.readAllText "test_empty_text.tmp")
if [[ -z "$text" ]]; then
    test_pass "Read text from empty file"
else
    test_fail "Read text from empty file"
fi

# Test 4: Read text from non-existing file
test_start "Read text from non-existing file"
if ! text=$(tfile.readAllText "nonexist.tmp" 2>&1); then
    test_pass "Read text from non-existing file (correctly failed)"
else
    test_fail "Read text from non-existing file (should have failed)"
fi
