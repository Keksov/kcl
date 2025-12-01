#!/bin/bash
# GetLastAccessTimeUtc
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetLastAccessTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetLastAccessTimeUtc returns datetime
kt_test_start "GetLastAccessTimeUtc - returns datetime value"
test_dir="$_KT_TMPDIR/utc_access_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastAccessTimeUtc - returns datetime value"
else
    kt_test_fail "GetLastAccessTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastAccessTimeUtc on newly created directory
kt_test_start "GetLastAccessTimeUtc - newly created directory"
test_dir="$_KT_TMPDIR/utc_access_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastAccessTimeUtc - newly created directory"
else
    kt_test_fail "GetLastAccessTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastAccessTimeUtc consistency
kt_test_start "GetLastAccessTimeUtc - consistent results"
test_dir="$_KT_TMPDIR/utc_access_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastAccessTimeUtc "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kt_test_pass "GetLastAccessTimeUtc - consistent results"
else
    kt_test_fail "GetLastAccessTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetLastAccessTimeUtc on nested directory
kt_test_start "GetLastAccessTimeUtc - nested directory"
test_dir="$_KT_TMPDIR/utc/access/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastAccessTimeUtc - nested directory"
else
    kt_test_fail "GetLastAccessTimeUtc - nested directory (expected: valid datetime)"
fi

# Cleanup\nkt_fixture_teardown


