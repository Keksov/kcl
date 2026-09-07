#!/bin/bash
# 027_read_all_lines.sh - Test TFile.ReadAllLines method
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# _KT_TMPDIR is already set by kt_test_init; re-assigning it (and then using it
# unquoted) was pointless and hid the fact that the fixture is per-test.

# Test 1: Read lines from existing file
kt_test_start "Read lines from existing file"
printf 'line1\nline2\nline3\n' > "$_KT_TMPDIR/readlines.tmp"
lines=$(tfile.readAllLines "$_KT_TMPDIR/readlines.tmp")
if [[ "$lines" == $'line1\nline2\nline3' ]]; then
    kt_test_pass "Read lines from existing file"
else
    kt_test_fail "Read lines from existing file (got: $(printf '%q' "$lines"))"
fi

# Test 2: the second argument is an OUTPUT ARRAY name, not an encoding.
# This port has no TEncoding; the old test passed the literal
# "TEncoding.UTF8" and asserted that the call still worked, which pinned a
# parameter the implementation never had. Since P3 the second argument fills a
# caller array (kcl/README.md 1.7) and a name that is not an identifier is a
# malformed CALL: rc 2, nothing written.
kt_test_start "Read lines into a caller array"
declare -a read_lines=()
rc=0
tfile.readAllLines "$_KT_TMPDIR/readlines.tmp" read_lines || rc=$?
if (( rc == 0 )) && (( ${#read_lines[@]} == 3 )) && [[ "${read_lines[1]}" == "line2" ]]; then
    kt_test_pass "Read lines into a caller array"
else
    kt_test_fail "rc=$rc n=${#read_lines[@]} lines=(${read_lines[*]})"
fi

kt_test_start "A non-identifier output name is rejected with rc 2"
rc=0
tfile.readAllLines "$_KT_TMPDIR/readlines.tmp" "TEncoding.UTF8" >/dev/null 2>&1 || rc=$?
if (( rc == 2 )); then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc (wanted 2)"
fi

# Test 3: Read lines from empty file
kt_test_start "Read lines from empty file"
touch "$_KT_TMPDIR/empty_lines.tmp"
lines=$(tfile.readAllLines "$_KT_TMPDIR/empty_lines.tmp")
if [[ -z "$lines" ]]; then
    kt_test_pass "Read lines from empty file"
else
    kt_test_fail "Read lines from empty file"
fi

# Test 4: Read lines from non-existing file
kt_test_start "Read lines from non-existing file"
if ! lines=$(tfile.readAllLines "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Read lines from non-existing file (correctly failed)"
else
    kt_test_fail "Read lines from non-existing file (should have failed)"
fi
