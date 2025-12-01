#!/bin/bash
# GetLastWriteTime
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetLastWriteTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetLastWriteTime returns datetime
kt_test_start "GetLastWriteTime - returns datetime value"
test_dir="$_KT_TMPDIR/write_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastWriteTime - returns datetime value"
else
    kt_test_fail "GetLastWriteTime - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastWriteTime on newly created directory
kt_test_start "GetLastWriteTime - newly created directory"
test_dir="$_KT_TMPDIR/write_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastWriteTime - newly created directory"
else
    kt_test_fail "GetLastWriteTime - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastWriteTime consistency
kt_test_start "GetLastWriteTime - consistent results"
test_dir="$_KT_TMPDIR/write_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastWriteTime "$test_dir")
# Note: do not sleep between calls - filesystem metadata may be updated
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastWriteTime "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kt_test_pass "GetLastWriteTime - consistent results"
else
    kt_test_fail "GetLastWriteTime - consistent results (expected same time)"
fi

# Test 4: GetLastWriteTime on nested directory
kt_test_start "GetLastWriteTime - nested directory"
test_dir="$_KT_TMPDIR/write/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastWriteTime - nested directory"
else
    kt_test_fail "GetLastWriteTime - nested directory (expected: valid datetime)"
fi

# Test 5: GetLastWriteTime with spaces in path
kt_test_start "GetLastWriteTime - directory with spaces"
test_dir="$_KT_TMPDIR/write dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    kt_test_pass "GetLastWriteTime - directory with spaces"
else
    kt_test_fail "GetLastWriteTime - directory with spaces (expected: valid datetime)"
fi

# Cleanup\nkt_fixture_teardown


