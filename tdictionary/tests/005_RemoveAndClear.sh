#!/bin/bash
# 005_RemoveAndClear.sh - Remove / Clear (P1.3)
# FPC seed: tests.generics.dictionary2.pas (DoTestRemove — remove-existing path).
# FPC impl refs: Remove :492 (absent key -> silent no-op), Clear :515.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "005: Remove and Clear"

TDictionary.new d
d.Add a A
d.Add b B
d.Add c C

kt_test_start "Remove existing: gone, count-1, neighbors intact"
d.Remove b
rc=$?
if [[ $rc -eq 0 && "$(d.count)" == "2" ]] && ! d.ContainsKey b \
   && [[ "$(d.GetItem a)" == "A" && "$(d.GetItem c)" == "C" ]]; then
    kt_test_pass "b removed, a/c untouched"
else
    kt_test_fail "rc=$rc count=$(d.count)"
fi

kt_test_start "Remove absent: SILENT no-op, rc=0 (FPC parity)"
errf="${TMPDIR:-/tmp}/td005_err.$$"
d.Remove b 2>"$errf"            # direct call — keep the no-op observable in THIS shell
rc=$?
err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
if [[ $rc -eq 0 && -z "$err" && "$(d.count)" == "2" ]]; then
    kt_test_pass "second Remove of same key: rc=0, no output, count stable"
else
    kt_test_fail "rc=$rc err=[$err] count=$(d.count)"
fi

kt_test_start "Remove never-existed key: rc=0"
d.Remove never_was
rc=$?
if [[ $rc -eq 0 && "$(d.count)" == "2" ]]; then
    kt_test_pass "silent no-op"
else
    kt_test_fail "rc=$rc count=$(d.count)"
fi

kt_test_start "Re-Add after Remove works (no tombstone artifacts)"
d.Add b B2
if [[ "$(d.GetItem b)" == "B2" && "$(d.count)" == "3" ]]; then
    kt_test_pass "b re-added with a new value"
else
    kt_test_fail "value=$(d.GetItem b) count=$(d.count)"
fi

kt_test_start "Remove exotic keys (empty, newline, glob)"
d.Add "" E; d.Add $'n\nl' N; d.Add '*' G
before=$(d.count)
d.Remove ""; d.Remove $'n\nl'; d.Remove '*'
after=$(d.count)
if [[ "$before" == "6" && "$after" == "3" ]] && ! d.ContainsKey "" && ! d.ContainsKey '*'; then
    kt_test_pass "exotic keys removed cleanly (6 -> 3)"
else
    kt_test_fail "before=$before after=$after"
fi

kt_test_start "Clear on populated dict: count 0, storage empty"
d.Clear
if [[ "$(d.count)" == "0" && ${#d_items[@]} -eq 0 ]]; then
    kt_test_pass "cleared"
else
    kt_test_fail "count=$(d.count) storage=${#d_items[@]}"
fi

kt_test_start "Dict fully usable after Clear"
d.Add fresh F
if [[ "$(d.GetItem fresh)" == "F" && "$(d.count)" == "1" ]]; then
    kt_test_pass "add-after-Clear ok"
else
    kt_test_fail "count=$(d.count)"
fi

kt_test_start "Interleaved sequence: final state matches storage exactly"
d.Clear
d.Add k1 1; d.Add k2 2; d.Remove k1; d.Add k3 3
d.AddOrSetValue k2 22; d.Remove nope; d.TryAdd k3 33; d.Add k4 4
# expected final: k2=22, k3=3, k4=4  (k1 removed; TryAdd k3 rejected)
if [[ "$(d.count)" == "3" && ${#d_items[@]} -eq 3 \
      && "$(d.GetItem k2)" == "22" && "$(d.GetItem k3)" == "3" && "$(d.GetItem k4)" == "4" ]] \
   && ! d.ContainsKey k1; then
    kt_test_pass "state machine consistent (count==storage==3)"
else
    kt_test_fail "count=$(d.count) storage=${#d_items[@]} k2=$(d.GetItem k2) k3=$(d.GetItem k3)"
fi

d.delete

kt_test_log "005_RemoveAndClear.sh completed"
