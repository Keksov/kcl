#!/bin/bash
# Exists
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Exists" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Existing directory
kt_test_start "Exists - existing directory returns true"
test_dir="$_KT_TMPDIR/existing"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Exists - existing directory returns true"
else
    kt_test_fail "Exists - existing directory returns true (expected: true, got: '$result')"
fi

# Test 2: Non-existent directory
kt_test_start "Exists - non-existent directory returns false"
test_dir="$_KT_TMPDIR/nonexistent"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "false" ]]; then
    kt_test_pass "Exists - non-existent directory returns false"
else
    kt_test_fail "Exists - non-existent directory returns false (expected: false, got: '$result')"
fi

# Test 3: File instead of directory
kt_test_start "Exists - file instead of directory returns false"
test_file="$_KT_TMPDIR/test_file.txt"
echo "content" > "$test_file"
result=$(tdirectory.exists "$test_file")
if [[ "$result" == "false" ]]; then
    kt_test_pass "Exists - file instead of directory returns false"
else
    kt_test_fail "Exists - file instead of directory returns false (expected: false, got: '$result')"
fi

# Test 4: Empty path
kt_test_start "Exists - empty path returns false"
result=$(tdirectory.exists "")
if [[ "$result" == "false" ]]; then
    kt_test_pass "Exists - empty path returns false"
else
    kt_test_fail "Exists - empty path returns false (expected: false, got: '$result')"
fi

# Test 5: Root directory exists
kt_test_start "Exists - root directory exists"
result=$(tdirectory.exists "/")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Exists - root directory exists"
else
    kt_test_fail "Exists - root directory exists (expected: true, got: '$result')"
fi

# Test 6: Directory with spaces
kt_test_start "Exists - directory with spaces"
test_dir="$_KT_TMPDIR/dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Exists - directory with spaces"
else
    kt_test_fail "Exists - directory with spaces (expected: true, got: '$result')"
fi

# Test 7: FollowLink parameter with true (default)
kt_test_start "Exists - FollowLink true with existing directory"
test_dir="$_KT_TMPDIR/followlink_true"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir" "true")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Exists - FollowLink true with existing directory"
else
    kt_test_fail "Exists - FollowLink true with existing directory (expected: true, got: '$result')"
fi

# Test 8: FollowLink parameter with false
kt_test_start "Exists - FollowLink false with existing directory"
test_dir="$_KT_TMPDIR/followlink_false"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir" "false")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Exists - FollowLink false with existing directory"
else
    kt_test_fail "Exists - FollowLink false with existing directory (expected: true, got: '$result')"
fi

# Test 9: Nested existing directory
kt_test_start "Exists - nested existing directory"
test_dir="$_KT_TMPDIR/nested/path/to/directory"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Exists - nested existing directory"
else
    kt_test_fail "Exists - nested existing directory (expected: true, got: '$result')"
fi

# Test 10: Directory after deletion
kt_test_start "Exists - deleted directory returns false"
test_dir="$_KT_TMPDIR/to_delete"
tdirectory.createDirectory "$test_dir"
tdirectory.delete "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "false" ]]; then
    kt_test_pass "Exists - deleted directory returns false"
else
    kt_test_fail "Exists - deleted directory returns false (expected: false after deletion, got: '$result')"
fi

# Cleanup\nkt_fixture_teardown


