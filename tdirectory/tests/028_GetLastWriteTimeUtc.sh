#!/bin/bash
# GetLastWriteTimeUtc
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetLastWriteTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetLastWriteTimeUtc returns datetime
kt_test_start "GetLastWriteTimeUtc - returns datetime value"
test_dir="$_KT_TMPDIR/utc_write_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - returns datetime value"
else
    kt_test_fail "GetLastWriteTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastWriteTimeUtc on newly created directory
kt_test_start "GetLastWriteTimeUtc - newly created directory"
test_dir="$_KT_TMPDIR/utc_write_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - newly created directory"
else
    kt_test_fail "GetLastWriteTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastWriteTimeUtc consistency
kt_test_start "GetLastWriteTimeUtc - consistent results"
test_dir="$_KT_TMPDIR/utc_write_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastWriteTimeUtc "$test_dir")
# Note: do not sleep between calls - filesystem metadata may be updated
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - consistent results"
else
    kt_test_fail "GetLastWriteTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetLastWriteTimeUtc on nested directory
kt_test_start "GetLastWriteTimeUtc - nested directory"
test_dir="$_KT_TMPDIR/utc/write/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - nested directory"
else
    kt_test_fail "GetLastWriteTimeUtc - nested directory (expected: valid datetime)"
fi

# Cleanup\nkt_fixture_teardown


