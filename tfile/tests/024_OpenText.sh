#!/bin/bash
# 024_open_text.sh - Test TFile.OpenText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Open existing text file
test_start "Open existing text file"
echo "text content" > test_opentext.tmp
reader=$(tfile.openText "test_opentext.tmp")
if [[ -n "$reader" ]]; then
    test_pass "Open existing text file"
    close_reader "$reader"
else
    test_fail "Open existing text file"
fi

# Test 2: Open non-existing file
test_start "Open non-existing text file"
if ! reader=$(tfile.openText "nonexist.tmp" 2>&1); then
    test_pass "Open non-existing text file (correctly failed)"
else
    test_fail "Open non-existing text file (should have failed)"
fi
