#!/bin/bash
# 005_get_filename.sh - Test TPath.getFileName and getFileNameWithoutExtension methods

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: getFileName - simple path
test_start "Get filename from simple path"
result=$(tpath.getFileName "/home/user/file.txt")
if [[ "$result" == "file.txt" ]]; then
    test_pass "Get filename from simple path"
else
    test_fail "Get filename from simple path (expected: file.txt, got: '$result')"
fi

# Test 2: getFileName - relative path
test_start "Get filename from relative path"
result=$(tpath.getFileName "folder/file.txt")
if [[ "$result" == "file.txt" ]]; then
    test_pass "Get filename from relative path"
else
    test_fail "Get filename from relative path (expected: file.txt, got: '$result')"
fi

# Test 3: getFileName - filename only
test_start "Get filename when only filename provided"
result=$(tpath.getFileName "file.txt")
if [[ "$result" == "file.txt" ]]; then
    test_pass "Get filename when only filename provided"
else
    test_fail "Get filename when only filename provided (expected: file.txt, got: '$result')"
fi

# Test 4: getFileName - empty path
test_start "Get filename from empty path"
result=$(tpath.getFileName "")
if [[ "$result" == "" ]]; then
    test_pass "Get filename from empty path"
else
    test_fail "Get filename from empty path (expected: empty, got: '$result')"
fi

# Test 5: getFileNameWithoutExtension - simple case
test_start "Get filename without extension"
result=$(tpath.getFileNameWithoutExtension "/home/user/file.txt")
if [[ "$result" == "file" ]]; then
    test_pass "Get filename without extension"
else
    test_fail "Get filename without extension (expected: file, got: '$result')"
fi

# Test 6: getFileNameWithoutExtension - no extension
test_start "Get filename without extension when no extension"
result=$(tpath.getFileNameWithoutExtension "/home/user/file")
if [[ "$result" == "file" ]]; then
    test_pass "Get filename without extension when no extension"
else
    test_fail "Get filename without extension when no extension (expected: file, got: '$result')"
fi

# Test 7: getFileNameWithoutExtension - multiple dots
test_start "Get filename without extension with multiple dots"
result=$(tpath.getFileNameWithoutExtension "file.tar.gz")
if [[ "$result" == "file.tar" ]]; then
    test_pass "Get filename without extension with multiple dots"
else
    test_fail "Get filename without extension with multiple dots (expected: file.tar, got: '$result')"
fi

# Test 8: getFileNameWithoutExtension - empty path
test_start "Get filename without extension from empty path"
result=$(tpath.getFileNameWithoutExtension "")
if [[ "$result" == "" ]]; then
    test_pass "Get filename without extension from empty path"
else
    test_fail "Get filename without extension from empty path (expected: empty, got: '$result')"
fi