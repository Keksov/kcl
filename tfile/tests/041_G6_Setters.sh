#!/bin/bash
# 041_G6_Setters.sh — review 2026-09-06, phase P3.
#
#   G6-07  tfile.set*Time and tfile.setAttributes were silent no-ops (`: ;`)
#          that answered rc 0, and tfile.getAttributes always answered the
#          literal "faNormal" — tdirectory implemented the same operations for
#          real. R13: one shared implementation, in tpath.
#   G6-08  the *Utc setters went through `date … +%Y%m%d%H%M.%S` and `touch -t`,
#          and `touch -t` reads LOCAL time: on this box (UTC+3)
#          setLastWriteTimeUtc f "2024-01-01 12:00:00" stored 09:00:00 UTC.
#   G6-26  tfile.getCreationTime had no `-1` fallback for filesystems that do
#          not record a birth time (tdirectory had one).
#   R13    creation time cannot be SET (POSIX has no API and Windows' is not
#          reachable through touch) -> rc 1, like .NET on Unix.
#
# Every assertion compares VALUES read back from the filesystem; the old tests
# 030-036 asserted `$? -eq 0` on a body that did nothing at all.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

kt_test_init "G6_Setters" "$SCRIPT_DIR" "$@"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"
F="$W/times.txt"
printf 'x\n' > "$F"

EPOCH=1700000000              # 2023-11-14 22:13:20 UTC
LOCAL_OF_EPOCH="$(date -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S')"
UTC_OF_EPOCH="$(date -u -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S')"

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# --- G6-07: setLastWriteTime actually moves mtime ---------------------------
kt_test_start "setLastWriteTime changes the file's mtime [G6-07]"
before="$(stat -c %Y "$F")"
tfile.setLastWriteTime "$F" "$EPOCH" || :
after="$(stat -c %Y "$F")"
if [[ "$after" == "$EPOCH" && "$after" != "$before" ]]; then
    kt_test_pass "mtime $before -> $after"
else
    kt_test_fail "mtime stayed $after (wanted $EPOCH)"
fi

eq "getLastWriteTime reads the value back in local time [G6-07]" \
   "$LOCAL_OF_EPOCH" "$(tfile.getLastWriteTime "$F")"
eq "getLastWriteTimeUtc reads the same instant in UTC [G6-07]" \
   "$UTC_OF_EPOCH" "$(tfile.getLastWriteTimeUtc "$F")"

# --- G6-08: the Utc setter stores UTC, not local ---------------------------
kt_test_start "setLastWriteTimeUtc stores the UTC instant it was given [G6-08]"
tfile.setLastWriteTimeUtc "$F" "2024-01-01 12:00:00" || :
got="$(tfile.getLastWriteTimeUtc "$F")"
if [[ "$got" == "2024-01-01 12:00:00" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "read back '$got' (the local-time round trip loses the TZ offset)"
fi

kt_test_start "the local setter stores the LOCAL instant it was given [G6-08]"
tfile.setLastWriteTime "$F" "2024-01-01 12:00:00" || :
got="$(tfile.getLastWriteTime "$F")"
if [[ "$got" == "2024-01-01 12:00:00" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "read back '$got'"
fi

kt_test_start "an epoch argument means the same instant in both setters [G6-08]"
tfile.setLastWriteTime "$F" "$EPOCH" || :
a="$(stat -c %Y "$F")"
tfile.setLastWriteTimeUtc "$F" "$EPOCH" || :
b="$(stat -c %Y "$F")"
if [[ "$a" == "$EPOCH" && "$b" == "$EPOCH" ]]; then
    kt_test_pass "both stored $EPOCH"
else
    kt_test_fail "local stored $a, utc stored $b"
fi

# --- G6-07: access time -----------------------------------------------------
kt_test_start "setLastAccessTime changes atime and leaves mtime alone [G6-07]"
tfile.setLastWriteTime "$F" "$EPOCH" || :
tfile.setLastAccessTime "$F" "1600000000" || :
read -r atime mtime <<< "$(stat -c '%X %Y' "$F")"
if [[ "$atime" == "1600000000" && "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "atime=$atime mtime=$mtime"
else
    kt_test_fail "atime=$atime mtime=$mtime"
fi

# NOTE on access time: NTFS rewrites a stored access time that is far in the
# past on the NEXT access, so only the read IMMEDIATELY after the touch is
# deterministic here (measured: `stat -c %X` right after the setter reports the
# value, a second access reports "now"). The atime assertions therefore check
# the value the setter stored, once; the FORMATTING of the getters is proven
# on mtime above, which is stable and goes through the same tpath._statTime.
kt_test_start "setLastAccessTimeUtc stores the UTC instant it was given [G6-08]"
tfile.setLastAccessTimeUtc "$F" "2024-01-01 12:00:00" || :
stored="$(stat -c %X "$F")"
want="$(date -u -d '2024-01-01 12:00:00' +%s)"
if [[ "$stored" == "$want" ]]; then
    kt_test_pass "stored $stored = 2024-01-01 12:00:00 UTC"
else
    kt_test_fail "stored $stored, expected $want (the local-time round trip loses the TZ offset)"
fi

kt_test_start "setLastAccessTime reads its argument as LOCAL time [G6-08]"
tfile.setLastAccessTime "$F" "2024-01-01 12:00:00" || :
stored="$(stat -c %X "$F")"
want="$(date -d '2024-01-01 12:00:00' +%s)"
if [[ "$stored" == "$want" ]]; then
    kt_test_pass "stored $stored = 2024-01-01 12:00:00 local"
else
    kt_test_fail "stored $stored, expected $want"
fi

kt_test_start "getLastAccessTime returns a well-formed timestamp [G6-07]"
got="$(tfile.getLastAccessTime "$F")"
if [[ "$got" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got '$got'"
fi

# --- R13: creation time cannot be set --------------------------------------
kt_test_start "setCreationTime answers rc 1 and changes nothing [R13]"
tfile.setLastWriteTime "$F" "$EPOCH" || :
rc=0
tfile.setCreationTime "$F" "2001-02-03 04:05:06" >/dev/null 2>&1 || rc=$?
mtime="$(stat -c %Y "$F")"
if (( rc == 1 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 1, mtime untouched"
else
    kt_test_fail "rc=$rc mtime=$mtime (wanted rc 1 and $EPOCH)"
fi

kt_test_start "setCreationTimeUtc answers rc 1 and changes nothing [R13]"
rc=0
tfile.setCreationTimeUtc "$F" "2001-02-03 04:05:06" >/dev/null 2>&1 || rc=$?
mtime="$(stat -c %Y "$F")"
if (( rc == 1 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 1, mtime untouched"
else
    kt_test_fail "rc=$rc mtime=$mtime"
fi

# --- G6-26: getCreationTime answers on a filesystem without a birth time ----
kt_test_start "getCreationTime answers a timestamp [G6-26]"
got="$(tfile.getCreationTime "$F")"
if [[ "$got" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "getCreationTime falls back to mtime when %W is -1 [G6-26]"
stat_calls="$W/stat_calls"
stat() {
    if [[ "$*" == *"%W"* ]]; then printf '%s\n' "-1"; return 0; fi
    command stat "$@"
}
tfile.setLastWriteTime "$F" "$EPOCH" || :
got="$(tfile.getCreationTime "$F")"
unset -f stat
if [[ "$got" == "$LOCAL_OF_EPOCH" ]]; then
    kt_test_pass "fell back to mtime: $got"
else
    kt_test_fail "got '$got', expected the mtime '$LOCAL_OF_EPOCH'"
fi

# --- the failure paths ------------------------------------------------------
for m in setLastWriteTime setLastWriteTimeUtc setLastAccessTime setLastAccessTimeUtc; do
    kt_test_start "$m on a missing file is rc 1 [1.2]"
    rc=0
    tfile.$m "$W/nosuch.txt" "$EPOCH" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )); then
        kt_test_pass "rc 1"
    else
        kt_test_fail "rc=$rc"
    fi
done

kt_test_start "setLastWriteTime with an unparsable time is rc 1 [1.2]"
tfile.setLastWriteTime "$F" "$EPOCH" || :
rc=0
tfile.setLastWriteTime "$F" "not-a-date" >/dev/null 2>&1 || rc=$?
mtime="$(stat -c %Y "$F")"
if (( rc == 1 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "rc 1, mtime untouched"
else
    kt_test_fail "rc=$rc mtime=$mtime"
fi

# --- G6-07: attributes are real --------------------------------------------
kt_test_start "setAttributes faReadOnly actually clears the write bit [G6-07]"
A="$W/attrs.txt"; printf 'a\n' > "$A"; chmod 644 "$A"
tfile.setAttributes "$A" "[faReadOnly]" || :
mode="$(stat -c %a "$A")"
if [[ "$mode" == "444" ]]; then
    kt_test_pass "mode $mode"
else
    kt_test_fail "mode $mode (wanted 444)"
fi

eq "getAttributes reports the read-only file [G6-07]" \
   "faNormal,faReadOnly" "$(tfile.getAttributes "$A")"

kt_test_start "setAttributes without faReadOnly restores the write bit [G6-07]"
tfile.setAttributes "$A" "[faArchive]" || :
mode="$(stat -c %a "$A")"
if [[ "$mode" == *"6"* || "$mode" == *"7"* ]]; then
    kt_test_pass "mode $mode"
else
    kt_test_fail "mode $mode is still not writable"
fi

eq "getAttributes reports a plain file as faNormal [G6-07]" \
   "faNormal" "$(tfile.getAttributes "$A")"

kt_test_start "getAttributes reports a dot-file as hidden [G6-07]"
H="$W/.hidden.txt"; printf 'h\n' > "$H"
got="$(tfile.getAttributes "$H")"
if [[ "$got" == *faHidden* ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "setAttributes on a missing file is rc 1 [1.2]"
rc=0
tfile.setAttributes "$W/nosuch.txt" "[faReadOnly]" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then
    kt_test_pass "rc 1"
else
    kt_test_fail "rc=$rc"
fi

chmod u+w "$A" 2>/dev/null || :
