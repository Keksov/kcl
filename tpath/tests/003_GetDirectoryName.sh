#!/bin/bash
# GetDirectoryName
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetDirectoryName" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Basic file path
kk_test_start "Get directory from simple path"
result=$(tpath.getDirectoryName "/home/user/file.txt")
if [[ "$result" == "/home/user" ]]; then
    kk_test_pass "Get directory from simple path"
else
    kk_test_fail "Get directory from simple path (expected: /home/user, got: '$result')"
fi

# Test 2: Path with trailing separator
kk_test_start "Get directory with trailing separator"
result=$(tpath.getDirectoryName "/home/user/")
if [[ "$result" == "/home" ]]; then
    kk_test_pass "Get directory with trailing separator"
else
    kk_test_fail "Get directory with trailing separator (expected: /home, got: '$result')"
fi

# Test 3: Root path
kk_test_start "Get directory from root path"
result=$(tpath.getDirectoryName "/file.txt")
expected=""
if [[ "$result" == "$expected" ]]; then
    kk_test_pass "Get directory from root path"
else
    kk_test_fail "Get directory from root path (expected: $expected, got: '$result')"
fi

# Test 4: Relative path
kk_test_start "Get directory from relative path"
result=$(tpath.getDirectoryName "folder/file.txt")
if [[ "$result" == "folder" ]]; then
    kk_test_pass "Get directory from relative path"
else
    kk_test_fail "Get directory from relative path (expected: folder, got: '$result')"
fi

# Test 5: No directory part
kk_test_start "Get directory when no directory exists"
result=$(tpath.getDirectoryName "file.txt")
if [[ "$result" == "" ]]; then
    kk_test_pass "Get directory when no directory exists"
else
    kk_test_fail "Get directory when no directory exists (expected: empty, got: '$result')"
fi

# Test 6: Empty path
kk_test_start "Get directory from empty path"
result=$(tpath.getDirectoryName "")
if [[ "$result" == "" ]]; then
    kk_test_pass "Get directory from empty path"
else
    kk_test_fail "Get directory from empty path (expected: empty, got: '$result')"
fi

# Test 7: Deep path
kk_test_start "Get directory from deep path"
result=$(tpath.getDirectoryName "/var/log/application/debug/app.log")
if [[ "$result" == "/var/log/application/debug" ]]; then
    kk_test_pass "Get directory from deep path"
else
    kk_test_fail "Get directory from deep path (expected: /var/log/application/debug, got: '$result')"
fi
