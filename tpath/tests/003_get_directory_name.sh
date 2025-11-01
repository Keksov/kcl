#!/bin/bash
# 003_get_directory_name.sh - Test TPath.getDirectoryName method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Basic file path
test_start "Get directory from simple path"
result=$(tpath.getDirectoryName "/home/user/file.txt")
if [[ "$result" == "/home/user" ]]; then
    test_pass "Get directory from simple path"
else
    test_fail "Get directory from simple path (expected: /home/user, got: '$result')"
fi

# Test 2: Path with trailing separator
test_start "Get directory with trailing separator"
result=$(tpath.getDirectoryName "/home/user/")
if [[ "$result" == "/home" ]]; then
    test_pass "Get directory with trailing separator"
else
    test_fail "Get directory with trailing separator (expected: /home, got: '$result')"
fi

# Test 3: Root path
test_start "Get directory from root path"
result=$(tpath.getDirectoryName "/file.txt")
if [[ "$result" == "" || "$result" == "/" ]]; then
    test_pass "Get directory from root path"
else
    test_fail "Get directory from root path (expected: empty or /, got: '$result')"
fi

# Test 4: Relative path
test_start "Get directory from relative path"
result=$(tpath.getDirectoryName "folder/file.txt")
if [[ "$result" == "folder" ]]; then
    test_pass "Get directory from relative path"
else
    test_fail "Get directory from relative path (expected: folder, got: '$result')"
fi

# Test 5: No directory part
test_start "Get directory when no directory exists"
result=$(tpath.getDirectoryName "file.txt")
if [[ "$result" == "" ]]; then
    test_pass "Get directory when no directory exists"
else
    test_fail "Get directory when no directory exists (expected: empty, got: '$result')"
fi

# Test 6: Empty path
test_start "Get directory from empty path"
result=$(tpath.getDirectoryName "")
if [[ "$result" == "" ]]; then
    test_pass "Get directory from empty path"
else
    test_fail "Get directory from empty path (expected: empty, got: '$result')"
fi

# Test 7: Deep path
test_start "Get directory from deep path"
result=$(tpath.getDirectoryName "/var/log/application/debug/app.log")
if [[ "$result" == "/var/log/application/debug" ]]; then
    test_pass "Get directory from deep path"
else
    test_fail "Get directory from deep path (expected: /var/log/application/debug, got: '$result')"
fi