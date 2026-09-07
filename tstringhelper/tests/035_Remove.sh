#!/bin/bash
# Remove
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Remove" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Remove from start index
kt_test_start "Remove - from start index"
result=$(string.remove "hello world" 5)
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Remove - from start index"
else
    kt_test_fail "Remove - from start index (expected: 'hello', got: '$result')"
fi

# Test 2: Remove with count
kt_test_start "Remove - with count"
result=$(string.remove "hello world" 0 5)
if [[ "$result" == " world" ]]; then
    kt_test_pass "Remove - with count"
else
    kt_test_fail "Remove - with count (expected: ' world', got: '$result')"
fi

# Test 3: Remove entire string
kt_test_start "Remove - entire string"
result=$(string.remove "hello" 0 5)
if [[ "$result" == "" ]]; then
    kt_test_pass "Remove - entire string"
else
    kt_test_fail "Remove - entire string (expected: '', got: '$result')"
fi

# Test 4: Remove nothing (start at end)
kt_test_start "Remove - nothing from end"
result=$(string.remove "hello" 5)
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Remove - nothing from end"
else
    kt_test_fail "Remove - nothing from end (expected: 'hello', got: '$result')"
fi

# Test 5: Remove middle section
kt_test_start "Remove - middle section"
result=$(string.remove "hello world test" 5 6)
if [[ "$result" == "hello test" ]]; then
kt_test_pass "Remove - middle section"
else
kt_test_fail "Remove - middle section (expected: 'hello test', got: '$result')"
fi

# Test 6: Remove single character
kt_test_start "Remove - single character"
result=$(string.remove "hello" 2 1)
if [[ "$result" == "helo" ]]; then
    kt_test_pass "Remove - single character"
else
    kt_test_fail "Remove - single character (expected: 'helo', got: '$result')"
fi

# Test 7: Remove from position 0
kt_test_start "Remove - from position 0"
result=$(string.remove "test" 0 2)
if [[ "$result" == "st" ]]; then
    kt_test_pass "Remove - from position 0"
else
    kt_test_fail "Remove - from position 0 (expected: 'st', got: '$result')"
fi

# Test 8: Remove with count larger than remaining
kt_test_start "Remove - count larger than string"
result=$(string.remove "hello" 2 100)
if [[ "$result" == "he" ]]; then
    kt_test_pass "Remove - count larger than string"
else
    kt_test_fail "Remove - count larger than string (expected: 'he', got: '$result')"
fi

# Test 9: Remove last character
kt_test_start "Remove - last character"
result=$(string.remove "hello" 4 1)
if [[ "$result" == "hell" ]]; then
    kt_test_pass "Remove - last character"
else
    kt_test_fail "Remove - last character (expected: 'hell', got: '$result')"
fi

# Test 10: Remove everything except first
kt_test_start "Remove - keep only first"
result=$(string.remove "hello world" 1)
if [[ "$result" == "h" ]]; then
    kt_test_pass "Remove - keep only first"
else
    kt_test_fail "Remove - keep only first (expected: 'h', got: '$result')"
fi

# --- P5: FPC Delete clamping (finding TSH-11) ------------------------------
# FPC: Remove(I) = Remove(I, Length-I); Remove(I,C) = Delete(Result,I+1,C),
# and Delete (rtl/inc/astrings.inc) does NOTHING when the 1-based index is
# past the end or below 1, or when the count is <= 0.
rm_is() {   # EXPECTED ARGS...
    local want="$1"; shift
    kt_test_start "remove $* -> '$want' [TSH-11]"
    RESULT="__unset__"
    string.remove "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "'$want'"
    else
        kt_test_fail "remove $* gave '$RESULT', expected '$want'"
    fi
}

rm_is "hello" hello -1
rm_is "hello" hello -1 3
rm_is ""      hello 0
rm_is "hello" hello 2 0
rm_is "hello" hello 2 -3
rm_is "hello" hello 5
rm_is "hello" hello 6
rm_is "hello" hello 99
rm_is "he"    hello 2 99
rm_is "hell"  hello 4 1

kt_test_start "an empty startIndex is a rejected value, not 0 [TSH-11, D1]"
rc=0; string.remove hello "" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
    kt_test_pass "rc 1, RESULT empty"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi
