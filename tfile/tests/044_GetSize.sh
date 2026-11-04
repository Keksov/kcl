#!/usr/bin/env bash
# 044_GetSize.sh — tfile.getSize (a kcl extension).
#
#   getSize F answers the size in bytes of a regular file, following a
#   symlink, from one `stat`. A directory, a FIFO or a broken link is rc 1.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/symlink_helper.sh"

kt_test_init "GetSize" "$SCRIPT_DIR" "$@"

TFILE_DIR="$SCRIPT_DIR/.."
UNIT="$TFILE_DIR/tfile.sh"
source "$UNIT"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"
OUT="$W/stdout.txt"

size_is() {   # TITLE EXPECTED FILE
    kt_test_start "$1"
    RESULT="__unset__"
    local rc=0
    tfile.getSize "$3" > "$OUT" 2>&1 || rc=$?
    local printed; printed="$(<"$OUT")"
    if (( rc == 0 )) && [[ "$RESULT" == "$2" && -z "$printed" ]]; then
        kt_test_pass "$1 ($2)"
    else
        kt_test_fail "$1 (rc $rc, RESULT '$RESULT', expected '$2', printed '$printed')"
    fi
}

refused() {   # TITLE PATH
    kt_test_start "$1"
    RESULT="__unset__"
    local rc=0
    tfile.getSize "$2" > "$OUT" 2>&1 || rc=$?
    local printed; printed="$(<"$OUT")"
    if (( rc == 1 )) && [[ -z "$RESULT" && -z "$printed" ]]; then
        kt_test_pass "$1 (rc 1, silent)"
    else
        kt_test_fail "$1 (rc $rc, RESULT '$RESULT', printed '$printed')"
    fi
}

: > "$W/empty"
printf 'abc' > "$W/three"
printf 'é' > "$W/utf8"
printf 'x\r\n' > "$W/crlf"
printf 'line\n' > "$W/-dash"
printf 'sp' > "$W/with space"
printf 'nl' > "$W/"$'new\nline'
head -c 100000 /dev/zero > "$W/big" 2>/dev/null \
    || { printf '%*s' 100000 '' > "$W/big"; }
mkdir -p "$W/dir"

size_is "an empty file is 0" 0 "$W/empty"
size_is "a three-byte file is 3" 3 "$W/three"
size_is "the size is in bytes, not characters" 2 "$W/utf8"
size_is "a CR counts" 3 "$W/crlf"
size_is "a name starting with a dash" 5 "$W/-dash"
size_is "a name with a space" 2 "$W/with space"
size_is "a name with a newline" 2 "$W/"$'new\nline'
size_is "a 100000-byte file" 100000 "$W/big"

kt_test_start "the size follows a write"
printf 'more' >> "$W/three"
tfile.getSize "$W/three"
if [[ "$RESULT" == 7 ]]; then kt_test_pass "7"; else kt_test_fail "got '$RESULT'"; fi

refused "a directory is rc 1" "$W/dir"
refused "a missing file is rc 1" "$W/nosuch"
refused "an empty argument is rc 1" ""

if kt_make_symlink "$W/link" three && kt_make_symlink "$W/broken" nowhere; then
    size_is "a symlink answers its target's size" 7 "$W/link"
    refused "a broken link is rc 1" "$W/broken"
else
    kt_test_start "symlinks"
    kt_test_fail "could not create native symlinks"
fi

if mkfifo "$W/pipe" 2>/dev/null; then
    refused "a FIFO is rc 1 (and is not opened)" "$W/pipe"
else
    kt_test_start "a FIFO is rc 1"
    kt_test_pass "mkfifo not available here (skipped)"
fi

kt_test_start "inside \$( ) the size is printed once"
got="$(tfile.getSize "$W/three")"
if [[ "$got" == 7 ]]; then kt_test_pass "7"; else kt_test_fail "got '$got'"; fi

kt_test_start "one stat call, no existence probe fork"
stat() { printf 'x' >> "$W/calls"; command stat "$@"; }
tpath._statFlavour   # the flavour probe is once per shell, not per call
: > "$W/calls"
tfile.getSize "$W/three"
unset -f stat
calls="$(<"$W/calls")"
if [[ "${#calls}" == 1 && "$RESULT" == 7 ]]; then kt_test_pass "1 call"; else kt_test_fail "${#calls} calls, RESULT '$RESULT'"; fi

kt_test_start "a caller's IFS does not matter"
IFS=':'
tfile.getSize "$W/big"
r=$RESULT
IFS=$' \t\n'
if [[ "$r" == 100000 ]]; then kt_test_pass "100000"; else kt_test_fail "got '$r'"; fi

kt_test_start "works under set -eu"
out="$(bash -c "set -eu
source '$UNIT'
tfile.getSize '$W/three'
echo \"\$RESULT\"" 2>&1)"
if [[ "$out" == 7 ]]; then kt_test_pass "7"; else kt_test_fail "got '$out'"; fi
