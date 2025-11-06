#!/bin/bash
# 027_read_all_lines.sh - Test TFile.ReadAllLines method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Read lines from existing file
test_start "Read lines from existing file"
echo -e "line1\nline2\nline3" > test_readlines.tmp
lines=$(tfile.readAllLines "test_readlines.tmp")
if [[ $(echo "$lines" | wc -l) -eq 3 ]]; then
    test_pass "Read lines from existing file"
else
    test_fail "Read lines from existing file"
fi

# Test 2: Read lines with encoding
test_start "Read lines with encoding"
lines=$(tfile.readAllLines "test_readlines.tmp" "TEncoding.UTF8")
if [[ $(echo "$lines" | wc -l) -eq 3 ]]; then
    test_pass "Read lines with encoding"
else
    test_fail "Read lines with encoding"
fi

# Test 3: Read lines from empty file
test_start "Read lines from empty file"
touch test_empty_lines.tmp
lines=$(tfile.readAllLines "test_empty_lines.tmp")
if [[ -z "$lines" ]]; then
    test_pass "Read lines from empty file"
else
    test_fail "Read lines from empty file"
fi

# Test 4: Read lines from non-existing file
test_start "Read lines from non-existing file"
if ! lines=$(tfile.readAllLines "nonexist.tmp" 2>&1); then
    test_pass "Read lines from non-existing file (correctly failed)"
else
    test_fail "Read lines from non-existing file (should have failed)"
fi
