#!/bin/bash
# GetLastWriteTimeUtc
#
# Rewritten for P3 (review 2026-09-06, G6-08): every case asserted only that
# the answer was NON-EMPTY, which cannot distinguish a correct UTC timestamp
# from one shifted by the local offset — and that shift was the finding. Each
# case now compares the answer with the value the filesystem holds.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetLastWriteTimeUtc" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

EPOCH=1700000000

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# Test 1: the answer is the directory's mtime, formatted in UTC
test_dir="$_KT_TMPDIR/utc_write_001"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTime "$test_dir" "$EPOCH" || :
eq "GetLastWriteTimeUtc - returns the stored write time in UTC" \
   "$(date -u -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S')" \
   "$(tdirectory.getLastWriteTimeUtc "$test_dir")"

# Test 2: the UTC and local getters describe the SAME instant
kt_test_start "GetLastWriteTimeUtc - agrees with the local getter"
utc="$(tdirectory.getLastWriteTimeUtc "$test_dir")"
loc="$(tdirectory.getLastWriteTime "$test_dir")"
e_utc="$(date -u -d "$utc" +%s)"
e_loc="$(date -d "$loc" +%s)"
if [[ "$e_utc" == "$EPOCH" && "$e_loc" == "$EPOCH" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - agrees with the local getter ($utc / $loc)"
else
    kt_test_fail "GetLastWriteTimeUtc - utc='$utc' ($e_utc) local='$loc' ($e_loc), wanted $EPOCH"
fi

# Test 3: a newly created directory answers its real mtime
kt_test_start "GetLastWriteTimeUtc - newly created directory"
test_dir="$_KT_TMPDIR/utc_write_new"
tdirectory.createDirectory "$test_dir"
want="$(date -u -d "@$(stat -c %Y "$test_dir")" '+%Y-%m-%d %H:%M:%S')"
got="$(tdirectory.getLastWriteTimeUtc "$test_dir")"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - newly created directory ($got)"
else
    kt_test_fail "GetLastWriteTimeUtc - newly created directory (got '$got', wanted '$want')"
fi

# Test 4: the write time does not move between two reads
kt_test_start "GetLastWriteTimeUtc - consistent results"
result1=$(tdirectory.getLastWriteTimeUtc "$test_dir")
result2=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ "$result1" == "$result2" && -n "$result1" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - consistent results ($result1)"
else
    kt_test_fail "GetLastWriteTimeUtc - consistent results ('$result1' vs '$result2')"
fi

# Test 5: a nested directory is no different
test_dir="$_KT_TMPDIR/utc/write/nested/path"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTimeUtc "$test_dir" "2024-01-01 12:00:00" || :
eq "GetLastWriteTimeUtc - nested directory" \
   "2024-01-01 12:00:00" "$(tdirectory.getLastWriteTimeUtc "$test_dir")"

# Test 6: a missing directory is rc 1 with an empty RESULT (kcl/README.md 1.2)
kt_test_start "GetLastWriteTimeUtc - missing directory"
rc=0
out="$(tdirectory.getLastWriteTimeUtc "$_KT_TMPDIR/nosuch" 2>&1)" || rc=$?
RESULT="__unset__"
tdirectory.getLastWriteTimeUtc "$_KT_TMPDIR/nosuch" >/dev/null 2>&1 || :
if (( rc == 1 )) && [[ -z "$out" && -z "$RESULT" ]]; then
    kt_test_pass "GetLastWriteTimeUtc - missing directory (rc 1, silent)"
else
    kt_test_fail "GetLastWriteTimeUtc - missing directory (rc=$rc out='$out' RESULT='$RESULT')"
fi

# Cleanup
kt_fixture_teardown
