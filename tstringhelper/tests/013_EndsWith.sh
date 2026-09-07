#!/bin/bash
# EndsWith
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "EndsWith" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: String ends with substring (case sensitive)
kt_test_start "EndsWith - case sensitive match"
result=$(string.endsWith "hello world" "world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "EndsWith - case sensitive match"
else
    kt_test_fail "EndsWith - case sensitive match (expected: true, got: '$result')"
fi

# Test 2: String does not end with substring
kt_test_start "EndsWith - no match"
result=$(string.endsWith "hello world" "hello")
if [[ "$result" == "false" ]]; then
    kt_test_pass "EndsWith - no match"
else
    kt_test_fail "EndsWith - no match (expected: false, got: '$result')"
fi

# Test 3: Case sensitive - different case
kt_test_start "EndsWith - case mismatch"
result=$(string.endsWith "hello world" "WORLD")
if [[ "$result" == "false" ]]; then
    kt_test_pass "EndsWith - case mismatch"
else
    kt_test_fail "EndsWith - case mismatch (expected: false, got: '$result')"
fi

# Test 4: Empty suffix
kt_test_start "EndsWith - empty suffix"
result=$(string.endsWith "hello" "")
if [[ "$result" == "true" ]]; then
    kt_test_pass "EndsWith - empty suffix"
else
    kt_test_fail "EndsWith - empty suffix (expected: true, got: '$result')"
fi

# Test 5: Suffix longer than string
kt_test_start "EndsWith - suffix longer than string"
result=$(string.endsWith "hi" "hello world")
if [[ "$result" == "false" ]]; then
    kt_test_pass "EndsWith - suffix longer than string"
else
    kt_test_fail "EndsWith - suffix longer than string (expected: false, got: '$result')"
fi

# Test 6: Exact match
kt_test_start "EndsWith - exact match"
result=$(string.endsWith "hello" "hello")
if [[ "$result" == "true" ]]; then
    kt_test_pass "EndsWith - exact match"
else
    kt_test_fail "EndsWith - exact match (expected: true, got: '$result')"
fi

# Test 7: Single character match
kt_test_start "EndsWith - single character match"
result=$(string.endsWith "hello" "o")
if [[ "$result" == "true" ]]; then
    kt_test_pass "EndsWith - single character match"
else
    kt_test_fail "EndsWith - single character match (expected: true, got: '$result')"
fi

# Test 8: Empty string
kt_test_start "EndsWith - empty string"
result=$(string.endsWith "" "test")
if [[ "$result" == "false" ]]; then
    kt_test_pass "EndsWith - empty string"
else
    kt_test_fail "EndsWith - empty string (expected: false, got: '$result')"
fi

# Test 9: EndsWith with IgnoreCase parameter (if supported)
kt_test_start "EndsWith - ignore case true"
result=$(string.endsWith "hello world" "WORLD" true)
if [[ "$result" == "true" || "$result" == "error" ]]; then
    kt_test_pass "EndsWith - ignore case true"
else
    kt_test_fail "EndsWith - ignore case true (expected: true or error, got: '$result')"
fi

# Test 10: With special characters
kt_test_start "EndsWith - special characters"
result=$(string.endsWith "hello.txt" ".txt")
if [[ "$result" == "true" ]]; then
    kt_test_pass "EndsWith - special characters"
else
    kt_test_fail "EndsWith - special characters (expected: true, got: '$result')"
fi

# --- P5 review remark 2: EndsWith keeps TStringHelper's own rule -----------
# syshelp.inc: `L:=system.Length(AValue); Result:=L=0;` — an EMPTY value is
# TRUE here, the opposite of EndsText (test 012). Both are TStringHelper's,
# and the asymmetry is upstream's, so both are pinned.
kt_test_start "an empty value is TRUE for endsWith (TStringHelper) [P5-F2]"
RESULT="__unset__"; rc=0
string.endsWith "hello" "" >/dev/null 2>&1 || rc=$?
if (( rc == 0 )) && [[ "$RESULT" == "true" ]]; then
    kt_test_pass "rc 0 / true"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

kt_test_start "an empty value against an empty string is TRUE [P5-F2]"
RESULT="__unset__"; rc=0
string.endsWith "" "" >/dev/null 2>&1 || rc=$?
if (( rc == 0 )) && [[ "$RESULT" == "true" ]]; then
    kt_test_pass "rc 0 / true"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi
