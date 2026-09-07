#!/bin/bash
# 031_set_creation_time.sh - Test TFile.SetCreationTime method
#
# Rewritten for P3 (review 2026-09-06, G6-07 / R13): the body was a silent
# no-op that answered rc 0, and this file asserted $? -eq 0 on it. A creation
# time cannot be SET here — POSIX has no API for it and Windows' is not
# reachable through touch — so the member answers rc 1, the way .NET's
# File.SetCreationTime does on Unix. What the file now pins is that it fails
# CLEANLY: rc 1, nothing printed, no timestamp of the file disturbed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

F="$_KT_TMPDIR/setcreate.tmp"
printf '%s\n' "content" > "$F"
EPOCH=1700000000
tfile.setLastWriteTime "$F" "$EPOCH" || :
tfile.setLastAccessTime "$F" "$EPOCH" || :

# Test 1: an epoch argument is refused, silently, and changes nothing
kt_test_start "Set creation time on existing file"
rc=0
out="$(tfile.setCreationTime "$F" "$EPOCH" 2>&1)" || rc=$?
read -r atime mtime <<< "$(stat -c '%X %Y' "$F")"
if (( rc == 1 )) && [[ -z "$out" ]] && [[ "$mtime" == "$EPOCH" && "$atime" == "$EPOCH" ]]; then
    kt_test_pass "Set creation time on existing file (rc 1, timestamps untouched)"
else
    kt_test_fail "Set creation time (rc=$rc out='$out' atime=$atime mtime=$mtime)"
fi

# Test 2: a date string is refused the same way
kt_test_start "Set creation time with a datetime string"
rc=0
tfile.setCreationTime "$F" "2001-02-03 04:05:06" >/dev/null 2>&1 || rc=$?
mtime="$(stat -c %Y "$F")"
if (( rc == 1 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "Set creation time with a datetime string (rc 1, mtime untouched)"
else
    kt_test_fail "Set creation time with a datetime string (rc=$rc mtime=$mtime)"
fi

# Test 3: a missing file is the same rc 1, and nothing is created
kt_test_start "Set creation time on non-existing file"
rc=0
tfile.setCreationTime "$_KT_TMPDIR/nonexist.tmp" "$EPOCH" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ ! -e "$_KT_TMPDIR/nonexist.tmp" ]]; then
    kt_test_pass "Set creation time on non-existing file (rc 1)"
else
    kt_test_fail "Set creation time on non-existing file (rc=$rc)"
fi

# Test 4: RESULT is empty on the failure path (kcl/README.md 1.2)
kt_test_start "Set creation time leaves RESULT empty"
RESULT="__unset__"
tfile.setCreationTime "$F" "$EPOCH" >/dev/null 2>&1 || :
if [[ -z "$RESULT" ]]; then
    kt_test_pass "Set creation time leaves RESULT empty"
else
    kt_test_fail "RESULT='$RESULT'"
fi

# Test 5: the getter still works — only the setter is unavailable
kt_test_start "Get creation time still answers"
got="$(tfile.getCreationTime "$F")"
if [[ "$got" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    kt_test_pass "Get creation time still answers ($got)"
else
    kt_test_fail "Get creation time still answers (got '$got')"
fi
