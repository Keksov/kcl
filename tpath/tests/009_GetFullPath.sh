#!/bin/bash
# GetFullPath
#
# Rewritten for P3 (review 2026-09-06): every case here used to assert only
# "non-empty" or "not the input", which passes on the failure path too — and
# the failure path was real (G6-13: plain `realpath` answers nothing when an
# intermediate component is missing, and the old body then echoed the RAW
# relative input). Each case now compares the whole answer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetFullPath" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# Test 1: a relative path becomes the working directory plus the path
kt_test_start "Convert relative path to absolute"
cd "$TMP" || exit 1
mkdir -p sub
result=$(tpath.getFullPath "sub")
if [[ "$result" == "$TMP/sub" ]]; then
    kt_test_pass "Convert relative path to absolute"
else
    kt_test_fail "Convert relative path to absolute (expected: $TMP/sub, got: '$result')"
fi

# Test 2: an existing absolute path is returned unchanged
eq "Absolute path remains absolute" "/tmp" "$(tpath.getFullPath "/tmp")"

# Test 3: empty in, empty out
eq "getFullPath with empty path" "" "$(tpath.getFullPath "")"

# Test 4: '.' is the working directory itself
eq "getFullPath with current directory" "$TMP" "$(tpath.getFullPath ".")"

# Test 5: '..' is the parent of the working directory
parent="${TMP%/*}"
eq "getFullPath with parent directory" "$parent" "$(tpath.getFullPath "..")"

# Test 6: '.' and '..' components inside the path are normalised away
eq "getFullPath collapses . and .. components" "$TMP/sub" \
   "$(tpath.getFullPath "./sub/./../sub")"

# Test 7: a long path is not truncated
long_name="$(printf 'a%.0s' {1..100})"
eq "getFullPath with very long path" "$TMP/folder/$long_name/file.txt" \
   "$(tpath.getFullPath "folder/$long_name/file.txt")"

# Test 8: spaces and shell metacharacters survive verbatim
special="folder/file with spaces & symbols!.txt"
eq "getFullPath with special characters" "$TMP/$special" \
   "$(tpath.getFullPath "$special")"

# Test 9 (G6-13): a path whose intermediate components do NOT exist still
# resolves — this is the case where the old code returned the raw input.
eq "getFullPath resolves a non-existent relative path [G6-13]" \
   "$TMP/nosuch/deeper/f.txt" "$(tpath.getFullPath "nosuch/deeper/f.txt")"

# Test 10: the direct call sets RESULT and prints nothing (decision D3)
kt_test_start "getFullPath direct call is silent and sets RESULT [D3]"
out_file="$TMP/gfp.out"
: > "$out_file"
tpath.getFullPath "sub" > "$out_file"
printed="$(<"$out_file")"
if [[ -z "$printed" && "$RESULT" == "$TMP/sub" ]]; then
    kt_test_pass "RESULT=$RESULT, nothing printed"
else
    kt_test_fail "printed='$printed' RESULT='$RESULT'"
fi

cd "$SCRIPT_DIR" || exit 1
