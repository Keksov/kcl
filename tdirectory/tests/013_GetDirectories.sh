#!/bin/bash
# GetDirectories
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetDirectories" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetDirectories with simple directory
kt_test_start "GetDirectories - basic subdirectory listing"
test_dir="$_KT_TMPDIR/simple"
tdirectory.createDirectory "$test_dir/sub1"
tdirectory.createDirectory "$test_dir/sub2"
tdirectory.createDirectory "$test_dir/sub3"
result=$(tdirectory.getDirectories "$test_dir")
if [[ "$result" =~ "sub1" && "$result" =~ "sub2" && "$result" =~ "sub3" ]]; then
    kt_test_pass "GetDirectories - basic subdirectory listing"
else
    kt_test_fail "GetDirectories - basic subdirectory listing (expected subdirs in output)"
fi

# Test 2: GetDirectories with search pattern
kt_test_start "GetDirectories - with search pattern"
test_dir="$_KT_TMPDIR/pattern_test"
tdirectory.createDirectory "$test_dir/app_001"
tdirectory.createDirectory "$test_dir/app_002"
tdirectory.createDirectory "$test_dir/other_dir"
result=$(tdirectory.getDirectories "$test_dir" "*app*")
if [[ "$result" =~ "app_001" && "$result" =~ "app_002" && ! "$result" =~ "other_dir" ]]; then
    kt_test_pass "GetDirectories - with search pattern"
else
    kt_test_fail "GetDirectories - with search pattern (expected only app* dirs)"
fi

# Test 3: GetDirectories with files present (should exclude files)
kt_test_start "GetDirectories - excludes files"
test_dir="$_KT_TMPDIR/mixed_content"
tdirectory.createDirectory "$test_dir/subdir"
echo "file content" > "$test_dir/file.txt"
result=$(tdirectory.getDirectories "$test_dir")
if [[ "$result" =~ "subdir" && ! "$result" =~ "file.txt" ]]; then
    kt_test_pass "GetDirectories - excludes files"
else
    kt_test_fail "GetDirectories - excludes files (expected only subdir)"
fi

# Test 4: GetDirectories empty directory
kt_test_start "GetDirectories - empty directory"
test_dir="$_KT_TMPDIR/empty_dir"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getDirectories "$test_dir")
if [[ -z "$result" ]]; then
    kt_test_pass "GetDirectories - empty directory"
else
    kt_test_fail "GetDirectories - empty directory (expected empty result)"
fi

# Test 5: GetDirectories with SearchOption TopDirectoryOnly
kt_test_start "GetDirectories - TopDirectoryOnly option"
test_dir="$_KT_TMPDIR/recursive_test"
tdirectory.createDirectory "$test_dir/level1"
tdirectory.createDirectory "$test_dir/level1/level2"
# Just get top-level directories (non-recursive)
result=$(tdirectory.getDirectories "$test_dir" "*" "TopDirectoryOnly")
if [[ "$result" =~ "level1" && ! "$result" =~ "level2" ]]; then
    kt_test_pass "GetDirectories - TopDirectoryOnly option"
else
    kt_test_fail "GetDirectories - TopDirectoryOnly option (expected only level1)"
fi

# Test 6: GetDirectories with SearchOption AllDirectories (recursive)
kt_test_start "GetDirectories - AllDirectories recursive"
test_dir="$_KT_TMPDIR/recursive_all"
tdirectory.createDirectory "$test_dir/a/b/c"
tdirectory.createDirectory "$test_dir/x/y"
result=$(tdirectory.getDirectories "$test_dir" "*" "AllDirectories")
if [[ "$result" =~ "a" && "$result" =~ "b" && "$result" =~ "c" && "$result" =~ "x" && "$result" =~ "y" ]]; then
    kt_test_pass "GetDirectories - AllDirectories recursive"
else
    kt_test_fail "GetDirectories - AllDirectories recursive (expected all subdirs)"
fi

# Test 7: GetDirectories with special characters in names
kt_test_start "GetDirectories - special characters in names"
test_dir="$_KT_TMPDIR/special_chars"
tdirectory.createDirectory "$test_dir/dir-with-dash"
tdirectory.createDirectory "$test_dir/dir_with_underscore"
tdirectory.createDirectory "$test_dir/dir.with.dots"
result=$(tdirectory.getDirectories "$test_dir")
if [[ "$result" =~ "dir-with-dash" && "$result" =~ "dir_with_underscore" && "$result" =~ "dir.with.dots" ]]; then
    kt_test_pass "GetDirectories - special characters in names"
else
    kt_test_fail "GetDirectories - special characters in names (expected all special char dirs)"
fi

# Cleanup\nkt_fixture_teardown


