#!/bin/bash
# 005_SetAlgebra.sh — thashset P2: the set algebra and the two AddRange forms.
#
# Source of truth: FPC 3.2.2 packages/rtl-generics/src/generics.collections.pas
# (tag release_3_2_2):
#   TCustomSet<T>.AddRange(array of T)   :2379  Result := True;
#                                               for i in AValues do
#                                                 Result := Add(i) and Result;
#   TCustomSet<T>.UnionWith              :2417  for i in AHashSet.Ptr^ do Add(i^);
#   TCustomSet<T>.IntersectWith          :2425  two-pass — collect SELF's members
#                                               that the operand lacks into LList,
#                                               then Remove each.
#   TCustomSet<T>.ExceptWith             :2442  for i in AHashSet.Ptr^ do Remove(i^);
#   TCustomSet<T>.SymmetricExceptWith    :2450  two-pass — for each of the OPERAND:
#                                               Contains -> mark in LList, else Add;
#                                               then Remove every marked one.
#   THashSet<T>.Add :2559 / Remove :2566 / Contains :2593 (the Booleans the four
#   procedures above drive).
# (The :2815/:2853/:2861/:2878/:2886 numbers carried in P0 came from a different
# revision of the file; the code is identical, only the line numbers moved.)
#
# Parity oracle: packages/rtl-generics/tests/tests.generics.sets.pas
# Test_Set_General :86–152 — a hand-computed truth table. Ported below in
# section A. One mapping: the seed's `NumbersC.AddRange(NumbersB)` (:117, :146)
# uses the TEnumerable overload (:2397) — a whole SET as the source. Our surface
# is varargs, so that step is ported twice: `C.UnionWith B` for the membership
# half and `C.AddRange <B's elements via ToArray>` for the Boolean half.
# `NumbersC := T.Create(NumbersA)` (the copy ctor, :2374) maps to `C.Assign A`.
#
# The four ops are `proc`: rc 0 on success, rc 1 + a kk.debug line when the
# operand is not a live THashSet — and then the set is left BYTE-IDENTICAL
# (validation happens before any mutation). AddRange/AddRangeFromArray answer a
# BOOLEAN (rc 0 iff every item was newly added) and are silent on rc 1;
# AddRangeFromArray answers rc 2 for a malformed CALL (bad input-array name,
# associative or non-array target) per kcl/README.md §1.2/§1.7.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TS_DIR="$SCRIPT_DIR/.."
UNIT="$TS_DIR/thashset.sh"
source "$UNIT"
source "$TS_DIR/../tqueuestack/tqueuestack.sh"   # a non-set instance that owns _items

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "005: THashSet set algebra + AddRange forms (P2)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# fill_set NAME [elem...] — create a fresh set and add every element
fill_set() {
    local __n="$1"; shift
    THashSet.new "$__n"
    local __e
    for __e in "$@"; do "$__n".Add "$__e" || :; done
}

# set_is NAME [expected...] — rc 0 iff the set holds EXACTLY these elements
# (Count equals the expected size AND every expected element is present).
# Expected lists must not contain duplicates.
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

# sig NAME — a byte-exact signature of the storage (used for "untouched")
sig() { declare -p "${1}_items"; }

# ---------------------------------------------------------------------------
# A. the FPC parity oracle: tests.generics.sets.pas Test_Set_General :86–152
# ---------------------------------------------------------------------------

kt_test_start "seed :96–103 — A={0,2,4,6,8}, B={1,3,5,7,9}, every Add is True"
allnew=1
THashSet.new NA; THashSet.new NB
for i in 0 1 2 3 4; do
    NA.Add "$(( i * 2 ))"     || allnew=0
    NB.Add "$(( i * 2 + 1 ))" || allnew=0
done
if [[ $allnew -eq 1 ]] && set_is NA 0 2 4 6 8 && set_is NB 1 3 5 7 9; then
    kt_test_pass "5+5 added, both validated"
else
    kt_test_fail "allnew=$allnew"
fi

kt_test_start "seed :106–111 — C:=copy(A); C.UnionWith(B) = {0..9}; Add(5)=False; AddRange(6,7)=False"
THashSet.new NC
NC.Assign NA                      # T.Create(NumbersA) — the copy ctor :2374
NC.UnionWith NB; ru=$?
NC.Add 5 2>/dev/null; r5=$?
NC.AddRange 6 7 2>/dev/null; rr=$?
NC.Count; nc="$RESULT"
if [[ $ru -eq 0 && $r5 -eq 1 && $rr -eq 1 && "$nc" == "10" ]] \
   && set_is NC 0 1 2 3 4 5 6 7 8 9 && set_is NB 1 3 5 7 9; then
    kt_test_pass "union {0..9}, Add rc 1, AddRange rc 1, count 10, operand intact"
else
    kt_test_fail "ru=$ru r5=$r5 rr=$rr count=$nc"
fi

kt_test_start "seed :114–118 — C.ExceptWith(B) = {0,2,4,6,8}; AddRange(B) = True -> {0..9}"
NC.ExceptWith NB; re=$?
NC.Count; n5="$RESULT"
ok1=0; set_is NC 0 2 4 6 8 && ok1=1
# seed :117 AddRange(NumbersB) is the TEnumerable overload :2397 — mapped to
# varargs over B's elements (the Boolean half) …
belems=(); NB.ToArray belems
NC.AddRange "${belems[@]}"; rb=$?
ok2=0; set_is NC 0 1 2 3 4 5 6 7 8 9 && ok2=1
# … and to UnionWith (the membership half) — must be idempotent here
NC.UnionWith NB
ok3=0; set_is NC 0 1 2 3 4 5 6 7 8 9 && ok3=1
if [[ $re -eq 0 && "$n5" == "5" && $ok1 -eq 1 && $rb -eq 0 && $ok2 -eq 1 && $ok3 -eq 1 ]]; then
    kt_test_pass "except -> 5, AddRange rc 0 -> {0..9}, union idempotent"
else
    kt_test_fail "re=$re n5=$n5 ok1=$ok1 rb=$rb ok2=$ok2 ok3=$ok3"
fi

kt_test_start "seed :121–135 — SymmetricExceptWith: {0..5} XOR {3..9} = {0,1,2,6,7,8,9}"
NA.Clear; NB.Clear; NC.Clear
NA.Count; a0="$RESULT"; NB.Count; b0="$RESULT"; NC.Count; c0="$RESULT"
NA.AddRange 0 1 2 3 4 5; ra=$?
NB.AddRange 3 4 5 6 7 8 9; rb=$?
NC.Assign NA
rs=1
if set_is NC 0 1 2 3 4 5; then NC.SymmetricExceptWith NB; rs=$?; fi
if [[ "$a0$b0$c0" == "000" && $ra -eq 0 && $rb -eq 0 && $rs -eq 0 ]] \
   && set_is NC 0 1 2 6 7 8 9 && set_is NB 3 4 5 6 7 8 9; then
    kt_test_pass "{0,1,2,6,7,8,9} (seed :135), operand intact"
else
    kt_test_fail "clear=$a0/$b0/$c0 ra=$ra rb=$rb rs=$rs"
fi

kt_test_start "seed :138–148 — IntersectWith: {0..5} AND {3..9} = {3,4,5}"
NA.Clear; NB.Clear; NC.Clear
NA.AddRange 0 1 2 3 4 5
NB.AddRange 3 4 5 6 7 8 9
aelems=(); NA.ToArray aelems
NC.AddRange "${aelems[@]}"; rc0=$?
NC.IntersectWith NB; ri=$?
if [[ $rc0 -eq 0 && $ri -eq 0 ]] && set_is NC 3 4 5 && set_is NB 3 4 5 6 7 8 9; then
    kt_test_pass "{3,4,5} (seed :148), operand intact"
else
    kt_test_fail "rc0=$rc0 ri=$ri"
fi
NA.delete; NB.delete; NC.delete

# ---------------------------------------------------------------------------
# B. hand-computed truth tables over every operand SHAPE
# ---------------------------------------------------------------------------
# Each row: "<title>|<A>|<B>|<union>|<intersect>|<except>|<symmetric>"
# (space-separated element lists; an empty field is the empty set).
SHAPES=(
  "empty/empty|||||||~"
  "empty/non-empty||1 2|1 2|||1 2|~"
  "non-empty/empty|1 2||1 2||1 2|1 2|~"
  "disjoint|1 2|3 4|1 2 3 4||1 2|1 2 3 4|~"
  "overlapping|1 2 3|3 4 5|1 2 3 4 5|3|1 2|1 2 4 5|~"
  "subset (A in B)|1 2|1 2 3 4|1 2 3 4|1 2||3 4|~"
  "superset (B in A)|1 2 3 4|1 2|1 2 3 4|1 2|3 4|3 4|~"
  "equal content, two instances|1 2 3|1 2 3|1 2 3|1 2 3|||~"
)

# shape_loop MEMBER FIELD_INDEX — every failure lands in the global BAD.
# Deliberately NOT wrapped in $( ): `Count` is a `func`, and kk._return PRINTS
# its value whenever BASH_SUBSHELL > 0, so a command substitution around this
# loop would capture every count set_is asks for and report it as a failure.
shape_loop() {
    local op="$1" fld="$2" row rc bsig
    local -a f ae be ee got
    BAD=""
    for row in "${SHAPES[@]}"; do
        IFS='|' read -ra f <<< "$row"
        read -ra ae <<< "${f[1]}"
        read -ra be <<< "${f[2]}"
        read -ra ee <<< "${f[$fld]}"
        fill_set SA ${ae[@]+"${ae[@]}"}
        fill_set SB ${be[@]+"${be[@]}"}
        bsig="$(sig SB)"
        SA."$op" SB; rc=$?
        [[ $rc -eq 0 ]] || BAD+="rc[${f[0]}]=$rc "
        if ! set_is SA ${ee[@]+"${ee[@]}"}; then
            got=(); SA.ToArray got
            BAD+="result[${f[0]}]='${got[*]}' want='${f[$fld]}' "
        fi
        [[ "$(sig SB)" == "$bsig" ]] || BAD+="operand-mutated[${f[0]}] "
        SA.delete; SB.delete
    done
    return 0
}

kt_test_start "UnionWith truth table over 8 operand shapes (FPC :2417)"
shape_loop UnionWith 3; bad="$BAD"
[[ -z "$bad" ]] && kt_test_pass "8 shapes correct, operand untouched" || kt_test_fail "$bad"

kt_test_start "IntersectWith truth table over 8 operand shapes (FPC :2425 two-pass)"
shape_loop IntersectWith 4; bad="$BAD"
[[ -z "$bad" ]] && kt_test_pass "8 shapes correct, operand untouched" || kt_test_fail "$bad"

kt_test_start "ExceptWith truth table over 8 operand shapes (FPC :2442)"
shape_loop ExceptWith 5; bad="$BAD"
[[ -z "$bad" ]] && kt_test_pass "8 shapes correct, operand untouched" || kt_test_fail "$bad"

kt_test_start "SymmetricExceptWith truth table over 8 operand shapes (FPC :2450 two-pass)"
shape_loop SymmetricExceptWith 6; bad="$BAD"
[[ -z "$bad" ]] && kt_test_pass "8 shapes correct, operand untouched" || kt_test_fail "$bad"

# ---------------------------------------------------------------------------
# C. self-operation edges (PLAN §2.3 / ledger S8, S3)
# ---------------------------------------------------------------------------

kt_test_start "a.UnionWith a = a (no-op; snapshot before mutation)"
fill_set SS x y z
SS.UnionWith SS; rc=$?
[[ $rc -eq 0 ]] && set_is SS x y z && kt_test_pass "unchanged, rc 0" || kt_test_fail "rc=$rc"
SS.delete

kt_test_start "a.IntersectWith a = a (FPC :2425 collects nothing)"
fill_set SS x y z
SS.IntersectWith SS; rc=$?
[[ $rc -eq 0 ]] && set_is SS x y z && kt_test_pass "unchanged, rc 0" || kt_test_fail "rc=$rc"
SS.delete

kt_test_start "a.ExceptWith a = {} (FPC :2442 removes every element of the operand)"
fill_set SS x y z
SS.ExceptWith SS; rc=$?
SS.Count; n="$RESULT"
[[ $rc -eq 0 && "$n" == "0" ]] && kt_test_pass "full drain, rc 0" || kt_test_fail "rc=$rc n=$n"
SS.delete

kt_test_start "a.SymmetricExceptWith a = {} (FPC :2450 marks everything, then removes)"
fill_set SS x y z
SS.SymmetricExceptWith SS; rc=$?
SS.Count; n="$RESULT"
[[ $rc -eq 0 && "$n" == "0" ]] && kt_test_pass "empty, rc 0" || kt_test_fail "rc=$rc n=$n"
SS.delete

# ---------------------------------------------------------------------------
# D. exotic elements through every algebra path
# ---------------------------------------------------------------------------
CANARY="$TMP/algebra_pwn"
rm -f "$CANARY"
declare -a EX=( ']' '[' 'a]b' "\$(touch '$CANARY')" '*' $'x\ny' 'k' 'kk' '' 'a\b' "it's" 'café' )
# EX[0..5] = the "left" block, EX[3..11] = the "right" block (overlap 3,4,5)
LEFT=( "${EX[@]:0:6}" ); RIGHT=( "${EX[@]:3:9}" )
HEAD=( "${EX[@]:0:3}" ); TAIL=( "${EX[@]:6:6}" )

kt_test_start "UnionWith over exotic elements (12 distinct, nothing executed)"
fill_set XA "${LEFT[@]}"; fill_set XB "${RIGHT[@]}"
XA.UnionWith XB; rc=$?
ok=1; set_is XA "${EX[@]}" || ok=0
[[ $rc -eq 0 && $ok -eq 1 && ! -e "$CANARY" ]] \
    && kt_test_pass "12 exotic elements united" || kt_test_fail "rc=$rc ok=$ok canary=$([[ -e $CANARY ]] && echo yes || echo no)"
XA.delete; XB.delete

kt_test_start "IntersectWith over exotic elements"
fill_set XA "${EX[@]}"; fill_set XB "${LEFT[@]}"
XA.IntersectWith XB; rc=$?
ok=1; set_is XA "${LEFT[@]}" || ok=0
[[ $rc -eq 0 && $ok -eq 1 && ! -e "$CANARY" ]] \
    && kt_test_pass "6 kept" || kt_test_fail "rc=$rc ok=$ok"
XA.delete; XB.delete

kt_test_start "ExceptWith over exotic elements (the G2-01 unset idiom under algebra)"
fill_set XA "${EX[@]}"; fill_set XB "${LEFT[@]}"
XA.ExceptWith XB; rc=$?
ok=1; set_is XA "${TAIL[@]}" || ok=0
[[ $rc -eq 0 && $ok -eq 1 && ! -e "$CANARY" ]] \
    && kt_test_pass "6 removed byte-exact" || kt_test_fail "rc=$rc ok=$ok"
XA.delete; XB.delete

kt_test_start "SymmetricExceptWith over exotic elements"
fill_set XA "${LEFT[@]}"; fill_set XB "${RIGHT[@]}"
XA.SymmetricExceptWith XB; rc=$?
ok=1; set_is XA "${HEAD[@]}" "${TAIL[@]}" || ok=0
[[ $rc -eq 0 && $ok -eq 1 && ! -e "$CANARY" ]] \
    && kt_test_pass "9 elements (3 head + 6 tail)" || kt_test_fail "rc=$rc ok=$ok"
XA.delete; XB.delete

kt_test_start "no algebra path ever EXECUTES an element"
[[ ! -e "$CANARY" ]] && kt_test_pass "canary absent after all four ops" \
    || { kt_test_fail "the element was executed: $CANARY exists"; rm -f "$CANARY"; }

# ---------------------------------------------------------------------------
# E. AddRange (FPC :2379 — AND-fold of per-item Add)
# ---------------------------------------------------------------------------

kt_test_start "AddRange: all new -> rc 0 (AND-fold True, FPC :2379)"
THashSet.new AR
AR.AddRange a b c; rc=$?
[[ $rc -eq 0 ]] && set_is AR a b c && kt_test_pass "rc 0, 3 elements" || kt_test_fail "rc=$rc"

kt_test_start "AddRange: any already-present item -> rc 1, the new ones still land"
AR.AddRange c d 2>/dev/null; rc=$?
[[ $rc -eq 1 ]] && set_is AR a b c d && kt_test_pass "rc 1, d added" || kt_test_fail "rc=$rc"

kt_test_start "AddRange: rc 1 is a silent ANSWER (no stderr even under debug)"
VERBOSE_KKLASS=debug
err="$(AR.AddRange a 2>&1)"; rc=$?
unset VERBOSE_KKLASS
[[ $rc -eq 1 && -z "$err" ]] && kt_test_pass "rc 1, nothing printed" || kt_test_fail "rc=$rc err='$err'"

kt_test_start "AddRange: a duplicate WITHIN the argument list makes it rc 1"
THashSet.new AR2
AR2.AddRange n1 n2 n1 2>/dev/null; rc=$?
[[ $rc -eq 1 ]] && set_is AR2 n1 n2 && kt_test_pass "rc 1, 2 distinct elements" || kt_test_fail "rc=$rc"
AR2.delete

kt_test_start "AddRange with zero arguments -> rc 0 (FPC Result:=True over an empty array)"
THashSet.new AR3
AR3.AddRange; rc=$?
AR3.Count; n="$RESULT"
[[ $rc -eq 0 && "$n" == "0" ]] && kt_test_pass "rc 0, still empty" || kt_test_fail "rc=$rc n=$n"
AR3.delete

kt_test_start "AddRange is order-independent in its result set"
THashSet.new AR4; THashSet.new AR5
AR4.AddRange p q r
AR5.AddRange r q p
ok=1; set_is AR4 p q r || ok=0; set_is AR5 p q r || ok=0
[[ $ok -eq 1 ]] && kt_test_pass "same set both orders" || kt_test_fail "ok=$ok"
AR4.delete; AR5.delete

kt_test_start "AddRange stores exotic elements byte-exact"
THashSet.new AR6
AR6.AddRange "${EX[@]}"; rc=$?
ok=1; set_is AR6 "${EX[@]}" || ok=0
[[ $rc -eq 0 && $ok -eq 1 && ! -e "$CANARY" ]] \
    && kt_test_pass "12 exotic elements, nothing executed" || kt_test_fail "rc=$rc ok=$ok"
AR6.delete
AR.delete

# ---------------------------------------------------------------------------
# F. AddRangeFromArray (bash extra: the bulk sibling)
# ---------------------------------------------------------------------------

kt_test_start "AddRangeFromArray fills from a caller indexed array -> rc 0"
THashSet.new FA
declare -a src_arr=(one two three)
FA.AddRangeFromArray src_arr; rc=$?
[[ $rc -eq 0 ]] && set_is FA one two three && kt_test_pass "rc 0, 3 elements" || kt_test_fail "rc=$rc"

kt_test_start "AddRangeFromArray over a SPARSE array takes the surviving elements"
THashSet.new FB
declare -a sparse=([0]=s0 [5]=s5 [9]=s9)
FB.AddRangeFromArray sparse; rc=$?
[[ $rc -eq 0 ]] && set_is FB s0 s5 s9 && kt_test_pass "rc 0, 3 elements over the holes" || kt_test_fail "rc=$rc"
FB.delete

kt_test_start "AddRangeFromArray over an EMPTY array -> rc 0 and no change"
declare -a empty_arr=()
FA.AddRangeFromArray empty_arr; rc=$?
[[ $rc -eq 0 ]] && set_is FA one two three && kt_test_pass "rc 0, untouched" || kt_test_fail "rc=$rc"

kt_test_start "AddRangeFromArray with an already-present element -> rc 1 (AND-fold)"
declare -a dup_arr=(two four)
FA.AddRangeFromArray dup_arr 2>/dev/null; rc=$?
[[ $rc -eq 1 ]] && set_is FA one two three four && kt_test_pass "rc 1, four added" || kt_test_fail "rc=$rc"

kt_test_start "AddRangeFromArray refuses a bad input-array name with rc 2, set untouched"
before="$(sig FA)"; bad=""
for name in "" "1abc" "a b" "a-b" "__ts_it" "RESULT" "IFS" "this" "state" "__kk_x" "FA_items"; do
    err="$(FA.AddRangeFromArray "$name" 2>&1)"; rc=$?
    [[ $rc -eq 2 ]] || bad+="rc[$name]=$rc "
    [[ -z "$err" ]] || bad+="noise[$name] "
done
[[ -z "$bad" && "$(sig FA)" == "$before" ]] \
    && kt_test_pass "11 bad names -> rc 2, storage byte-identical" || kt_test_fail "$bad"

kt_test_start "AddRangeFromArray refuses an ASSOCIATIVE array with rc 2"
declare -A assoc_src=([a]=1 [b]=2)
before="$(sig FA)"
FA.AddRangeFromArray assoc_src 2>/dev/null; rc=$?
[[ $rc -eq 2 && "$(sig FA)" == "$before" ]] \
    && kt_test_pass "rc 2, storage untouched" || kt_test_fail "rc=$rc"

kt_test_start "AddRangeFromArray refuses a plain (non-array) variable with rc 2"
plain_var=hello
before="$(sig FA)"
FA.AddRangeFromArray plain_var 2>/dev/null; rc=$?
[[ $rc -eq 2 && "$(sig FA)" == "$before" ]] \
    && kt_test_pass "rc 2, storage untouched" || kt_test_fail "rc=$rc"

kt_test_start "AddRangeFromArray on an UNSET variable is rc 2 and does not abort under set -eu"
out="$(bash -c "set -eu
source '$UNIT'
THashSet.new h
rc=0
h.AddRangeFromArray no_such_array_at_all || rc=\$?
h.Count
printf 'rc=%s count=%s' \"\$rc\" \"\$RESULT\"
h.delete" 2>&1)"
[[ "$out" == "rc=2 count=0" ]] && kt_test_pass "$out" || kt_test_fail "got '$out'"

kt_test_start "AddRangeFromArray reports a bad name under VERBOSE_KKLASS=debug"
errf="$TMP/arfa.err"
VERBOSE_KKLASS=debug
FA.AddRangeFromArray "1bad" 2>"$errf"; rc=$?
unset VERBOSE_KKLASS
msg="$(<"$errf")"
[[ $rc -eq 2 && "$msg" == *AddRangeFromArray* ]] \
    && kt_test_pass "rc 2 + debug line" || kt_test_fail "rc=$rc msg='$msg'"

kt_test_start "AddRangeFromArray carries exotic elements byte-exact"
THashSet.new FC
declare -a ex_arr=( "${EX[@]}" )
FC.AddRangeFromArray ex_arr; rc=$?
ok=1; set_is FC "${EX[@]}" || ok=0
[[ $rc -eq 0 && $ok -eq 1 && ! -e "$CANARY" ]] \
    && kt_test_pass "12 exotic elements, nothing executed" || kt_test_fail "rc=$rc ok=$ok"
FC.delete
FA.delete

# ---------------------------------------------------------------------------
# G. operand validation — rc 1, atomic, debug-logged (PLAN §2.3, R5)
# ---------------------------------------------------------------------------

kt_test_start "the four ops refuse a missing operand with rc 1 and change nothing"
fill_set VA keep1 keep2
before="$(sig VA)"; bad=""
for op in UnionWith IntersectWith ExceptWith SymmetricExceptWith; do
    VA."$op" 2>/dev/null; rc=$?
    [[ $rc -eq 1 ]] || bad+="rc[$op]=$rc "
    [[ "$(sig VA)" == "$before" ]] || bad+="mutated[$op] "
done
[[ -z "$bad" ]] && kt_test_pass "4 ops rc 1, storage byte-identical" || kt_test_fail "$bad"

kt_test_start "the four ops refuse a plain string operand with rc 1 and change nothing"
before="$(sig VA)"; bad=""
declare -A fake_items=([kx]=1)          # looks like a set's storage, is not a set
for op in UnionWith IntersectWith ExceptWith SymmetricExceptWith; do
    VA."$op" fake 2>/dev/null; rc=$?
    [[ $rc -eq 1 ]] || bad+="rc[$op]=$rc "
    VA."$op" "not a name" 2>/dev/null; rc=$?
    [[ $rc -eq 1 ]] || bad+="rc2[$op]=$rc "
    [[ "$(sig VA)" == "$before" ]] || bad+="mutated[$op] "
done
[[ -z "$bad" ]] && kt_test_pass "8 rejections, storage byte-identical" || kt_test_fail "$bad"

kt_test_start "the four ops refuse a TQueue that merely owns an _items array [R5]"
TQueue.new QQ
QQ.Enqueue 1; QQ.Enqueue 2
before="$(sig VA)"; bad=""
for op in UnionWith IntersectWith ExceptWith SymmetricExceptWith; do
    VA."$op" QQ 2>/dev/null; rc=$?
    [[ $rc -eq 1 ]] || bad+="rc[$op]=$rc "
    [[ "$(sig VA)" == "$before" ]] || bad+="mutated[$op] "
done
QQ.delete
[[ -z "$bad" ]] && kt_test_pass "4 ops rc 1, set byte-identical" || kt_test_fail "$bad"

kt_test_start "a rejected operand produces a debug line under VERBOSE_KKLASS=debug"
errf="$TMP/algebra.err"
: >"$errf"
VERBOSE_KKLASS=debug
for op in UnionWith IntersectWith ExceptWith SymmetricExceptWith; do
    VA."$op" not_a_set 2>>"$errf"
done
unset VERBOSE_KKLASS
lines="$(grep -c . "$errf")"
missing=""
for op in UnionWith IntersectWith ExceptWith SymmetricExceptWith; do
    grep -q "$op" "$errf" || missing+="$op "
done
[[ "$lines" == "4" && -z "$missing" ]] \
    && kt_test_pass "4 debug lines, one per member" || kt_test_fail "lines=$lines missing='$missing'"

kt_test_start "with the debug switch OFF the rejection is completely silent"
out="$(VA.UnionWith not_a_set 2>&1)"; rc=$?
[[ $rc -eq 1 && -z "$out" ]] && kt_test_pass "rc 1, no output" || kt_test_fail "rc=$rc out='$out'"

# P2-F1: a non-IDENTIFIER operand reached `${!name_class}` inside TSet._isSet,
# and the indirect expansion printed `bad name_class: invalid variable name` on
# stderr — rc 1 and atomicity were right, the silence of kcl/README.md 1.2 was
# not. The same path is Assign's (P1), so the guard sits in the shared helper.
kt_test_start "a NON-IDENTIFIER operand is refused silently too [P2-F1]"
bad=""
for cand in "not a name" "a[0]" "1abc" "a-b" 'x$y' "'" '@' 'a.b'; do
    for op in UnionWith IntersectWith ExceptWith SymmetricExceptWith Assign; do
        out="$(VA."$op" "$cand" 2>&1)"; rc=$?
        [[ $rc -eq 1 ]] || bad+="rc[$op:$cand]=$rc "
        [[ -z "$out" ]] || bad+="noise[$op:$cand] "
    done
done
VA.Count; n="$RESULT"
[[ -z "$bad" && "$n" == "2" ]] && kt_test_pass "40 rejections, silent, set intact" || kt_test_fail "$bad n=$n"
VA.delete

# ---------------------------------------------------------------------------
# H. the P2 stubs are gone
# ---------------------------------------------------------------------------

kt_test_start "no public member answers with the __ths_pending__ sentinel (Notify is P3)"
THashSet.new PS
THashSet.new PT
PT.Add other
declare -a pout=()
declare -a pin=(pa pb)
cbz() { :; }
seen=""
run_member() {   # NAME ARGS... : run, then look for the sentinel in RESULT + output
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
[[ -z "$seen" ]] && kt_test_pass "15 members, no sentinel (Notify excluded — P3)" \
    || kt_test_fail "sentinel still returned by: $seen"
PS.delete; PT.delete

# ---------------------------------------------------------------------------
# I. zero forks
# ---------------------------------------------------------------------------

kt_test_start "the six P2 members do not fork (BASHPID unchanged)"
fill_set ZA a b c
fill_set ZB c d e
declare -a zin=(f g)
p0=$BASHPID; ok=1
ZA.AddRange h i          || :; [[ $BASHPID == "$p0" ]] || ok=0
ZA.AddRangeFromArray zin || :; [[ $BASHPID == "$p0" ]] || ok=0
ZA.UnionWith ZB;              [[ $BASHPID == "$p0" ]] || ok=0
ZA.IntersectWith ZB;          [[ $BASHPID == "$p0" ]] || ok=0
ZA.ExceptWith ZB;             [[ $BASHPID == "$p0" ]] || ok=0
ZA.SymmetricExceptWith ZB;    [[ $BASHPID == "$p0" ]] || ok=0
[[ $ok -eq 1 ]] && kt_test_pass "BASHPID $p0 throughout" || kt_test_fail "a member forked"
ZA.delete; ZB.delete

kt_test_start "PATH='' : all six P2 members run fork-free"
zf="$(
    PATH=''
    source "$UNIT" 2>/dev/null
    THashSet.new P; THashSet.new Q
    P.AddRange a b c || :
    declare -a inp=(d e)
    P.AddRangeFromArray inp || :
    Q.AddRange c d f || :
    P.UnionWith Q
    P.Count >/dev/null; u="$RESULT"                # a b c d e f = 6
    P.IntersectWith Q
    P.Count >/dev/null; i="$RESULT"                # c d f = 3
    P.ExceptWith Q
    P.Count >/dev/null; x="$RESULT"                # 0
    P.AddRange a b || :
    P.SymmetricExceptWith Q
    P.Count >/dev/null; s="$RESULT"                # a b c d f = 5
    P.delete; Q.delete
    printf '%s|%s|%s|%s' "$u" "$i" "$x" "$s"
)"
[[ "$zf" == "6|3|0|5" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

# ---------------------------------------------------------------------------
# J. relative performance gate (kcl/README.md §1.8)
# ---------------------------------------------------------------------------

kt_test_start "1k UnionWith and 1k IntersectWith cost at most 3x a 1k Add loop"
now_us() { local t="${EPOCHREALTIME}"; US="${t//[.,]/}"; }   # fork-free clock
THashSet.new PA
now_us; t0=$US
for ((i=0; i<1000; i++)); do PA.Add "base$i" || :; done
now_us; t1=$US
base=$(( t1 - t0 )); (( base > 0 )) || base=1

THashSet.new PU; THashSet.new PV                 # disjoint 1k / 1k
for ((i=0; i<1000; i++)); do PU.Add "u$i" || :; PV.Add "v$i" || :; done
now_us; t0=$US; PU.UnionWith PV; now_us; t1=$US
union=$(( t1 - t0 ))

THashSet.new PX; THashSet.new PY                 # 1k / 1k with 50% overlap
for ((i=0; i<1000; i++)); do PX.Add "o$i" || :; done
for ((i=500; i<1500; i++)); do PY.Add "o$i" || :; done
now_us; t0=$US; PX.IntersectWith PY; now_us; t1=$US
inter=$(( t1 - t0 ))

PU.Count; nu="$RESULT"; PX.Count; nx="$RESULT"
lim=$(( base * 3 ))
if [[ "$nu" == "2000" && "$nx" == "500" ]] && (( union <= lim && inter <= lim )); then
    kt_test_pass "add ${base}us, union ${union}us, intersect ${inter}us (limit ${lim}us)"
else
    kt_test_fail "add=${base}us union=${union}us intersect=${inter}us limit=${lim}us union-count=$nu inter-count=$nx"
fi
PA.delete; PU.delete; PV.delete; PX.delete; PY.delete

kt_test_log "005_SetAlgebra.sh completed"
