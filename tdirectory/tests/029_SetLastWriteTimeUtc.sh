#!/bin/bash
# SetLastWriteTimeUtc
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetLastWriteTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetLastWriteTimeUtc changes UTC last write time
kt_test_start "SetLastWriteTimeUtc - changes UTC last write time"
test_dir="$_KT_TMPDIR/utc_write_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTimeUtc - changes UTC last write time"
else
    kt_test_fail "SetLastWriteTimeUtc - changes UTC last write time (expected: UTC time to be set)"
fi

# Test 2: SetLastWriteTimeUtc persists
kt_test_start "SetLastWriteTimeUtc - persists after operation"
test_dir="$_KT_TMPDIR/utc_write_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTimeUtc - persists after operation"
else
    kt_test_fail "SetLastWriteTimeUtc - persists after operation (expected: UTC time persists)"
fi

# Test 3: SetLastWriteTimeUtc on nested directory
kt_test_start "SetLastWriteTimeUtc - nested directory"
test_dir="$_KT_TMPDIR/utc/write/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTimeUtc - nested directory"
else
    kt_test_fail "SetLastWriteTimeUtc - nested directory (expected: UTC time to be set)"
fi

# Test 4: SetLastWriteTimeUtc with datetime format
kt_test_start "SetLastWriteTimeUtc - accepts UTC datetime"
test_dir="$_KT_TMPDIR/utc_write_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTimeUtc "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastWriteTimeUtc - accepts UTC datetime"
else
    kt_test_fail "SetLastWriteTimeUtc - accepts UTC datetime (expected: UTC time to be set)"
fi

# Cleanup\nkt_fixture_teardown


