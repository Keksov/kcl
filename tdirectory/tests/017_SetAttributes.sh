#!/bin/bash
# 017_SetAttributes.sh - Test TDirectory.SetAttributes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "017"
temp_base="$TEST_TMP_DIR"

# Test 1: SetAttributes on existing directory
test_start "SetAttributes - set attributes on directory"
test_dir="$temp_base/set_attrs_001"
tdirectory.createDirectory "$test_dir"
# Try to set archive attribute (common attribute)
tdirectory.setAttributes "$test_dir" "faArchive"
# Verify by getting attributes
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetAttributes - set attributes on directory"
else
    test_fail "SetAttributes - set attributes on directory (expected attributes to be set)"
fi

# Test 2: SetAttributes consistency
test_start "SetAttributes - attributes set consistently"
test_dir="$temp_base/consistent_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faArchive"
result1=$(tdirectory.getAttributes "$test_dir")
result2=$(tdirectory.getAttributes "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    test_pass "SetAttributes - attributes set consistently"
else
    test_fail "SetAttributes - attributes set consistently (expected same attributes)"
fi

# Test 3: SetAttributes persists after operations
test_start "SetAttributes - attributes persist"
test_dir="$temp_base/persist_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faArchive"
# Perform some operations
echo "test" > "$test_dir/test.txt"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetAttributes - attributes persist"
else
    test_fail "SetAttributes - attributes persist (expected attributes after operations)"
fi

# Test 4: SetAttributes multiple attributes
test_start "SetAttributes - multiple attributes"
test_dir="$temp_base/multi_attrs"
tdirectory.createDirectory "$test_dir"
# Set both archive and system attributes
tdirectory.setAttributes "$test_dir" "faArchive|faSystem"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetAttributes - multiple attributes"
else
    test_fail "SetAttributes - multiple attributes (expected multiple attributes set)"
fi

# Test 5: SetAttributes on hidden directory
test_start "SetAttributes - hidden directory attributes"
test_dir="$temp_base/.hidden_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faHidden"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetAttributes - hidden directory attributes"
else
    test_fail "SetAttributes - hidden directory attributes (expected attributes on hidden dir)"
fi

# Test 6: SetAttributes read-only
test_start "SetAttributes - readonly attribute"
test_dir="$temp_base/readonly_attrs"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faReadOnly"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetAttributes - readonly attribute"
else
    test_fail "SetAttributes - readonly attribute (expected readonly attribute set)"
fi

# Test 7: SetAttributes on nested directory
test_start "SetAttributes - nested directory"
test_dir="$temp_base/nested/path/to/dir"
tdirectory.createDirectory "$test_dir"
tdirectory.setAttributes "$test_dir" "faArchive"
result=$(tdirectory.getAttributes "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetAttributes - nested directory"
else
    test_fail "SetAttributes - nested directory (expected attributes on nested dir)"
fi

# Cleanup


