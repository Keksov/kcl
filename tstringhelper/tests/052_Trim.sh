#!/bin/bash
# Trim
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Trim" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim spaces
kt_test_start "Trim leading and trailing spaces"
result=$(string.trim "  hello world  ")
if [[ "$result" == "hello world" ]]; then
    kt_test_pass "Trim leading and trailing spaces"
else
    kt_test_fail "Trim leading and trailing spaces (expected: 'hello world', got: '$result')"
fi

# Test 2: No spaces to trim
kt_test_start "Trim no spaces"
result=$(string.trim "hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim no spaces"
else
    kt_test_fail "Trim no spaces (expected: 'hello', got: '$result')"
fi

# Test 3: Only spaces
kt_test_start "Trim only spaces"
result=$(string.trim "   ")
if [[ "$result" == "" ]]; then
    kt_test_pass "Trim only spaces"
else
    kt_test_fail "Trim only spaces (expected: '', got: '$result')"
fi

# Test 4: Leading spaces
kt_test_start "Trim leading spaces"
result=$(string.trim "  hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim leading spaces"
else
    kt_test_fail "Trim leading spaces (expected: 'hello', got: '$result')"
fi

# Test 5: Trailing spaces
kt_test_start "Trim trailing spaces"
result=$(string.trim "hello  ")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim trailing spaces"
else
    kt_test_fail "Trim trailing spaces (expected: 'hello', got: '$result')"
fi

# --- P5: FPC's Trim set is [#0..' '], not [[:space:]] (finding TSH-12) -----
# rtl/objpas/sysutils/sysstr.inc:624  `Const WhiteSpace = [#0..' '];`
# Trim/TrimLeft/TrimRight strip every character with a code <= 32, which is
# the six ASCII whitespace characters PLUS the other C0 control characters.
# DEL (#127) is NOT in the set, and [[:cntrl:]] would have swept it up.
trim_is() {   # TITLE EXPECTED MEMBER INPUT
    local title="$1" want="$2" member="$3" in="$4"
    kt_test_start "$title"
    RESULT="__unset__"
    "$member" "$in" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title (expected $(printf '%q' "$want"), got $(printf '%q' "$RESULT"))"
    fi
}

trim_is "trim strips tab and newline [TSH-12]"        "x" string.trim      $'\t\nx\n\t'
trim_is "trim strips vertical tab and form feed [TSH-12]" "x" string.trim  $'\v\fx\f\v'
trim_is "trim strips carriage return [TSH-12]"        "x" string.trim      $'\rx\r'
trim_is "trim strips SOH and STX (control chars) [TSH-12]" "x" string.trim $'\001x\002'
trim_is "trim strips ESC [TSH-12]"                    "x" string.trim      $'\033x\033'
trim_is "trim keeps DEL, which is #127 (FPC set ends at #32) [TSH-12]" \
    $'\177x\177' string.trim $'\177x\177'
trim_is "trim keeps inner control characters [TSH-12]" $'a\tb' string.trim $' a\tb '
trim_is "trimLeft strips control characters [TSH-12]" $'x\t' string.trimLeft  $'\001\t x\t'
trim_is "trimRight strips control characters [TSH-12]" $'\tx' string.trimRight $'\tx \t\001'
trim_is "trim of only control characters is empty [TSH-12]" "" string.trim $'\001\002\t\n '
trim_is "trim keeps a value that looks like an echo option [X-ECHO]" "-n" string.trim "  -n  "
trim_is "trim keeps inner newlines [TSH-12]" $'a\nb' string.trim $'  a\nb  '

# --- trimStart / trimEnd take an explicit character SET (FPC) --------------
set_is() {   # TITLE EXPECTED MEMBER INPUT SET
    kt_test_start "$1"
    RESULT="__unset__"
    "$3" "$4" "$5" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$2" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected $(printf '%q' "$2"), got $(printf '%q' "$RESULT"))"
    fi
}

set_is "trimStart with an EMPTY set changes nothing (FPC HaveChar) [TSH-12]" \
    "abc" string.trimStart "abc" ""
set_is "trimEnd with an EMPTY set changes nothing (FPC HaveChar) [TSH-12]" \
    "abc" string.trimEnd "abc" ""
set_is "trimStart does not strip whitespace unless it is in the set [TSH-12]" \
    "  abc" string.trimStart "  abc" "."
set_is "trimEnd does not strip whitespace unless it is in the set [TSH-12]" \
    "abc  " string.trimEnd "abc  " "."
set_is "trimStart of a string made only of set characters is empty [TSH-12]" \
    "" string.trimStart "..." "."
set_is "trimEnd of a string made only of set characters is empty [TSH-12]" \
    "" string.trimEnd "..." "."
set_is "trimStart with a glob metacharacter in the set [TSH-12]" \
    "abc" string.trimStart "**abc" "*"
set_is "trimEnd with a bracket in the set [TSH-12]" \
    "abc" string.trimEnd "abc]]" "]"
