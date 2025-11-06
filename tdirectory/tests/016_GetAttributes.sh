#!/bin/bash
# 016_GetAttributes.sh - Test TDirectory.GetAttributes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
temp_base="$(tpath.getTempPath)/tdirectory_test_$$"
tdirectory.createDirectory "$temp_base"

# Test 1: GetAttributes on existing directory
test_start "GetAttributes - existing directory returns attributes"
test_dir="$temp_base/test_dir"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetAttributes - existing directory returns attributes"
else
    test_fail "GetAttributes - existing directory returns attributes (expected: non-empty)"
fi

# Test 2: GetAttributes includes directory attribute
test_start "GetAttributes - includes directory attribute"
test_dir="$temp_base/dir_test"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir")
if [[ "$result" =~ "Directory" ]] || [[ "$result" =~ "oDirectory" ]] || [[ "$result" =~ "D" ]]; then
    test_pass "GetAttributes - includes directory attribute"
else
    test_fail "GetAttributes - includes directory attribute (expected Directory info, got: '$result')"
fi

# Test 3: GetAttributes with FollowLink true
test_start "GetAttributes - FollowLink true"
test_dir="$temp_base/follow_link_true"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir" "true")
if [[ -n "$result" ]]; then
    test_pass "GetAttributes - FollowLink true"
else
    test_fail "GetAttributes - FollowLink true (expected: non-empty)"
fi

# Test 4: GetAttributes with FollowLink false
test_start "GetAttributes - FollowLink false"
test_dir="$temp_base/follow_link_false"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir" "false")
if [[ -n "$result" ]]; then
    test_pass "GetAttributes - FollowLink false"
else
    test_fail "GetAttributes - FollowLink false (expected: non-empty)"
fi

# Test 5: GetAttributes for non-existent directory
test_start "GetAttributes - non-existent directory"
test_dir="$temp_base/nonexistent_attrs"
result=$(tdirectory.getAttributes "$test_dir" 2>/dev/null)
# Should either return empty or error
if [[ -z "$result" ]]; then
    test_pass "GetAttributes - non-existent directory"
else
    test_fail "GetAttributes - non-existent directory (expected empty or error)"
fi

# Test 6: GetAttributes for hidden directory
test_start "GetAttributes - hidden directory"
test_dir="$temp_base/.hidden_dir"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetAttributes - hidden directory"
else
    test_fail "GetAttributes - hidden directory (expected: non-empty)"
fi

# Test 7: GetAttributes consistency
test_start "GetAttributes - consistent results"
test_dir="$temp_base/consistency_test"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getAttributes "$test_dir")
result2=$(tdirectory.getAttributes "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetAttributes - consistent results"
else
    test_fail "GetAttributes - consistent results (expected same results)"
fi

# Test 8: GetAttributes after directory creation
test_start "GetAttributes - after creation"
test_dir="$temp_base/after_create"
tdirectory.createDirectory "$test_dir"
sleep 1  # Small delay to ensure attributes are set
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetAttributes - after creation"
else
    test_fail "GetAttributes - after creation (expected: non-empty after creation)"
fi

# Cleanup
rm -rf "$temp_base" 2>/dev/null || true

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
