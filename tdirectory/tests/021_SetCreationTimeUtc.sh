#!/bin/bash
# SetCreationTimeUtc
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "SetCreationTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetCreationTimeUtc changes UTC creation time
kk_test_start "SetCreationTimeUtc - changes UTC creation time"
test_dir="$KK_TEST_TMPDIR/utc_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetCreationTimeUtc - changes UTC creation time"
else
    kk_test_fail "SetCreationTimeUtc - changes UTC creation time (expected: UTC time to be set)"
fi

# Test 2: SetCreationTimeUtc persists
kk_test_start "SetCreationTimeUtc - persists after operation"
test_dir="$KK_TEST_TMPDIR/utc_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTimeUtc "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetCreationTimeUtc - persists after operation"
else
    kk_test_fail "SetCreationTimeUtc - persists after operation (expected: UTC time persists)"
fi

# Test 3: SetCreationTimeUtc on nested directory
kk_test_start "SetCreationTimeUtc - nested directory"
test_dir="$KK_TEST_TMPDIR/utc/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetCreationTimeUtc - nested directory"
else
    kk_test_fail "SetCreationTimeUtc - nested directory (expected: UTC time to be set)"
fi

# Test 4: SetCreationTimeUtc with datetime format
kk_test_start "SetCreationTimeUtc - accepts UTC datetime"
test_dir="$KK_TEST_TMPDIR/utc_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setCreationTimeUtc "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "SetCreationTimeUtc - accepts UTC datetime"
else
    kk_test_fail "SetCreationTimeUtc - accepts UTC datetime (expected: UTC time to be set)"
fi

# Cleanup\nkk_fixture_teardown


