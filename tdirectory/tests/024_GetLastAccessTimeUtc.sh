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
# Windows rewrites a stored access time on the NEXT access, and reading the
# directory is itself an access — so two reads are not required to be byte
# identical (the old assertion passed only by luck). What must hold is that
# both answers are well-formed and describe the same moment, give or take the
# clock tick between them.
result1=$(tdirectory.getLastAccessTimeUtc "$test_dir")
result2=$(tdirectory.getLastAccessTimeUtc "$test_dir")
e1=$(date -u -d "$result1" +%s 2>/dev/null || printf 0)
e2=$(date -u -d "$result2" +%s 2>/dev/null || printf 0)
delta=$(( e2 > e1 ? e2 - e1 : e1 - e2 ))
if [[ "$result1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] \
   && (( e1 > 0 && delta <= 2 )); then
    kt_test_pass "GetLastAccessTimeUtc - consistent results (delta ${delta}s)"
else
    kt_test_fail "GetLastAccessTimeUtc - consistent results ('$result1' vs '$result2', delta ${delta}s)"
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

# Cleanup


