#!/bin/bash
# GetCreationTimeUtc
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetCreationTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Setup temp directory
init_test_tmpdir "020"
temp_base="$TEST_TMP_DIR"

# Test 1: GetCreationTimeUtc returns datetime
kk_test_start "GetCreationTimeUtc - returns datetime value"
test_dir="$temp_base/utc_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetCreationTimeUtc - returns datetime value"
else
    kk_test_fail "GetCreationTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetCreationTimeUtc on newly created directory
kk_test_start "GetCreationTimeUtc - newly created directory"
test_dir="$temp_base/utc_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetCreationTimeUtc - newly created directory"
else
    kk_test_fail "GetCreationTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetCreationTimeUtc consistency
kk_test_start "GetCreationTimeUtc - consistent results"
test_dir="$temp_base/utc_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getCreationTimeUtc "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "GetCreationTimeUtc - consistent results"
else
    kk_test_fail "GetCreationTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetCreationTimeUtc on nested directory
kk_test_start "GetCreationTimeUtc - nested directory"
test_dir="$temp_base/utc/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetCreationTimeUtc - nested directory"
else
    kk_test_fail "GetCreationTimeUtc - nested directory (expected: valid datetime)"
fi

# Test 5: GetCreationTimeUtc with spaces in path
kk_test_start "GetCreationTimeUtc - directory with spaces"
test_dir="$temp_base/utc dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetCreationTimeUtc - directory with spaces"
else
    kk_test_fail "GetCreationTimeUtc - directory with spaces (expected: valid datetime)"
fi

# Cleanup


