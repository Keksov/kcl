#!/bin/bash
# 030_set_attributes.sh - Test TFile.SetAttributes method
#
# Rewritten for P3 (review 2026-09-06, G6-07): the body used to be a silent
# no-op (`if [[ ! -e "$1" ]]; then return 1; fi; :`) and this file asserted
# `$? -eq 0` on it — an assertion the no-op could not fail. Every case now
# reads the resulting mode back.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

F="$_KT_TMPDIR/setattr.tmp"
printf '%s\n' "content" > "$F"
chmod 644 "$F"

# Test 1: faReadOnly clears every write bit
kt_test_start "Set attributes on existing file"
rc=0
tfile.setAttributes "$F" "[faReadOnly]" || rc=$?
mode="$(stat -c %a "$F")"
if (( rc == 0 )) && [[ "$mode" == "444" ]] && [[ ! -w "$F" ]]; then
    kt_test_pass "Set attributes on existing file (mode $mode)"
else
    kt_test_fail "Set attributes on existing file (rc=$rc mode=$mode)"
fi

# Test 2: getAttributes agrees with what was just set
kt_test_start "Attributes read back as faReadOnly"
attrs="$(tfile.getAttributes "$F")"
if [[ "$attrs" == "faNormal,faReadOnly" ]]; then
    kt_test_pass "Attributes read back as faReadOnly"
else
    kt_test_fail "Attributes read back as faReadOnly (got '$attrs')"
fi

# Test 3: any other token list restores the owner write bit
kt_test_start "Clearing faReadOnly makes the file writable again"
rc=0
tfile.setAttributes "$F" "[faArchive]" || rc=$?
mode="$(stat -c %a "$F")"
if (( rc == 0 )) && [[ -w "$F" ]]; then
    kt_test_pass "Clearing faReadOnly makes the file writable again (mode $mode)"
else
    kt_test_fail "Clearing faReadOnly (rc=$rc mode=$mode)"
fi

# Test 4: a missing file is rc 1 and nothing is created
kt_test_start "Set attributes on non-existing file"
rc=0
out="$(tfile.setAttributes "$_KT_TMPDIR/nonexist.tmp" "[faReadOnly]" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$out" ]] && [[ ! -e "$_KT_TMPDIR/nonexist.tmp" ]]; then
    kt_test_pass "Set attributes on non-existing file (rc 1, silent)"
else
    kt_test_fail "Set attributes on non-existing file (rc=$rc out='$out')"
fi

# Test 5: a directory is not a TFile subject
kt_test_start "Set attributes on a directory is rc 1"
mkdir -p "$_KT_TMPDIR/attr_dir"
rc=0
tfile.setAttributes "$_KT_TMPDIR/attr_dir" "[faReadOnly]" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then
    kt_test_pass "Set attributes on a directory is rc 1"
else
    kt_test_fail "Set attributes on a directory (rc=$rc)"
fi

chmod u+w "$F" 2>/dev/null || :
