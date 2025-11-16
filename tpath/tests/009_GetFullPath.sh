#!/bin/bash
# 009_get_full_path.sh - Test TPath.getFullPath method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Relative path to absolute
test_start "Convert relative path to absolute"
result=$(tpath.getFullPath ".")
if [[ "$result" == /* ]] || [[ "$result" =~ ^[A-Za-z]: ]]; then
    test_pass "Convert relative path to absolute"
else
    test_fail "Convert relative path to absolute (expected absolute path, got: '$result')"
fi

# Test 2: Already absolute path
test_start "Absolute path remains absolute"
result=$(tpath.getFullPath "/tmp")
if [[ "$result" == "/tmp" ]] || [[ "$result" =~ ^/.*tmp.* ]]; then
    test_pass "Absolute path remains absolute"
else
    test_fail "Absolute path remains absolute (got: '$result')"
fi

# Test 3: Empty path
test_start "getFullPath with empty path"
result=$(tpath.getFullPath "")
if [[ "$result" == "" ]]; then
    test_pass "getFullPath with empty path"
else
    test_fail "getFullPath with empty path (expected empty, got: '$result')"
fi

# Test 4: Current directory
test_start "getFullPath with current directory"
result=$(tpath.getFullPath ".")
if [[ -n "$result" && "$result" != "." ]]; then
    test_pass "getFullPath with current directory"
else
    test_fail "getFullPath with current directory (got: '$result')"
fi

# Test 5: Parent directory
test_start "getFullPath with parent directory"
result=$(tpath.getFullPath "..")
if [[ -n "$result" && "$result" != ".." ]]; then
    test_pass "getFullPath with parent directory"
else
    test_fail "getFullPath with parent directory (got: '$result')"
fi