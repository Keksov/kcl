#!/bin/bash
# 006_Events.sh — thashset P3: the OnNotify event seam.
#
# Source of truth: FPC 3.2.2 packages/rtl-generics/src/generics.collections.pas
# at the **release_3_2_2** tag. FPC has no virtual `Notify` on a set — the seam
# is the property plus a private forwarder:
#
#   TCustomSet<T>.OnNotify                 :526  read GetOnNotify write SetOnNotify
#                                                (both virtual abstract, :495/:496)
#   THashSet<T>.SetOnNotify                :2530 FOnNotify := AValue;
#                                                if Assigned(AValue) then
#                                                  FInternalDictionary.OnKeyNotify
#                                                    := InternalDictionaryNotify
#                                                else
#                                                  FInternalDictionary.OnKeyNotify := nil;
#   THashSet<T>.InternalDictionaryNotify   :2500 FOnNotify(Self, AItem, AAction);
#   THashSet<T>.GetOnNotify                :2525 Result := FInternalDictionary.OnKeyNotify;
#
# So: the SENDER handed to the callback is the SET (`Self`), not the internal
# dictionary; the whole event stream of a set is the internal dictionary's
# OnKeyNotify; and when no callback is assigned the dictionary is not hooked at
# all — nothing is dispatched. That is exactly the `_notify` gate here.
#
# The events themselves come from the members that mutate the dictionary:
#   Destroy  :2554  FInternalDictionary.Free   -> Clear -> `removed` per element (S5)
#   Add      :2559  Result := not ContainsKey; if Result then dict.Add  (cnAdded, S1)
#   Remove   :2566  DoRemove(LIndex, cnRemoved)                          (S2)
#   Extract  :2576  miss -> Exit(Default(T)) with NO DoRemove;           (S6)
#                   hit  -> DoRemove(LIndex, cnExtracted)
#   Clear    :2588  FInternalDictionary.Clear                            (S4)
# and, for the algebra, from the `Add`/`Remove` those four procedures drive
# (AddRange :2379, UnionWith :2417, IntersectWith :2425, ExceptWith :2442,
# SymmetricExceptWith :2450).
#
# Parity oracle: packages/rtl-generics/tests/tests.generics.sets.pas
# Test_TCustomSet_Notification :261–338 (entered through
# Test_THashSet_Notification :340). Ported case for case in section A, with the
# two `EnumerableStrings*` AddRange overloads mapped to our varargs AddRange.
#
# Port-local pins (documented in README.md / thashset.sh):
#   * the callback signature is `cb <inst> <item> <added|removed|extracted>`;
#   * `Notify` is a PUBLIC VIRTUAL seam (the house pattern), which FPC does not
#     have — `_notifyHook` lets a subclass that overrides it receive events with
#     no user callback attached;
#   * `onNotify NAME` is a validating setter: '' clears (rc 0), a name that is
#     not a function is rc 2 and leaves the current hook alone;
#   * a dangling callback name is a kk.debug line and a no-op, never a crash;
#   * the callback's exit status is IGNORED (an FPC event returns nothing);
#   * events fire AFTER the mutation, so a callback observes the new state, and
#     a callback that mutates the set is delivered its own events (re-entrant).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TS_DIR="$SCRIPT_DIR/.."
UNIT="$TS_DIR/thashset.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "006: THashSet events — onNotify / Notify / _notifyHook (P3)"

# ---------------------------------------------------------------------------
# a descendant that OVERRIDES the virtual seam — the reason `_notifyHook`
# exists. It arms the hook in its constructor (the TObjectDictionary pattern,
# tdictionary.sh:628) so events are dispatched with NO user callback attached.
# ---------------------------------------------------------------------------
HOOKREC=()

class TRecordingSet : THashSet
    public
        constructor Create
        override proc Notify
end

TRecordingSet.Create() {
    inherited
    _notifyHook=1
    return 0
}

TRecordingSet.Notify() {
    inherited Notify "$@"          # the user callback first, as FPC's overrides do
    HOOKREC+=("$1:$2")
    return 0
}

build TRecordingSet

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

REC=()
rec()      { REC+=("$2:$3"); return 0; }          # cb: <inst> <item> <action>
recsend()  { REC+=("$1|$2:$3"); return 0; }       # ... capturing the sender

# ms_is ARRNAME expected... — rc 0 iff the array holds exactly these entries as
# a MULTISET (order-insensitive: hash iteration order is unspecified). Fork-free
# and byte-exact, so exotic elements compare correctly.
ms_is() {
    local -n __a="$1"; shift
    local -a __exp=( "$@" )
    (( ${#__a[@]} == ${#__exp[@]} )) || return 1
    local -a __pool=( ${__a[@]+"${__a[@]}"} )
    local __e __i __hit
    for __e in ${__exp[@]+"${__exp[@]}"}; do
        __hit=-1
        for __i in "${!__pool[@]}"; do
            if [[ "${__pool[$__i]}" == "$__e" ]]; then __hit=$__i; break; fi
        done
        (( __hit >= 0 )) || return 1
        unset '__pool[$__hit]'
    done
    return 0
}

# fill_set NAME [elem...] — a fresh set with these elements (005's helper)
fill_set() {
    local __n="$1"; shift
    THashSet.new "$__n"
    local __e
    for __e in "$@"; do "$__n".Add "$__e" || :; done
}

# set_is NAME [expected...] — rc 0 iff the set holds EXACTLY these elements
set_is() {
    local __n="$1"; shift
    local -a __exp=( "$@" )
    local __e __c
    "$__n".Count; __c="$RESULT"
    [[ "$__c" == "${#__exp[@]}" ]] || return 1
    for __e in ${__exp[@]+"${__exp[@]}"}; do
        "$__n".Contains "$__e" || return 1
    done
    return 0
}

# consistent NAME — rc 0 iff Count, the raw storage and ToArray all agree.
# This is the invariant a mutating callback must not be able to break.
consistent() {
    local -n __st="${1}_items"
    local __keys=${#__st[@]}
    "$1".Count
    [[ "$RESULT" == "$__keys" ]] || return 1
    local -a __arr=()
    "$1".ToArray __arr || return 1
    [[ "$RESULT" == "$__keys" && ${#__arr[@]} -eq $__keys ]] || return 1
    return 0
}

# ---------------------------------------------------------------------------
# A. the FPC parity oracle, ported case for case:
#    tests.generics.sets.pas Test_TCustomSet_Notification :261-338
# ---------------------------------------------------------------------------

THashSet.new AS
THashSet.new LS
AS.on_notify = "rec"                      # :271  ASet.OnNotify := NotifyTestStr

kt_test_start "seed :274-279 — Add + 3x AddRange fire 'added' seven times, in call order"
REC=()
ok=1
AS.Add Aaa           || ok=0              # :275  AssertTrue(ASet.Add('Aaa'))
AS.AddRange Bbb Ccc  || ok=0              # :276  AddRange(['Bbb','Ccc'])
AS.AddRange Ddd Eee  || ok=0              # :277  AddRange(LStringsObj)  -> varargs
AS.AddRange Fff Ggg  || ok=0              # :278  AddRange(LStringsIntf) -> varargs
[[ $ok -eq 1 && "${REC[*]}" == "Aaa:added Bbb:added Ccc:added Ddd:added Eee:added Fff:added Ggg:added" ]] \
    && kt_test_pass "7 added, all AddRange folds True" || kt_test_fail "ok=$ok [${REC[*]}]"

kt_test_start "seed :282-286 — Remove -> cnRemoved, Extract -> cnExtracted"
REC=()
AS.Remove Ccc; rcR=$?                     # :284  AssertTrue(ASet.Remove('Ccc'))
AS.Extract Aaa; xv="$RESULT"              # :285  AssertEquals(Extract('Aaa'),'Aaa')
[[ $rcR -eq 0 && "$xv" == "Aaa" && "${REC[*]}" == "Ccc:removed Aaa:extracted" ]] \
    && kt_test_pass "the action split" || kt_test_fail "rc=$rcR v='$xv' [${REC[*]}]"

kt_test_start "seed :289-292 — ExceptWith fires 'removed' for the hit only"
LS.Add Bbb                                # :289  (LSet has NO listener)
REC=()
AS.ExceptWith LS                          # :291
[[ "${REC[*]}" == "Bbb:removed" ]] && kt_test_pass "one event, operand silent" \
    || kt_test_fail "[${REC[*]}]"

kt_test_start "seed :295-298 — IntersectWith fires 'removed' for the victims only"
LS.AddRange Eee Fff Ggg || :              # :295  LSet = {Bbb,Eee,Fff,Ggg}
REC=()
AS.IntersectWith LS                       # :297  ASet {Ddd,Eee,Fff,Ggg} -> {Eee,Fff,Ggg}
[[ "${REC[*]}" == "Ddd:removed" ]] && kt_test_pass "Ddd only" || kt_test_fail "[${REC[*]}]"

kt_test_start "seed :301-306 — SymmetricExceptWith: 'added' (pass 1) before 'removed' (pass 2)"
LS.Clear                                  # :301
LS.AddRange Fff FPC || :                  # :302
REC=()
AS.SymmetricExceptWith LS                 # :305  expects FPC cnAdded, Fff cnRemoved
[[ "${REC[*]}" == "FPC:added Fff:removed" ]] \
    && kt_test_pass "two-pass order is deterministic" || kt_test_fail "[${REC[*]}]"

kt_test_start "seed :309-313 — Remove then Extract again"
REC=()
AS.Remove Eee; rcR=$?                     # :311
AS.Extract Ggg; xv="$RESULT"              # :312
[[ $rcR -eq 0 && "$xv" == "Ggg" && "${REC[*]}" == "Eee:removed Ggg:extracted" ]] \
    && kt_test_pass "removed + extracted" || kt_test_fail "rc=$rcR v='$xv' [${REC[*]}]"

kt_test_start "seed :316-320 — UnionWith fires 'added' for the new element"
LS.Clear; LS.Add Polandball || :          # :316-317
REC=()
AS.UnionWith LS                           # :319
[[ "${REC[*]}" == "Polandball:added" ]] && kt_test_pass "one added" || kt_test_fail "[${REC[*]}]"

kt_test_start "seed :323-328 — Remove, then Clear fires 'removed' for what is left"
REC=()
AS.Remove FPC || :                        # :324
AS.Clear                                  # :327
[[ "${REC[*]}" == "FPC:removed Polandball:removed" ]] \
    && kt_test_pass "S4 over the last element" || kt_test_fail "[${REC[*]}]"

kt_test_start "seed :330-336 (S5) — ASet.Free fires 'removed' during delete"
REC=()
AS.Add Polandball || :                    # :331
AS.delete                                 # :335  ASet.Free -> FInternalDictionary.Free
[[ "${REC[*]}" == "Polandball:added Polandball:removed" ]] \
    && kt_test_pass "Destroy -> Clear -> events (FPC :2554)" || kt_test_fail "[${REC[*]}]"
LS.delete

# ---------------------------------------------------------------------------
# B. per-member sequences — the S-pins, one case each
# ---------------------------------------------------------------------------

kt_test_start "S1: Add new -> one 'added'; Add duplicate -> NO event, no mutation"
THashSet.new B1
B1.on_notify = "rec"
REC=()
B1.Add one; rc1=$?
B1.Add one 2>/dev/null; rc2=$?
B1.Count; n="$RESULT"
[[ $rc1 -eq 0 && $rc2 -eq 1 && "$n" == "1" && "${REC[*]}" == "one:added" ]] \
    && kt_test_pass "one event for two calls" || kt_test_fail "rc=$rc1/$rc2 n=$n [${REC[*]}]"

kt_test_start "S2: 'removed' fires AFTER the element is gone (callback sees Contains false)"
SEEN_PRESENT=; SEEN_COUNT=
probe() {
    REC+=("$2:$3")
    "$1".Contains "$2" && SEEN_PRESENT=yes || SEEN_PRESENT=no
    "$1".Count; SEEN_COUNT="$RESULT"
    return 0
}
B1.on_notify = "probe"
B1.Add two || :
REC=()
B1.Remove two
[[ "${REC[*]}" == "two:removed" && "$SEEN_PRESENT" == "no" && "$SEEN_COUNT" == "1" ]] \
    && kt_test_pass "post-mutation callback" || kt_test_fail "[${REC[*]}] present=$SEEN_PRESENT n=$SEEN_COUNT"

kt_test_start "S2: Remove miss fires nothing"
REC=()
B1.Remove nosuch 2>/dev/null; rc=$?
[[ $rc -eq 1 && ${#REC[@]} -eq 0 ]] && kt_test_pass "silent miss" || kt_test_fail "rc=$rc [${REC[*]}]"

kt_test_start "S6: Extract hit -> one 'extracted' AFTER removal; miss -> nothing"
B1.Add three || :
REC=(); SEEN_PRESENT=
B1.Extract three; v1="$RESULT"
r1="${REC[*]}"; p1="$SEEN_PRESENT"
REC=()
B1.Extract nosuch; v2="$RESULT"
[[ "$v1" == "three" && "$r1" == "three:extracted" && "$p1" == "no" \
   && "$v2" == "" && ${#REC[@]} -eq 0 ]] \
    && kt_test_pass "extracted after removal, miss silent" \
    || kt_test_fail "v1='$v1' r1='$r1' p1=$p1 v2='$v2' [${REC[*]}]"

kt_test_start "Extract's RESULT survives a callback that clobbers RESULT"
clobber() { RESULT="CLOBBERED"; return 0; }
B1.on_notify = "clobber"
B1.Add four || :
B1.Extract four
[[ "$RESULT" == "four" ]] && kt_test_pass "kk._return runs after the event" \
    || kt_test_fail "got '$RESULT'"
B1.delete

kt_test_start "S4: Clear empties FIRST — the first callback already sees Count 0"
CLEAR_COUNTS=()
ccb() { REC+=("$2:$3"); "$1".Count; CLEAR_COUNTS+=("$RESULT"); return 0; }
fill_set B2 c1 c2 c3
B2.on_notify = "ccb"
REC=()
B2.Clear
ok=1
for c in "${CLEAR_COUNTS[@]}"; do [[ "$c" == "0" ]] || ok=0; done
if [[ $ok -eq 1 && ${#CLEAR_COUNTS[@]} -eq 3 ]] && ms_is REC c1:removed c2:removed c3:removed; then
    kt_test_pass "empty-then-notify, 3 removed"
else
    kt_test_fail "counts=[${CLEAR_COUNTS[*]}] [${REC[*]}]"
fi

kt_test_start "S4: Clear on an empty set fires nothing"
REC=()
B2.Clear
[[ ${#REC[@]} -eq 0 ]] && kt_test_pass "no events" || kt_test_fail "[${REC[*]}]"
B2.delete

kt_test_start "S5: delete on a HOOK-LESS set fires nothing and still frees the storage"
fill_set B3 d1 d2
REC=()
B3.delete
alive=0; declare -p B3_items >/dev/null 2>&1 && alive=1
[[ ${#REC[@]} -eq 0 && $alive -eq 0 ]] && kt_test_pass "silent teardown" \
    || kt_test_fail "[${REC[*]}] alive=$alive"

kt_test_start "S5: delete on a hooked set fires 'removed' for EVERY element"
fill_set B4 e1 e2 e3
B4.on_notify = "rec"
REC=()
B4.delete
alive=0; declare -p B4_items >/dev/null 2>&1 && alive=1
if [[ $alive -eq 0 ]] && ms_is REC e1:removed e2:removed e3:removed; then
    kt_test_pass "3 removed then storage gone"
else
    kt_test_fail "[${REC[*]}] alive=$alive"
fi

kt_test_start "Assign: every 'removed' precedes every 'added' (two phases)"
fill_set B5 old1 old2
fill_set B6 new1 new2 new3
B5.on_notify = "rec"
REC=()
B5.Assign B6
# phase check: the last removed must come before the first added
last_rm=-1; first_add=-1
for i in "${!REC[@]}"; do
    case "${REC[$i]}" in
        *:removed) last_rm=$i ;;
        *:added)   [[ $first_add -lt 0 ]] && first_add=$i ;;
    esac
done
if (( last_rm >= 0 && first_add > last_rm )) \
   && ms_is REC old1:removed old2:removed new1:added new2:added new3:added; then
    kt_test_pass "2 removed then 3 added"
else
    kt_test_fail "[${REC[*]}] last_rm=$last_rm first_add=$first_add"
fi
B5.delete; B6.delete

kt_test_start "AddRange / AddRangeFromArray fire 'added' only for the genuinely new"
fill_set B7 keep
B7.on_notify = "rec"
REC=()
B7.AddRange keep fresh1 2>/dev/null || :
declare -a src=( keep fresh2 )
B7.AddRangeFromArray src 2>/dev/null || :
[[ "${REC[*]}" == "fresh1:added fresh2:added" ]] \
    && kt_test_pass "duplicates are silent" || kt_test_fail "[${REC[*]}]"
B7.delete

# ---------------------------------------------------------------------------
# C. the algebra ops — event multisets against the P2 truth tables
#    A = {a,b,c,d}, B = {c,d,e,f}
# ---------------------------------------------------------------------------

kt_test_start "UnionWith fires 'added' for the operand-only elements"
fill_set CA a b c d; fill_set CB c d e f
CA.on_notify = "rec"; REC=()
CA.UnionWith CB
if ms_is REC e:added f:added && set_is CA a b c d e f; then
    kt_test_pass "2 added (c,d skipped)" ; else kt_test_fail "[${REC[*]}]"; fi
CA.delete; CB.delete

kt_test_start "IntersectWith fires 'removed' for the victims only"
fill_set CA a b c d; fill_set CB c d e f
CA.on_notify = "rec"; REC=()
CA.IntersectWith CB
if ms_is REC a:removed b:removed && set_is CA c d; then
    kt_test_pass "2 removed"; else kt_test_fail "[${REC[*]}]"; fi
CA.delete; CB.delete

kt_test_start "ExceptWith fires 'removed' for the hits only"
fill_set CA a b c d; fill_set CB c d e f
CA.on_notify = "rec"; REC=()
CA.ExceptWith CB
if ms_is REC c:removed d:removed && set_is CA a b; then
    kt_test_pass "2 removed, e/f silent"; else kt_test_fail "[${REC[*]}]"; fi
CA.delete; CB.delete

kt_test_start "SymmetricExceptWith fires 'added' for operand-only and 'removed' for common"
fill_set CA a b c d; fill_set CB c d e f
CA.on_notify = "rec"; REC=()
CA.SymmetricExceptWith CB
last_add=-1; first_rm=-1
for i in "${!REC[@]}"; do
    case "${REC[$i]}" in
        *:added)   last_add=$i ;;
        *:removed) [[ $first_rm -lt 0 ]] && first_rm=$i ;;
    esac
done
if ms_is REC e:added f:added c:removed d:removed && set_is CA a b e f \
   && (( first_rm > last_add )); then
    kt_test_pass "2 added (pass 1) then 2 removed (pass 2)"
else
    kt_test_fail "[${REC[*]}] last_add=$last_add first_rm=$first_rm"
fi
CA.delete; CB.delete

kt_test_start "self-ops: a UNION a and a INTERSECT a fire NOTHING"
fill_set CS s1 s2 s3
CS.on_notify = "rec"; REC=()
CS.UnionWith CS
CS.IntersectWith CS
[[ ${#REC[@]} -eq 0 ]] && set_is CS s1 s2 s3 && kt_test_pass "no-ops are silent" \
    || kt_test_fail "[${REC[*]}]"

kt_test_start "self-ops: a EXCEPT a fires 'removed' x |a|"
REC=()
CS.ExceptWith CS
if ms_is REC s1:removed s2:removed s3:removed; then
    CS.Count; n="$RESULT"
    [[ "$n" == "0" ]] && kt_test_pass "3 removed, set empty" || kt_test_fail "n=$n"
else
    kt_test_fail "[${REC[*]}]"
fi

kt_test_start "self-ops: a SYMEXCEPT a fires 'removed' x |a|"
CS.AddRange t1 t2 || :
REC=()
CS.SymmetricExceptWith CS
if ms_is REC t1:removed t2:removed; then
    CS.Count; n="$RESULT"
    [[ "$n" == "0" ]] && kt_test_pass "2 removed, set empty" || kt_test_fail "n=$n"
else
    kt_test_fail "[${REC[*]}]"
fi
CS.delete

kt_test_start "an empty operand fires nothing; a rejected operand fires nothing"
fill_set CE x y
THashSet.new CF                      # empty
CE.on_notify = "rec"; REC=()
CE.UnionWith CF
CE.ExceptWith CF
CE.SymmetricExceptWith CF
CE.UnionWith not_a_set 2>/dev/null || :
CE.IntersectWith not_a_set 2>/dev/null || :
[[ ${#REC[@]} -eq 0 ]] && set_is CE x y && kt_test_pass "silent" || kt_test_fail "[${REC[*]}]"
CE.delete; CF.delete

# ---------------------------------------------------------------------------
# D. the callback signature, byte-exact, over exotic elements
# ---------------------------------------------------------------------------

DCANARY="$TMP/notify_pwn"
rm -f "$DCANARY"
declare -a DEX=( '' ']' '[' 'a]b' $'x\ny' "\$(touch '$DCANARY')" '*' "it's" 'a\b' 'k' 'kk' 'café' )

SREC=()
srec() { SREC+=("$1|$2|$3"); return 0; }

kt_test_start "cb receives <inst> <item> <action> byte-exact for 12 exotic elements"
THashSet.new DS
DS.on_notify = "srec"
SREC=()
DS.AddRange "${DEX[@]}"; rc=$?
exp=()
for e in "${DEX[@]}"; do exp+=( "DS|$e|added" ); done
[[ $rc -eq 0 && "${SREC[*]}" == "${exp[*]}" && ${#SREC[@]} -eq ${#DEX[@]} && ! -e "$DCANARY" ]] \
    && kt_test_pass "12 signatures byte-exact, nothing executed" \
    || kt_test_fail "rc=$rc n=${#SREC[@]} canary=$([[ -e $DCANARY ]] && echo yes || echo no)"

kt_test_start "the same 12 come back through Clear's 'removed' events"
SREC=()
DS.Clear
exp=()
for e in "${DEX[@]}"; do exp+=( "DS|$e|removed" ); done
if ms_is SREC "${exp[@]}"; then
    [[ ! -e "$DCANARY" ]] && kt_test_pass "12 removed, canary absent" \
        || kt_test_fail "the element was EXECUTED"
else
    kt_test_fail "n=${#SREC[@]}"
fi

kt_test_start "the '' element and 'k'/'kk' survive Remove/Extract events distinctly"
DS.AddRange '' k kk || :
SREC=()
DS.Remove ''
DS.Extract kk >/dev/null
DS.Remove k
[[ "${SREC[*]}" == "DS||removed DS|kk|extracted DS|k|removed" ]] \
    && kt_test_pass "k-prefix keeps them apart in the event stream" || kt_test_fail "[${SREC[*]}]"
DS.delete
rm -f "$DCANARY"

# ---------------------------------------------------------------------------
# E. mutating / re-entrant callbacks — the invariant must hold
# ---------------------------------------------------------------------------

kt_test_start "a callback that ADDS during Clear leaves a consistent set"
addcb() {
    REC+=("$2:$3")
    if [[ "$3" == "removed" ]]; then "$1".Add REBORN || :; fi
    return 0
}
fill_set E1 x1 x2 x3
E1.on_notify = "addcb"
REC=()
E1.Clear
if ms_is REC x1:removed x2:removed x3:removed REBORN:added \
   && set_is E1 REBORN && consistent E1; then
    kt_test_pass "3 removed + 1 added, Count==storage==ToArray"
else
    kt_test_fail "[${REC[*]}]"
fi
E1.delete

kt_test_start "a callback that REMOVES another element during UnionWith stays consistent"
remcb() {
    REC+=("$2:$3")
    if [[ "$2" == "c" && "$3" == "added" ]]; then "$1".Remove a || :; fi
    return 0
}
fill_set E2 a b; fill_set E3 c d
E2.on_notify = "remcb"
REC=()
E2.UnionWith E3
if ms_is REC c:added d:added a:removed && set_is E2 b c d && consistent E2; then
    kt_test_pass "re-entrant removal delivered, set = {b,c,d}"
else
    kt_test_fail "[${REC[*]}]"
fi
E2.delete; E3.delete

kt_test_start "a callback that calls Clear during Add leaves the set empty and consistent"
CB_DEPTH=0
clearcb() {
    REC+=("$2:$3")
    if [[ "$3" == "added" ]]; then
        CB_DEPTH=$(( CB_DEPTH + 1 ))
        if (( CB_DEPTH <= 1 )); then "$1".Clear; fi
    fi
    return 0
}
THashSet.new E4
E4.on_notify = "clearcb"
REC=()
E4.Add zz; rc=$?
E4.Count; n="$RESULT"
[[ $rc -eq 0 && "$n" == "0" && "${REC[*]}" == "zz:added zz:removed" ]] && consistent E4 \
    && kt_test_pass "Add rc 0, set emptied by its own event" \
    || kt_test_fail "rc=$rc n=$n [${REC[*]}]"
E4.delete

kt_test_start "re-entrant Add terminates under a counter guard and stays consistent"
RDEPTH=0
recur() {
    REC+=("$2:$3")
    RDEPTH=$(( RDEPTH + 1 ))
    if (( RDEPTH < 5 )) && [[ "$3" == "added" ]]; then "$1".Add "gen$RDEPTH" || :; fi
    return 0
}
THashSet.new E5
E5.on_notify = "recur"
REC=()
E5.Add seed || :
if [[ ${#REC[@]} -eq 5 ]] && set_is E5 seed gen1 gen2 gen3 gen4 && consistent E5; then
    kt_test_pass "5 nested 'added', 5 elements"
else
    kt_test_fail "n=${#REC[@]} depth=$RDEPTH [${REC[*]}]"
fi
E5.delete

# ---------------------------------------------------------------------------
# F. robustness: dangling name, callback status, debug lines, detach
# ---------------------------------------------------------------------------

kt_test_start "a dangling callback name is a no-op: the mutation happens, rc 0, silent"
THashSet.new F1
F1.on_notify = "no_such_fn_xyz"
err="$(F1.Add q1 2>&1)"; rcsub=$?
F1.Add q2 2>/dev/null; rc=$?
F1.Contains q2; rcc=$?
[[ $rcsub -eq 0 && -z "$err" && $rc -eq 0 && $rcc -eq 0 ]] \
    && kt_test_pass "rc 0, element stored, nothing printed" \
    || kt_test_fail "rcsub=$rcsub err='$err' rc=$rc rcc=$rcc"

kt_test_start "a dangling callback logs exactly one kk.debug line PER EVENT under the switch"
errf="$TMP/notify.err"
: >"$errf"
VERBOSE_KKLASS=debug
F1.Add q3 2>>"$errf"
F1.Remove q3 2>>"$errf"
unset VERBOSE_KKLASS
lines="$(grep -c . "$errf")"
named=0; grep -q "no_such_fn_xyz" "$errf" && named=1
[[ "$lines" == "2" && $named -eq 1 ]] && kt_test_pass "2 lines naming the callback" \
    || kt_test_fail "lines=$lines named=$named: $(tr '\n' '|' <"$errf")"
F1.delete

kt_test_start "the callback's exit status is IGNORED (FPC events return nothing)"
failcb() { REC+=("$2:$3"); return "${FAILRC:-1}"; }
THashSet.new F2
F2.on_notify = "failcb"
REC=()
FAILRC=1; F2.Add r1; rcA=$?
FAILRC=2; F2.Remove r1; rcR=$?
FAILRC=7; F2.Add r2; rcA2=$?
F2.Extract r2; rcX=$?; xv="$RESULT"
[[ $rcA -eq 0 && $rcR -eq 0 && $rcA2 -eq 0 && $rcX -eq 0 && "$xv" == "r2" \
   && "${REC[*]}" == "r1:added r1:removed r2:added r2:extracted" ]] \
    && kt_test_pass "member rc unaffected by cb rc 1/2/7" \
    || kt_test_fail "rc=$rcA/$rcR/$rcA2/$rcX v='$xv' [${REC[*]}]"
unset FAILRC
F2.delete

kt_test_start "a failing callback does not abort a 'set -eu' script (child bash)"
cat >"$TMP/sete_events.sh" <<'EOS'
set -eu
source "$1"
failcb() { return 1; }
THashSet.new S
S.on_notify = "failcb"
S.Add x || :
S.Add y || :
S.Remove x || :
S.Clear
S.Count
printf '%s' "$RESULT"
EOS
out="$(bash "$TMP/sete_events.sh" "$UNIT" 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == "0" ]] && kt_test_pass "survives set -eu, Count 0" \
    || kt_test_fail "rc=$rc out='$out'"

kt_test_start "detaching the callback mid-life stops the events"
fill_set F3 g1
F3.on_notify = "rec"
F3.Add g2 || :
F3.on_notify = ""
REC=()
F3.Add g3 || :; F3.Remove g1 || :; F3.Clear
[[ ${#REC[@]} -eq 0 ]] && kt_test_pass "no events after detach" || kt_test_fail "[${REC[*]}]"
F3.delete

kt_test_start "the sender argument is the instance handle"
fill_set F4
F4.on_notify = "recsend"
REC=()
F4.Add h1 || :
[[ "${REC[0]}" == "F4|h1:added" ]] && kt_test_pass "sender F4 (FPC :2500 passes Self)" \
    || kt_test_fail "${REC[0]}"
F4.delete

# ---------------------------------------------------------------------------
# G. the virtual seam: _notifyHook + an overriding subclass
# ---------------------------------------------------------------------------

kt_test_start "a fresh set exposes _notifyHook, and it is empty like on_notify"
THashSet.new G1
hookfn=0; declare -F G1._notifyHook >/dev/null 2>&1 && hookfn=1
[[ $hookfn -eq 1 && "$(G1.on_notify)" == "" && "$(G1._notifyHook 2>/dev/null)" == "" ]] \
    && kt_test_pass "member present, both off" \
    || kt_test_fail "member=$hookfn cb='$(G1.on_notify)' hook='$(G1._notifyHook 2>/dev/null)'"
G1.delete

kt_test_start "a subclass that overrides Notify receives events with NO on_notify set"
TRecordingSet.new G2
HOOKREC=()
G2.Add v1 || :
G2.Add v1 2>/dev/null || :
G2.Remove v1 || :
[[ "$(G2.on_notify)" == "" && "$(G2._notifyHook)" == "1" \
   && "${HOOKREC[*]}" == "v1:added v1:removed" ]] \
    && kt_test_pass "_notifyHook drives the virtual dispatch" \
    || kt_test_fail "hook='$(G2._notifyHook)' [${HOOKREC[*]}]"

kt_test_start "with a user callback too, the override calls the inherited body FIRST"
ORDER=()
ordcb() { ORDER+=("user:$2:$3"); return 0; }
G2.on_notify = "ordcb"
HOOKREC=(); ORDER=()
G2.Add v2 || :
[[ "${ORDER[*]}" == "user:v2:added" && "${HOOKREC[*]}" == "v2:added" ]] \
    && kt_test_pass "inherited (user event) then the override's own tail" \
    || kt_test_fail "order=[${ORDER[*]}] hook=[${HOOKREC[*]}]"
G2.on_notify = ""

kt_test_start "the subclass fires 'removed' per element on delete too (S5 through the seam)"
G2.AddRange w1 w2 || :
HOOKREC=()
G2.delete
ms_is HOOKREC v2:removed w1:removed w2:removed \
    && kt_test_pass "3 removed through the override" || kt_test_fail "[${HOOKREC[*]}]"

kt_test_start "the gate blocks dispatch: an override with _notifyHook cleared gets NOTHING"
TRecordingSet.new G3
pre="$(G3._notifyHook 2>/dev/null)"      # the ctor armed it
G3._notifyHook = ""
armed="$(G3._notifyHook 2>/dev/null)"
HOOKREC=()
G3.Add u1 || :
G3.Remove u1 || :
G3.AddRange u2 u3 || :
G3.Clear
[[ "$pre" == "1" && -z "$armed" && ${#HOOKREC[@]} -eq 0 ]] && set_is G3 \
    && kt_test_pass "hook cleared -> no dispatch, ops still correct" \
    || kt_test_fail "pre='$pre' armed='$armed' [${HOOKREC[*]}]"
G3.delete

# ---------------------------------------------------------------------------
# H. the onNotify validating setter
# ---------------------------------------------------------------------------

kt_test_start "onNotify FN sets the hook (rc 0) and the events start"
THashSet.new H1
H1.onNotify rec; rc=$?
REC=()
H1.Add p1 || :
[[ $rc -eq 0 && "$(H1.on_notify)" == "rec" && "${REC[*]}" == "p1:added" ]] \
    && kt_test_pass "rc 0, read-back 'rec', event fired" \
    || kt_test_fail "rc=$rc cb='$(H1.on_notify)' [${REC[*]}]"

kt_test_start "onNotify with a name that is not a function -> rc 2, the hook is UNCHANGED"
err="$(H1.onNotify no_such_fn_xyz 2>&1)"; rc=$?
REC=()
H1.Add p2 || :
[[ $rc -eq 2 && -z "$err" && "$(H1.on_notify)" == "rec" && "${REC[*]}" == "p2:added" ]] \
    && kt_test_pass "rc 2, silent, previous hook kept" \
    || kt_test_fail "rc=$rc err='$err' cb='$(H1.on_notify)' [${REC[*]}]"

kt_test_start "onNotify's rejection is reported under VERBOSE_KKLASS=debug"
errf="$TMP/onnotify.err"
: >"$errf"
VERBOSE_KKLASS=debug
H1.onNotify 'not a name' 2>>"$errf" || :
H1.onNotify 'a[0]' 2>>"$errf" || :
unset VERBOSE_KKLASS
lines="$(grep -c . "$errf")"
[[ "$lines" == "2" && "$(H1.on_notify)" == "rec" ]] \
    && kt_test_pass "2 debug lines, hook intact" \
    || kt_test_fail "lines=$lines cb='$(H1.on_notify)'"

kt_test_start "onNotify '' clears the hook (rc 0) and the events stop"
H1.onNotify ""; rc1=$?
H1.onNotify; rc2=$?
REC=()
H1.Add p3 || :; H1.Clear
[[ $rc1 -eq 0 && $rc2 -eq 0 && "$(H1.on_notify)" == "" && ${#REC[@]} -eq 0 ]] \
    && kt_test_pass "cleared, silent" || kt_test_fail "rc=$rc1/$rc2 [${REC[*]}]"

kt_test_start "the direct var assignment keeps working alongside onNotify (house way)"
H1.on_notify = "rec"
REC=()
H1.Add p4 || :
[[ "$(H1.on_notify)" == "rec" && "${REC[*]}" == "p4:added" ]] \
    && kt_test_pass "both spellings drive the same var" \
    || kt_test_fail "cb='$(H1.on_notify)' [${REC[*]}]"
H1.delete

# ---------------------------------------------------------------------------
# I. surface, forks, cost
# ---------------------------------------------------------------------------

kt_test_start "no public member — Notify INCLUDED — answers with a __ths_pending__ sentinel"
THashSet.new PS
THashSet.new PT
PT.Add other || :
declare -a pout=()
declare -a pin=(pa pb)
cbz() { :; }
seen=""
run_member() {
    local out
    RESULT=""
    out="$( "$@" 2>&1 )" || :
    "$@" >/dev/null 2>&1 || :
    [[ "$out" == *__ths_pending__* || "$RESULT" == *__ths_pending__* ]] && seen+="$1 "
    return 0
}
run_member PS.Count
run_member PS.Add z1
run_member PS.Contains z1
run_member PS.Remove z1
run_member PS.Extract z1
run_member PS.ToArray pout
run_member PS.ForEach cbz
run_member PS.AddRange q1 q2
run_member PS.AddRangeFromArray pin
run_member PS.UnionWith PT
run_member PS.IntersectWith PT
run_member PS.ExceptWith PT
run_member PS.SymmetricExceptWith PT
run_member PS.Assign PT
run_member PS.Clear
run_member PS.Notify nz added
run_member PS.onNotify cbz
[[ -z "$seen" ]] && kt_test_pass "17 members, no stub left in the unit" \
    || kt_test_fail "sentinel still returned by: $seen"
PS.delete; PT.delete

kt_test_start "the event path does not fork (BASHPID unchanged with a listener attached)"
fill_set ZA a b c
fill_set ZB c d e
ZA.on_notify = "rec"
p0=$BASHPID; ok=1
REC=()
ZA.Add zz            || :; [[ $BASHPID == "$p0" ]] || ok=0
ZA.Remove zz         || :; [[ $BASHPID == "$p0" ]] || ok=0
ZA.Extract a         >/dev/null; [[ $BASHPID == "$p0" ]] || ok=0
ZA.UnionWith ZB;              [[ $BASHPID == "$p0" ]] || ok=0
ZA.SymmetricExceptWith ZB;    [[ $BASHPID == "$p0" ]] || ok=0
ZA.Clear;                     [[ $BASHPID == "$p0" ]] || ok=0
ZA.onNotify rec;              [[ $BASHPID == "$p0" ]] || ok=0
[[ $ok -eq 1 && ${#REC[@]} -gt 0 ]] && kt_test_pass "BASHPID $p0 throughout, ${#REC[@]} events" \
    || kt_test_fail "a member forked (ok=$ok, events=${#REC[@]})"
ZA.delete; ZB.delete

kt_test_start "PATH='' : the whole event path runs fork-free"
zf="$(
    PATH=''
    source "$UNIT" 2>/dev/null
    Z_REC=()
    zrec() { Z_REC+=("$2:$3"); return 0; }
    THashSet.new Z; THashSet.new Y
    Z.onNotify zrec
    Z.Add x || :
    Z.Add x 2>/dev/null || :
    Y.Add w || :
    Z.UnionWith Y
    Z.Extract x >/dev/null
    Z.delete; Y.delete
    printf '%s' "${Z_REC[*]}"
)"
[[ "$zf" == "x:added w:added x:extracted w:removed" ]] && kt_test_pass "$zf" \
    || kt_test_fail "PATH='' got '$zf'"

kt_test_start "hook-less cost: 1k Add with a listener stays inside 5x the unhooked loop"
now_us() { local t="${EPOCHREALTIME}"; US="${t//[.,]/}"; }   # fork-free clock
THashSet.new NB
now_us; t0=$US
for ((i=0; i<1000; i++)); do NB.Add "n$i" || :; done
now_us; t1=$US
base=$(( t1 - t0 )); (( base > 0 )) || base=1
NB.delete

nullcb() { return 0; }
THashSet.new NH
NH.on_notify = "nullcb"
now_us; t0=$US
for ((i=0; i<1000; i++)); do NH.Add "n$i" || :; done
now_us; t1=$US
hooked=$(( t1 - t0 ))
NH.delete
limit=$(( base * 5 ))
(( hooked <= limit )) \
    && kt_test_pass "unhooked ${base}us / hooked ${hooked}us per 1k Add (limit ${limit}us)" \
    || kt_test_fail "unhooked ${base}us, hooked ${hooked}us > ${limit}us"

kt_test_log "006_Events.sh completed"
