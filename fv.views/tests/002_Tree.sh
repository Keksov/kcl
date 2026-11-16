#!/usr/bin/env bash
# 002_Tree.sh - the view tree (FV TGroup.Insert / InsertBefore / Delete,
# TView.MakeFirst / PutInFrontOf / Next / Prev / NextView / PrevView,
# TGroup.First / Last, Done): the subview lists back to front, Owner, Current
# (FV ResetCurrent: the front-most visible selectable view after an insert, a
# delete or a z-order move of a selectable view; the sfSelected bits move),
# the refusals (rc and RESULT), V.delete of a group (subviews destroyed, the
# lists and private entries freed), and the redraw hook's calls.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: the view tree"

HOOK=()
fv.views._changed() { HOOK+=("$1 $2 ${3:-.} $4 $5 $6 $7"); }

TGroup.new desk 0 1 80 23
TGroup.new w1 0 0 40 20
TGroup.new w2 40 0 80 20
TView.new st 0 0 80 1
st_data[Options]=0

kt_test_start "insert: each new view in front (the end of the list); Owner set; a selectable one becomes Current"
fv.views.insert desk w1; r1=$?
fv.views.insert desk w2; r2=$?
fv.views.insert desk st; r3=$?
fvw_tree desk
if [[ $r1$r2$r3 == 000 && $REPLY == 'desk[{w1[]} {w2[]} st]*w2' && ${w1_data[Owner]} == desk && ${st_data[Owner]} == desk ]]; then kt_test_pass "$REPLY"
else kt_test_fail "rc=$r1$r2$r3 tree=$REPLY"; fi

fvw_check "the sfSelected bit is on the Current view only" "0 32 0" \
    "$(( w1_data[State] & FV_SF_SELECTED )) $(( w2_data[State] & FV_SF_SELECTED )) $(( st_data[State] & FV_SF_SELECTED ))"
fvw_check "the hook got one insert per view, with the view's absolute rect" \
    "insert w1 desk 0 1 40 21|insert w2 desk 40 1 80 21|insert st desk 0 1 80 2" "$(IFS='|'; echo "${HOOK[*]}")"

kt_test_start "first / last / next / prev (rings) / nextView / prevView (nil at the ends)"
out=''
fv.views.first desk; out+="$?:$RESULT "
fv.views.last desk; out+="$?:$RESULT "
fv.views.next st; out+="$?:$RESULT "
fv.views.next w1; out+="$?:$RESULT "
fv.views.prev w1; out+="$?:$RESULT "
fv.views.prev st; out+="$?:$RESULT "
fv.views.nextView w2; out+="$?:$RESULT "
fv.views.nextView w1; out+="$?:[$RESULT] "
fv.views.prevView w2; out+="$?:$RESULT "
fv.views.prevView st; out+="$?:[$RESULT]"
want='0:st 0:w1 0:w2 0:st 0:w2 0:w1 0:w1 1:[] 0:st 1:[]'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "navigation of a view without an owner and of an empty group: nil (rc 1, RESULT '')"
TView.new lone 0 0 1 1
TGroup.new eg 0 0 5 5
out=''
for f in next prev nextView prevView; do RESULT=x; fv.views.$f lone; out+="$?[$RESULT]"; done
RESULT=x; fv.views.first eg; out+=" $?[$RESULT]"
RESULT=x; fv.views.last eg; out+="$?[$RESULT]"
if [[ $out == '1[]1[]1[]1[] 1[]1[]' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out]"; fi

kt_test_start "makeFirst: to the front; a selectable view becomes Current (FV ResetCurrent); the hook says order"
HOOK=()
fv.views.makeFirst w1
fvw_tree desk
if [[ $REPLY == 'desk[{w2[]} st {w1[]}]*w1' && ${HOOK[*]} == 'order w1 desk 0 1 40 21' ]] && (( !(w2_data[State] & FV_SF_SELECTED) && (w1_data[State] & FV_SF_SELECTED) )); then kt_test_pass "$REPLY"
else kt_test_fail "tree=$REPLY hook=[${HOOK[*]}]"; fi

kt_test_start "makeFirst of the front view, putInFrontOf itself or of its NextView: no-ops (no hook)"
HOOK=()
fv.views.makeFirst w1; a=$?
fv.views.putInFrontOf w1 w1; b=$?
fv.views.putInFrontOf w1 st; c=$?
fv.views.putInFrontOf w2 ''; d=$?
fvw_tree desk
if [[ $a$b$c$d == 0000 && $REPLY == 'desk[{w2[]} st {w1[]}]*w1' && ${#HOOK[@]} == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$a$b$c$d tree=$REPLY hook=${#HOOK[@]}"; fi

kt_test_start "putInFrontOf: directly in front of the target; '' = behind every sibling"
fv.views.putInFrontOf w1 w2; fvw_tree desk; t1=$REPLY
fv.views.putInFrontOf st ''; fvw_tree desk; t2=$REPLY
fv.views.putInFrontOf w2 w1; fvw_tree desk; t3=$REPLY
want='desk[{w2[]} {w1[]} st]*w1|desk[st {w2[]} {w1[]}]*w1|desk[st {w1[]} {w2[]}]*w2'
if [[ "$t1|$t2|$t3" == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$t1|$t2|$t3] want [$want]"; fi

kt_test_start "putInFrontOf an invisible view: moved, Current not reset, no hook (FV: RemoveView + InsertView only)"
HOOK=()
w1_data[State]=$(( w1_data[State] & ~FV_SF_VISIBLE ))
fv.views.makeFirst w1
fvw_tree desk
if [[ $REPLY == 'desk[st {w2[]} {w1[]}]*w2' && ${#HOOK[@]} == 0 ]]; then kt_test_pass "$REPLY"; else kt_test_fail "tree=$REPLY hook=[${HOOK[*]}]"; fi
w1_data[State]=$(( w1_data[State] | FV_SF_VISIBLE ))

kt_test_start "a non-selectable view moved to the front leaves Current alone"
fv.views.makeFirst st
fvw_tree desk
if [[ $REPLY == 'desk[{w2[]} {w1[]} st]*w2' ]]; then kt_test_pass "$REPLY"; else kt_test_fail "tree=$REPLY"; fi

kt_test_start "insertBefore: in front of the target; '' = at the back; Current per FV ResetCurrent (the front-most selectable)"
TView.new a 0 0 2 2; TView.new b 0 0 2 2
a_data[Options]=$FV_OF_SELECTABLE
fv.views.insertBefore desk a w2; r1=$?
fv.views.insertBefore desk b ''; r2=$?
fvw_tree desk
if [[ $r1$r2 == 00 && $REPLY == 'desk[b {w2[]} a {w1[]} st]*w1' ]]; then kt_test_pass "$REPLY"; else kt_test_fail "rc=$r1$r2 tree=$REPLY"; fi

kt_test_start "delete: out of the list, Owner '', Current reset (FV Hide -> ResetCurrent), the view stays live and keeps its State; hook delete with its old rect"
HOOK=()
fv.views.delete desk w1; r=$?
fvw_tree desk
if [[ $r == 0 && $REPLY == 'desk[b {w2[]} a st]*a' && -z ${w1_data[Owner]} ]] && fv.views.isView w1 && (( w1_data[State] & FV_SF_VISIBLE )) \
   && [[ ${HOOK[*]} == 'delete w1 desk 0 1 40 21' ]]; then kt_test_pass "$REPLY"
else kt_test_fail "rc=$r tree=$REPLY owner=${w1_data[Owner]} hook=[${HOOK[*]}]"; fi

kt_test_start "deleting a non-selectable non-current view keeps Current; deleting the last selectable empties it"
fv.views.delete desk b; fvw_tree desk; t1=$REPLY
fv.views.delete desk a; fv.views.delete desk w2; fvw_tree desk; t2=$REPLY
if [[ $t1 == 'desk[{w2[]} a st]*a' && $t2 == 'desk[st]' && -z ${desk_data[Current]} ]] && (( !(w2_data[State] & FV_SF_SELECTED) )); then kt_test_pass "ok"
else kt_test_fail "[$t1] [$t2] cur=${desk_data[Current]}"; fi

kt_test_start "a deleted view can be inserted again (anywhere)"
fv.views.insert w2 w1; r=$?
fv.views.insert desk w2; r+=$?
fvw_tree desk
if [[ $r == 00 && $REPLY == 'desk[st {w2[{w1[]}]*w1}]*w2' ]]; then kt_test_pass "$REPLY"; else kt_test_fail "rc=$r tree=$REPLY"; fi

kt_test_start "refusals: rc 2 (wrong argument count, not a group, not a view), rc 1 (already owned, a cycle, a target that is not a subview, delete of a non-subview); RESULT '' and the tree unchanged"
out=''
RESULT=x; fv.views.insert desk; out+="$?[$RESULT]"
RESULT=x; fv.views.insert st a; out+="$?[$RESULT]"
RESULT=x; fv.views.insert nosuch a; out+="$?[$RESULT]"
RESULT=x; fv.views.insert desk nosuch; out+="$?[$RESULT]"
RESULT=x; fv.views.insert desk 'a b'; out+="$?[$RESULT]"
RESULT=x; fv.views.insert desk w1; out+="$?[$RESULT]"
RESULT=x; fv.views.insert w1 w2; out+="$?[$RESULT]"
RESULT=x; fv.views.insert w2 w2; out+="$?[$RESULT]"
RESULT=x; fv.views.insertBefore desk a w1; out+="$?[$RESULT]"
RESULT=x; fv.views.delete desk w1; out+="$?[$RESULT]"
RESULT=x; fv.views.delete desk; out+="$?[$RESULT]"
RESULT=x; fv.views.putInFrontOf w1 st; out+="$?[$RESULT]"
RESULT=x; fv.views.makeFirst nosuch; out+="$?[$RESULT]"
RESULT=x; fv.views.next; out+="$?[$RESULT]"
fvw_tree desk
want='2[]2[]2[]2[]2[]1[]1[]1[]1[]1[]2[]1[]2[]2[]'
if [[ $out == "$want" && $REPLY == 'desk[st {w2[{w1[]}]*w1}]*w2' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want] tree=$REPLY"; fi

kt_test_start "a cycle is refused: a group cannot go into its own subtree (rc 1)"
TGroup.new cp 0 0 9 9; TGroup.new cq 0 0 5 5; TGroup.new cr 0 0 2 2
fv.views.insert cp cq; fv.views.insert cq cr
RESULT=x; fv.views.insert cr cp; r=$?
fvw_tree cp
if [[ $r == 1 && -z $RESULT && $REPLY == 'cp[{cq[{cr[]}]*cr}]*cq' && -z ${cp_data[Owner]} ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r tree=$REPLY"; fi
cp.delete

kt_test_start "procedures leave RESULT as it was; the refusals print nothing on stdout / stderr (no debug switch)"
RESULT=keep
out=$( { fv.views.makeFirst w1; fv.views.putInFrontOf st w2; fv.views.insert nosuch x; fv.views.delete desk nosuch; } 2>&1 )
fv.views.makeFirst st
if [[ $RESULT == keep && -z $out ]]; then kt_test_pass "ok"; else kt_test_fail "RESULT=$RESULT out=[$out]"; fi

kt_test_start "V.delete of a group: out of its owner (one delete hook), its subtree destroyed, the lists and private entries freed"
TView.new c 0 0 1 1; fv.views.insert w1 c
HOOK=()
w2.delete
fvw_tree desk
gone=1
for v in w2 w1 c; do
    if declare -F "$v.delete" >/dev/null || [[ -n ${__FV_VW_LIVE[$v]-}${__FV_VW_AX[$v]-}${__FV_VW_C3[$v]-}${__FV_VW_GRP[$v]-} ]] || declare -p "${v}_views" >/dev/null 2>&1; then gone=0; fi
done
if [[ $REPLY == 'desk[st]' && $gone == 1 && ${HOOK[*]} == 'delete w2 desk 40 1 80 21' && -z ${desk_data[Current]} ]]; then kt_test_pass "ok"
else kt_test_fail "tree=$REPLY gone=$gone hook=[${HOOK[*]}]"; fi

kt_test_start "V.delete of a view without an owner; a user's own .delete of a subview first removes it from the list"
TGroup.new g 0 0 9 9; TView.new k1 0 0 1 1; TView.new k2 0 0 1 1
fv.views.insert g k1; fv.views.insert g k2
k1.delete
fvw_tree g; t=$REPLY
g.delete
if [[ $t == 'g[k2]' ]] && ! fv.views.isView g && ! fv.views.isView k2 && ! declare -F k2.delete >/dev/null; then kt_test_pass "ok"; else kt_test_fail "tree=$t"; fi

kt_test_start "a name is free for a new view after .delete (the private entries do not leak into it)"
TGroup.new w2 1 2 3 4; r=$?
fvw_tree w2
if [[ $r == 0 && $REPLY == 'w2[]' && ${__FV_VW_AX[w2]} == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r tree=$REPLY"; fi

kt_test_start "names that differ only in case are different views (also under nocasematch)"
TGroup.new cg 0 0 9 9; TView.new Kx 0 0 1 1; TView.new kx 0 0 1 1
shopt -s nocasematch
fv.views.insert cg kx; fv.views.insert cg Kx
fv.views.putInFrontOf kx Kx
fv.views.delete cg Kx; r=$?
shopt -u nocasematch
fvw_tree cg
if [[ $r == 0 && $REPLY == 'cg[kx]' ]]; then kt_test_pass "$REPLY"; else kt_test_fail "rc=$r tree=$REPLY"; fi

kt_test_log "002_Tree.sh completed"
