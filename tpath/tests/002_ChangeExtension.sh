#!/bin/bash
# 002_change_extension.sh - Test TPath.changeExtension method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Change extension with dot
test_start "Change extension with dot"
result=$(tpath.changeExtension "file.txt" ".md")
if [[ "$result" == "file.md" ]]; then
    test_pass "Change extension with dot"
else
    test_fail "Change extension with dot (expected: file.md, got: '$result')"
fi

# Test 2: Change extension without dot
test_start "Change extension without dot"
result=$(tpath.changeExtension "file.txt" "md")
if [[ "$result" == "file.md" ]]; then
    test_pass "Change extension without dot"
else
    test_fail "Change extension without dot (expected: file.md, got: '$result')"
fi

# Test 3: Remove extension (empty extension)
test_start "Remove extension with empty string"
result=$(tpath.changeExtension "file.txt" "")
if [[ "$result" == "file" ]]; then
    test_pass "Remove extension with empty string"
else
    test_fail "Remove extension (expected: file, got: '$result')"
fi

# Test 4: File with path
test_start "Change extension with path"
result=$(tpath.changeExtension "/path/to/file.txt" ".md")
if [[ "$result" == "/path/to/file.md" ]]; then
    test_pass "Change extension with path"
else
    test_fail "Change extension with path (expected: /path/to/file.md, got: '$result')"
fi

# Test 5: File without extension
test_start "Add extension to file without extension"
result=$(tpath.changeExtension "file" ".txt")
if [[ "$result" == "file.txt" ]]; then
    test_pass "Add extension to file without extension"
else
    test_fail "Add extension to file without extension (expected: file.txt, got: '$result')"
fi

# Test 6: File with multiple dots
test_start "Change extension in file with multiple dots"
result=$(tpath.changeExtension "file.tar.gz" ".zip")
if [[ "$result" == "file.tar.zip" ]]; then
    test_pass "Change extension in file with multiple dots"
else
    test_fail "Change extension in file with multiple dots (expected: file.tar.zip, got: '$result')"
fi

# Test 7: Empty path
test_start "Change extension with empty path"
result=$(tpath.changeExtension "" ".txt")
if [[ "$result" == "" ]]; then
    test_pass "Change extension with empty path"
else
    test_fail "Change extension with empty path (expected: empty, got: '$result')"
fi