#!/bin/bash
# 006_path_analysis.sh - Test TPath path analysis methods

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: hasExtension - with extension
test_start "hasExtension - file with extension"
result=$(tpath.hasExtension "file.txt")
if [[ "$result" == "true" ]]; then
    test_pass "hasExtension - file with extension"
else
    test_fail "hasExtension - file with extension (expected: true, got: '$result')"
fi

# Test 2: hasExtension - without extension
test_start "hasExtension - file without extension"
result=$(tpath.hasExtension "file")
if [[ "$result" == "false" ]]; then
    test_pass "hasExtension - file without extension"
else
    test_fail "hasExtension - file without extension (expected: false, got: '$result')"
fi

# Test 3: isPathRooted - absolute path
test_start "isPathRooted - absolute path"
result=$(tpath.isPathRooted "/home/user")
if [[ "$result" == "true" ]]; then
    test_pass "isPathRooted - absolute path"
else
    test_fail "isPathRooted - absolute path (expected: true, got: '$result')"
fi

# Test 4: isPathRooted - relative path
test_start "isPathRooted - relative path"
result=$(tpath.isPathRooted "folder/file.txt")
if [[ "$result" == "false" ]]; then
    test_pass "isPathRooted - relative path"
else
    test_fail "isPathRooted - relative path (expected: false, got: '$result')"
fi

# Test 5: isRelativePath - relative
test_start "isRelativePath - relative path"
result=$(tpath.isRelativePath "folder/file.txt")
if [[ "$result" == "true" ]]; then
    test_pass "isRelativePath - relative path"
else
    test_fail "isRelativePath - relative path (expected: true, got: '$result')"
fi

# Test 6: isRelativePath - absolute
test_start "isRelativePath - absolute path"
result=$(tpath.isRelativePath "/home/user")
if [[ "$result" == "false" ]]; then
    test_pass "isRelativePath - absolute path"
else
    test_fail "isRelativePath - absolute path (expected: false, got: '$result')"
fi

# Test 7: isUNCPath - UNC path
test_start "isUNCPath - UNC path"
result=$(tpath.isUNCPath "//server/share")
if [[ "$result" == "true" ]]; then
    test_pass "isUNCPath - UNC path"
else
    test_fail "isUNCPath - UNC path (expected: true, got: '$result')"
fi

# Test 8: isUNCPath - non-UNC path
test_start "isUNCPath - non-UNC path"
result=$(tpath.isUNCPath "/home/user")
if [[ "$result" == "false" ]]; then
    test_pass "isUNCPath - non-UNC path"
else
    test_fail "isUNCPath - non-UNC path (expected: false, got: '$result')"
fi

# Test 9: isDriveRooted - drive path (Windows-style)
test_start "isDriveRooted - drive path"
result=$(tpath.isDriveRooted "C:/Users")
if [[ "$result" == "true" ]]; then
    test_pass "isDriveRooted - drive path"
else
    test_fail "isDriveRooted - drive path (expected: true, got: '$result')"
fi

# Test 10: isDriveRooted - non-drive path
test_start "isDriveRooted - non-drive path"
result=$(tpath.isDriveRooted "/home/user")
if [[ "$result" == "false" ]]; then
    test_pass "isDriveRooted - non-drive path"
else
    test_fail "isDriveRooted - non-drive path (expected: false, got: '$result')"
fi

# Test 11: isExtendedPrefixed - extended prefix
test_start "isExtendedPrefixed - extended prefix"
result=$(tpath.isExtendedPrefixed "//?/C:/path")
if [[ "$result" == "true" ]]; then
    test_pass "isExtendedPrefixed - extended prefix"
else
    test_fail "isExtendedPrefixed - extended prefix (expected: true, got: '$result')"
fi

# Test 12: isExtendedPrefixed - non-extended path
test_start "isExtendedPrefixed - non-extended path"
result=$(tpath.isExtendedPrefixed "/home/user")
if [[ "$result" == "false" ]]; then
    test_pass "isExtendedPrefixed - non-extended path"
else
    test_fail "isExtendedPrefixed - non-extended path (expected: false, got: '$result')"
fi