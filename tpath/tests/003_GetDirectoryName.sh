#!/bin/bash
# GetDirectoryName
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetDirectoryName" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Basic file path
kt_test_start "Get directory from simple path"
result=$(tpath.getDirectoryName "/home/user/file.txt")
if [[ "$result" == "/home/user" ]]; then
    kt_test_pass "Get directory from simple path"
else
    kt_test_fail "Get directory from simple path (expected: /home/user, got: '$result')"
fi

# Test 2: Path with trailing separator
kt_test_start "Get directory with trailing separator"
result=$(tpath.getDirectoryName "/home/user/")
if [[ "$result" == "/home" ]]; then
    kt_test_pass "Get directory with trailing separator"
else
    kt_test_fail "Get directory with trailing separator (expected: /home, got: '$result')"
fi

# Test 3: Root path
kt_test_start "Get directory from root path"
result=$(tpath.getDirectoryName "/file.txt")
expected=""
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "Get directory from root path"
else
    kt_test_fail "Get directory from root path (expected: $expected, got: '$result')"
fi

# Test 4: Relative path
kt_test_start "Get directory from relative path"
result=$(tpath.getDirectoryName "folder/file.txt")
if [[ "$result" == "folder" ]]; then
    kt_test_pass "Get directory from relative path"
else
    kt_test_fail "Get directory from relative path (expected: folder, got: '$result')"
fi

# Test 5: No directory part
kt_test_start "Get directory when no directory exists"
result=$(tpath.getDirectoryName "file.txt")
if [[ "$result" == "" ]]; then
    kt_test_pass "Get directory when no directory exists"
else
    kt_test_fail "Get directory when no directory exists (expected: empty, got: '$result')"
fi

# Test 6: Empty path
kt_test_start "Get directory from empty path"
result=$(tpath.getDirectoryName "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Get directory from empty path"
else
    kt_test_fail "Get directory from empty path (expected: empty, got: '$result')"
fi

# Test 7: Deep path
kt_test_start "Get directory from deep path"
result=$(tpath.getDirectoryName "/var/log/application/debug/app.log")
if [[ "$result" == "/var/log/application/debug" ]]; then
    kt_test_pass "Get directory from deep path"
else
    kt_test_fail "Get directory from deep path (expected: /var/log/application/debug, got: '$result')"
fi
