#!/bin/bash
# 013_GetDirectories.sh - Test TDirectory.GetDirectories method (multiple overloads)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
temp_base="$(tpath.getTempPath)/tdirectory_test_$$"
tdirectory.createDirectory "$temp_base"

# Test 1: GetDirectories with simple directory
test_start "GetDirectories - basic subdirectory listing"
test_dir="$temp_base/simple"
tdirectory.createDirectory "$test_dir/sub1"
tdirectory.createDirectory "$test_dir/sub2"
tdirectory.createDirectory "$test_dir/sub3"
result=$(tdirectory.getDirectories "$test_dir")
if [[ "$result" =~ "sub1" && "$result" =~ "sub2" && "$result" =~ "sub3" ]]; then
    test_pass "GetDirectories - basic subdirectory listing"
else
    test_fail "GetDirectories - basic subdirectory listing (expected subdirs in output)"
fi

# Test 2: GetDirectories with search pattern
test_start "GetDirectories - with search pattern"
test_dir="$temp_base/pattern_test"
tdirectory.createDirectory "$test_dir/app_001"
tdirectory.createDirectory "$test_dir/app_002"
tdirectory.createDirectory "$test_dir/other_dir"
result=$(tdirectory.getDirectories "$test_dir" "*app*")
if [[ "$result" =~ "app_001" && "$result" =~ "app_002" && ! "$result" =~ "other_dir" ]]; then
    test_pass "GetDirectories - with search pattern"
else
    test_fail "GetDirectories - with search pattern (expected only app* dirs)"
fi

# Test 3: GetDirectories with files present (should exclude files)
test_start "GetDirectories - excludes files"
test_dir="$temp_base/mixed_content"
tdirectory.createDirectory "$test_dir/subdir"
echo "file content" > "$test_dir/file.txt"
result=$(tdirectory.getDirectories "$test_dir")
if [[ "$result" =~ "subdir" && ! "$result" =~ "file.txt" ]]; then
    test_pass "GetDirectories - excludes files"
else
    test_fail "GetDirectories - excludes files (expected only subdir)"
fi

# Test 4: GetDirectories empty directory
test_start "GetDirectories - empty directory"
test_dir="$temp_base/empty_dir"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getDirectories "$test_dir")
if [[ -z "$result" ]]; then
    test_pass "GetDirectories - empty directory"
else
    test_fail "GetDirectories - empty directory (expected empty result)"
fi

# Test 5: GetDirectories with SearchOption TopDirectoryOnly
test_start "GetDirectories - TopDirectoryOnly option"
test_dir="$temp_base/recursive_test"
tdirectory.createDirectory "$test_dir/level1"
tdirectory.createDirectory "$test_dir/level1/level2"
# Just get top-level directories (non-recursive)
result=$(tdirectory.getDirectories "$test_dir" "*" "TopDirectoryOnly")
if [[ "$result" =~ "level1" && ! "$result" =~ "level2" ]]; then
    test_pass "GetDirectories - TopDirectoryOnly option"
else
    test_fail "GetDirectories - TopDirectoryOnly option (expected only level1)"
fi

# Test 6: GetDirectories with SearchOption AllDirectories (recursive)
test_start "GetDirectories - AllDirectories recursive"
test_dir="$temp_base/recursive_all"
tdirectory.createDirectory "$test_dir/a/b/c"
tdirectory.createDirectory "$test_dir/x/y"
result=$(tdirectory.getDirectories "$test_dir" "*" "AllDirectories")
if [[ "$result" =~ "a" && "$result" =~ "b" && "$result" =~ "c" && "$result" =~ "x" && "$result" =~ "y" ]]; then
    test_pass "GetDirectories - AllDirectories recursive"
else
    test_fail "GetDirectories - AllDirectories recursive (expected all subdirs)"
fi

# Test 7: GetDirectories with special characters in names
test_start "GetDirectories - special characters in names"
test_dir="$temp_base/special_chars"
tdirectory.createDirectory "$test_dir/dir-with-dash"
tdirectory.createDirectory "$test_dir/dir_with_underscore"
tdirectory.createDirectory "$test_dir/dir.with.dots"
result=$(tdirectory.getDirectories "$test_dir")
if [[ "$result" =~ "dir-with-dash" && "$result" =~ "dir_with_underscore" && "$result" =~ "dir.with.dots" ]]; then
    test_pass "GetDirectories - special characters in names"
else
    test_fail "GetDirectories - special characters in names (expected all special char dirs)"
fi

# Cleanup
rm -rf "$temp_base" 2>/dev/null || true

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
