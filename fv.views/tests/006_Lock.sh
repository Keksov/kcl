#!/usr/bin/env bash
# 006_Lock.sh - the two lock counters (design §1.7, decision D17):
#   * lockScreenUpdate / unlockScreenUpdate: the drawing goes on into the
#     buffer, the terminal update is held (nested counts), sent once at 0;
#     unlockScreenUpdate at 0 is a no-op; RESULT kept;
#   * lock G / unlock G (FV TGroup.Lock / Unlock, LockFlag): while G is
#     locked no drawView of G or of a view inside it is drawn (the hooks'
#     redraws included: move, insert), the terminal update is held; at the
#     outermost unlock G is redrawn ONCE (also after several changes, and for
#     FV's "Lock; change fields; Unlock" with no drawView at all); nested
#     counts; an inner group's unlock inside its locked owner draws nothing,
#     the owner's unlock draws both once; LockFlag mirrors the count; unlock
#     of an unlocked group is a no-op; a group destroyed while locked no
#     longer holds the update, and destroying it (or a window holding a
#     locked group) sends the removal to the terminal at once; refusals rc 2.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "006: lockScreenUpdate and lock / unlock"

fvw_scene
fv.views.drawView desk

kt_test_start "lockScreenUpdate: drawing reaches the buffer, the terminal gets nothing until the outermost unlockScreenUpdate"
fvw_outsize; s0=$REPLY
RESULT=keep
fv.views.lockScreenUpdate; fv.views.lockScreenUpdate
fv.views.moveTo w2 31 5
fvw_outsize; s1=$REPLY
rk=$RESULT; fvw_cells 31 10 1; buf=$RESULT
fv.views.unlockScreenUpdate
fvw_outsize; s2=$REPLY
fv.views.unlockScreenUpdate
fvw_outsize; s3=$REPLY
fv.views.unlockScreenUpdate; rz=$?
fvw_outsize; s4=$REPLY
if [[ $s1 == "$s0" && $s2 == "$s0" && $s3 -gt $s2 && $s4 == "$s3" && $rz == 0 && $rk == keep && $buf == '║' ]]; then kt_test_pass "ok"
else kt_test_fail "sizes $s0 $s1 $s2 $s3 $s4 rc=$rz RESULT=$rk buffer=[$buf]"; fi
fv.views.moveTo w2 30 5
fv.views.drawView desk

kt_test_start "lock w2: drawView, a move and an insert inside it draw nothing and update nothing"
fvw_classes
fvw_outsize; s0=$REPLY
fvw_cells 31 6 12; before=$RESULT
FVW_DRAWS=()
fv.views.lock w2
fv.views.drawView w2l
TTList.new xl 1 1 12 3
fv.views.insert w2 xl
fv.views.moveTo w2l 1 3
fvw_outsize; s1=$REPLY
fvw_cells 31 6 12; mid=$RESULT
r="${FVW_DRAWS[w2l]:-0}${FVW_DRAWS[xl]:-0} ${w2_data[LockFlag]} $__FV_VW_LOCKN"
if [[ $s1 == "$s0" && $mid == "$before" && $r == '00 1 1' ]]; then kt_test_pass "ok"; else kt_test_fail "sizes $s0 $s1 cells [$before] -> [$mid] draws/lock [$r]"; fi

kt_test_start "unlock w2: redrawn once (each list drawn once), the terminal updated"
FVW_DRAWS=()
RESULT=keep
fv.views.unlock w2; rk=$RESULT
fvw_outsize; s2=$REPLY
fvw_cells 31 6 12; after=$RESULT
r="${FVW_DRAWS[w2l]:-0}${FVW_DRAWS[xl]:-0} ${w2_data[LockFlag]} $__FV_VW_LOCKN $rk"
if [[ $s2 -gt $s1 && $after == 'row 0 of xl ' && $r == '11 0 0 keep' ]]; then kt_test_pass "ok"; else kt_test_fail "size $s1 -> $s2 cells [$after] [$r]"; fi
xl.delete
fv.views.moveTo w2l 1 1
fv.views.drawView desk

kt_test_start "FV's 'Lock; change fields; Unlock': no drawView inside, the unlock still redraws the group"
fv.views.lock w2
w2_data[Title]='Renamed'
fv.views.unlock w2; rk=$RESULT
fvw_cells 30 5 40; t=$RESULT
if [[ $t == *' Renamed '* ]]; then kt_test_pass "ok"; else kt_test_fail "[$t]"; fi

kt_test_start "nested counts: lock twice, unlock once -> still locked (nothing drawn); the second unlock redraws once"
FVW_DRAWS=()
fv.views.lock w2; fv.views.lock w2
fv.views.drawView w2
fv.views.unlock w2; rk=$RESULT
a="${FVW_DRAWS[w2l]:-0} ${w2_data[LockFlag]} $__FV_VW_LOCKN"
fv.views.unlock w2; rk=$RESULT
b="${FVW_DRAWS[w2l]:-0} ${w2_data[LockFlag]} $__FV_VW_LOCKN"
if [[ $a == '0 1 1' && $b == '1 0 0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi

kt_test_start "an inner group locked inside its locked owner: the inner unlock draws nothing, the owner's unlock draws everything once"
FVW_DRAWS=()
fvw_outsize; s0=$REPLY
fv.views.lock desk; fv.views.lock w1
fv.views.drawView w1l
fv.views.unlock w1
a="${FVW_DRAWS[w1l]:-0}${FVW_DRAWS[w2l]:-0}"
fvw_outsize; s1=$REPLY
fv.views.unlock desk
b="${FVW_DRAWS[w1l]:-0}${FVW_DRAWS[w2l]:-0} $__FV_VW_LOCKN"
if [[ $a == 00 && $s1 == "$s0" && $b == '11 0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] size $s0 $s1 [$b]"; fi

kt_test_start "a locked group holds the update for draws elsewhere too; lockScreenUpdate + lock together: sent once both are released"
fv.views.lock w1
fv.views.lockScreenUpdate
fvw_outsize; s0=$REPLY
fv.views.moveTo w2 31 5
fvw_outsize; s1=$REPLY
fv.views.unlockScreenUpdate
fvw_outsize; s2=$REPLY
fv.views.unlock w1
fvw_outsize; s3=$REPLY
if [[ $s1 == "$s0" && $s2 == "$s0" && $s3 -gt $s2 ]]; then kt_test_pass "ok"; else kt_test_fail "sizes $s0 $s1 $s2 $s3"; fi
fv.views.moveTo w2 30 5

kt_test_start "unlock of an unlocked group: a no-op (rc 0, nothing drawn); refusals: not a group, a wrong count (rc 2)"
FVW_DRAWS=()
fv.views.unlock w2; a="$? ${FVW_DRAWS[w2l]:-0} $__FV_VW_LOCKN"
out=''
fv.views.lock w2l; out+="$?"; fv.views.unlock nosuch; out+="$?"; fv.views.lock; out+="$?"
fv.views.lockScreenUpdate x; out+="$?"; fv.views.unlockScreenUpdate x; out+="$?"
if [[ $a == '0 0 0' && $out == 22222 && $__FV_VW_LSU == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$out] LSU=$__FV_VW_LSU"; fi

kt_test_start "the aliases Lock / Unlock; a group destroyed while locked releases the update"
TGroup.new tmpg 0 0 5 5
fv.views.insert desk tmpg
tmpg.Lock; tmpg.Lock
a=$__FV_VW_LOCKN
tmpg.delete
b=$__FV_VW_LOCKN
fvw_outsize; s0=$REPLY
fv.views.moveTo w2 31 5
fvw_outsize; s1=$REPLY
desk.Lock; desk.Unlock
if [[ $a == 2 && $b == 0 && $s1 -gt $s0 ]]; then kt_test_pass "ok"; else kt_test_fail "LOCKN $a -> $b, sizes $s0 $s1"; fi

kt_test_start "destroying a locked window sends its removal to the terminal at once (the destroy releases the hold), nothing left for a later update"
fv.views.drawView desk
fvw_outsize; s0=$REPLY
fv.views.lock w2
w2.delete
fvw_outsize; s1=$REPLY
fv.video.updateScreen
fvw_outsize; s2=$REPLY
fvw_cells 50 10 1; c=$RESULT
if [[ $s1 -gt $s0 && $s2 == "$s1" && $__FV_VW_LOCKN == 0 && $c == ' ' ]]; then kt_test_pass "ok"; else kt_test_fail "sizes $s0 $s1 $s2 LOCKN=$__FV_VW_LOCKN cell [$c]"; fi

kt_test_start "destroying a window that holds a locked group sends the removal too"
TGroup.new inner 1 1 5 5
fv.views.insert w1 inner
fv.views.lock inner
fvw_outsize; s0=$REPLY
w1.delete
fvw_outsize; s1=$REPLY
fv.video.updateScreen
fvw_outsize; s2=$REPLY
if [[ $s1 -gt $s0 && $s2 == "$s1" && $__FV_VW_LOCKN == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "sizes $s0 $s1 $s2 LOCKN=$__FV_VW_LOCKN"; fi

fvw_unscene
kt_test_log "006_Lock.sh completed"
