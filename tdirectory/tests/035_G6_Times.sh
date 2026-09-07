#!/bin/bash
# 035_G6_Times.sh — review 2026-09-06, phase P3.
#
#   G6-08  the *Utc setters formatted the value with `date -u … +%Y%m%d%H%M.%S`
#          and then handed it to `touch -t`, which reads LOCAL time: on this
#          box (UTC+3) setLastWriteTimeUtc d "2024-01-01 12:00:00" stored
#          09:00:00 UTC. setCreationTime mapped to `-m`, i.e. it silently set
#          the WRITE time instead. Everything now goes through an epoch and
#          `touch -d @epoch` (R13, shared with tfile through tpath).
#   R13    a creation time cannot be SET — rc 1, as .NET does on Unix.
#
# The old tests 027-029 asserted only that the GETTER answered something
# non-empty afterwards, which a no-op setter also satisfies.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G6_Times" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
source "$TDIRECTORY_DIR/tdirectory.sh"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"
D="$W/times"
mkdir -p "$D"

EPOCH=1700000000
OTHER=1600000000

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# --- the write time round-trips exactly ------------------------------------
kt_test_start "setLastWriteTime stores the epoch it was given [G6-08]"
tdirectory.setLastWriteTime "$D" "$EPOCH" || :
stored="$(stat -c %Y "$D")"
if [[ "$stored" == "$EPOCH" ]]; then
    kt_test_pass "$stored"
else
    kt_test_fail "stored $stored, wanted $EPOCH"
fi

eq "getLastWriteTime formats it in local time [G6-08]" \
   "$(date -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S')" "$(tdirectory.getLastWriteTime "$D")"
eq "getLastWriteTimeUtc formats the same instant in UTC [G6-08]" \
   "$(date -u -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S')" "$(tdirectory.getLastWriteTimeUtc "$D")"

kt_test_start "setLastWriteTimeUtc reads its argument as UTC [G6-08]"
tdirectory.setLastWriteTimeUtc "$D" "2024-01-01 12:00:00" || :
got="$(tdirectory.getLastWriteTimeUtc "$D")"
if [[ "$got" == "2024-01-01 12:00:00" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "read back '$got' — the local-time round trip loses the TZ offset"
fi

kt_test_start "setLastWriteTime reads its argument as LOCAL time [G6-08]"
tdirectory.setLastWriteTime "$D" "2024-01-01 12:00:00" || :
got="$(tdirectory.getLastWriteTime "$D")"
if [[ "$got" == "2024-01-01 12:00:00" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "read back '$got'"
fi

kt_test_start "the two setters agree when they are given an epoch [G6-08]"
tdirectory.setLastWriteTime "$D" "$EPOCH" || :
a="$(stat -c %Y "$D")"
tdirectory.setLastWriteTimeUtc "$D" "$EPOCH" || :
b="$(stat -c %Y "$D")"
if [[ "$a" == "$EPOCH" && "$b" == "$EPOCH" ]]; then
    kt_test_pass "both $EPOCH"
else
    kt_test_fail "local $a, utc $b"
fi

# --- the access time --------------------------------------------------------
# A DIRECTORY's access time is not a witness on this filesystem: Windows
# rewrites a stored access time that is far in the past on the next access,
# and enumerating a directory counts as one. What is deterministic — and what
# the finding is actually about — is that the `-a` setter succeeds and does
# NOT move the write time, while the `-m` setter does.
kt_test_start "setLastAccessTime succeeds and leaves the write time alone [G6-08]"
tdirectory.setLastWriteTime "$D" "$EPOCH" || :
rc=0
tdirectory.setLastAccessTime "$D" "$OTHER" || rc=$?
mtime="$(stat -c %Y "$D")"
if (( rc == 0 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 0, mtime still $mtime"
else
    kt_test_fail "rc=$rc mtime=$mtime (wanted $EPOCH)"
fi

kt_test_start "setLastAccessTimeUtc succeeds and leaves the write time alone [G6-08]"
rc=0
tdirectory.setLastAccessTimeUtc "$D" "2024-01-01 12:00:00" || rc=$?
mtime="$(stat -c %Y "$D")"
if (( rc == 0 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 0, mtime still $mtime"
else
    kt_test_fail "rc=$rc mtime=$mtime"
fi

# --- R13: the creation time is not settable --------------------------------
kt_test_start "setCreationTime is rc 1 and does not touch the write time [R13, G6-08]"
tdirectory.setLastWriteTime "$D" "$EPOCH" || :
rc=0
out="$(tdirectory.setCreationTime "$D" "2001-02-03 04:05:06" 2>&1)" || rc=$?
mtime="$(stat -c %Y "$D")"
if (( rc == 1 )) && [[ -z "$out" && "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 1, silent, mtime untouched"
else
    kt_test_fail "rc=$rc out='$out' mtime=$mtime (the old body mapped this to touch -m)"
fi

kt_test_start "setCreationTimeUtc is rc 1 and does not touch the write time [R13]"
rc=0
tdirectory.setCreationTimeUtc "$D" "2001-02-03 04:05:06" >/dev/null 2>&1 || rc=$?
mtime="$(stat -c %Y "$D")"
if (( rc == 1 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 1, mtime untouched"
else
    kt_test_fail "rc=$rc mtime=$mtime"
fi

kt_test_start "getCreationTime still answers a well-formed timestamp [G6-26]"
got="$(tdirectory.getCreationTime "$D")"
if [[ "$got" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got '$got'"
fi

# --- the failure paths -----------------------------------------------------
for m in setLastWriteTime setLastWriteTimeUtc setLastAccessTime setLastAccessTimeUtc; do
    kt_test_start "$m on a missing directory is rc 1 and creates nothing [1.2]"
    rc=0
    tdirectory.$m "$W/nosuch" "$EPOCH" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ ! -e "$W/nosuch" ]]; then
        kt_test_pass "rc 1"
    else
        kt_test_fail "rc=$rc"
    fi
done

kt_test_start "a setter refuses an unparsable time and touches nothing [1.2]"
tdirectory.setLastWriteTime "$D" "$EPOCH" || :
rc=0
tdirectory.setLastWriteTime "$D" "not-a-date" >/dev/null 2>&1 || rc=$?
mtime="$(stat -c %Y "$D")"
if (( rc == 1 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 1, mtime untouched"
else
    kt_test_fail "rc=$rc mtime=$mtime"
fi

for m in getLastWriteTime getLastWriteTimeUtc getLastAccessTime getLastAccessTimeUtc getCreationTime; do
    kt_test_start "$m on a missing directory is rc 1 and RESULT empty [1.2]"
    RESULT="__unset__"
    rc=0
    tdirectory.$m "$W/nosuch" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "rc 1, RESULT empty"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
done

# --- attributes -------------------------------------------------------------
# NOTE: `chmod` on a DIRECTORY is a no-op on this MSYS/NTFS box (measured:
# `chmod a-w d` returns 0 and the mode stays 755, while the same call on a
# FILE gives 444). So the read-only bit of a directory is not something a test
# can force here; what IS pinned is that setAttributes reports honestly and
# that getAttributes describes the mode the filesystem actually holds.
kt_test_start "setAttributes on a directory answers rc 0 [G6-07]"
A="$W/attrs"
mkdir -p "$A"
rc=0
tdirectory.setAttributes "$A" "faReadOnly" || rc=$?
if (( rc == 0 )); then
    kt_test_pass "rc 0"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "getAttributes matches the mode the filesystem reports [G6-07]"
mode="$(stat -c %a "$A")"
owner="${mode: -3:1}"
if (( (8#$owner & 2) == 0 )); then
    want="faDirectory,faReadOnly"
else
    want="faDirectory"
fi
got="$(tdirectory.getAttributes "$A")"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "mode $mode -> $got"
else
    kt_test_fail "mode $mode gave '$got', expected '$want'"
fi

kt_test_start "setAttributes without faReadOnly answers rc 0 and keeps it writable [G6-07]"
rc=0
tdirectory.setAttributes "$A" "faArchive" || rc=$?
if (( rc == 0 )) && [[ -w "$A" ]]; then
    kt_test_pass "rc 0, writable (mode $(stat -c %a "$A"))"
else
    kt_test_fail "rc=$rc writable=$([[ -w "$A" ]] && echo yes || echo no)"
fi

eq "getAttributes reports a plain directory [G6-07]" \
   "faDirectory" "$(tdirectory.getAttributes "$A")"

kt_test_start "getAttributes DOES see a read-only FILE (the same helper) [G6-07]"
RO="$W/ro.txt"
: > "$RO"
chmod 444 "$RO"
got="$(tdirectory.getAttributes "$RO")"
chmod u+w "$RO"
if [[ "$got" == "faNormal,faReadOnly" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "setAttributes on a missing directory is rc 1 [1.2]"
rc=0
tdirectory.setAttributes "$W/nosuch" "faReadOnly" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then
    kt_test_pass "rc 1"
else
    kt_test_fail "rc=$rc"
fi
