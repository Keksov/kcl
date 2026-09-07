#!/bin/bash
# StartsText
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "StartsText" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: String starts with substring (case insensitive)
kt_test_start "StartsText - starts with"
result=$(string.startsText "hello" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - starts with"
else
    kt_test_fail "StartsText - starts with (expected: true, got: '$result')"
fi

# Test 2: String does not start with substring
kt_test_start "StartsText - does not start with"
result=$(string.startsText "world" "hello world")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - does not start with"
else
    kt_test_fail "StartsText - does not start with (expected: false, got: '$result')"
fi

# Test 3: Case insensitive matching
kt_test_start "StartsText - case insensitive"
result=$(string.startsText "HELLO" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - case insensitive"
else
    kt_test_fail "StartsText - case insensitive (expected: true, got: '$result')"
fi

# Test 4: Match with mixed case
kt_test_start "StartsText - mixed case"
result=$(string.startsText "HeLLo" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - mixed case"
else
    kt_test_fail "StartsText - mixed case (expected: true, got: '$result')"
fi

# Test 5: Empty substring
kt_test_start "StartsText - empty substring is FALSE (TStringHelper rule)"
result=$(string.startsText "" "hello")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - empty substring"
else
    kt_test_fail "StartsText - empty substring (expected: false, got: <$result>)"
fi

# Test 6: Empty text
kt_test_start "StartsText - empty text"
result=$(string.startsText "hello" "")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - empty text"
else
    kt_test_fail "StartsText - empty text (expected: false, got: '$result')"
fi

# Test 7: Both empty
kt_test_start "StartsText - both empty is FALSE (TStringHelper rule)"
result=$(string.startsText "" "")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - both empty"
else
    kt_test_fail "StartsText - both empty (expected: false, got: <$result>)"
fi

# Test 8: Substring longer than text
kt_test_start "StartsText - substring longer"
result=$(string.startsText "hello world" "hi")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - substring longer"
else
    kt_test_fail "StartsText - substring longer (expected: false, got: '$result')"
fi

# Test 9: Exact match
kt_test_start "StartsText - exact match"
result=$(string.startsText "hello" "hello")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - exact match"
else
    kt_test_fail "StartsText - exact match (expected: true, got: '$result')"
fi

# Test 10: Single character
kt_test_start "StartsText - single character"
result=$(string.startsText "h" "hello")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - single character"
else
    kt_test_fail "StartsText - single character (expected: true, got: '$result')"
fi

# --- P5 review remark 2: the EndsText rule, applied to its sibling ---------
# TStringHelper has no StartsText member at all (only the EndsText class
# function), and StrUtils.AnsiStartsText answers TRUE for an empty subtext.
# Since this unit ports TStringHelper, startsText follows its sibling
# EndsText — an empty subtext is FALSE — so the two Text predicates agree.
# StartsWith/EndsWith are TStringHelper members and keep their own rule
# (`Result := L<=0`, i.e. an empty value is TRUE).
bool_is() {   # TITLE EXPECTED-RC EXPECTED-RESULT MEMBER ARGS...
    local title="$1" wantrc="$2" wantres="$3"; shift 3
    kt_test_start "$title"
    RESULT="__unset__"
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if (( rc == wantrc )) && [[ "$RESULT" == "$wantres" ]]; then
        kt_test_pass "rc $rc / $RESULT"
    else
        kt_test_fail "$title: rc=$rc RESULT='$RESULT' (wanted rc $wantrc / '$wantres')"
    fi
}

bool_is "an EMPTY subtext is false, like endsText [P5-F2]" \
    1 false string.startsText "" "hello world"
bool_is "an empty subtext against an empty text is false too [P5-F2]" \
    1 false string.startsText "" ""
bool_is "a non-empty subtext still matches case-insensitively [P5-F2]" \
    0 true string.startsText "HELLO" "hello world"
bool_is "an empty TEXT with a non-empty subtext is false [P5-F2]" \
    1 false string.startsText "x" ""
