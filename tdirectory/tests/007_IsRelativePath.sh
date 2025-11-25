#!/bin/bash
# IsRelativePath
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "IsRelativePath" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Relative path
kk_test_start "IsRelativePath - relative path returns true"
result=$(tdirectory.isRelativePath "folder/subfolder")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsRelativePath - relative path returns true"
else
    kk_test_fail "IsRelativePath - relative path returns true (expected: true, got: '$result')"
fi

# Test 2: Absolute path with leading slash
kk_test_start "IsRelativePath - absolute path returns false"
result=$(tdirectory.isRelativePath "/home/user/document")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsRelativePath - absolute path returns false"
else
    kk_test_fail "IsRelativePath - absolute path returns false (expected: false, got: '$result')"
fi

# Test 3: Current directory reference
kk_test_start "IsRelativePath - current directory reference is relative"
result=$(tdirectory.isRelativePath ".")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsRelativePath - current directory reference is relative"
else
    kk_test_fail "IsRelativePath - current directory reference is relative (expected: true, got: '$result')"
fi

# Test 4: Parent directory reference
kk_test_start "IsRelativePath - parent directory reference is relative"
result=$(tdirectory.isRelativePath "..")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsRelativePath - parent directory reference is relative"
else
    kk_test_fail "IsRelativePath - parent directory reference is relative (expected: true, got: '$result')"
fi

# Test 5: Relative path with spaces
kk_test_start "IsRelativePath - relative path with spaces"
result=$(tdirectory.isRelativePath "my folder/subfolder")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsRelativePath - relative path with spaces"
else
    kk_test_fail "IsRelativePath - relative path with spaces (expected: true, got: '$result')"
fi

# Test 6: Empty path
kk_test_start "IsRelativePath - empty path"
result=$(tdirectory.isRelativePath "")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsRelativePath - empty path"
else
    kk_test_fail "IsRelativePath - empty path (expected: true, got: '$result')"
fi

# Test 7: Windows drive path is absolute
kk_test_start "IsRelativePath - Windows drive path is absolute"
result=$(tdirectory.isRelativePath "C:/Users/file.txt")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsRelativePath - Windows drive path is absolute"
else
    kk_test_fail "IsRelativePath - Windows drive path is absolute (expected: false, got: '$result')"
fi

# Test 8: Relative path with multiple components
kk_test_start "IsRelativePath - relative path with multiple components"
result=$(tdirectory.isRelativePath "a/b/c/d/e/f")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsRelativePath - relative path with multiple components"
else
    kk_test_fail "IsRelativePath - relative path with multiple components (expected: true, got: '$result')"
fi

# Test 9: UNC path is absolute
kk_test_start "IsRelativePath - UNC path is absolute"
result=$(tdirectory.isRelativePath "//server/share/file")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsRelativePath - UNC path is absolute"
else
    kk_test_fail "IsRelativePath - UNC path is absolute (expected: false, got: '$result')"
fi

# Test 10: Single relative name
kk_test_start "IsRelativePath - single relative name"
result=$(tdirectory.isRelativePath "filename.txt")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsRelativePath - single relative name"
else
    kk_test_fail "IsRelativePath - single relative name (expected: true, got: '$result')"
fi


