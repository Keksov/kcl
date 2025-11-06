#!/bin/bash
# 007_IsRelativePath.sh - Test TDirectory.IsRelativePath method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Relative path
test_start "IsRelativePath - relative path returns true"
result=$(tdirectory.isRelativePath "folder/subfolder")
if [[ "$result" == "true" ]]; then
    test_pass "IsRelativePath - relative path returns true"
else
    test_fail "IsRelativePath - relative path returns true (expected: true, got: '$result')"
fi

# Test 2: Absolute path with leading slash
test_start "IsRelativePath - absolute path returns false"
result=$(tdirectory.isRelativePath "/home/user/document")
if [[ "$result" == "false" ]]; then
    test_pass "IsRelativePath - absolute path returns false"
else
    test_fail "IsRelativePath - absolute path returns false (expected: false, got: '$result')"
fi

# Test 3: Current directory reference
test_start "IsRelativePath - current directory reference is relative"
result=$(tdirectory.isRelativePath ".")
if [[ "$result" == "true" ]]; then
    test_pass "IsRelativePath - current directory reference is relative"
else
    test_fail "IsRelativePath - current directory reference is relative (expected: true, got: '$result')"
fi

# Test 4: Parent directory reference
test_start "IsRelativePath - parent directory reference is relative"
result=$(tdirectory.isRelativePath "..")
if [[ "$result" == "true" ]]; then
    test_pass "IsRelativePath - parent directory reference is relative"
else
    test_fail "IsRelativePath - parent directory reference is relative (expected: true, got: '$result')"
fi

# Test 5: Relative path with spaces
test_start "IsRelativePath - relative path with spaces"
result=$(tdirectory.isRelativePath "my folder/subfolder")
if [[ "$result" == "true" ]]; then
    test_pass "IsRelativePath - relative path with spaces"
else
    test_fail "IsRelativePath - relative path with spaces (expected: true, got: '$result')"
fi

# Test 6: Empty path
test_start "IsRelativePath - empty path"
result=$(tdirectory.isRelativePath "")
if [[ "$result" == "true" ]]; then
    test_pass "IsRelativePath - empty path"
else
    test_fail "IsRelativePath - empty path (expected: true, got: '$result')"
fi

# Test 7: Windows drive path is absolute
test_start "IsRelativePath - Windows drive path is absolute"
result=$(tdirectory.isRelativePath "C:/Users/file.txt")
if [[ "$result" == "false" ]]; then
    test_pass "IsRelativePath - Windows drive path is absolute"
else
    test_fail "IsRelativePath - Windows drive path is absolute (expected: false, got: '$result')"
fi

# Test 8: Relative path with multiple components
test_start "IsRelativePath - relative path with multiple components"
result=$(tdirectory.isRelativePath "a/b/c/d/e/f")
if [[ "$result" == "true" ]]; then
    test_pass "IsRelativePath - relative path with multiple components"
else
    test_fail "IsRelativePath - relative path with multiple components (expected: true, got: '$result')"
fi

# Test 9: UNC path is absolute
test_start "IsRelativePath - UNC path is absolute"
result=$(tdirectory.isRelativePath "//server/share/file")
if [[ "$result" == "false" ]]; then
    test_pass "IsRelativePath - UNC path is absolute"
else
    test_fail "IsRelativePath - UNC path is absolute (expected: false, got: '$result')"
fi

# Test 10: Single relative name
test_start "IsRelativePath - single relative name"
result=$(tdirectory.isRelativePath "filename.txt")
if [[ "$result" == "true" ]]; then
    test_pass "IsRelativePath - single relative name"
else
    test_fail "IsRelativePath - single relative name (expected: true, got: '$result')"
fi

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
