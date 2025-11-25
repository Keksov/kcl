#!/bin/bash
# GetDirectoryRoot
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetDirectoryRoot" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Root for Unix absolute path
kk_test_start "GetDirectoryRoot - Unix absolute path"
result=$(tdirectory.getDirectoryRoot "/home/user/documents")
if [[ "$result" == "/" ]]; then
    kk_test_pass "GetDirectoryRoot - Unix absolute path"
else
    kk_test_fail "GetDirectoryRoot - Unix absolute path (expected: /, got: '$result')"
fi

# Test 2: Root for Windows drive path
kk_test_start "GetDirectoryRoot - Windows drive path"
result=$(tdirectory.getDirectoryRoot "C:/Users/documents")
if [[ "$result" == "C:" ]]; then
    kk_test_pass "GetDirectoryRoot - Windows drive path"
else
    kk_test_fail "GetDirectoryRoot - Windows drive path (expected: C:, got: '$result')"
fi

# Test 3: Root for relative path
kk_test_start "GetDirectoryRoot - relative path"
result=$(tdirectory.getDirectoryRoot "folder/subfolder")
if [[ "$result" == "" ]]; then
    kk_test_pass "GetDirectoryRoot - relative path"
else
    kk_test_fail "GetDirectoryRoot - relative path (expected: empty, got: '$result')"
fi

# Test 4: Root for UNC path
kk_test_start "GetDirectoryRoot - UNC path"
result=$(tdirectory.getDirectoryRoot "//server/share/file")
if [[ "$result" == "//server" ]]; then
    kk_test_pass "GetDirectoryRoot - UNC path"
else
    kk_test_fail "GetDirectoryRoot - UNC path (expected: //server, got: '$result')"
fi

# Test 5: Root for empty path
kk_test_start "GetDirectoryRoot - empty path"
result=$(tdirectory.getDirectoryRoot "")
if [[ "$result" == "" ]]; then
    kk_test_pass "GetDirectoryRoot - empty path"
else
    kk_test_fail "GetDirectoryRoot - empty path (expected: empty, got: '$result')"
fi

# Test 6: Root for single slash
kk_test_start "GetDirectoryRoot - single slash"
result=$(tdirectory.getDirectoryRoot "/")
if [[ "$result" == "/" ]]; then
    kk_test_pass "GetDirectoryRoot - single slash"
else
    kk_test_fail "GetDirectoryRoot - single slash (expected: /, got: '$result')"
fi

# Test 7: Root for path with trailing slash
kk_test_start "GetDirectoryRoot - path with trailing slash"
result=$(tdirectory.getDirectoryRoot "/home/user/")
if [[ "$result" == "/" ]]; then
    kk_test_pass "GetDirectoryRoot - path with trailing slash"
else
    kk_test_fail "GetDirectoryRoot - path with trailing slash (expected: /, got: '$result')"
fi

# Test 8: Root for deep Unix path
kk_test_start "GetDirectoryRoot - deep Unix path"
result=$(tdirectory.getDirectoryRoot "/var/log/application/debug/messages")
if [[ "$result" == "/" ]]; then
    kk_test_pass "GetDirectoryRoot - deep Unix path"
else
    kk_test_fail "GetDirectoryRoot - deep Unix path (expected: /, got: '$result')"
fi

# Test 9: Root for Windows UNC share
kk_test_start "GetDirectoryRoot - Windows UNC share"
result=$(tdirectory.getDirectoryRoot "\\\\server\\share\\file")
if [[ "$result" == *"server"* ]]; then
    kk_test_pass "GetDirectoryRoot - Windows UNC share"
else
    kk_test_fail "GetDirectoryRoot - Windows UNC share (expected server in root, got: '$result')"
fi

# Test 10: Root for current directory
kk_test_start "GetDirectoryRoot - current directory"
result=$(tdirectory.getDirectoryRoot ".")
if [[ "$result" == "" ]]; then
    kk_test_pass "GetDirectoryRoot - current directory"
else
    kk_test_fail "GetDirectoryRoot - current directory (expected: empty, got: '$result')"
fi


