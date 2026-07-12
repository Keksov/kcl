#!/bin/bash
# 007_ValueQueries.sh - ContainsValue + GetValueDef (P2.2)
# FPC impl ref: ContainsValue :750-774 (linear scan, default equality).
# GetValueDef is a documented bash convenience (TryGetValue sugar), NOT in
# FPC TDictionary — see TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "007: ContainsValue and GetValueDef"

TDictionary.new d
d.Add a "apple"
d.Add b "banana"
d.Add c "apple"        # duplicate VALUE under a different key — legal

kt_test_start "ContainsValue hit / miss via exit status"
if d.ContainsValue "banana" && ! d.ContainsValue "cherry"; then
    kt_test_pass "hit rc=0, miss rc!=0"
else
    kt_test_fail "ContainsValue broken"
fi

kt_test_start "ContainsValue: duplicate values still found after removing ONE holder"
d.Remove a
if d.ContainsValue "apple"; then
    kt_test_pass "second holder (c) still matches"
else
    kt_test_fail "value lost though key c still holds it"
fi

kt_test_start "ContainsValue: gone after the LAST holder is removed"
d.Remove c
if ! d.ContainsValue "apple"; then
    kt_test_pass "no holders -> miss"
else
    kt_test_fail "phantom value"
fi

kt_test_start "ContainsValue: empty-string value"
d.Add hollow ""
if d.ContainsValue ""; then
    kt_test_pass "'' value found"
else
    kt_test_fail "'' value not found"
fi

kt_test_start "ContainsValue: multiline value, exact match only"
v=$'line1\nline2'
d.Add ml "$v"
if d.ContainsValue "$v" && ! d.ContainsValue "line1"; then
    kt_test_pass "exact multiline match; substring does NOT match"
else
    kt_test_fail "multiline matching broken"
fi

kt_test_start "ContainsValue on an EMPTY dict"
TDictionary.new empty
if ! empty.ContainsValue anything; then
    kt_test_pass "empty dict -> rc!=0 (FPC: Length(FItems)=0 -> False)"
else
    kt_test_fail "empty dict claims a value"
fi
empty.delete

kt_test_start "GetValueDef: present key returns the stored value"
d.GetValueDef b "DFLT" >/dev/null
if [[ "$RESULT" == "banana" ]]; then
    kt_test_pass "stored value wins"
else
    kt_test_fail "RESULT=[$RESULT]"
fi

kt_test_start "GetValueDef: present key with EMPTY value returns '' (not the default)"
d.GetValueDef hollow "DFLT" >/dev/null
if [[ "$RESULT" == "" ]]; then
    kt_test_pass "existence decides, not truthiness"
else
    kt_test_fail "RESULT=[$RESULT] — default leaked over a stored ''"
fi

kt_test_start "GetValueDef: absent key returns the default"
d.GetValueDef ghost "DFLT" >/dev/null
rc=$?
if [[ $rc -eq 0 && "$RESULT" == "DFLT" ]]; then
    kt_test_pass "default delivered, rc=0 (never an error)"
else
    kt_test_fail "rc=$rc RESULT=[$RESULT]"
fi

kt_test_start "GetValueDef: absent key, default omitted -> ''"
d.GetValueDef ghost >/dev/null
if [[ "$RESULT" == "" ]]; then
    kt_test_pass "missing default defaults to ''"
else
    kt_test_fail "RESULT=[$RESULT]"
fi

d.delete

kt_test_log "007_ValueQueries.sh completed"
