#!/bin/bash
# 043_G6_ReturnContract.sh — decision D3 + default R8 for tfile.
#
# Before P3 every member answered by printing, so reading one cost a fork and
# a member that wrote to stdout could not double as a predicate. The contract
# is now kcl/README.md 1.1-1.3:
#
#   * a DIRECT call prints NOTHING and leaves the value in RESULT;
#   * inside `$( )` the value is printed exactly ONCE (old callers keep working);
#   * a predicate answers with its exit status as well (R8), with true/false
#     still in RESULT;
#   * an error is rc 1 + RESULT='' and prints nothing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TFILE_DIR="$SCRIPT_DIR/.."
UNIT="$TFILE_DIR/tfile.sh"
source "$UNIT"

kt_test_init "G6_ReturnContract" "$SCRIPT_DIR" "$@"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"
OUT="$W/stdout.txt"
F="$W/rc.txt"
printf 'hello' > "$F"

silent_direct() {   # TITLE EXPECTED-RESULT MEMBER ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    RESULT="__unset__"
    : > "$OUT"
    "$@" > "$OUT" 2>&1 || :
    local printed; printed="$(<"$OUT")"
    if [[ -n "$printed" ]]; then
        kt_test_fail "$title: a direct call printed '$printed'"
    elif [[ "$RESULT" != "$want" ]]; then
        kt_test_fail "$title: RESULT='$RESULT', expected '$want'"
    else
        kt_test_pass "$title"
    fi
}

capture_once() {   # TITLE EXPECTED MEMBER ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    local got; got="$("$@")" || :
    if [[ "$got" == "$want" ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title (expected '$want', got '$got')"
    fi
}

rc_is() {   # TITLE EXPECTED-RC MEMBER ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if (( rc == want )); then
        kt_test_pass "$title (rc $rc)"
    else
        kt_test_fail "$title (rc $rc, expected $want)"
    fi
}

# --- direct calls are silent -----------------------------------------------
silent_direct "readAllText: direct call is silent and sets RESULT [D3]" \
    "hello" tfile.readAllText "$F"
silent_direct "readAllLines: direct call is silent and sets RESULT [D3]" \
    "hello" tfile.readAllLines "$F"
silent_direct "readAllBytes: direct call is silent and sets RESULT [D3]" \
    "hello" tfile.readAllBytes "$F"
silent_direct "exists: direct call is silent and sets RESULT [D3, R8]" \
    "true" tfile.exists "$F"
silent_direct "getAttributes: direct call is silent and sets RESULT [D3]" \
    "faNormal" tfile.getAttributes "$F"
silent_direct "fileAttributesToInteger: direct call is silent [D3]" \
    "1" tfile.fileAttributesToInteger "[faReadOnly]"
silent_direct "integerToFileAttributes: direct call is silent [D3]" \
    "[ReadOnly]" tfile.integerToFileAttributes 1
silent_direct "openRead: direct call is silent and RESULTs the handle [D3]" \
    "$F" tfile.openRead "$F"
silent_direct "createText: direct call is silent and RESULTs the handle [D3]" \
    "$W/ct.txt" tfile.createText "$W/ct.txt"

# --- $( ) still prints exactly once ----------------------------------------
capture_once "\$( ) prints readAllText exactly once [D3]" "hello" \
    tfile.readAllText "$F"
capture_once "\$( ) prints exists exactly once [D3, R8]" "true" \
    tfile.exists "$F"
capture_once "\$( ) prints 'false' for a missing file [D3, R8]" "false" \
    tfile.exists "$W/nosuch.txt"
capture_once "\$( ) prints integerToFileAttributes exactly once [D3]" "[ReadOnly, Archive]" \
    tfile.integerToFileAttributes 33

# X-ECHO: an appended value that looks like an echo option must be written.
kt_test_start "appendAllText writes '-neE' verbatim [X-ECHO, G6-03]"
A="$W/ap.txt"; : > "$A"
tfile.appendAllText "$A" "-neE"
if [[ "$(wc -c < "$A")" == "4" ]]; then
    kt_test_pass "4 bytes"
else
    kt_test_fail "$(wc -c < "$A") bytes"
fi

kt_test_start "readAllText round-trips a value that looks like an echo option [X-ECHO]"
RESULT="__unset__"
tfile.readAllText "$A" >/dev/null
if [[ "$RESULT" == "-neE" ]]; then
    kt_test_pass "RESULT=-neE"
else
    kt_test_fail "RESULT=$(printf '%q' "$RESULT")"
fi

# --- predicates answer with rc (R8) ----------------------------------------
rc_is "exists on a file -> rc 0 [R8]"        0 tfile.exists "$F"
rc_is "exists on a missing file -> rc 1 [R8]" 1 tfile.exists "$W/nosuch.txt"
rc_is "exists on a directory -> rc 1 [R8]"   1 tfile.exists "$W"

# --- the error contract ----------------------------------------------------
kt_test_start "readAllText of a missing file: rc 1, RESULT empty, silent [1.2]"
RESULT="__unset__"
: > "$OUT"
rc=0
tfile.readAllText "$W/nosuch.txt" > "$OUT" 2>&1 || rc=$?
printed="$(<"$OUT")"
if (( rc == 1 )) && [[ -z "$RESULT" && -z "$printed" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' printed='$printed'"
fi

kt_test_start "getAttributes of a missing file: rc 1, RESULT empty, silent [1.2]"
RESULT="__unset__"
: > "$OUT"
rc=0
tfile.getAttributes "$W/nosuch.txt" > "$OUT" 2>&1 || rc=$?
printed="$(<"$OUT")"
if (( rc == 1 )) && [[ -z "$RESULT" && -z "$printed" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' printed='$printed'"
fi

# --- the locale self-heal (D6) ---------------------------------------------
kt_test_start "the unit exports a UTF-8 LC_CTYPE into a bare environment [D6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
d=\$(mktemp -d)
printf 'дом' > \"\$d/f.txt\"
tfile.readAllText \"\$d/f.txt\" >/dev/null
printf '%s|%s' \"\${LC_CTYPE:-}\" \"\${#RESULT}\"
rm -rf -- \"\$d\"" 2>&1)"
if [[ "$out" == "C.UTF-8|3" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out', expected 'C.UTF-8|3'"
fi

# --- booleans under set -e -------------------------------------------------
kt_test_start "a false predicate under set -e reaches the caller through if/|| [1.3, D7]"
out="$(bash -c "set -eu
source '$UNIT'
if tfile.exists /no/such/file; then printf 'yes'; else printf 'no'; fi
tfile.exists /no/such/file || printf ' or-ok'
printf ' end'" 2>&1)"
if [[ "$out" == "no or-ok end" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi
