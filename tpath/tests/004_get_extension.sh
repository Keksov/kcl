#!/bin/bash
# 004_get_extension.sh - Test TPath.getExtension method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Simple extension
test_start "Get simple extension"
result=$(tpath.getExtension "file.txt")
if [[ "$result" == ".txt" ]]; then
    test_pass "Get simple extension"
else
    test_fail "Get simple extension (expected: .txt, got: '$result')"
fi

# Test 2: No extension
test_start "Get extension from file without extension"
result=$(tpath.getExtension "file")
if [[ "$result" == "" ]]; then
    test_pass "Get extension from file without extension"
else
    test_fail "Get extension from file without extension (expected: empty, got: '$result')"
fi

# Test 3: Multiple dots
test_start "Get extension from file with multiple dots"
result=$(tpath.getExtension "file.tar.gz")
if [[ "$result" == ".gz" ]]; then
    test_pass "Get extension from file with multiple dots"
else
    test_fail "Get extension from file with multiple dots (expected: .gz, got: '$result')"
fi

# Test 4: Path with extension
test_start "Get extension from path"
result=$(tpath.getExtension "/home/user/document.pdf")
if [[ "$result" == ".pdf" ]]; then
    test_pass "Get extension from path"
else
    test_fail "Get extension from path (expected: .pdf, got: '$result')"
fi

# Test 5: Hidden file with extension
test_start "Get extension from hidden file"
result=$(tpath.getExtension ".bashrc")
if [[ "$result" == ".bashrc" ]]; then
    test_pass "Get extension from hidden file"
else
    test_fail "Get extension from hidden file (expected: .bashrc, got: '$result')"
fi

# Test 6: Empty path
test_start "Get extension from empty path"
result=$(tpath.getExtension "")
if [[ "$result" == "" ]]; then
    test_pass "Get extension from empty path"
else
    test_fail "Get extension from empty path (expected: empty, got: '$result')"
fi

# Test 7: Directory with dot in name
test_start "Get extension from directory with dot"
result=$(tpath.getExtension "/path/folder.name/file.txt")
if [[ "$result" == ".txt" ]]; then
    test_pass "Get extension from directory with dot"
else
    test_fail "Get extension from directory with dot (expected: .txt, got: '$result')"
fi