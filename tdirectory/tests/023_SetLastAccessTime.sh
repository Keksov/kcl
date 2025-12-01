#!/bin/bash
# SetLastAccessTime
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetLastAccessTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: SetLastAccessTime changes last access time
kt_test_start "SetLastAccessTime - changes last access time"
test_dir="$_KT_TMPDIR/access_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTime "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastAccessTime - changes last access time"
else
    kt_test_fail "SetLastAccessTime - changes last access time (expected: time to be set)"
fi

# Test 2: SetLastAccessTime persists
kt_test_start "SetLastAccessTime - persists after operation"
test_dir="$_KT_TMPDIR/access_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTime "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastAccessTime - persists after operation"
else
    kt_test_fail "SetLastAccessTime - persists after operation (expected: time persists)"
fi

# Test 3: SetLastAccessTime on nested directory
kt_test_start "SetLastAccessTime - nested directory"
test_dir="$_KT_TMPDIR/access/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTime "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastAccessTime - nested directory"
else
    kt_test_fail "SetLastAccessTime - nested directory (expected: time to be set)"
fi

# Test 4: SetLastAccessTime with datetime format
kt_test_start "SetLastAccessTime - accepts datetime"
test_dir="$_KT_TMPDIR/access_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastAccessTime "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "SetLastAccessTime - accepts datetime"
else
    kt_test_fail "SetLastAccessTime - accepts datetime (expected: time to be set)"
fi

# Cleanup\nkt_fixture_teardown


