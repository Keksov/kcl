#!/bin/bash
# 011_Notifications.sh - onKeyNotify / onValueNotify mechanics (P5.1)
# FPC impl refs: KeyNotify/ValueNotify/PairNotify :40-70 (PairNotify = KeyNotify
# THEN ValueNotify), SetValue :54-63 (assign FIRST, then ValueNotify(old,
# removed) + ValueNotify(new, added), key silent), AddItem :420 (notify AFTER
# insertion), DoRemove :477 (notify AFTER removal), Clear :515 (storage emptied
# FIRST, then per-pair removed), Destroy :128 (Clear -> notifications fire).
# Callback contract: cb <dict> <item> <added|removed|extracted>.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "011: notification mechanics"

declare -a LOG=()
k_rec() { LOG+=("K:$2:$3"); }
v_rec() { LOG+=("V:$2:$3"); }
log_is() {  # compare LOG to expected tokens
    local exp=("$@")
    [[ ${#LOG[@]} -eq ${#exp[@]} ]] || return 1
    local i
    for i in "${!exp[@]}"; do
        [[ "${LOG[$i]}" == "${exp[$i]}" ]] || return 1
    done
}

kt_test_start "mutations with NO callbacks attached stay silent and correct"
TDictionary.new d
d.Add a 1 && d.AddOrSetValue a 2 && d.Remove a && [[ "$(d.count)" == "0" ]]
if [[ $? -eq 0 && ${#LOG[@]} -eq 0 ]]; then
    kt_test_pass "guard off: no events, semantics intact"
else
    kt_test_fail "unexpected events or failed ops"
fi

kt_test_start "property wiring: set and read back both hooks"
d.onKeyNotify = k_rec
d.onValueNotify = v_rec
if [[ "$(d.onKeyNotify)" == "k_rec" && "$(d.onValueNotify)" == "v_rec" ]]; then
    kt_test_pass "hooks stored"
else
    kt_test_fail "read-back: [$(d.onKeyNotify)] [$(d.onValueNotify)]"
fi

kt_test_start "Add fires KeyNotify THEN ValueNotify with 'added' (PairNotify order)"
LOG=()
d.Add x VX
if log_is "K:x:added" "V:VX:added"; then
    kt_test_pass "K before V, both added"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "duplicate Add fires NOTHING (raise precedes notify)"
LOG=()
d.Add x OTHER 2>/dev/null
if [[ $? -eq 1 && ${#LOG[@]} -eq 0 ]]; then
    kt_test_pass "no events on rejected Add"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "TryAdd: silent on present, K+V added on insert"
LOG=()
d.TryAdd x ZZZ
d.TryAdd y VY
if log_is "K:y:added" "V:VY:added"; then
    kt_test_pass "only the successful insert notified"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "SetItem overwrite: V(old,removed) THEN V(new,added), key SILENT"
LOG=()
d.SetItem y VY2
if log_is "V:VY:removed" "V:VY2:added"; then
    kt_test_pass "FPC SetValue order, no key event"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "SetItem miss: no events"
LOG=()
d.SetItem ghost g 2>/dev/null
if [[ ${#LOG[@]} -eq 0 ]]; then
    kt_test_pass "nothing fired"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "callback observes the NEW value already stored (FPC assigns first)"
SEEN_AT_EVENT=""
v_check() { [[ "$3" == "removed" ]] && SEEN_AT_EVENT="$(d.GetItem y)"; }
d.onValueNotify = v_check
d.SetItem y VY3
d.onValueNotify = v_rec
if [[ "$SEEN_AT_EVENT" == "VY3" ]]; then
    kt_test_pass "during old-removed event the dict already holds VY3"
else
    kt_test_fail "saw [$SEEN_AT_EVENT]"
fi

kt_test_start "AddOrSetValue: insert -> K+V added; overwrite -> V removed + V added"
LOG=()
d.AddOrSetValue z VZ
d.AddOrSetValue z VZ2
if log_is "K:z:added" "V:VZ:added" "V:VZ:removed" "V:VZ2:added"; then
    kt_test_pass "both branches correct"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "Remove: K+V removed AFTER the pair is gone; miss fires nothing"
GONE_AT_EVENT=""
k_check() { [[ "$3" == "removed" ]] && { d.ContainsKey "$2" || GONE_AT_EVENT=1; }; }
d.onKeyNotify = k_check
LOG=()
d.Remove z
d.Remove z
d.onKeyNotify = k_rec
if log_is "V:VZ2:removed" && [[ "$GONE_AT_EVENT" == "1" ]]; then
    kt_test_pass "value event logged, key event saw the pair already absent, miss silent"
else
    kt_test_fail "LOG: ${LOG[*]} gone=$GONE_AT_EVENT"
fi

kt_test_start "ExtractPair: 'extracted' action; miss fires nothing"
LOG=()
d.ExtractPair y >/dev/null
d.ExtractPair y >/dev/null
if log_is "K:y:extracted" "V:VY3:extracted"; then
    kt_test_pass "extracted pair notified once"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "Clear: per-pair removed events, storage ALREADY empty during them"
d.Clear                     # drop leftovers silently? no — collect then reset LOG
LOG=()
d.Add c1 V1
d.Add c2 V2
COUNT_AT_EVENT=""
k_cnt() { [[ "$3" == "removed" ]] && COUNT_AT_EVENT+="$(d.count)"; }
d.onKeyNotify = k_cnt
LOG=()
d.Clear
d.onKeyNotify = k_rec
sorted="$(printf '%s\n' "${LOG[@]}" | sort | tr '\n' ' ')"
if [[ "$sorted" == "V:V1:removed V:V2:removed " && "$COUNT_AT_EVENT" == "00" ]]; then
    kt_test_pass "2 value-removed events (set-compare), count was 0 during both"
else
    kt_test_fail "LOG: ${LOG[*]} count-at-event=[$COUNT_AT_EVENT]"
fi

kt_test_start "Destroy (.delete) fires removal events via Clear"
LOG=()
d.Add last VLAST
LOG=()
d.delete
sorted="$(printf '%s\n' "${LOG[@]}" | sort | tr '\n' ' ')"
if [[ "$sorted" == "K:last:removed V:VLAST:removed " ]]; then
    kt_test_pass "destructor notified the remaining pair"
else
    kt_test_fail "LOG: ${LOG[*]}"
fi

kt_test_start "unhooking (empty name) stops events; callback rc ignored"
TDictionary.new e
e.onValueNotify = v_fail
v_fail() { LOG+=("V:$2:$3"); return 5; }
LOG=()
e.Add k1 v1                  # rc-5 callback must not break Add
rc=$?
e.onValueNotify = ""
e.Add k2 v2
if [[ $rc -eq 0 && ${#LOG[@]} -eq 1 && "${LOG[0]}" == "V:v1:added" ]]; then
    kt_test_pass "one event before unhook; nonzero cb rc didn't fail the op"
else
    kt_test_fail "rc=$rc LOG: ${LOG[*]}"
fi

kt_test_start "invalid callback name: mutation still succeeds"
e.onKeyNotify = no_such_function_xyz
e.Add k3 v3 2>/dev/null
rc=$?
if [[ $rc -eq 0 && "$(e.GetItem k3)" == "v3" ]]; then
    kt_test_pass "op unaffected by a dangling hook"
else
    kt_test_fail "rc=$rc"
fi
e.delete

kt_test_start "callback receives the DICT NAME as \$1"
TDictionary.new sender
GOT_SENDER=""
s_rec() { GOT_SENDER="$1"; }
sender.onKeyNotify = s_rec
sender.Add sk sv
if [[ "$GOT_SENDER" == "sender" ]]; then
    kt_test_pass "sender == instance name"
else
    kt_test_fail "sender=[$GOT_SENDER]"
fi
sender.delete

kt_test_log "011_Notifications.sh completed"
