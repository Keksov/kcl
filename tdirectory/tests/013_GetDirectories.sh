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

tdirectory_test_expect_lines() {
    local test_name="$1"
    local actual="$2"
    shift 2

    local expected=""
    local expected_line
    for expected_line in "$@"; do
        if [[ -n "$expected" ]]; then
            expected+=$'\n'
        fi
        expected+="$expected_line"
    done

    if [[ "$actual" == "$expected" ]]; then
        kt_test_pass "$test_name"
    else
        kt_test_fail "$test_name (expected exact result: '$expected', got: '$actual')"
    fi
}

# Test 1: GetDirectories with simple directory
kt_test_start "GetDirectories - basic subdirectory listing"
test_dir="$_KT_TMPDIR/simple"
tdirectory.createDirectory "$test_dir/sub1"
tdirectory.createDirectory "$test_dir/sub2"
tdirectory.createDirectory "$test_dir/sub3"
result=$(tdirectory.getDirectories "$test_dir")
tdirectory_test_expect_lines "GetDirectories - basic subdirectory listing" "$result" "$test_dir/sub1" "$test_dir/sub2" "$test_dir/sub3"

# Test 2: GetDirectories with search pattern
kt_test_start "GetDirectories - with search pattern"
test_dir="$_KT_TMPDIR/pattern_test"
tdirectory.createDirectory "$test_dir/app_001"
tdirectory.createDirectory "$test_dir/app_002"
tdirectory.createDirectory "$test_dir/other_dir"
result=$(tdirectory.getDirectories "$test_dir" "*app*")
tdirectory_test_expect_lines "GetDirectories - with search pattern" "$result" "$test_dir/app_001" "$test_dir/app_002"

# Test 3: GetDirectories with files present (should exclude files)
kt_test_start "GetDirectories - excludes files"
test_dir="$_KT_TMPDIR/mixed_content"
tdirectory.createDirectory "$test_dir/subdir"
echo "file content" > "$test_dir/file.txt"
result=$(tdirectory.getDirectories "$test_dir")
tdirectory_test_expect_lines "GetDirectories - excludes files" "$result" "$test_dir/subdir"

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
tdirectory_test_expect_lines "GetDirectories - TopDirectoryOnly option" "$result" "$test_dir/level1"

# Test 6: GetDirectories with SearchOption AllDirectories (recursive)
kt_test_start "GetDirectories - AllDirectories recursive"
test_dir="$_KT_TMPDIR/recursive_all"
tdirectory.createDirectory "$test_dir/a/b/c"
tdirectory.createDirectory "$test_dir/x/y"
result=$(tdirectory.getDirectories "$test_dir" "*" "AllDirectories")
tdirectory_test_expect_lines "GetDirectories - AllDirectories recursive" "$result" "$test_dir/a" "$test_dir/a/b" "$test_dir/a/b/c" "$test_dir/x" "$test_dir/x/y"

# Test 7: GetDirectories with special characters in names
kt_test_start "GetDirectories - special characters in names"
test_dir="$_KT_TMPDIR/special_chars"
tdirectory.createDirectory "$test_dir/dir-with-dash"
tdirectory.createDirectory "$test_dir/dir_with_underscore"
tdirectory.createDirectory "$test_dir/dir.with.dots"
result=$(tdirectory.getDirectories "$test_dir")
tdirectory_test_expect_lines "GetDirectories - special characters in names" "$result" "$test_dir/dir.with.dots" "$test_dir/dir_with_underscore" "$test_dir/dir-with-dash"

# Cleanup\nkt_fixture_teardown


