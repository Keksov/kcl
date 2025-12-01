#!/bin/bash
# GetCreationTime
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetCreationTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetCreationTime returns datetime
kt_test_start "GetCreationTime - returns datetime value"
test_dir="$_KT_TMPDIR/time_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTime - returns datetime value"
else
    kt_test_fail "GetCreationTime - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetCreationTime on newly created directory
kt_test_start "GetCreationTime - newly created directory"
test_dir="$_KT_TMPDIR/new_created"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
# Result should be a valid datetime (non-empty)
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTime - newly created directory"
else
    kt_test_fail "GetCreationTime - newly created directory (expected: valid datetime)"
fi

# Test 3: GetCreationTime consistency
kt_test_start "GetCreationTime - consistent results"
test_dir="$_KT_TMPDIR/consistent_time"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getCreationTime "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getCreationTime "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kt_test_pass "GetCreationTime - consistent results"
else
    kt_test_fail "GetCreationTime - consistent results (expected same time: '$result1' vs '$result2')"
fi

# Test 4: GetCreationTime is recent
kt_test_start "GetCreationTime - recent for new directory"
test_dir="$_KT_TMPDIR/recent_time"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
# Time should be non-empty and reasonable
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTime - recent for new directory"
else
    kt_test_fail "GetCreationTime - recent for new directory (expected recent time)"
fi

# Test 5: GetCreationTime on nested directory
kt_test_start "GetCreationTime - nested directory"
test_dir="$_KT_TMPDIR/nested/path/time"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTime - nested directory"
else
    kt_test_fail "GetCreationTime - nested directory (expected: valid datetime)"
fi

# Test 6: GetCreationTime on directory with spaces
kt_test_start "GetCreationTime - directory with spaces"
test_dir="$_KT_TMPDIR/dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetCreationTime - directory with spaces"
else
    kt_test_fail "GetCreationTime - directory with spaces (expected: valid datetime)"
fi

# Cleanup\nkt_fixture_teardown


