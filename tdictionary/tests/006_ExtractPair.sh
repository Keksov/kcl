#!/bin/bash
# 006_ExtractPair.sh - ExtractPair (P2.1)
# FPC impl ref: ExtractPair :503-513 — hit: Result=(AKey, DoRemove(...)) with
# cnExtracted; miss: Exit(Default(TPair(TKey,TValue))) -> ('','') and rc=0
# (NOT an error). NB: FPC's miss shape equals the ''-key hit shape (Default
# key is '') — the same documented ambiguity exists here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "006: ExtractPair"

TDictionary.new d
d.Add alpha "VA"
d.Add beta "VB"

kt_test_start "hit: RESULT_KEY + RESULT set, pair removed"
d.ExtractPair alpha >/dev/null
rc=$?
if [[ $rc -eq 0 && "$RESULT_KEY" == "alpha" && "$RESULT" == "VA" && "$(d.count)" == "1" ]] \
   && ! d.ContainsKey alpha; then
    kt_test_pass "extracted (alpha,VA), count 2 -> 1"
else
    kt_test_fail "rc=$rc KEY=[$RESULT_KEY] VAL=[$RESULT] count=$(d.count)"
fi

kt_test_start "miss: Default pair ('',''), rc=0, dict untouched"
d.ExtractPair beta >/dev/null            # prime RESULT/RESULT_KEY... and re-add
d.Add beta "VB"                          # restore
d.ExtractPair missing >/dev/null
rc=$?
if [[ $rc -eq 0 && "$RESULT_KEY" == "" && "$RESULT" == "" && "$(d.count)" == "1" ]]; then
    kt_test_pass "miss is NOT an error; empty pair returned; stale values not leaked"
else
    kt_test_fail "rc=$rc KEY=[$RESULT_KEY] VAL=[$RESULT] count=$(d.count)"
fi

kt_test_start "''-key hit: same shape as miss (FPC ambiguity), value delivered"
d.Add "" "V-empty"
d.ContainsKey ""                          # the documented disambiguation step
had=$?
d.ExtractPair "" >/dev/null
if [[ $had -eq 0 && "$RESULT_KEY" == "" && "$RESULT" == "V-empty" ]] && ! d.ContainsKey ""; then
    kt_test_pass "extract of ''-keyed pair works; ContainsKey beforehand disambiguates"
else
    kt_test_fail "had=$had KEY=[$RESULT_KEY] VAL=[$RESULT]"
fi

kt_test_start "extracting the last pair empties the dict"
d.ExtractPair beta >/dev/null
if [[ "$RESULT" == "VB" && "$(d.count)" == "0" && ${#d_items[@]} -eq 0 ]]; then
    kt_test_pass "dict empty after last extraction"
else
    kt_test_fail "VAL=[$RESULT] count=$(d.count)"
fi

kt_test_start "exotic key extraction (newline key, glob key)"
d.Add $'x\ny' NL
d.Add '*' GLOB
d.ExtractPair $'x\ny' >/dev/null
ok1=$([[ "$RESULT_KEY" == $'x\ny' && "$RESULT" == "NL" ]] && echo 1 || echo 0)
d.ExtractPair '*' >/dev/null
ok2=$([[ "$RESULT_KEY" == '*' && "$RESULT" == "GLOB" ]] && echo 1 || echo 0)
if [[ $ok1 -eq 1 && $ok2 -eq 1 && "$(d.count)" == "0" ]]; then
    kt_test_pass "exotic keys extracted byte-exact"
else
    kt_test_fail "ok1=$ok1 ok2=$ok2 count=$(d.count)"
fi

kt_test_start "trailing-newline value survives extraction via RESULT"
v=$'tail\n\n'
d.Add tn "$v"
d.ExtractPair tn >/dev/null
if [[ "$RESULT" == "$v" ]]; then
    kt_test_pass "value lossless on the direct-call path"
else
    kt_test_fail "got $(printf '%q' "$RESULT")"
fi

kt_test_start "\$() caveat pinned: yields the value but does NOT mutate the parent"
d.Add cap CV
out="$(d.ExtractPair cap)"
if [[ "$out" == "CV" ]] && d.ContainsKey cap && [[ "$(d.GetItem cap)" == "CV" ]]; then
    kt_test_pass "subshell echo delivers the value; removal stayed in the subshell — use a DIRECT call for real extraction (RESULT_KEY/RESULT)"
else
    kt_test_fail "out=[$out] contains=$(d.ContainsKey cap; echo $?)"
fi

d.delete

kt_test_log "006_ExtractPair.sh completed"
