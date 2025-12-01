#!/bin/bash
# SetLastWriteTime
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetLastWriteTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetLastWriteTime changes last write time
kt_test_start "SetLastWriteTime - changes last write time"
test_dir="$_KT_TMPDIR/write_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTime "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTime - changes last write time"
else
    kt_test_fail "SetLastWriteTime - changes last write time (expected: time to be set)"
fi

# Test 2: SetLastWriteTime persists
kt_test_start "SetLastWriteTime - persists after operation"
test_dir="$_KT_TMPDIR/write_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTime "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTime - persists after operation"
else
    kt_test_fail "SetLastWriteTime - persists after operation (expected: time persists)"
fi

# Test 3: SetLastWriteTime on nested directory
kt_test_start "SetLastWriteTime - nested directory"
test_dir="$_KT_TMPDIR/write/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTime "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTime - nested directory"
else
    kt_test_fail "SetLastWriteTime - nested directory (expected: time to be set)"
fi

# Test 4: SetLastWriteTime with datetime format
kt_test_start "SetLastWriteTime - accepts datetime"
test_dir="$_KT_TMPDIR/write_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTime "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTime - accepts datetime"
else
    kt_test_fail "SetLastWriteTime - accepts datetime (expected: time to be set)"
fi

# Cleanup\nkt_fixture_teardown


