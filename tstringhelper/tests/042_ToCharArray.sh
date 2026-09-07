#!/bin/bash
# ToCharArray
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToCharArray" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To char array
kt_test_start "To char array"
result=$(string.toCharArray "hi")
expected=$'h\ni'
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "To char array"
else
    kt_test_fail "To char array (expected two lines 'h' and 'i', got: '$result')"
fi

# Test 2: To char array with range
kt_test_start "To char array - range"
result=$(string.toCharArray "hello" 1 3)
expected=$'e\nl\nl'
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "To char array - range"
else
    kt_test_fail "To char array - range (expected three lines 'e', 'l', 'l', got: '$result')"
fi

# --- P5: the optional output array (kcl/README.md 1.7) ---------------------
# Joining the characters with newlines cannot express a string that CONTAINS a
# newline, so toCharArray takes an optional array name as its fourth argument
# and then returns the character COUNT in RESULT. Without it the joined form
# is kept, so `$(string.toCharArray abc)` still prints one character per line.
kt_test_start "toCharArray fills a caller array and returns the count [1.7]"
declare -a chars=(sentinel)
RESULT="__unset__"
string.toCharArray "hi" 0 2 chars >/dev/null 2>&1 || :
if [[ "$RESULT" == "2" && "${chars[0]}" == "h" && "${chars[1]}" == "i" && ${#chars[@]} == 2 ]]; then
    kt_test_pass "2 characters"
else
    kt_test_fail "RESULT='$RESULT' chars=(${chars[*]})"
fi

kt_test_start "a newline is ONE element of the array [1.7]"
declare -a chars2=()
string.toCharArray $'a\nb' >/dev/null 2>&1 || :
string.toCharArray $'a\nb' 0 3 chars2 >/dev/null 2>&1 || :
if [[ "$RESULT" == "3" && "${chars2[1]}" == $'\n' ]]; then
    kt_test_pass "3 elements, the middle one is the newline"
else
    kt_test_fail "RESULT='$RESULT' element 1 = $(printf '%q' "${chars2[1]:-}")"
fi

kt_test_start "a reserved output array name is rc 2 [1.7]"
rc=0
string.toCharArray "abc" 0 3 RESULT >/dev/null 2>&1 || rc=$?
if (( rc == 2 )); then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "the range is clamped to the end of the string"
declare -a chars3=()
string.toCharArray "abc" 1 99 chars3 >/dev/null 2>&1 || :
if [[ "$RESULT" == "2" && "${chars3[0]}" == "b" && "${chars3[1]}" == "c" ]]; then
    kt_test_pass "2 characters"
else
    kt_test_fail "RESULT='$RESULT' chars=(${chars3[*]})"
fi

kt_test_start "a start index past the end is rc 1"
rc=0
string.toCharArray "abc" 9 1 >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then
    kt_test_pass "rc 1"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "non-ASCII characters are single elements [TSH-04]"
declare -a chars4=()
string.toCharArray "мир" 0 3 chars4 >/dev/null 2>&1 || :
if [[ "$RESULT" == "3" && "${chars4[0]}" == "м" && "${chars4[2]}" == "р" ]]; then
    kt_test_pass "м и р"
else
    kt_test_fail "RESULT='$RESULT' chars=(${chars4[*]})"
fi
