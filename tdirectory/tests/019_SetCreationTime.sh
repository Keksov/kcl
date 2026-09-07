#!/bin/bash
# SetCreationTime
#
# Rewritten for P3 (review 2026-09-06, G6-08 / R13): the body mapped this to
# `touch -m`, i.e. it silently set the WRITE time and answered rc 0, and this
# file asserted only that the GETTER afterwards was non-empty — which a no-op
# satisfies too. A creation time cannot be SET here (POSIX has no API and
# Windows' is not reachable through touch), so the member answers rc 1, the
# way .NET's Directory.SetCreationTime does on Unix. What the file pins is
# that it fails CLEANLY.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetCreationTime" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

EPOCH=1700000000

# Test 1: an epoch argument is refused, silently, and the write time does not move
kt_test_start "SetCreationTime - refuses an epoch and touches nothing"
test_dir="$_KT_TMPDIR/creation_set_001"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTime "$test_dir" "$EPOCH" || :
rc=0
out="$(tdirectory.setCreationTime "$test_dir" "$EPOCH" 2>&1)" || rc=$?
mtime="$(stat -c %Y "$test_dir")"
if (( rc == 1 )) && [[ -z "$out" && "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "SetCreationTime - rc 1, silent, write time untouched"
else
    kt_test_fail "SetCreationTime - rc=$rc out='$out' mtime=$mtime (the old body set the WRITE time here)"
fi

# Test 2: a datetime string is refused the same way
kt_test_start "SetCreationTime - refuses a datetime string"
rc=0
tdirectory.setCreationTime "$test_dir" "2001-02-03 04:05:06" >/dev/null 2>&1 || rc=$?
mtime="$(stat -c %Y "$test_dir")"
if (( rc == 1 )) && [[ "$mtime" == "$EPOCH" ]]; then
    kt_test_pass "SetCreationTime - rc 1, write time untouched"
else
    kt_test_fail "SetCreationTime - rc=$rc mtime=$mtime"
fi

# Test 3: RESULT is empty on the failure path (kcl/README.md 1.2)
kt_test_start "SetCreationTime - leaves RESULT empty"
RESULT="__unset__"
tdirectory.setCreationTime "$test_dir" "$EPOCH" >/dev/null 2>&1 || :
if [[ -z "$RESULT" ]]; then
    kt_test_pass "SetCreationTime - RESULT empty"
else
    kt_test_fail "SetCreationTime - RESULT='$RESULT'"
fi

# Test 4: a missing directory is the same rc 1, and nothing is created
kt_test_start "SetCreationTime - missing directory"
rc=0
tdirectory.setCreationTime "$_KT_TMPDIR/nosuch" "$EPOCH" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ ! -e "$_KT_TMPDIR/nosuch" ]]; then
    kt_test_pass "SetCreationTime - rc 1, nothing created"
else
    kt_test_fail "SetCreationTime - rc=$rc"
fi

# Test 5: the GETTER still answers a well-formed timestamp
kt_test_start "SetCreationTime - the getter still answers"
got="$(tdirectory.getCreationTime "$test_dir")"
if [[ "$got" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    kt_test_pass "SetCreationTime - the getter still answers ($got)"
else
    kt_test_fail "SetCreationTime - the getter answered '$got'"
fi

# Cleanup
kt_fixture_teardown
