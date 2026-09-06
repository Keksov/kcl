#!/bin/bash
# 013_ObjectDictionary.sh - TObjectDictionary ownership matrix (P6)
# FPC refs: TObjectDictionary = TObjectOpenAddressingLP (dictionariesh.inc:669);
# KeyNotify/ValueNotify overrides free the item after `inherited` iff the
# ownership flag is set AND the action is cnRemoved (impl:2389-2405) — never
# on cnExtracted. Owned items here are kklass instance names; freeing calls
# `$item.delete`; non-instance strings are skipped silently.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "013: TObjectDictionary ownerships"

alive() { declare -F "$1.delete" >/dev/null 2>&1; }

kt_test_start "constructor: token forms and validation"
TObjectDictionary.new c1 doOwnsValues
TObjectDictionary.new c2 doOwnsKeys
TObjectDictionary.new c3 "doOwnsKeys doOwnsValues"
TObjectDictionary.new c4 "doOwnsKeys,doOwnsValues"
TObjectDictionary.new c5 ""
TObjectDictionary.new c6 doOwnsEverything 2>/dev/null
rc6=$?
if [[ $rc6 -eq 1 ]] && alive c1 && alive c5; then
    kt_test_pass "value/key/both/comma/empty accepted; unknown token rc=1"
else
    kt_test_fail "rc6=$rc6"
fi
c1.delete; c2.delete; c3.delete; c4.delete; c5.delete; c6.delete 2>/dev/null

# Decision R3 (review 2026-09-06, finding G2-10): a REJECTED constructor token
# leaves a usable instance carrying the class DEFAULTS, plus rc 1 — identically
# in tqueuestack (default owning) and here (default: no ownership). The old
# test only checked that rc was 1 and that OTHER instances were alive; nothing
# pinned the state of the instance whose token was refused, and a half-applied
# ownership set is exactly the kind of drift that frees a caller's live object.
kt_test_start "R3: a rejected ctor token leaves an instance with DEFAULTS + rc 1 [G2-10]"
TObjectDictionary.new r1 "doOwnsKeys,bogus" 2>/dev/null
rc1=$?
TDictionary.new keyobj
r1.Add keyobj v0
r1.Remove keyobj          # non-owning default => the key instance survives
n1="$(r1.count)"
kobj_alive=freed; alive keyobj && kobj_alive=alive
r1.delete
if [[ $rc1 -eq 1 && "$n1" == "0" && "$kobj_alive" == "alive" ]] && ! alive r1; then
    kt_test_pass "rc 1, usable, non-owning defaults, clean delete"
else
    kt_test_fail "rc=$rc1 count=$n1 key=$kobj_alive"
fi
alive keyobj && keyobj.delete

# Decision R4 (review 2026-09-06): storing an owned value back over ITSELF
# frees it — FPC's TObjectDictionary.SetValue runs Notify(cnRemoved) on the old
# value without comparing pointers, and bash cannot tell "the same handle" from
# "another handle with the same name". Kept as parity, documented in README.md
# with the guard idiom; pinned here so the behaviour cannot drift silently.
kt_test_start "R4: AddOrSetValue with the SAME owned handle frees it (FPC parity)"
TObjectDictionary.new r4 doOwnsValues
TDictionary.new payload
r4.Add k payload
r4.AddOrSetValue k payload
same_state=alive; alive payload || same_state=freed
r4.GetItem k; stored="$RESULT"
r4.delete
if [[ "$same_state" == "freed" && "$stored" == "payload" ]]; then
    kt_test_pass "handle freed, the dead name is still stored (documented)"
else
    kt_test_fail "payload=$same_state stored='$stored'"
fi
alive payload && payload.delete

kt_test_start "R4 counterpart: TObjectList.Put with the same handle does NOT free"
# The asymmetry is upstream's (TList.Put notifies only when the pointer really
# changes); the README says so, and this is the other half of the claim.
source "$SCRIPT_DIR/../../tobjectlist/tobjectlist.sh"
TObjectList.new ol
TDictionary.new held
ol.Add held
ol.Put 0 held
put_state=alive; alive held || put_state=freed
ol.delete
[[ "$put_state" == "alive" ]] && kt_test_pass "same-handle Put is a no-op" \
    || kt_test_fail "held=$put_state"
alive held && held.delete

kt_test_start "inherited API surface intact (Add/GetItem/count/Keys)"
TObjectDictionary.new od doOwnsValues
od.Add k0 plainstring
if [[ "$(od.GetItem k0)" == "plainstring" && "$(od.count)" == "1" && "$(od.Keys)" == "k0" ]]; then
    kt_test_pass "subclass inherits the full TDictionary surface"
else
    kt_test_fail "surface broken"
fi
od.Remove k0

kt_test_start "doOwnsValues: Remove FREES the value instance"
TDictionary.new v1
od.Add a v1
od.Remove a
if ! alive v1; then
    kt_test_pass "v1 freed on remove"
else
    kt_test_fail "v1 still alive"; v1.delete
fi

kt_test_start "doOwnsValues: ExtractPair does NOT free (ownership handed back)"
TDictionary.new v2
od.Add b v2
od.ExtractPair b >/dev/null
if alive v2 && [[ "$RESULT" == "v2" ]]; then
    kt_test_pass "v2 alive after extraction, caller owns it now"
else
    kt_test_fail "v2 freed or wrong RESULT=[$RESULT]"
fi
v2.delete

kt_test_start "doOwnsValues: AddOrSetValue overwrite frees the REPLACED value only"
TDictionary.new v3; TDictionary.new v4
od.Add c v3
od.AddOrSetValue c v4
if ! alive v3 && alive v4; then
    kt_test_pass "old freed, new alive"
else
    kt_test_fail "v3-alive=$(alive v3 && echo y || echo n) v4-alive=$(alive v4 && echo y || echo n)"
fi

kt_test_start "doOwnsValues: SetItem overwrite frees the replaced value"
TDictionary.new v5
od.SetItem c v5
if ! alive v4 && alive v5; then
    kt_test_pass "SetItem swap freed v4, kept v5"
else
    kt_test_fail "v4/v5 state wrong"
fi

kt_test_start "failed duplicate Add frees NOTHING"
TDictionary.new v6
od.Add c v6 2>/dev/null
rc=$?
if [[ $rc -eq 1 ]] && alive v5 && alive v6 && [[ "$(od.GetItem c)" == "v5" ]]; then
    kt_test_pass "raise precedes notify: both instances alive, value unchanged"
else
    kt_test_fail "rc=$rc"
fi
v6.delete

kt_test_start "doOwnsValues: Clear frees every owned value"
TDictionary.new v7
od.Add d2 v7
od.Clear
if ! alive v5 && ! alive v7 && [[ "$(od.count)" == "0" ]]; then
    kt_test_pass "all values freed on Clear"
else
    kt_test_fail "leak after Clear"
fi

kt_test_start "doOwnsValues: destroy (.delete) frees remaining owned values"
TDictionary.new v8
od.Add e v8
od.delete
if ! alive v8; then
    kt_test_pass "destructor freed v8"
else
    kt_test_fail "v8 leaked"; v8.delete
fi

kt_test_start "plain-string values under doOwnsValues are skipped silently"
TObjectDictionary.new od2 doOwnsValues
od2.Add s "not an instance"
errf="${TMPDIR:-/tmp}/td013_err.$$"
od2.Remove s 2>"$errf"          # direct call — $() would mutate a subshell copy only
rc=$?
err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
if [[ $rc -eq 0 && -z "$err" && "$(od2.count)" == "0" ]]; then
    kt_test_pass "no error, no output, pair really removed in the parent shell"
else
    kt_test_fail "rc=$rc err=[$err] count=$(od2.count)"
fi
od2.delete

kt_test_start "doOwnsKeys: Remove frees the KEY instance, value untouched"
TObjectDictionary.new odk doOwnsKeys
TDictionary.new kobj; TDictionary.new vobj
odk.Add kobj vobj
odk.Remove kobj
if ! alive kobj && alive vobj; then
    kt_test_pass "key freed, value alive (no doOwnsValues)"
else
    kt_test_fail "kobj-alive=$(alive kobj && echo y || echo n) vobj-alive=$(alive vobj && echo y || echo n)"
fi
vobj.delete; odk.delete

kt_test_start "both flags: key AND value freed on Remove"
TObjectDictionary.new odb "doOwnsKeys doOwnsValues"
TDictionary.new bk; TDictionary.new bv
odb.Add bk bv
odb.Remove bk
if ! alive bk && ! alive bv; then
    kt_test_pass "both freed"
else
    kt_test_fail "bk-alive=$(alive bk && echo y || echo n) bv-alive=$(alive bv && echo y || echo n)"
fi
odb.delete

kt_test_start "no ownerships: nothing is ever freed (plain TDictionary behavior)"
TObjectDictionary.new odn ""
TDictionary.new n1
odn.Add x n1
odn.Remove x
odn.delete
if alive n1; then
    kt_test_pass "n1 alive through remove+destroy"
    n1.delete
else
    kt_test_fail "n1 freed without ownership"
fi

kt_test_start "user callbacks fire BEFORE the free (inherited first)"
TObjectDictionary.new odc doOwnsValues
TDictionary.new w1
WAS_ALIVE_AT_EVENT=""
vcb() { [[ "$3" == "removed" ]] && { declare -F "$2.delete" >/dev/null 2>&1 && WAS_ALIVE_AT_EVENT=1; }; }
odc.onValueNotify = vcb
odc.Add k w1
odc.Remove k
if [[ "$WAS_ALIVE_AT_EVENT" == "1" ]] && ! alive w1; then
    kt_test_pass "event saw the instance alive; freed right after (FPC order: inherited, then Free)"
else
    kt_test_fail "at-event=$WAS_ALIVE_AT_EVENT after=$(alive w1 && echo alive || echo freed)"
fi
odc.delete

kt_test_start "leak scan: freed instances leave no storage globals behind"
leak=""
for v in v1 v3 v4 v5 v7 v8; do
    declare -p "${v}_items" >/dev/null 2>&1 && leak+="$v "
done
if [[ -z "$leak" ]]; then
    kt_test_pass "no ${v}_items leftovers for freed instances"
else
    kt_test_fail "leaked storage: $leak"
fi

kt_test_log "013_ObjectDictionary.sh completed"
