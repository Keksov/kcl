#!/bin/bash
# GetAttributes
#
# Rewritten for P3 (review 2026-09-06):
#   * the fixtures used to be created with FIXED names inside the REAL
#     `%TEMP%` (whatever tpath.getTempPath answered) and were removed only on
#     the happy path — two runs in parallel, or one aborted run, left a
#     chmod 000 directory behind in the user's temp. Everything now lives in
#     the per-test `_KT_TMPDIR` that ktests creates and removes.
#   * "regular file" asserted only "non-empty and not faDirectory"; each case
#     now compares the whole token list.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetAttributes" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"

temp_dir="$(cd "$(kt_fixture_tmpdir)" && pwd)"
test_file="$temp_dir/test_file.txt"
test_dir="$temp_dir/test_dir"
readonly_file="$temp_dir/readonly_file.txt"
hidden_file="$temp_dir/.hidden_file.txt"
denied_dir="$temp_dir/denied"

printf '%s\n' "test content" > "$test_file"
mkdir -p "$test_dir"
printf '%s\n' "readonly content" > "$readonly_file"
chmod 444 "$readonly_file"
printf '%s\n' "hidden content" > "$hidden_file"

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# Test 1: a plain writable file is exactly faNormal
eq "GetAttributes for regular file" "faNormal" "$(tpath.getAttributes "$test_file")"

# Test 2: a directory is exactly faDirectory
eq "GetAttributes for directory" "faDirectory" "$(tpath.getAttributes "$test_dir")"

# Test 3: a mode-444 file is faNormal,faReadOnly
eq "GetAttributes for read-only file" "faNormal,faReadOnly" \
   "$(tpath.getAttributes "$readonly_file")"

# Test 4: a dot-file is faNormal,faHidden
eq "GetAttributes for hidden file" "faNormal,faHidden" \
   "$(tpath.getAttributes "$hidden_file")"

# Test 5: a missing path is rc 1 + RESULT '' + no output (kcl/README.md 1.2)
kt_test_start "GetAttributes for non-existent file"
rc=0
out="$(tpath.getAttributes "$temp_dir/non_existent_file.txt" 2>&1)" || rc=$?
RESULT="__unset__"
tpath.getAttributes "$temp_dir/non_existent_file.txt" >/dev/null 2>&1 || :
if (( rc == 1 )) && [[ -z "$out" && -z "$RESULT" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc out='$out' RESULT='$RESULT'"
fi

# Test 6: an empty path is the same error
kt_test_start "GetAttributes with empty path"
rc=0
out="$(tpath.getAttributes "" 2>&1)" || rc=$?
RESULT="__unset__"
tpath.getAttributes "" >/dev/null 2>&1 || :
if (( rc == 1 )) && [[ -z "$out" && -z "$RESULT" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc out='$out' RESULT='$RESULT'"
fi

# Test 7: a directory whose permissions were taken away still answers
kt_test_start "GetAttributes for permission denied path"
mkdir -p "$denied_dir"
chmod 000 "$denied_dir"
result="$(tpath.getAttributes "$denied_dir" 2>/dev/null)" || result=""
chmod 755 "$denied_dir"
if [[ "$result" == faDirectory* ]]; then
    kt_test_pass "$result"
else
    kt_test_fail "expected a faDirectory token list, got '$result'"
fi

# Test 8: a NUL in the path can never name a file — rc 1, nothing printed
kt_test_start "GetAttributes with null bytes in path"
null_path="test$(printf '\0')file.txt"
RESULT="__unset__"
rc=0
result="$(tpath.getAttributes "$null_path" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$result" ]]; then
    kt_test_pass "rc 1, silent"
else
    kt_test_fail "rc=$rc result='$result'"
fi

# Test 9: the direct call is silent and answers through RESULT (decision D3)
kt_test_start "GetAttributes direct call is silent and sets RESULT [D3]"
out_file="$temp_dir/attrs.out"
: > "$out_file"
tpath.getAttributes "$test_dir" > "$out_file"
printed="$(<"$out_file")"
if [[ -z "$printed" && "$RESULT" == "faDirectory" ]]; then
    kt_test_pass "RESULT=$RESULT, nothing printed"
else
    kt_test_fail "printed='$printed' RESULT='$RESULT'"
fi

chmod u+w "$readonly_file" 2>/dev/null || true
