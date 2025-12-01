#!/bin/bash
# GetLastAccessTime
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetLastAccessTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetLastAccessTime returns datetime
kt_test_start "GetLastAccessTime - returns datetime value"
test_dir="$_KT_TMPDIR/access_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastAccessTime - returns datetime value"
else
    kt_test_fail "GetLastAccessTime - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastAccessTime on newly created directory
kt_test_start "GetLastAccessTime - newly created directory"
test_dir="$_KT_TMPDIR/access_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastAccessTime - newly created directory"
else
    kt_test_fail "GetLastAccessTime - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastAccessTime consistency
kt_test_start "GetLastAccessTime - consistent results"
test_dir="$_KT_TMPDIR/access_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastAccessTime "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastAccessTime "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kt_test_pass "GetLastAccessTime - consistent results"
else
    kt_test_fail "GetLastAccessTime - consistent results (expected same time)"
fi

# Test 4: GetLastAccessTime on nested directory
kt_test_start "GetLastAccessTime - nested directory"
test_dir="$_KT_TMPDIR/access/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastAccessTime - nested directory"
else
    kt_test_fail "GetLastAccessTime - nested directory (expected: valid datetime)"
fi

# Test 5: GetLastAccessTime with spaces in path
kt_test_start "GetLastAccessTime - directory with spaces"
test_dir="$_KT_TMPDIR/access dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastAccessTime - directory with spaces"
else
    kt_test_fail "GetLastAccessTime - directory with spaces (expected: valid datetime)"
fi

# Cleanup\nkt_fixture_teardown


