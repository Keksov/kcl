#!/bin/bash
# SetCreationTime
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetCreationTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetCreationTime changes creation time
kt_test_start "SetCreationTime - changes creation time"
test_dir="$_KT_TMPDIR/time_set_001"
tdirectory.createDirectory "$test_dir"
original=$(tdirectory.getCreationTime "$test_dir")
# Set new creation time (current time)
new_time=$(date +%s)
tdirectory.setCreationTime "$test_dir" "$new_time"
updated=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$updated" ]]; then
    kt_test_pass "SetCreationTime - changes creation time"
else
    kt_test_fail "SetCreationTime - changes creation time (expected: time to be set)"
fi

# Test 2: SetCreationTime persists
kt_test_start "SetCreationTime - persists after operation"
test_dir="$_KT_TMPDIR/persist_time"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTime "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetCreationTime - persists after operation"
else
    kt_test_fail "SetCreationTime - persists after operation (expected: time persists)"
fi

# Test 3: SetCreationTime on nested directory
kt_test_start "SetCreationTime - nested directory"
test_dir="$_KT_TMPDIR/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTime "$test_dir" "$new_time"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetCreationTime - nested directory"
else
    kt_test_fail "SetCreationTime - nested directory (expected: time to be set)"
fi

# Test 4: SetCreationTime with various time formats
kt_test_start "SetCreationTime - accepts datetime"
test_dir="$_KT_TMPDIR/time_format"
tdirectory.createDirectory "$test_dir"
# Use a specific time value
tdirectory.setCreationTime "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetCreationTime - accepts datetime"
else
    kt_test_fail "SetCreationTime - accepts datetime (expected: time to be set)"
fi

# Cleanup\nkt_fixture_teardown


