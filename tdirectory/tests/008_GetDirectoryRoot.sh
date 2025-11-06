#!/bin/bash
# 008_GetDirectoryRoot.sh - Test TDirectory.GetDirectoryRoot method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Root for Unix absolute path
test_start "GetDirectoryRoot - Unix absolute path"
result=$(tdirectory.getDirectoryRoot "/home/user/documents")
if [[ "$result" == "/" ]]; then
    test_pass "GetDirectoryRoot - Unix absolute path"
else
    test_fail "GetDirectoryRoot - Unix absolute path (expected: /, got: '$result')"
fi

# Test 2: Root for Windows drive path
test_start "GetDirectoryRoot - Windows drive path"
result=$(tdirectory.getDirectoryRoot "C:/Users/documents")
if [[ "$result" == "C:" ]]; then
    test_pass "GetDirectoryRoot - Windows drive path"
else
    test_fail "GetDirectoryRoot - Windows drive path (expected: C:, got: '$result')"
fi

# Test 3: Root for relative path
test_start "GetDirectoryRoot - relative path"
result=$(tdirectory.getDirectoryRoot "folder/subfolder")
if [[ "$result" == "" ]]; then
    test_pass "GetDirectoryRoot - relative path"
else
    test_fail "GetDirectoryRoot - relative path (expected: empty, got: '$result')"
fi

# Test 4: Root for UNC path
test_start "GetDirectoryRoot - UNC path"
result=$(tdirectory.getDirectoryRoot "//server/share/file")
if [[ "$result" == "//server" ]]; then
    test_pass "GetDirectoryRoot - UNC path"
else
    test_fail "GetDirectoryRoot - UNC path (expected: //server, got: '$result')"
fi

# Test 5: Root for empty path
test_start "GetDirectoryRoot - empty path"
result=$(tdirectory.getDirectoryRoot "")
if [[ "$result" == "" ]]; then
    test_pass "GetDirectoryRoot - empty path"
else
    test_fail "GetDirectoryRoot - empty path (expected: empty, got: '$result')"
fi

# Test 6: Root for single slash
test_start "GetDirectoryRoot - single slash"
result=$(tdirectory.getDirectoryRoot "/")
if [[ "$result" == "/" ]]; then
    test_pass "GetDirectoryRoot - single slash"
else
    test_fail "GetDirectoryRoot - single slash (expected: /, got: '$result')"
fi

# Test 7: Root for path with trailing slash
test_start "GetDirectoryRoot - path with trailing slash"
result=$(tdirectory.getDirectoryRoot "/home/user/")
if [[ "$result" == "/" ]]; then
    test_pass "GetDirectoryRoot - path with trailing slash"
else
    test_fail "GetDirectoryRoot - path with trailing slash (expected: /, got: '$result')"
fi

# Test 8: Root for deep Unix path
test_start "GetDirectoryRoot - deep Unix path"
result=$(tdirectory.getDirectoryRoot "/var/log/application/debug/messages")
if [[ "$result" == "/" ]]; then
    test_pass "GetDirectoryRoot - deep Unix path"
else
    test_fail "GetDirectoryRoot - deep Unix path (expected: /, got: '$result')"
fi

# Test 9: Root for Windows UNC share
test_start "GetDirectoryRoot - Windows UNC share"
result=$(tdirectory.getDirectoryRoot "\\\\server\\share\\file")
if [[ "$result" == *"server"* ]]; then
    test_pass "GetDirectoryRoot - Windows UNC share"
else
    test_fail "GetDirectoryRoot - Windows UNC share (expected server in root, got: '$result')"
fi

# Test 10: Root for current directory
test_start "GetDirectoryRoot - current directory"
result=$(tdirectory.getDirectoryRoot ".")
if [[ "$result" == "" ]]; then
    test_pass "GetDirectoryRoot - current directory"
else
    test_fail "GetDirectoryRoot - current directory (expected: empty, got: '$result')"
fi

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
