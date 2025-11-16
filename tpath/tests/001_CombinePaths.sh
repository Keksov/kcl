#!/bin/bash
# 001_combine_paths.sh - Test TPath.combine method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Basic path combination
test_start "Combine two relative paths"
result=$(tpath.combine "path1" "path2")
# Should combine with separator
if [[ "$result" == "path1"*"path2" ]]; then
    test_pass "Combine two relative paths"
else
    test_fail "Combine two relative paths (expected: path1[/\\]path2, got: '$result')"
fi

# Test 2: Absolute path2 returns path2
test_start "Combine with absolute path2"
result=$(tpath.combine "path1" "/absolute/path")
if [[ "$result" == "/absolute/path" ]]; then
    test_pass "Combine with absolute path2"
else
    test_fail "Combine with absolute path2 (expected: /absolute/path, got: '$result')"
fi

# Test 3: Empty path1
test_start "Combine with empty path1"
result=$(tpath.combine "" "path2")
if [[ "$result" == "path2" ]]; then
    test_pass "Combine with empty path1"
else
    test_fail "Combine with empty path1 (expected: path2, got: '$result')"
fi

# Test 4: Empty path2
test_start "Combine with empty path2"
result=$(tpath.combine "path1" "")
if [[ "$result" == "path1" ]]; then
    test_pass "Combine with empty path2"
else
    test_fail "Combine with empty path2 (expected: path1, got: '$result')"
fi

# Test 5: Path1 with trailing separator
test_start "Combine path1 with trailing separator"
result=$(tpath.combine "path1/" "path2")
if [[ "$result" == "path1"*"path2" ]]; then
    test_pass "Combine path1 with trailing separator"
else
    test_fail "Combine path1 with trailing separator (got: '$result')"
fi

# Test 6: Complex path combination
test_start "Combine complex paths"
result=$(tpath.combine "/home/user" "documents/file.txt")
if [[ "$result" == "/home/user"*"documents"*"file.txt" ]]; then
    test_pass "Combine complex paths"
else
    test_fail "Combine complex paths (got: '$result')"
fi