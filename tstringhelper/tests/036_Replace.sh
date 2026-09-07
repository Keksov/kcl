#!/bin/bash
# Replace
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Replace" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Replace single character.
# P5 / TSH-05: FPC's Replace(OldValue,NewValue) is Replace(...,[rfReplaceAll]),
# so the default replaces ALL occurrences. This assertion used to expect
# "heLlo" — the first occurrence only, which is the .NET default, not FPC's —
# and that is what kept the defect green (kcl/PLAN.md section 4).
kt_test_start "Replace - replace character (ALL occurrences, FPC default)"
result=$(string.replace "hello" "l" "L")
if [[ "$result" == "heLLo" ]]; then
    kt_test_pass "Replace - replace character"
else
    kt_test_fail "Replace - replace character (expected: 'heLLo', got: '$result')"
fi

# Test 2: Replace substring
kt_test_start "Replace - replace substring"
result=$(string.replace "hello world" "world" "universe")
if [[ "$result" == "hello universe" ]]; then
    kt_test_pass "Replace - replace substring"
else
    kt_test_fail "Replace - replace substring (expected: 'hello universe', got: '$result')"
fi

# Test 3: Replace not found
kt_test_start "Replace - not found"
result=$(string.replace "hello" "z" "x")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Replace - not found"
else
    kt_test_fail "Replace - not found (expected: 'hello', got: '$result')"
fi

# Test 4: Replace with empty string (all occurrences — see test 1, TSH-05)
kt_test_start "Replace - replace with empty"
result=$(string.replace "hello" "l" "")
if [[ "$result" == "heo" ]]; then
    kt_test_pass "Replace - replace with empty"
else
    kt_test_fail "Replace - replace with empty (expected: 'heo', got: '$result')"
fi

# Test 5: Replace empty with string
kt_test_start "Replace - empty to string"
result=$(string.replace "ab" "" "x")
if [[ "$result" == "ab" ]]; then
    kt_test_pass "Replace - empty to string"
else
    kt_test_fail "Replace - empty to string (expected: 'ab', got: '$result')"
fi

# Test 6: Replace all occurrences (with flag)
kt_test_start "Replace - all occurrences"
result=$(string.replace "aaa" "a" "b" "rfReplaceAll")
if [[ "$result" == "bbb" ]]; then
    kt_test_pass "Replace - all occurrences"
else
    kt_test_fail "Replace - all occurrences (expected: 'bbb', got: '$result')"
fi

# Test 7: Replace case insensitive (if supported)
kt_test_start "Replace - ignore case"
result=$(string.replace "HELLO" "hello" "hi" "rfIgnoreCase")
if [[ "$result" == "hi" ]]; then
    kt_test_pass "Replace - ignore case"
else
    kt_test_fail "Replace - ignore case (expected: 'hi', got: '$result')"
fi

# Test 8: Replace at start
kt_test_start "Replace - at start"
result=$(string.replace "hello world" "hello" "goodbye")
if [[ "$result" == "goodbye world" ]]; then
    kt_test_pass "Replace - at start"
else
    kt_test_fail "Replace - at start (expected: 'goodbye world', got: '$result')"
fi

# Test 9: Replace at end
kt_test_start "Replace - at end"
result=$(string.replace "hello world" "world" "earth")
if [[ "$result" == "hello earth" ]]; then
    kt_test_pass "Replace - at end"
else
    kt_test_fail "Replace - at end (expected: 'hello earth', got: '$result')"
fi

# Test 10: Replace with special characters
kt_test_start "Replace - special characters"
result=$(string.replace "test@mail" "@" ".")
if [[ "$result" == "test.mail" ]]; then
    kt_test_pass "Replace - special characters"
else
    kt_test_fail "Replace - special characters (expected: 'test.mail', got: '$result')"
fi

# Test 11: Replace treats glob metacharacters literally
kt_test_start "Replace - literal glob metacharacter"
result=$(string.replace "a*b*c" "*" "X" "rfReplaceAll")
if [[ "$result" == "aXbXc" ]]; then
    kt_test_pass "Replace - literal glob metacharacter"
else
    kt_test_fail "Replace - literal glob metacharacter (expected: 'aXbXc', got: '$result')"
fi

# Test 12: Ignore-case replace treats search text literally
kt_test_start "Replace - ignore case literal text"
result=$(string.replace "a.b axb A.B" "a.b" "X" "rfReplaceAll rfIgnoreCase")
if [[ "$result" == "X axb X" ]]; then
    kt_test_pass "Replace - ignore case literal text"
else
    kt_test_fail "Replace - ignore case literal text (expected: 'X axb X', got: '$result')"
fi

# --- P5: the flag set decides, and it is FPC's (finding TSH-05) ------------
# FPC (rtl/objpas/sysutils/syshelp.inc):
#     Replace(Old,New)        = StringReplace(Self,Old,New,[rfReplaceAll])
#     Replace(Old,New,Flags)  = StringReplace(Self,Old,New,Flags)
# so OMITTING the flags means "all", while passing an EMPTY flag set means
# "the first occurrence only". The distinction is made on the argument COUNT,
# not on emptiness.
rep_is() {   # EXPECTED ARGS...
    local want="$1"; shift
    kt_test_start "replace $* -> '$want' [TSH-05]"
    RESULT="__unset__"
    string.replace "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "'$want'"
    else
        kt_test_fail "replace $* gave '$RESULT', expected '$want'"
    fi
}

rep_is "a+b+c" "a-b-c" "-" "+"
rep_is "a+b-c" "a-b-c" "-" "+" ""
rep_is "a+b+c" "a-b-c" "-" "+" "rfReplaceAll"
rep_is "hi hello" "hello hello" "HELLO" "hi" "rfIgnoreCase"
rep_is "hi hi"    "hello hello" "HELLO" "hi" "rfIgnoreCase rfReplaceAll"
rep_is "X axb X"  "a.b axb A.B" "a.b" "X" "rfReplaceAll rfIgnoreCase"
rep_is "ab"       "ab" "" "x"
rep_is "ab"       "ab" "" "x" "rfReplaceAll"
rep_is "aXbXc"    "a*b*c" "*" "X" "rfReplaceAll"
rep_is "a!b"      "a?b" "?" "!"
rep_is "a[b"      "a]b" "]" "["
rep_is "xbxbx"    "ababa" "a" "x"

# The replacement text is DATA: bash treats an unquoted `&` in ${s//p/r} as
# "the matched text" and a backslash as an escape, so both must survive.
rep_is 'a&b'      "a-b" "-" "&"
rep_is 'a&&b'     "a-b" "-" "&&"
rep_is 'a\nb'     "a-b" "-" '\n'
rep_is 'a\b'      "a-b" "-" '\'
rep_is "a-b"      "a&b" "&" "-"
rep_is "-n"       "x-n" "x" ""

# The replacement is not rescanned (FPC copies it into the result).
rep_is "aa"       "a" "a" "aa"
rep_is "--"       "-" "-" "--"

kt_test_start "an unknown flag token is ignored, like FPC's set syntax [TSH-05]"
RESULT="__unset__"
string.replace "a-b-c" "-" "+" "rfSomethingElse" >/dev/null 2>&1 || :
if [[ "$RESULT" == "a+b-c" ]]; then
    kt_test_pass "an unrecognised token leaves an empty flag set (first only)"
else
    kt_test_fail "got '$RESULT'"
fi

kt_test_start "replace does not fork [TSH-09, 1.8]"
body="$(declare -f string.__static_replace)"
body="${body//\$((/ARITH}"
if [[ "$body" != *'$('* && "$body" != *'`'* ]]; then
    kt_test_pass "no command substitution"
else
    kt_test_fail "the body shells out"
fi
