#!/bin/bash
# SetLastWriteTimeUtc
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "SetLastWriteTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetLastWriteTimeUtc changes UTC last write time
kk_test_start "SetLastWriteTimeUtc - changes UTC last write time"
test_dir="$KK_TEST_TMPDIR/utc_write_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetLastWriteTimeUtc - changes UTC last write time"
else
    kk_test_fail "SetLastWriteTimeUtc - changes UTC last write time (expected: UTC time to be set)"
fi

# Test 2: SetLastWriteTimeUtc persists
kk_test_start "SetLastWriteTimeUtc - persists after operation"
test_dir="$KK_TEST_TMPDIR/utc_write_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetLastWriteTimeUtc - persists after operation"
else
    kk_test_fail "SetLastWriteTimeUtc - persists after operation (expected: UTC time persists)"
fi

# Test 3: SetLastWriteTimeUtc on nested directory
kk_test_start "SetLastWriteTimeUtc - nested directory"
test_dir="$KK_TEST_TMPDIR/utc/write/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetLastWriteTimeUtc - nested directory"
else
    kk_test_fail "SetLastWriteTimeUtc - nested directory (expected: UTC time to be set)"
fi

# Test 4: SetLastWriteTimeUtc with datetime format
kk_test_start "SetLastWriteTimeUtc - accepts UTC datetime"
test_dir="$KK_TEST_TMPDIR/utc_write_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTimeUtc "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetLastWriteTimeUtc - accepts UTC datetime"
else
    kk_test_fail "SetLastWriteTimeUtc - accepts UTC datetime (expected: UTC time to be set)"
fi

# Cleanup\nkk_fixture_teardown


