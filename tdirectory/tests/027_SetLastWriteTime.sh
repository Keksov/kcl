#!/bin/bash
# SetLastWriteTime
#
# Rewritten for P3 (review 2026-09-06, G6-08): every case here asserted only
# that the GETTER afterwards answered something NON-EMPTY, which a no-op
# setter satisfies just as well — and the *Utc setter really was storing a
# value shifted by the local UTC offset, because it formatted with
# `date -u … +%Y%m%d%H%M.%S` and then handed that to `touch -t`, which reads
# LOCAL time. Each case now reads the stored value back out of the filesystem.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetLastWriteTime" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

EPOCH=1700000000
OTHER=1600000000

# Test 1: an epoch argument is stored verbatim
kt_test_start "SetLastWriteTime - changes the write time"
test_dir="$_KT_TMPDIR/write_set_001"
tdirectory.createDirectory "$test_dir"
rc=0
tdirectory.setLastWriteTime "$test_dir" "$EPOCH" || rc=$?
stored="$(stat -c %Y "$test_dir")"
if (( rc == 0 )) && [[ "$stored" == "$EPOCH" ]]; then
    kt_test_pass "SetLastWriteTime - changes the write time ($stored)"
else
    kt_test_fail "SetLastWriteTime - changes the write time (rc=$rc stored=$stored, wanted $EPOCH)"
fi

# Test 2: the value survives a write INTO the directory... it does not: adding
# an entry is a directory modification, so the write time moves. Pin the real
# behaviour instead of "still non-empty".
kt_test_start "SetLastWriteTime - a new entry moves the directory's write time"
test_dir="$_KT_TMPDIR/write_persist"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTime "$test_dir" "$EPOCH" || :
printf 'file\n' > "$test_dir/file.txt"
stored="$(stat -c %Y "$test_dir")"
if [[ "$stored" != "$EPOCH" ]]; then
    kt_test_pass "SetLastWriteTime - a new entry moves the write time ($stored)"
else
    kt_test_fail "SetLastWriteTime - a new entry moves the write time (still $stored)"
fi

# Test 3: a nested directory is no different
kt_test_start "SetLastWriteTime - nested directory"
test_dir="$_KT_TMPDIR/write/nested/path"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTime "$test_dir" "$OTHER" || :
stored="$(stat -c %Y "$test_dir")"
if [[ "$stored" == "$OTHER" ]]; then
    kt_test_pass "SetLastWriteTime - nested directory ($stored)"
else
    kt_test_fail "SetLastWriteTime - nested directory (stored=$stored, wanted $OTHER)"
fi

# Test 4: a datetime string is read in the right zone (G6-08)
kt_test_start "SetLastWriteTime - accepts a datetime string"
test_dir="$_KT_TMPDIR/write_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTime "$test_dir" "2024-01-01 12:00:00" || :
stored="$(stat -c %Y "$test_dir")"
want="$(date -d '2024-01-01 12:00:00' +%s)"
if [[ "$stored" == "$want" ]]; then
    kt_test_pass "SetLastWriteTime - accepts a datetime string ($stored)"
else
    kt_test_fail "SetLastWriteTime - accepts a datetime string (stored=$stored, wanted $want)"
fi

# Test 5: the getter reads back exactly what was stored
kt_test_start "SetLastWriteTime - the getter reads it back"
tdirectory.setLastWriteTime "$test_dir" "$EPOCH" || :
got="$(tdirectory.getLastWriteTime "$test_dir")"
want="$(date -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S')"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "SetLastWriteTime - the getter reads it back ($got)"
else
    kt_test_fail "SetLastWriteTime - the getter reads it back (got '$got', wanted '$want')"
fi

# Test 6: a missing directory is rc 1, silent, and nothing is created
kt_test_start "SetLastWriteTime - missing directory"
rc=0
out="$(tdirectory.setLastWriteTime "$_KT_TMPDIR/nosuch" "$EPOCH" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$out" ]] && [[ ! -e "$_KT_TMPDIR/nosuch" ]]; then
    kt_test_pass "SetLastWriteTime - missing directory (rc 1, silent)"
else
    kt_test_fail "SetLastWriteTime - missing directory (rc=$rc out='$out')"
fi

# Cleanup
kt_fixture_teardown
