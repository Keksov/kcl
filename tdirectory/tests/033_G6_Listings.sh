#!/bin/bash
# 033_G6_Listings.sh — review 2026-09-06, phase P3.
#
#   G6-09  the listings globbed `"$dir"/*` without `dotglob`, so a dot-entry
#          was invisible to getFiles/getDirectories/getFileSystemEntries while
#          isEmpty counted it through `ls -A` — the two disagreed about the
#          same directory. FPC's TDirectory and .NET both include them (R13).
#   G6-17  the recursive helpers followed directory SYMLINKS: with
#          `loop/a/back -> loop` the review got 21 entries for one real
#          subdirectory. R13: recursion does not descend into a link.
#   G6-24  a trailing separator on the argument came out doubled in every
#          returned path (`dir/` -> `dir//sub`).
#   G6-25  `shopt -s failglob` in the CALLER aborted the listing.
#   1.7    the listings can now fill a caller ARRAY, which is the only
#          newline-safe way to return file names.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/symlink_helper.sh"

kt_test_init "G6_Listings" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
source "$TDIRECTORY_DIR/tdirectory.sh"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# --- G6-09: dot entries are part of the listing ----------------------------
D="$W/dots"
mkdir -p "$D/.hiddendir" "$D/plaindir"
: > "$D/.hiddenfile"
: > "$D/plainfile"

eq "getFiles includes dot-files [G6-09, R13]" \
   "$D/.hiddenfile"$'\n'"$D/plainfile" "$(tdirectory.getFiles "$D")"
eq "getDirectories includes dot-directories [G6-09, R13]" \
   "$D/.hiddendir"$'\n'"$D/plaindir" "$(tdirectory.getDirectories "$D")"
eq "getFileSystemEntries includes both [G6-09, R13]" \
   "$D/.hiddendir"$'\n'"$D/.hiddenfile"$'\n'"$D/plaindir"$'\n'"$D/plainfile" \
   "$(tdirectory.getFileSystemEntries "$D")"

kt_test_start "isEmpty agrees with the listing about a dot-only directory [G6-09]"
H="$W/dotonly"
mkdir -p "$H"
: > "$H/.onlyhidden"
listed="$(tdirectory.getFileSystemEntries "$H")"
if ! tdirectory.isEmpty "$H" && [[ -n "$listed" ]]; then
    kt_test_pass "both say not empty"
else
    kt_test_fail "isEmpty said '$RESULT', listing was '$listed'"
fi

eq "a pattern still applies to dot entries [G6-09]" \
   "$D/.hiddenfile" "$(tdirectory.getFiles "$D" ".hidden*")"

# --- G6-24: a trailing separator is not doubled ----------------------------
eq "a trailing '/' on the argument does not double in the result [G6-24]" \
   "$D/plaindir" "$(tdirectory.getDirectories "$D/" "plaindir")"
eq "several trailing separators are stripped [G6-24]" \
   "$D/plainfile" "$(tdirectory.getFiles "$D///" "plainfile")"

# --- G6-17: recursion does not descend into a directory symlink ------------
kt_test_start "recursion does not follow a directory symlink [G6-17, R13]"
L="$W/loop"
mkdir -p "$L/a"
: > "$L/a/real.txt"
if kt_make_symlink "$L/a/back" "$L"; then
    dirs="$(tdirectory.getDirectories "$L" "*" AllDirectories)"
    n=$(printf '%s\n' "$dirs" | grep -c . || true)
    if [[ "$dirs" == "$L/a"$'\n'"$L/a/back" ]] || [[ "$dirs" == "$L/a" ]]; then
        kt_test_pass "$n entries, no cycle: $(printf '%s' "${dirs//$'\n'/ | }")"
    else
        kt_test_fail "$n entries: $(printf '%s' "${dirs//$'\n'/ | }")"
    fi
else
    kt_test_fail "could not create a directory symlink for the cycle test"
fi

kt_test_start "a recursive FILE listing does not walk into a directory symlink [G6-17]"
files="$(tdirectory.getFiles "$L" "*" AllDirectories)"
if [[ "$files" == "$L/a/real.txt" ]]; then
    kt_test_pass "one file"
else
    kt_test_fail "got: $(printf '%s' "${files//$'\n'/ | }")"
fi

kt_test_start "a recursive ENTRY listing does not walk into a directory symlink [G6-17]"
entries="$(tdirectory.getFileSystemEntries "$L" "*" AllDirectories)"
count=$(printf '%s\n' "$entries" | grep -c . || true)
if (( count <= 3 )); then
    kt_test_pass "$count entries"
else
    kt_test_fail "$count entries: $(printf '%s' "${entries//$'\n'/ | }")"
fi

# --- G6-25: the caller's failglob must not break the listing ---------------
kt_test_start "a caller's failglob does not break a listing [G6-25]"
E="$W/emptydir"
mkdir -p "$E"
shopt -s failglob
rc=0
out="$(tdirectory.getFiles "$E" 2>&1)" || rc=$?
shopt -u failglob
if (( rc == 0 )) && [[ -z "$out" ]]; then
    kt_test_pass "empty listing, rc 0"
else
    kt_test_fail "rc=$rc out='$out'"
fi

kt_test_start "the listing restores the caller's failglob [G6-25]"
shopt -s failglob
tdirectory.getFiles "$D" >/dev/null || :
if shopt -q failglob; then
    kt_test_pass "still set"
    shopt -u failglob
else
    kt_test_fail "the listing cleared the caller's failglob"
fi

kt_test_start "the listing restores the caller's dotglob [G6-09]"
shopt -u dotglob
tdirectory.getFiles "$D" >/dev/null || :
if shopt -q dotglob; then
    kt_test_fail "the listing left dotglob on"
    shopt -u dotglob
else
    kt_test_pass "still off"
fi

# --- 1.7: the output-array form --------------------------------------------
kt_test_start "getFiles fills a caller array and RESULTs the count [1.7]"
declare -a found=()
rc=0
tdirectory.getFiles "$D" "*" TopDirectoryOnly found || rc=$?
if (( rc == 0 )) && (( ${#found[@]} == 2 )) \
   && [[ "${found[0]}" == "$D/.hiddenfile" && "${found[1]}" == "$D/plainfile" ]] \
   && [[ "$RESULT" == "2" ]]; then
    kt_test_pass "2 entries, RESULT=2"
else
    kt_test_fail "rc=$rc n=${#found[@]} RESULT='$RESULT' (${found[*]})"
fi

kt_test_start "a file name containing a NEWLINE survives the array form [1.7]"
N="$W/newline"
mkdir -p "$N"
: > "$N/$(printf 'we\nird').txt"
: > "$N/plain.txt"
declare -a nfound=()
tdirectory.getFiles "$N" "*" TopDirectoryOnly nfound || :
if (( ${#nfound[@]} == 2 )); then
    kt_test_pass "2 entries even though one name holds a newline"
else
    kt_test_fail "n=${#nfound[@]} (${nfound[*]})"
fi

kt_test_start "a reserved output-array name is rc 2 [1.7]"
rc=0
tdirectory.getFiles "$D" "*" TopDirectoryOnly RESULT >/dev/null 2>&1 || rc=$?
if (( rc == 2 )); then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "getDirectories and getFileSystemEntries take the array too [1.7]"
declare -a dfound=() efound=()
tdirectory.getDirectories "$D" "*" TopDirectoryOnly dfound || :
tdirectory.getFileSystemEntries "$D" "*" TopDirectoryOnly efound || :
if (( ${#dfound[@]} == 2 && ${#efound[@]} == 4 )); then
    kt_test_pass "2 directories, 4 entries"
else
    kt_test_fail "dirs=${#dfound[@]} entries=${#efound[@]}"
fi

# --- the error contract ----------------------------------------------------
kt_test_start "a listing of a missing directory is rc 1 and silent [1.2]"
rc=0
out="$(tdirectory.getFiles "$W/nosuchdir" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$out" ]]; then
    kt_test_pass "rc 1, silent"
else
    kt_test_fail "rc=$rc out='$out'"
fi
