#!/bin/bash
# Exists
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Exists" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Existing directory
kk_test_start "Exists - existing directory returns true"
test_dir="$KK_TEST_TMPDIR/existing"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Exists - existing directory returns true"
else
    kk_test_fail "Exists - existing directory returns true (expected: true, got: '$result')"
fi

# Test 2: Non-existent directory
kk_test_start "Exists - non-existent directory returns false"
test_dir="$KK_TEST_TMPDIR/nonexistent"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Exists - non-existent directory returns false"
else
    kk_test_fail "Exists - non-existent directory returns false (expected: false, got: '$result')"
fi

# Test 3: File instead of directory
kk_test_start "Exists - file instead of directory returns false"
test_file="$KK_TEST_TMPDIR/test_file.txt"
echo "content" > "$test_file"
result=$(tdirectory.exists "$test_file")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Exists - file instead of directory returns false"
else
    kk_test_fail "Exists - file instead of directory returns false (expected: false, got: '$result')"
fi

# Test 4: Empty path
kk_test_start "Exists - empty path returns false"
result=$(tdirectory.exists "")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Exists - empty path returns false"
else
    kk_test_fail "Exists - empty path returns false (expected: false, got: '$result')"
fi

# Test 5: Root directory exists
kk_test_start "Exists - root directory exists"
result=$(tdirectory.exists "/")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Exists - root directory exists"
else
    kk_test_fail "Exists - root directory exists (expected: true, got: '$result')"
fi

# Test 6: Directory with spaces
kk_test_start "Exists - directory with spaces"
test_dir="$KK_TEST_TMPDIR/dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Exists - directory with spaces"
else
    kk_test_fail "Exists - directory with spaces (expected: true, got: '$result')"
fi

# Test 7: FollowLink parameter with true (default)
kk_test_start "Exists - FollowLink true with existing directory"
test_dir="$KK_TEST_TMPDIR/followlink_true"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir" "true")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Exists - FollowLink true with existing directory"
else
    kk_test_fail "Exists - FollowLink true with existing directory (expected: true, got: '$result')"
fi

# Test 8: FollowLink parameter with false
kk_test_start "Exists - FollowLink false with existing directory"
test_dir="$KK_TEST_TMPDIR/followlink_false"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir" "false")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Exists - FollowLink false with existing directory"
else
    kk_test_fail "Exists - FollowLink false with existing directory (expected: true, got: '$result')"
fi

# Test 9: Nested existing directory
kk_test_start "Exists - nested existing directory"
test_dir="$KK_TEST_TMPDIR/nested/path/to/directory"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Exists - nested existing directory"
else
    kk_test_fail "Exists - nested existing directory (expected: true, got: '$result')"
fi

# Test 10: Directory after deletion
kk_test_start "Exists - deleted directory returns false"
test_dir="$KK_TEST_TMPDIR/to_delete"
tdirectory.createDirectory "$test_dir"
tdirectory.delete "$test_dir"
result=$(tdirectory.exists "$test_dir")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Exists - deleted directory returns false"
else
    kk_test_fail "Exists - deleted directory returns false (expected: false after deletion, got: '$result')"
fi

# Cleanup\nkk_fixture_teardown


