#!/bin/bash
# 036_SetLastWriteTimeUtc.sh - Test TFile.SetLastWriteTimeUtc method
#
# Rewritten for P3 (review 2026-09-06, G6-07/G6-08): tfile.set*Time was a
# silent no-op that answered rc 0, and this file asserted $? -eq 0 on it — an
# assertion the no-op could not fail. Every case now reads the stored value
# back out of the filesystem with `stat`, which is the only thing that can
# tell a working setter from a no-op.
#
# The write time is the stable one: it is not rewritten by a read.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

F="$_KT_TMPDIR/setter.tmp"
printf '%s\n' "content" > "$F"
EPOCH=1700000000
OTHER=1600000000

# Test 1: an epoch argument is stored verbatim
kt_test_start "SetLastWriteTimeUtc stores an epoch argument"
rc=0
tfile.setLastWriteTimeUtc "$F" "$EPOCH" || rc=$?
stored="$(stat -c '%Y' "$F")"
if (( rc == 0 )) && [[ "$stored" == "$EPOCH" ]]; then
    kt_test_pass "SetLastWriteTimeUtc stores an epoch argument ($stored)"
else
    kt_test_fail "SetLastWriteTimeUtc stores an epoch argument (rc=$rc stored=$stored, wanted $EPOCH)"
fi

# Test 2: a datetime string is read in the right zone (G6-08)
kt_test_start "SetLastWriteTimeUtc reads a datetime string as UTC"
rc=0
tfile.setLastWriteTimeUtc "$F" "2024-01-01 12:00:00" || rc=$?
stored="$(stat -c '%Y' "$F")"
want="$(date -u -d '2024-01-01 12:00:00' +%s)"
if (( rc == 0 )) && [[ "$stored" == "$want" ]]; then
    kt_test_pass "SetLastWriteTimeUtc reads a datetime string ($stored)"
else
    kt_test_fail "SetLastWriteTimeUtc reads a datetime string (rc=$rc stored=$stored, wanted $want)"
fi

# Test 3: a second call really moves the value (a no-op would keep it)
kt_test_start "SetLastWriteTimeUtc moves the value on a second call"
tfile.setLastWriteTimeUtc "$F" "$OTHER" || :
stored="$(stat -c '%Y' "$F")"
if [[ "$stored" == "$OTHER" ]]; then
    kt_test_pass "SetLastWriteTimeUtc moves the value on a second call ($stored)"
else
    kt_test_fail "SetLastWriteTimeUtc moves the value on a second call (stored=$stored, wanted $OTHER)"
fi

# Test 4: the getter reads back exactly what was stored
kt_test_start "getLastWriteTimeUtc reads the stored value back"
tfile.setLastWriteTimeUtc "$F" "$EPOCH" || :
got="$(tfile.getLastWriteTimeUtc "$F")"
want="$(date -u -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S')"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "getLastWriteTimeUtc reads the stored value back ($got)"
else
    kt_test_fail "getLastWriteTimeUtc reads the stored value back (got '$got', wanted '$want')"
fi

# Test 5: a missing file is rc 1, silent, and creates nothing
kt_test_start "SetLastWriteTimeUtc on non-existing file"
rc=0
out="$(tfile.setLastWriteTimeUtc "$_KT_TMPDIR/nonexist.tmp" "$EPOCH" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$out" ]] && [[ ! -e "$_KT_TMPDIR/nonexist.tmp" ]]; then
    kt_test_pass "SetLastWriteTimeUtc on non-existing file (rc 1, silent)"
else
    kt_test_fail "SetLastWriteTimeUtc on non-existing file (rc=$rc out='$out')"
fi

# Test 6: an unparsable time is rc 1 and leaves the value alone
kt_test_start "SetLastWriteTimeUtc rejects an unparsable time"
tfile.setLastWriteTimeUtc "$F" "$EPOCH" || :
rc=0
tfile.setLastWriteTimeUtc "$F" "not-a-date" >/dev/null 2>&1 || rc=$?
stored="$(stat -c '%Y' "$F")"
if (( rc == 1 )) && [[ "$stored" == "$EPOCH" ]]; then
    kt_test_pass "SetLastWriteTimeUtc rejects an unparsable time (rc 1, value untouched)"
else
    kt_test_fail "SetLastWriteTimeUtc rejects an unparsable time (rc=$rc stored=$stored)"
fi
