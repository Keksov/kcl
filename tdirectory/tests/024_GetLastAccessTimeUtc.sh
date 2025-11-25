#!/bin/bash
# GetLastAccessTimeUtc
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetLastAccessTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Setup temp directory
init_test_tmpdir "024"
temp_base="$TEST_TMP_DIR"

# Test 1: GetLastAccessTimeUtc returns datetime
kk_test_start "GetLastAccessTimeUtc - returns datetime value"
test_dir="$temp_base/utc_access_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastAccessTimeUtc - returns datetime value"
else
    kk_test_fail "GetLastAccessTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastAccessTimeUtc on newly created directory
kk_test_start "GetLastAccessTimeUtc - newly created directory"
test_dir="$temp_base/utc_access_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastAccessTimeUtc - newly created directory"
else
    kk_test_fail "GetLastAccessTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastAccessTimeUtc consistency
kk_test_start "GetLastAccessTimeUtc - consistent results"
test_dir="$temp_base/utc_access_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastAccessTimeUtc "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "GetLastAccessTimeUtc - consistent results"
else
    kk_test_fail "GetLastAccessTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetLastAccessTimeUtc on nested directory
kk_test_start "GetLastAccessTimeUtc - nested directory"
test_dir="$temp_base/utc/access/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastAccessTimeUtc - nested directory"
else
    kk_test_fail "GetLastAccessTimeUtc - nested directory (expected: valid datetime)"
fi

# Cleanup


