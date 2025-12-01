#!/bin/bash
# GetFullPath
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetFullPath" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Relative path to absolute
kt_test_start "Convert relative path to absolute"
result=$(tpath.getFullPath ".")
if [[ "$result" == /* ]] || [[ "$result" =~ ^[A-Za-z]: ]]; then
    kt_test_pass "Convert relative path to absolute"
else
    kt_test_fail "Convert relative path to absolute (expected absolute path, got: '$result')"
fi

# Test 2: Already absolute path
kt_test_start "Absolute path remains absolute"
result=$(tpath.getFullPath "/tmp")
expected="/tmp"
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "Absolute path remains absolute"
else
    kt_test_fail "Absolute path remains absolute (expected: $expected, got: '$result')"
fi

# Test 3: Empty path
kt_test_start "getFullPath with empty path"
result=$(tpath.getFullPath "")
if [[ "$result" == "" ]]; then
    kt_test_pass "getFullPath with empty path"
else
    kt_test_fail "getFullPath with empty path (expected empty, got: '$result')"
fi

# Test 4: Current directory
kt_test_start "getFullPath with current directory"
result=$(tpath.getFullPath ".")
if [[ -n "$result" && "$result" != "." ]]; then
    kt_test_pass "getFullPath with current directory"
else
    kt_test_fail "getFullPath with current directory (got: '$result')"
fi

# Test 5: Parent directory
kt_test_start "getFullPath with parent directory"
result=$(tpath.getFullPath "..")
if [[ -n "$result" && "$result" != ".." ]]; then
    kt_test_pass "getFullPath with parent directory"
else
    kt_test_fail "getFullPath with parent directory (got: '$result')"
fi

# Test 6: Very long path
kt_test_start "getFullPath with very long path"
long_path="folder/$(printf 'a%.0s' {1..100})/file.txt"
result=$(tpath.getFullPath "$long_path")
if [[ -n "$result" ]]; then
    kt_test_pass "getFullPath with very long path"
else
    kt_test_fail "getFullPath with very long path (got empty)"
fi

# Test 7: Path with special characters
kt_test_start "getFullPath with special characters"
special_path="folder/file with spaces & symbols!.txt"
result=$(tpath.getFullPath "$special_path")
if [[ -n "$result" ]]; then
    kt_test_pass "getFullPath with special characters"
else
    kt_test_fail "getFullPath with special characters (got empty)"
fi
