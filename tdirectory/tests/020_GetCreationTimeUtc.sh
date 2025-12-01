#!/bin/bash
# GetCreationTimeUtc
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetCreationTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetCreationTimeUtc returns datetime
kt_test_start "GetCreationTimeUtc - returns datetime value"
test_dir="$_KT_TMPDIR/utc_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTimeUtc - returns datetime value"
else
    kt_test_fail "GetCreationTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetCreationTimeUtc on newly created directory
kt_test_start "GetCreationTimeUtc - newly created directory"
test_dir="$_KT_TMPDIR/utc_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTimeUtc - newly created directory"
else
    kt_test_fail "GetCreationTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetCreationTimeUtc consistency
kt_test_start "GetCreationTimeUtc - consistent results"
test_dir="$_KT_TMPDIR/utc_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getCreationTimeUtc "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kt_test_pass "GetCreationTimeUtc - consistent results"
else
    kt_test_fail "GetCreationTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetCreationTimeUtc on nested directory
kt_test_start "GetCreationTimeUtc - nested directory"
test_dir="$_KT_TMPDIR/utc/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTimeUtc - nested directory"
else
    kt_test_fail "GetCreationTimeUtc - nested directory (expected: valid datetime)"
fi

# Test 5: GetCreationTimeUtc with spaces in path
kt_test_start "GetCreationTimeUtc - directory with spaces"
test_dir="$_KT_TMPDIR/utc dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTimeUtc - directory with spaces"
else
    kt_test_fail "GetCreationTimeUtc - directory with spaces (expected: valid datetime)"
fi

# Cleanup\nkt_fixture_teardown


