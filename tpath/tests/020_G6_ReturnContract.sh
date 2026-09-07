#!/bin/bash
# 020_G6_ReturnContract.sh — decision D3 + default R8 for tpath.
#
# Before P3 every member printed its answer with `printf '%s\n'`, so the only
# way to read one was `$( )` — a fork per call (0.65 ms direct against 23 ms
# for 200 combines, finding G6-16), and a member that wrote to stdout could
# never be used as a predicate. The contract is now kcl/README.md 1.1-1.3:
#
#   * a DIRECT call prints NOTHING and leaves the value in RESULT;
#   * inside `$( )` the value is printed exactly ONCE (old callers keep working);
#   * a predicate answers with its exit status as well (R8), with true/false
#     still in RESULT so `$(tpath.isPathRooted x)` also keeps working;
#   * an error is rc 1 + RESULT='' and prints nothing (kcl/README.md 1.2).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G6_ReturnContract" "$SCRIPT_DIR" "$@"

TPATH_DIR="$SCRIPT_DIR/.."
UNIT="$TPATH_DIR/tpath.sh"
source "$UNIT"

TMP="$(kt_fixture_tmpdir)"
OUT="$TMP/stdout.txt"

# --- direct call: silent, value in RESULT ----------------------------------
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

silent_direct "getFileName: direct call is silent and sets RESULT [D3]" \
    "b.txt" tpath.getFileName "/a/b.txt"
silent_direct "getDirectoryName: direct call is silent and sets RESULT [D3]" \
    "/a" tpath.getDirectoryName "/a/b.txt"
silent_direct "getExtension: direct call is silent and sets RESULT [D3]" \
    ".txt" tpath.getExtension "/a/b.txt"
silent_direct "combine: direct call is silent and sets RESULT [D3]" \
    "/a/b" tpath.combine "/a" "b"
silent_direct "changeExtension: direct call is silent and sets RESULT [D3]" \
    "/a/b.md" tpath.changeExtension "/a/b.txt" ".md"
silent_direct "getPathRoot: direct call is silent and sets RESULT [D3]" \
    "/" tpath.getPathRoot "/a/b.txt"
silent_direct "isPathRooted: direct call is silent and sets RESULT [D3, R8]" \
    "true" tpath.isPathRooted "/a"
silent_direct "getDirectorySeparatorChar: direct call is silent [D3]" \
    "/" tpath.getDirectorySeparatorChar

# --- $( ) still prints exactly once ----------------------------------------
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

capture_once "\$( ) prints getFileName exactly once [D3]" "b.txt" \
    tpath.getFileName "/a/b.txt"
capture_once "\$( ) prints combine exactly once [D3]" "/a/b" \
    tpath.combine "/a" "b"
capture_once "\$( ) prints a boolean exactly once [D3, R8]" "true" \
    tpath.isPathRooted "/a"
capture_once "\$( ) prints 'false' for a false predicate [D3, R8]" "false" \
    tpath.isPathRooted "rel"

# Values are DATA: an answer that looks like an echo option round-trips.
capture_once "a value that looks like an echo option survives \$( ) [X-ECHO]" "-n" \
    tpath.getFileName "/a/-n"
silent_direct "... and reaches RESULT verbatim on a direct call [X-ECHO]" "-neE" \
    tpath.getFileName "/a/-neE"

# --- booleans answer with rc (R8) ------------------------------------------
rc_is() {   # TITLE EXPECTED-RC MEMBER ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    local rc=0
    "$@" >/dev/null || rc=$?
    if (( rc == want )); then
        kt_test_pass "$title (rc $rc)"
    else
        kt_test_fail "$title (rc $rc, expected $want)"
    fi
}

rc_is "isPathRooted /a -> rc 0 [R8]"            0 tpath.isPathRooted "/a"
rc_is "isPathRooted rel -> rc 1 [R8]"           1 tpath.isPathRooted "rel"
rc_is "isRelativePath rel -> rc 0 [R8]"         0 tpath.isRelativePath "rel"
rc_is "isRelativePath /a -> rc 1 [R8]"          1 tpath.isRelativePath "/a"
rc_is "hasExtension a.txt -> rc 0 [R8]"         0 tpath.hasExtension "a.txt"
rc_is "hasExtension a -> rc 1 [R8]"             1 tpath.hasExtension "a"
rc_is "isUNCPath //s/x -> rc 0 [R8]"            0 tpath.isUNCPath "//s/x"
rc_is "isUNCPath /s -> rc 1 [R8]"               1 tpath.isUNCPath "/s"
rc_is "isDriveRooted C:/x -> rc 0 [R8]"         0 tpath.isDriveRooted "C:/x"
rc_is "isDriveRooted /x -> rc 1 [R8]"           1 tpath.isDriveRooted "/x"
rc_is "matchesPattern a.txt a.* -> rc 0 [R8]"   0 tpath.matchesPattern "a.txt" "a.*"
rc_is "matchesPattern a.txt b.* -> rc 1 [R8]"   1 tpath.matchesPattern "a.txt" "b.*"
rc_is "isValidFileNameChar a -> rc 0 [R8]"      0 tpath.isValidFileNameChar "a"
rc_is "isValidFileNameChar / -> rc 1 [R8]"      1 tpath.isValidFileNameChar "/"
rc_is "hasValidPathChars /a/b -> rc 0 [R8]"     0 tpath.hasValidPathChars "/a/b"

# --- the error contract ----------------------------------------------------
kt_test_start "getAttributes of a missing path: rc 1, RESULT empty, no output [1.2]"
RESULT="__unset__"
: > "$OUT"
rc=0
tpath.getAttributes "$TMP/no_such_file_g6" > "$OUT" 2>&1 || rc=$?
printed="$(<"$OUT")"
if (( rc == 1 )) && [[ -z "$RESULT" && -z "$printed" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' printed='$printed'"
fi

kt_test_start "getAttributes with an empty path: rc 1, RESULT empty [1.2]"
RESULT="__unset__"
rc=0
tpath.getAttributes "" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
    kt_test_pass "rc 1, RESULT empty"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

# --- the locale self-heal (D6) ---------------------------------------------
kt_test_start "the unit exports a UTF-8 LC_CTYPE into a bare environment [D6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
printf '%s|%s' \"\${LC_CTYPE:-}\" \"\$(tpath.getFileName '/a/дом.txt')\"" 2>&1)"
if [[ "$out" == "C.UTF-8|дом.txt" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out', expected 'C.UTF-8|дом.txt'"
fi

kt_test_start "the self-heal does not override an explicit locale [D6]"
out="$(env -u LC_CTYPE -u LANG LC_ALL=C.UTF-8 bash -c "
source '$UNIT'
printf '%s' \"\${LC_CTYPE:-unset}\"" 2>&1)"
if [[ "$out" == "unset" ]]; then
    kt_test_pass "LC_CTYPE left alone when LC_ALL is set"
else
    kt_test_fail "got '$out'"
fi

# --- booleans under set -e (kcl/README.md 1.3) -----------------------------
kt_test_start "a false predicate under set -e reaches the caller through if/|| [1.3, D7]"
out="$(bash -c "set -eu
source '$UNIT'
if tpath.isPathRooted rel; then printf 'rooted'; else printf 'relative'; fi
tpath.isPathRooted rel || printf ' or-ok'
printf ' end'" 2>&1)"
if [[ "$out" == "relative or-ok end" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi
