#!/bin/bash
# IsRelativePath
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "IsRelativePath" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Relative path
kt_test_start "IsRelativePath - relative path returns true"
result=$(tdirectory.isRelativePath "folder/subfolder")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsRelativePath - relative path returns true"
else
    kt_test_fail "IsRelativePath - relative path returns true (expected: true, got: '$result')"
fi

# Test 2: Absolute path with leading slash
kt_test_start "IsRelativePath - absolute path returns false"
result=$(tdirectory.isRelativePath "/home/user/document")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsRelativePath - absolute path returns false"
else
    kt_test_fail "IsRelativePath - absolute path returns false (expected: false, got: '$result')"
fi

# Test 3: Current directory reference
kt_test_start "IsRelativePath - current directory reference is relative"
result=$(tdirectory.isRelativePath ".")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsRelativePath - current directory reference is relative"
else
    kt_test_fail "IsRelativePath - current directory reference is relative (expected: true, got: '$result')"
fi

# Test 4: Parent directory reference
kt_test_start "IsRelativePath - parent directory reference is relative"
result=$(tdirectory.isRelativePath "..")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsRelativePath - parent directory reference is relative"
else
    kt_test_fail "IsRelativePath - parent directory reference is relative (expected: true, got: '$result')"
fi

# Test 5: Relative path with spaces
kt_test_start "IsRelativePath - relative path with spaces"
result=$(tdirectory.isRelativePath "my folder/subfolder")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsRelativePath - relative path with spaces"
else
    kt_test_fail "IsRelativePath - relative path with spaces (expected: true, got: '$result')"
fi

# Test 6: Empty path
kt_test_start "IsRelativePath - empty path"
result=$(tdirectory.isRelativePath "")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsRelativePath - empty path"
else
    kt_test_fail "IsRelativePath - empty path (expected: true, got: '$result')"
fi

# Test 7: Windows drive path is absolute
kt_test_start "IsRelativePath - Windows drive path is absolute"
result=$(tdirectory.isRelativePath "C:/Users/file.txt")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsRelativePath - Windows drive path is absolute"
else
    kt_test_fail "IsRelativePath - Windows drive path is absolute (expected: false, got: '$result')"
fi

# Test 8: Relative path with multiple components
kt_test_start "IsRelativePath - relative path with multiple components"
result=$(tdirectory.isRelativePath "a/b/c/d/e/f")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsRelativePath - relative path with multiple components"
else
    kt_test_fail "IsRelativePath - relative path with multiple components (expected: true, got: '$result')"
fi

# Test 9: UNC path is absolute
kt_test_start "IsRelativePath - UNC path is absolute"
result=$(tdirectory.isRelativePath "//server/share/file")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsRelativePath - UNC path is absolute"
else
    kt_test_fail "IsRelativePath - UNC path is absolute (expected: false, got: '$result')"
fi

# Test 10: Single relative name
kt_test_start "IsRelativePath - single relative name"
result=$(tdirectory.isRelativePath "filename.txt")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsRelativePath - single relative name"
else
    kt_test_fail "IsRelativePath - single relative name (expected: true, got: '$result')"
fi


