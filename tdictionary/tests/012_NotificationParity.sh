#!/bin/bash
# 012_NotificationParity.sh - FPC-seed notification scenarios (P5.2)
# Ports the assertion logic of rtl-generics tests.generics.dictionary.pas:
#   TestValueNotification        -> values notified 'added' on Add
#   TestValueNotificationDelete  -> values notified 'removed' on Remove/Free
#   TestNotificationDelete       -> keys notified 'removed' on Remove/Free
#   TestKeyValueNotificationSet  -> dict[k]:=v => value old-removed + new-added,
#                                   key silent
# adapted to the bash callback contract: cb <dict> <item> <action>.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "012: notification parity (dictionary.pas analogs)"

declare -a KLOG=() VLOG=()
k_rec() { KLOG+=("$2:$3"); }
v_rec() { VLOG+=("$2:$3"); }

kt_test_start "TestValueNotification analog: Add sequence notifies values 'added' in order"
TDictionary.new d
d.onValueNotify = v_rec
VLOG=()
d.Add k1 v1
d.Add k2 v2
d.Add k3 v3
if [[ "${VLOG[*]}" == "v1:added v2:added v3:added" ]]; then
    kt_test_pass "3 adds -> 3 value-added events in call order"
else
    kt_test_fail "VLOG: ${VLOG[*]}"
fi

kt_test_start "TestValueNotificationDelete analog: Remove notifies values 'removed'"
VLOG=()
d.Remove k1
d.Remove k2
if [[ "${VLOG[*]}" == "v1:removed v2:removed" ]]; then
    kt_test_pass "2 removes -> 2 value-removed events"
else
    kt_test_fail "VLOG: ${VLOG[*]}"
fi

kt_test_start "TestNotificationDelete analog: keys 'removed' on Remove AND on Free"
d.onKeyNotify = k_rec
KLOG=()
d.Remove k3            # explicit remove
d.Add k4 v4
KLOG_BEFORE_FREE=${#KLOG[@]}
d.delete               # Free -> Destroy -> Clear -> removal events
if [[ "${KLOG[*]}" == "k3:removed k4:added k4:removed" && $KLOG_BEFORE_FREE -eq 2 ]]; then
    kt_test_pass "explicit remove + destructor removal both notified"
else
    kt_test_fail "KLOG: ${KLOG[*]}"
fi

kt_test_start "TestKeyValueNotificationSet analog: overwrite = value swap, key silent"
TDictionary.new s
s.onKeyNotify = k_rec
s.onValueNotify = v_rec
s.Add key OLD
KLOG=(); VLOG=()
s.SetItem key MID          # Items[key] := MID
s.AddOrSetValue key NEW    # AddOrSetValue over existing
if [[ "${VLOG[*]}" == "OLD:removed MID:added MID:removed NEW:added" && ${#KLOG[@]} -eq 0 ]]; then
    kt_test_pass "two overwrites -> four value events, zero key events"
else
    kt_test_fail "VLOG: ${VLOG[*]} KLOG: ${KLOG[*]}"
fi
s.delete

kt_test_start "Assign notifies: old content removed, copied pairs added"
TDictionary.new src2; src2.Add n1 w1; src2.Add n2 w2
TDictionary.new dst2; dst2.Add old wOLD
dst2.onKeyNotify = k_rec
dst2.onValueNotify = v_rec
KLOG=(); VLOG=()
dst2.Assign src2
ksorted="$(printf '%s\n' "${KLOG[@]}" | sort | tr '\n' ' ')"
vsorted="$(printf '%s\n' "${VLOG[@]}" | sort | tr '\n' ' ')"
if [[ "$ksorted" == "n1:added n2:added old:removed " \
      && "$vsorted" == "w1:added w2:added wOLD:removed " ]]; then
    kt_test_pass "removal of prior content + addition of copies all notified"
else
    kt_test_fail "K: $ksorted V: $vsorted"
fi
src2.delete; dst2.delete

kt_test_start "AddPairs notifies each inserted pair"
TDictionary.new b
b.onValueNotify = v_rec
VLOG=()
b.AddPairs p1 q1 p2 q2
if [[ "${VLOG[*]}" == "q1:added q2:added" ]]; then
    kt_test_pass "bulk insert -> per-pair added events"
else
    kt_test_fail "VLOG: ${VLOG[*]}"
fi
b.delete

kt_test_log "012_NotificationParity.sh completed"
