#!/bin/bash
# 036_G6_ReturnContract.sh — decision D3 + default R8 for tdirectory.
#
# Before P3 every member printed its answer (exists/isEmpty even printed
# without a newline, G6-24) and error messages went to stderr unconditionally.
# The contract is now kcl/README.md 1.1-1.3:
#
#   * a DIRECT call prints NOTHING and leaves the value in RESULT;
#   * inside `$( )` the value is printed exactly ONCE (old callers keep working);
#   * a predicate answers with its exit status as well (R8), true/false in RESULT;
#   * an error is rc 1 + RESULT='' and prints nothing unless
#     VERBOSE_KKLASS=debug is set (1.2).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G6_ReturnContract" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
UNIT="$TDIRECTORY_DIR/tdirectory.sh"
source "$UNIT"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"
OUT="$W/stdout.txt"
mkdir -p "$W/sub"
: > "$W/sub/f.txt"

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
silent_direct "exists: direct call is silent and sets RESULT [D3, R8]" \
    "true" tdirectory.exists "$W/sub"
silent_direct "isEmpty: direct call is silent and sets RESULT [D3, R8]" \
    "false" tdirectory.isEmpty "$W/sub"
silent_direct "getFiles: direct call is silent and sets RESULT [D3]" \
    "$W/sub/f.txt" tdirectory.getFiles "$W/sub"
silent_direct "getCurrentDirectory: direct call is silent and sets RESULT [D3]" \
    "$PWD" tdirectory.getCurrentDirectory
silent_direct "getDirectoryRoot: direct call is silent and sets RESULT [D3]" \
    "/" tdirectory.getDirectoryRoot "/a/b"
silent_direct "getParent: direct call is silent and sets RESULT [D3]" \
    "$W" tdirectory.getParent "$W/sub"
silent_direct "isRelativePath: direct call is silent and sets RESULT [D3, R8]" \
    "true" tdirectory.isRelativePath "rel/path"
silent_direct "getAttributes: direct call is silent and sets RESULT [D3]" \
    "faDirectory" tdirectory.getAttributes "$W/sub"

# --- $( ) still prints exactly once ----------------------------------------
capture_once "\$( ) prints exists exactly once [D3, R8]" "true" \
    tdirectory.exists "$W/sub"
capture_once "\$( ) prints 'false' for a missing directory [D3, R8]" "false" \
    tdirectory.exists "$W/nosuch"
mkdir -p "$W/empty_for_capture"
capture_once "\$( ) prints isEmpty exactly once [D3, R8]" "true" \
    tdirectory.isEmpty "$W/empty_for_capture"
capture_once "\$( ) prints a listing exactly once [D3]" "$W/sub/f.txt" \
    tdirectory.getFiles "$W/sub"

# --- predicates answer with rc (R8) ----------------------------------------
mkdir -p "$W/emptydir"
rc_is "exists on a directory -> rc 0 [R8]"        0 tdirectory.exists "$W/sub"
rc_is "exists on a missing path -> rc 1 [R8]"     1 tdirectory.exists "$W/nosuch"
rc_is "exists on a FILE -> rc 1 [R8]"             1 tdirectory.exists "$W/sub/f.txt"
rc_is "isEmpty on an empty directory -> rc 0 [R8]" 0 tdirectory.isEmpty "$W/emptydir"
rc_is "isEmpty on a populated directory -> rc 1 [R8]" 1 tdirectory.isEmpty "$W/sub"
rc_is "isEmpty on a missing path -> rc 1 [R8]"    1 tdirectory.isEmpty "$W/nosuch"
rc_is "isRelativePath rel -> rc 0 [R8]"           0 tdirectory.isRelativePath "rel"
rc_is "isRelativePath /abs -> rc 1 [R8]"          1 tdirectory.isRelativePath "/abs"

# --- the error contract is SILENT unless VERBOSE_KKLASS=debug (1.2) --------
kt_test_start "createDirectory with an empty path: rc 1, silent [1.2]"
rc=0
out="$(tdirectory.createDirectory "" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$out" ]]; then
    kt_test_pass "rc 1, silent"
else
    kt_test_fail "rc=$rc out='$out'"
fi

kt_test_start "delete of a missing directory: rc 1, silent [1.2]"
rc=0
out="$(tdirectory.delete "$W/nosuch" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$out" ]]; then
    kt_test_pass "rc 1, silent"
else
    kt_test_fail "rc=$rc out='$out'"
fi

kt_test_start "copy with a missing source: rc 1, silent [1.2]"
rc=0
out="$(tdirectory.copy "$W/nosuch" "$W/target" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$out" ]] && [[ ! -e "$W/target" ]]; then
    kt_test_pass "rc 1, silent, nothing created"
else
    kt_test_fail "rc=$rc out='$out'"
fi

kt_test_start "VERBOSE_KKLASS=debug turns the diagnostics back on [1.2]"
out="$(VERBOSE_KKLASS=debug tdirectory.delete "$W/nosuch" 2>&1 || true)"
if [[ -n "$out" ]]; then
    kt_test_pass "diagnostic present under debug"
else
    kt_test_fail "no diagnostic under VERBOSE_KKLASS=debug"
fi

# --- setCurrentDirectory still runs in the CALLER's shell ------------------
kt_test_start "setCurrentDirectory changes the caller's directory and RESULTs it [D3]"
here="$PWD"
rc=0
tdirectory.setCurrentDirectory "$W/sub" || rc=$?
moved="$PWD"
tdirectory.getCurrentDirectory
read_back="$RESULT"
cd "$here" || exit 1
if (( rc == 0 )) && [[ "$moved" == "$W/sub" && "$read_back" == "$W/sub" ]]; then
    kt_test_pass "cd took effect and RESULT agreed"
else
    kt_test_fail "rc=$rc moved='$moved' RESULT='$read_back'"
fi

kt_test_start "setCurrentDirectory with a missing path: rc 1, caller stays put [1.2]"
here="$PWD"
rc=0
tdirectory.setCurrentDirectory "$W/nosuch" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ "$PWD" == "$here" ]]; then
    kt_test_pass "rc 1, still in $here"
else
    kt_test_fail "rc=$rc PWD='$PWD'"
fi

# --- the locale self-heal (D6) ---------------------------------------------
kt_test_start "the unit exports a UTF-8 LC_CTYPE into a bare environment [D6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
d=\$(mktemp -d)
mkdir -p \"\$d/дом\"
tdirectory.getDirectories \"\$d\" >/dev/null
printf '%s|%s' \"\${LC_CTYPE:-}\" \"\${RESULT##*/}\"
rm -rf -- \"\$d\"" 2>&1)"
if [[ "$out" == "C.UTF-8|дом" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out', expected 'C.UTF-8|дом'"
fi

# --- booleans under set -e -------------------------------------------------
kt_test_start "a false predicate under set -e reaches the caller through if/|| [1.3, D7]"
out="$(bash -c "set -eu
source '$UNIT'
if tdirectory.exists /no/such/dir; then printf 'yes'; else printf 'no'; fi
tdirectory.exists /no/such/dir || printf ' or-ok'
printf ' end'" 2>&1)"
if [[ "$out" == "no or-ok end" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi

# --- G6-27: the re-source guard --------------------------------------------
kt_test_start "re-sourcing the unit under set -eu is a no-op [G6-27, D7]"
out="$(bash -c "set -eu
source '$UNIT'
source '$UNIT'
tdirectory.exists '$W' >/dev/null
printf OK" 2>&1)"
if [[ "$out" == "OK" ]]; then
    kt_test_pass "OK"
else
    kt_test_fail "got '$out'"
fi
