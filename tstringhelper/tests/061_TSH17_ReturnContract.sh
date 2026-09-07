#!/bin/bash
# 061_TSH17_ReturnContract.sh — decision D3 + default R8 for tstringhelper.
#
# Finding TSH-17: the unit's contract was inverted against kcl/README.md 1.1 —
# every member printed its answer with `printf '%s\n'` and left RESULT empty,
# so the ONLY way to read one was `$( )`: a fork per call (1-16 ms on a large
# shell against 0.2-0.7 ms for a direct call), and a member that writes to
# stdout can never double as a predicate. After P5 the contract is:
#
#   * a DIRECT call prints NOTHING and leaves the value in RESULT;
#   * inside `$( )` the value is printed exactly ONCE (old callers keep working);
#   * a predicate answers with its exit status as well (R8), with true/false
#     still in RESULT so `$(string.isEmpty x)` also keeps working;
#   * an error is rc 1 + RESULT='' and prints nothing (kcl/README.md 1.2),
#     rc 2 for a malformed call such as a reserved output-array name (1.7).
#
# The class is STATIC, so this is `static proc` + string._ret, not `static func`:
# kklass's thin static dispatcher re-prints kk._return's value unconditionally
# (kcl/README.md 1.1, P3 deviation 1).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TSH17_ReturnContract" "$SCRIPT_DIR" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# PARALLEL — a neighbour's teardown deletes it while we are using it, and a
# redirect into a vanished directory means the member never runs at all
# (kcl_ledger.json, found_in_P4/P4-F2).
PRIVTMP="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$PRIVTMP"

UNIT="$SCRIPT_DIR/../tstringhelper.sh"
source "$UNIT"

TMP="$PRIVTMP"
mkdir -p "$TMP"
OUT="$TMP/stdout.txt"

# --- 1. a direct call is silent and answers in RESULT -----------------------
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

silent_direct "length: direct call is silent and sets RESULT [D3]"       "5"       string.length "hello"
silent_direct "trim: direct call is silent and sets RESULT [D3]"         "hi"      string.trim "  hi  "
silent_direct "substring: direct call is silent and sets RESULT [D3]"    "world"   string.substring "hello world" 6
silent_direct "indexOf: direct call is silent and sets RESULT [D3]"      "2"       string.indexOf "hello" "l"
silent_direct "toUpper: direct call is silent and sets RESULT [D3]"      "ABC"     string.toUpper "abc"
silent_direct "replace: direct call is silent and sets RESULT [D3]"      "a+b+c"   string.replace "a-b-c" "-" "+"
silent_direct "padLeft: direct call is silent and sets RESULT [D3]"      "   ab"   string.padLeft "ab" 5
silent_direct "quotedString: direct call is silent and sets RESULT [D3]" "'it''s'" string.quotedString "it's"
silent_direct "create: direct call is silent and sets RESULT [D3]"       "xxx"     string.create "x" 3
silent_direct "countChar: direct call is silent and sets RESULT [D3]"    "3"       string.countChar "banana" "a"
silent_direct "join: direct call is silent and sets RESULT [D3]"         "a,b,c"   string.join "," a b c
silent_direct "toInteger: direct call is silent and sets RESULT [D3]"    "42"      string.toInteger "42"
silent_direct "equals: a boolean is silent too and RESULT is true [D3,R8]"  "true"  string.equals "a" "a"
silent_direct "equals: ... and 'false' for the false answer [D3,R8]"        "false" string.equals "a" "b"
silent_direct "a value that looks like an echo option reaches RESULT [X-ECHO]" "-n" \
    string.substring "-name" 0 2
silent_direct "a value with an embedded newline survives [X-ECHO]" $'a\nb' \
    string.trim $'  a\nb  '

# --- 2. `$( )` still prints the value exactly once --------------------------
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

capture_once "\$( ) prints trim exactly once [D3]"        "hi"    string.trim "  hi  "
capture_once "\$( ) prints replace exactly once [D3]"     "a+b+c" string.replace "a-b-c" "-" "+"
capture_once "\$( ) prints length exactly once [D3]"      "5"     string.length "hello"
capture_once "\$( ) prints 'true' for a true predicate [R8]"  "true"  string.equals "a" "a"
capture_once "\$( ) prints 'false' for a false predicate [R8]" "false" string.equals "a" "b"
capture_once "\$( ) prints an echo-option value verbatim [X-ECHO]" "-neE" string.trim "  -neE  "

# --- 3. predicates answer with their exit status (R8) -----------------------
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

rc_is "equals a a -> rc 0 [R8]"                 0 string.equals "a" "a"
rc_is "equals a b -> rc 1 [R8]"                 1 string.equals "a" "b"
rc_is "contains abc b -> rc 0 [R8]"             0 string.contains "abc" "b"
rc_is "contains abc z -> rc 1 [R8]"             1 string.contains "abc" "z"
rc_is "startsWith abc a -> rc 0 [R8]"           0 string.startsWith "abc" "a"
rc_is "startsWith abc b -> rc 1 [R8]"           1 string.startsWith "abc" "b"
rc_is "endsWith abc c -> rc 0 [R8]"             0 string.endsWith "abc" "c"
rc_is "endsWith abc a -> rc 1 [R8]"             1 string.endsWith "abc" "a"
rc_is "startsText ABC abcd -> rc 0 [R8]"        0 string.startsText "ABC" "abcd"
rc_is "endsText CD abcd -> rc 0 [R8]"           0 string.endsText "CD" "abcd"
rc_is "isEmpty '' -> rc 0 [R8]"                 0 string.isEmpty ""
rc_is "isEmpty x -> rc 1 [R8]"                  1 string.isEmpty "x"
rc_is "isNullOrEmpty '' -> rc 0 [R8]"           0 string.isNullOrEmpty ""
rc_is "isNullOrWhiteSpace '  ' -> rc 0 [R8]"    0 string.isNullOrWhiteSpace "  "
rc_is "isNullOrWhiteSpace ' x ' -> rc 1 [R8]"   1 string.isNullOrWhiteSpace " x "
rc_is "isDelimiter a,b 1 , -> rc 0 [R8]"        0 string.isDelimiter "a,b" 1 ","
rc_is "isDelimiter a,b 0 , -> rc 1 [R8]"        1 string.isDelimiter "a,b" 0 ","
rc_is "toBoolean True -> rc 0 [R8]"             0 string.toBoolean "True"
rc_is "toBoolean 0 -> rc 1 [R8]"                1 string.toBoolean "0"

# --- 4. the error contract (kcl/README.md 1.2) ------------------------------
fails_silently() {   # TITLE EXPECTED-RC MEMBER ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    RESULT="__unset__"
    : > "$OUT"
    local rc=0
    "$@" > "$OUT" 2>&1 || rc=$?
    local printed; printed="$(<"$OUT")"
    if (( rc == want )) && [[ -z "$RESULT" && -z "$printed" ]]; then
        kt_test_pass "$title (rc $rc)"
    else
        kt_test_fail "$title: rc=$rc RESULT='$RESULT' printed='$printed' (wanted rc $want)"
    fi
}

fails_silently "chars past the end: rc 1, RESULT empty, silent [1.2]"     1 string.chars "hello" 10
fails_silently "substring with a non-numeric index: rc 1 [1.2, D1]"       1 string.substring "hello" "abc"
fails_silently "toInteger of a word: rc 1, RESULT empty [TSH-14]"         1 string.toInteger "hello"
fails_silently "toDouble of a word: rc 1, RESULT empty [TSH-18]"          1 string.toDouble "abc"
fails_silently "split into a RESERVED array name: rc 2 [1.7]"             2 string.split "a,b" "," RESULT
fails_silently "copyTo into a RESERVED array name: rc 2 [1.7, TSH-16]"    2 string.copyTo "abc" 0 IFS 0 2

# --- 5. no forks on the hot paths (kcl/README.md 1.8, TSH-09) ---------------
kt_test_start "member bodies contain no command substitution [1.8]"
forking=""
for m in indexOf indexOfAny lastIndexOf lastIndexOfAny replace countChar \
         substring remove insert trim padLeft padRight split quotedString \
         deQuotedString create length toUpper toLower; do
    body="$(declare -f "string.__static_$m" 2>/dev/null)"
    # `$((` is arithmetic, not a fork — take it out before looking for `$(`.
    body="${body//\$((/ARITH}"
    if [[ -z "$body" ]]; then
        forking+="$m(missing) "
    elif [[ "$body" == *'$('* || "$body" == *'`'* ]]; then
        forking+="$m "
    fi
done
if [[ -z "$forking" ]]; then
    kt_test_pass "19 members, no command substitution and no backticks"
else
    kt_test_fail "command substitution in: $forking"
fi

kt_test_start "200 direct calls are faster than 200 through a subshell [1.1, 1.8]"
t0=${EPOCHREALTIME/./}
for ((i = 0; i < 200; i++)); do string.indexOf "hello world" "o" >/dev/null; done
t1=${EPOCHREALTIME/./}
for ((i = 0; i < 200; i++)); do : "$(string.indexOf "hello world" "o")"; done
t2=${EPOCHREALTIME/./}
direct=$(( (t1 - t0) / 1000 )); forked=$(( (t2 - t1) / 1000 ))
if (( direct < forked )); then
    kt_test_pass "direct ${direct} ms < subshell ${forked} ms"
else
    kt_test_fail "direct ${direct} ms is not faster than subshell ${forked} ms"
fi

# --- 6. booleans under set -e (kcl/README.md 1.3) ---------------------------
kt_test_start "a false predicate under set -e reaches the caller through if/|| [1.3, D7]"
out="$(bash -c "set -eu
source '$UNIT'
if string.isEmpty x; then printf 'empty'; else printf 'not-empty'; fi
string.isEmpty x || printf ' or-ok'
! string.isEmpty x && printf ' bang-ok'
printf ' end'" 2>&1)"
if [[ "$out" == "not-empty or-ok bang-ok end" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi
