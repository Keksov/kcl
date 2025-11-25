#!/bin/bash
# GetLastAccessTime
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetLastAccessTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Setup temp directory
init_test_tmpdir "022"
temp_base="$TEST_TMP_DIR"

# Test 1: GetLastAccessTime returns datetime
kk_test_start "GetLastAccessTime - returns datetime value"
test_dir="$temp_base/access_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastAccessTime - returns datetime value"
else
    kk_test_fail "GetLastAccessTime - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastAccessTime on newly created directory
kk_test_start "GetLastAccessTime - newly created directory"
test_dir="$temp_base/access_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastAccessTime - newly created directory"
else
    kk_test_fail "GetLastAccessTime - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastAccessTime consistency
kk_test_start "GetLastAccessTime - consistent results"
test_dir="$temp_base/access_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastAccessTime "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastAccessTime "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "GetLastAccessTime - consistent results"
else
    kk_test_fail "GetLastAccessTime - consistent results (expected same time)"
fi

# Test 4: GetLastAccessTime on nested directory
kk_test_start "GetLastAccessTime - nested directory"
test_dir="$temp_base/access/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastAccessTime - nested directory"
else
    kk_test_fail "GetLastAccessTime - nested directory (expected: valid datetime)"
fi

# Test 5: GetLastAccessTime with spaces in path
kk_test_start "GetLastAccessTime - directory with spaces"
test_dir="$temp_base/access dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    kk_test_pass "GetLastAccessTime - directory with spaces"
else
    kk_test_fail "GetLastAccessTime - directory with spaces (expected: valid datetime)"
fi

# Cleanup


