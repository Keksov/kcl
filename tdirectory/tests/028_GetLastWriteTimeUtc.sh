#!/bin/bash
# GetLastWriteTimeUtc
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetLastWriteTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetLastWriteTimeUtc returns datetime
kk_test_start "GetLastWriteTimeUtc - returns datetime value"
test_dir="$KK_TEST_TMPDIR/utc_write_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastWriteTimeUtc - returns datetime value"
else
    kk_test_fail "GetLastWriteTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastWriteTimeUtc on newly created directory
kk_test_start "GetLastWriteTimeUtc - newly created directory"
test_dir="$KK_TEST_TMPDIR/utc_write_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastWriteTimeUtc - newly created directory"
else
    kk_test_fail "GetLastWriteTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastWriteTimeUtc consistency
kk_test_start "GetLastWriteTimeUtc - consistent results"
test_dir="$KK_TEST_TMPDIR/utc_write_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastWriteTimeUtc "$test_dir")
# Note: do not sleep between calls - filesystem metadata may be updated
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "GetLastWriteTimeUtc - consistent results"
else
    kk_test_fail "GetLastWriteTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetLastWriteTimeUtc on nested directory
kk_test_start "GetLastWriteTimeUtc - nested directory"
test_dir="$KK_TEST_TMPDIR/utc/write/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastWriteTimeUtc - nested directory"
else
    kk_test_fail "GetLastWriteTimeUtc - nested directory (expected: valid datetime)"
fi

# Cleanup\nkk_fixture_teardown


