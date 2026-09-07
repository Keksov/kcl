#!/bin/bash
# Substring
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Substring" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Substring from index
kt_test_start "Substring from index"
result=$(string.substring "hello world" 6)
if [[ "$result" == "world" ]]; then
    kt_test_pass "Substring from index"
else
    kt_test_fail "Substring from index (expected: 'world', got: '$result')"
fi

# Test 2: Substring with length
kt_test_start "Substring with length"
result=$(string.substring "hello world" 0 5)
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Substring with length"
else
    kt_test_fail "Substring with length (expected: 'hello', got: '$result')"
fi

# Test 3: Substring beyond length
kt_test_start "Substring beyond length"
result=$(string.substring "hello" 3 10)
if [[ "$result" == "lo" ]]; then
    kt_test_pass "Substring beyond length"
else
    kt_test_fail "Substring beyond length (expected: 'lo', got: '$result')"
fi

# Test 4: Start index 0
kt_test_start "Start index 0"
result=$(string.substring "hello" 0)
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Start index 0"
else
    kt_test_fail "Start index 0 (expected: 'hello', got: '$result')"
fi

# Test 5: Empty string
kt_test_start "Empty string substring"
result=$(string.substring "" 0)
if [[ "$result" == "" ]]; then
    kt_test_pass "Empty string substring"
else
    kt_test_fail "Empty string substring (expected: '', got: '$result')"
fi

# --- P5: FPC Copy clamping (finding TSH-11) --------------------------------
# FPC: Substring(I) = Substring(I, Length-I); Substring(I,L) = Copy(Self,I+1,L),
# and Copy (rtl/inc/astrings.inc, fpc_ansistr_copy) clamps like this:
#     dec(index); if Index<0 then Index:=0;
#     if (Size>Length(S)) or (Index+Size>Length(S)) then Size:=Length(S)-Index;
#     if Size<=0 then Result:='';
# so a negative start reads from the beginning, a negative length is empty and
# a start past the end is empty. The old member handed the raw numbers to
# ${s:i:n}, where a negative offset counts from the END of the string.
sub_is() {   # EXPECTED ARGS...
    local want="$1"; shift
    kt_test_start "substring $* -> '$want' [TSH-11]"
    RESULT="__unset__"
    string.substring "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "'$want'"
    else
        kt_test_fail "substring $* gave '$RESULT', expected '$want'"
    fi
}

sub_is "hello" hello -3
sub_is "hello" hello -1
sub_is ""      hello 1 -1
sub_is ""      hello 0 -5
sub_is ""      hello 10
sub_is ""      hello 10 2
sub_is ""      hello 5
sub_is ""      hello 0 0
sub_is "lo"    hello 3 10
sub_is "hello" hello 0 99
sub_is "ello"  hello 1
sub_is "el"    hello 1 2
sub_is "hel"   hello -2 3

kt_test_start "an empty startIndex is a rejected value, not 0 [D1]"
rc=0; string.substring hello "" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
    kt_test_pass "rc 1, RESULT empty"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi
