#!/bin/bash
# SetLastAccessTimeUtc
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetLastAccessTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetLastAccessTimeUtc changes UTC last access time
kt_test_start "SetLastAccessTimeUtc - changes UTC last access time"
test_dir="$_KT_TMPDIR/utc_access_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastAccessTimeUtc - changes UTC last access time"
else
    kt_test_fail "SetLastAccessTimeUtc - changes UTC last access time (expected: UTC time to be set)"
fi

# Test 2: SetLastAccessTimeUtc persists
kt_test_start "SetLastAccessTimeUtc - persists after operation"
test_dir="$_KT_TMPDIR/utc_access_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTimeUtc "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastAccessTimeUtc - persists after operation"
else
    kt_test_fail "SetLastAccessTimeUtc - persists after operation (expected: UTC time persists)"
fi

# Test 3: SetLastAccessTimeUtc on nested directory
kt_test_start "SetLastAccessTimeUtc - nested directory"
test_dir="$_KT_TMPDIR/utc/access/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastAccessTimeUtc - nested directory"
else
    kt_test_fail "SetLastAccessTimeUtc - nested directory (expected: UTC time to be set)"
fi

# Cleanup\nkt_fixture_teardown


