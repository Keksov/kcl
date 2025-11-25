#!/bin/bash
# GetAttributes
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetAttributes" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Setup temp directory
init_test_tmpdir "016"
temp_base="$TEST_TMP_DIR"

# Test 1: GetAttributes on existing directory
kk_test_start "GetAttributes - existing directory returns attributes"
test_dir="$temp_base/test_dir"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir" || true)
if [[ -n "$result" ]]; then
    kk_test_pass "GetAttributes - existing directory returns attributes"
else
    kk_test_fail "GetAttributes - existing directory returns attributes (expected: non-empty)"
fi

# Test 2: GetAttributes includes directory attribute
kk_test_start "GetAttributes - includes directory attribute"
test_dir="$temp_base/dir_test"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir" || true)
if [[ "$result" =~ "faDirectory" ]]; then
    kk_test_pass "GetAttributes - includes directory attribute"
else
    kk_test_fail "GetAttributes - includes directory attribute (expected faDirectory, got: '$result')"
fi

# Test 3: GetAttributes with FollowLink true
kk_test_start "GetAttributes - FollowLink true"
test_dir="$temp_base/follow_link_true"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir" "true" || true)
if [[ -n "$result" ]]; then
    kk_test_pass "GetAttributes - FollowLink true"
else
    kk_test_fail "GetAttributes - FollowLink true (expected: non-empty)"
fi

# Test 4: GetAttributes with FollowLink false
kk_test_start "GetAttributes - FollowLink false"
test_dir="$temp_base/follow_link_false"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir" "false" || true)
if [[ -n "$result" ]]; then
    kk_test_pass "GetAttributes - FollowLink false"
else
    kk_test_fail "GetAttributes - FollowLink false (expected: non-empty)"
fi

# Test 5: GetAttributes for non-existent directory
kk_test_start "GetAttributes - non-existent directory"
test_dir="$temp_base/nonexistent_attrs"
result=$(tdirectory.getAttributes "$test_dir" 2>/dev/null || true)
# Should either return empty or error
if [[ -z "$result" ]]; then
    kk_test_pass "GetAttributes - non-existent directory"
else
    kk_test_fail "GetAttributes - non-existent directory (expected empty or error)"
fi

# Test 6: GetAttributes for hidden directory
kk_test_start "GetAttributes - hidden directory"
test_dir="$temp_base/.hidden_dir"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getAttributes "$test_dir" || true)
if [[ -n "$result" ]]; then
    kk_test_pass "GetAttributes - hidden directory"
else
    kk_test_fail "GetAttributes - hidden directory (expected: non-empty)"
fi

# Test 7: GetAttributes consistency
kk_test_start "GetAttributes - consistent results"
test_dir="$temp_base/consistency_test"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getAttributes "$test_dir" || true)
result2=$(tdirectory.getAttributes "$test_dir" || true)
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "GetAttributes - consistent results"
else
    kk_test_fail "GetAttributes - consistent results (expected same results)"
fi

# Test 8: GetAttributes after directory creation
kk_test_start "GetAttributes - after creation"
test_dir="$temp_base/after_create"
tdirectory.createDirectory "$test_dir"
sleep 1  # Small delay to ensure attributes are set
result=$(tdirectory.getAttributes "$test_dir" || true)
if [[ -n "$result" ]]; then
    kk_test_pass "GetAttributes - after creation"
else
    kk_test_fail "GetAttributes - after creation (expected: non-empty after creation)"
fi

# Cleanup


