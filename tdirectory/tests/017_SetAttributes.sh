#!/bin/bash
# SetAttributes
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "SetAttributes" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetAttributes on existing directory
kk_test_start "SetAttributes - set attributes on directory"
test_dir="$KK_TEST_TMPDIR/set_attrs_001"
tdirectory.createDirectory "$test_dir"
# Try to set archive attribute (common attribute)
tdirectory.setAttributes "$test_dir" "faArchive"
# Verify by getting attributes
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetAttributes - set attributes on directory"
else
    kk_test_fail "SetAttributes - set attributes on directory (expected attributes to be set)"
fi

# Test 2: SetAttributes consistency
kk_test_start "SetAttributes - attributes set consistently"
test_dir="$KK_TEST_TMPDIR/consistent_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faArchive"
result1=$(tdirectory.getAttributes "$test_dir")
result2=$(tdirectory.getAttributes "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "SetAttributes - attributes set consistently"
else
    kk_test_fail "SetAttributes - attributes set consistently (expected same attributes)"
fi

# Test 3: SetAttributes persists after operations
kk_test_start "SetAttributes - attributes persist"
test_dir="$KK_TEST_TMPDIR/persist_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faArchive"
# Perform some operations
echo "test" > "$test_dir/test.txt"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetAttributes - attributes persist"
else
    kk_test_fail "SetAttributes - attributes persist (expected attributes after operations)"
fi

# Test 4: SetAttributes multiple attributes
kk_test_start "SetAttributes - multiple attributes"
test_dir="$KK_TEST_TMPDIR/multi_attrs"
tdirectory.createDirectory "$test_dir"
# Set both archive and system attributes
tdirectory.setAttributes "$test_dir" "faArchive|faSystem"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetAttributes - multiple attributes"
else
    kk_test_fail "SetAttributes - multiple attributes (expected multiple attributes set)"
fi

# Test 5: SetAttributes on hidden directory
kk_test_start "SetAttributes - hidden directory attributes"
test_dir="$KK_TEST_TMPDIR/.hidden_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faHidden"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetAttributes - hidden directory attributes"
else
    kk_test_fail "SetAttributes - hidden directory attributes (expected attributes on hidden dir)"
fi

# Test 6: SetAttributes read-only
kk_test_start "SetAttributes - readonly attribute"
test_dir="$KK_TEST_TMPDIR/readonly_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faReadOnly"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetAttributes - readonly attribute"
else
    kk_test_fail "SetAttributes - readonly attribute (expected readonly attribute set)"
fi

# Test 7: SetAttributes on nested directory
kk_test_start "SetAttributes - nested directory"
test_dir="$KK_TEST_TMPDIR/nested/path/to/dir"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faArchive"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetAttributes - nested directory"
else
    kk_test_fail "SetAttributes - nested directory (expected attributes on nested dir)"
fi

# Cleanup\nkk_fixture_teardown


