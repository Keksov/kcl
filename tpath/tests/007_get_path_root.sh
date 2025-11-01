#!/bin/bash
# 007_get_path_root.sh - Test TPath.getPathRoot method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Unix absolute path
test_start "Get root from Unix absolute path"
result=$(tpath.getPathRoot "/home/user/file.txt")
if [[ "$result" == "/" ]]; then
    test_pass "Get root from Unix absolute path"
else
    test_fail "Get root from Unix absolute path (expected: /, got: '$result')"
fi

# Test 2: Windows drive path
test_start "Get root from Windows drive path"
result=$(tpath.getPathRoot "C:/Users/file.txt")
if [[ "$result" == "C:" ]]; then
    test_pass "Get root from Windows drive path"
else
    test_fail "Get root from Windows drive path (expected: C:, got: '$result')"
fi

# Test 3: UNC path
test_start "Get root from UNC path"
result=$(tpath.getPathRoot "//server/share/file.txt")
if [[ "$result" == "//server" ]]; then
    test_pass "Get root from UNC path"
else
    test_fail "Get root from UNC path (expected: //server, got: '$result')"
fi

# Test 4: Relative path
test_start "Get root from relative path"
result=$(tpath.getPathRoot "folder/file.txt")
if [[ "$result" == "" ]]; then
    test_pass "Get root from relative path"
else
    test_fail "Get root from relative path (expected: empty, got: '$result')"
fi

# Test 5: Empty path
test_start "Get root from empty path"
result=$(tpath.getPathRoot "")
if [[ "$result" == "" ]]; then
    test_pass "Get root from empty path"
else
    test_fail "Get root from empty path (expected: empty, got: '$result')"
fi

# Test 6: Root only
test_start "Get root from root path"
result=$(tpath.getPathRoot "/")
if [[ "$result" == "/" ]]; then
    test_pass "Get root from root path"
else
    test_fail "Get root from root path (expected: /, got: '$result')"
fi