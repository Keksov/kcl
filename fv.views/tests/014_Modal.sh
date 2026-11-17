#!/usr/bin/env bash
# 014_Modal.sh - modal views of stage 2c-3 (design §2.2, §2.1's EOF latch,
# R5, R6; FV Execute, ExecView, EndModal, Valid, MouseEvent), events from a
# scripted source (fvw_events: __FV_VW_GETEVENT, no terminal):
#   * execView: RESULT = endModal's command; the modal view inserted and
#     removed again, the screen == a full repaint after it; Current, Phase,
#     the top view and the event record put back; sfModal while it runs,
#     its Options restored; the old Current stays selected (EnterSelect);
#   * Valid on the endModal path: a refusal keeps the loop going, Valid
#     asked with each EndState; endModal from a leaf inside the dialog;
#   * modal in modal (an inner dialog run from the outer one's handler):
#     both results right, the outer loop goes on with its own events;
#   * the END OF INPUT: the loop ends with cmCancel without asking Valid;
#     the latch: a new execView answers cmCancel at once, no event read;
#     a Valid that opens a "save?" box at the end cannot spin; a failing
#     event source (rc 2) is taken for the end of input (one debug line);
#     a root group's Execute (no owner: the application) ends with cmQuit;
#   * one terminal update per handled event, yet a nested modal view and a
#     handler's drawing before its mouse tracking are shown at once;
#   * the owner-process rule: execView / Execute inside $( ) refused, rc 2,
#     one debug line, nothing run;
#   * no HandleEvent for evNothing (idle ticks cost no dispatch);
#   * a dialog destroying itself in its handler: cmCancel, the tree sound;
#   * endModal without a modal view: rc 1; refusals (rc 2);
#   * mouseEvent: tracking returns the move events (rc 0) and ends at the
#     mouse-up (rc 1), other events dropped; at the end of input rc 1, no
#     spin.
# A terminal resize during a modal view or a drag is P2 stage 2f (fv.app's
# _getEvent handles cmResizeApp) and 2d (dragView): not tested here.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "014: modal views"

# TTDlg: a dialog-like window: cmOK / cmCancel / cmYes / cmNo end it; cmNest
# runs an inner dialog; cmSelf destroys it; cmTrack runs a mouse tracking
# loop; Valid logs each ask and refuses cmOK once while REFUSE=1; with
# BOXVALID a Valid(cmCancel) opens a box (execView) and agrees afterwards
class TTDlg : TWindow
    public
        override proc HandleEvent
        override func Valid
end
TTDlg.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evCommand ]; then
        case $FV_EV_COMMAND in
            cmOK|cmCancel|cmYes|cmNo)
                SEEN+="$this:$FV_EV_COMMAND:modal=$(( State & FV_SF_MODAL ? 1 : 0 )):top=$__FV_VW_TOPVIEW;"
                fv.views.endModal "$this" "$FV_EV_COMMAND"; fv.views.clearEvent "$this" ;;
            cmNest)
                TTDlg.new inner 20 8 50 16 'Inner' 0
                fv.views.execView desk inner; NEST=$RESULT
                inner.delete; fv.views.clearEvent "$this" ;;
            cmSelf) fv.views.clearEvent "$this"; "$this.delete" ;;
            cmTrack)
                Title=Tracked; fv.views.drawView "$this"
                while fv.views.mouseEvent "$this" "$FV_EM_MOUSEMOVE"; do :; done
                fv.views.clearEvent "$this" ;;
        esac
    elif [ "$FV_EV_WHAT" = evKeyDown ]; then
        SEEN+="$this:$FV_EV_KEY;"
        fv.views.clearEvent "$this"
    fi
}
TTDlg.Valid() {
    VASK+="$this:$1;"
    if [[ $1 == cmOK && ${REFUSE:-0} == 1 ]]; then REFUSE=0; return 1; fi
    if [[ $1 == cmCancel && -n ${BOXVALID-} ]]; then
        BOXVALID=''
        TTDlg.new box 30 10 50 14 'Save?' 0
        fv.views.execView desk box; BOX=$RESULT
        box.delete
    fi
    inherited Valid "$@"
}
build TTDlg
# a leaf of the dialog that ends it from inside (FV: a button's press)
class TEnder : TView
    public
        override proc HandleEvent
end
TEnder.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbEnter ]; then fv.views.endModal "$this" cmDefault; fv.views.clearEvent "$this"; fi
}
build TEnder

fvw_tscene
fv.views.drawView app
SEEN='' VASK='' NEST='' BOX=''
TTDlg.new dlg 10 5 60 18 'Dialog' 0

kt_test_start "execView: RESULT = endModal's command; dlg inserted, modal and the top view while it runs, removed after; == a full repaint"
fvw_events 'key kbA' 'cmd cmOK'
fv.views.execView desk dlg; r="$?:$RESULT"
fvw_tree desk; t=$REPLY
if [[ $r == '0:cmOK' && $SEEN == 'dlg:kbA;dlg:cmOK:modal=1:top=dlg;' && $VASK == 'dlg:cmOK;' && -z ${dlg_data[Owner]} && -z $__FV_VW_TOPVIEW ]] \
   && [[ $t == 'desk[bg {w1[w1__fvframe w1l]*w1l} {w2[w2__fvframe w2l]*w2l}]*w2' ]] && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "rc:RESULT [$r] seen [$SEEN] valid [$VASK] owner [${dlg_data[Owner]}] top [$__FV_VW_TOPVIEW] tree [$t] diff [$FVW_DIFF]"; fi

kt_test_start "put back after it: the event record, desk's Phase, dlg's Options and State (no sfModal), Current with its bits; EnterSelect kept w2 selected"
fvw_events 'run probe' 'cmd cmYes'
probe() { bits_in="$(( w2_data[State] & (FV_SF_SELECTED | FV_SF_FOCUSED) ))/${desk_data[Current]}"; }
FV_EV_WHAT=evKeyDown FV_EV_KEY=kbOuter FV_EV_COMMAND=cmOuter FV_EV_INFO=outer FV_EV_MOUSE_X=3 FV_EV_WHEEL=1
desk_data[Phase]=phPostProcess
o1=${dlg_data[Options]}
fv.views.execView desk dlg
r="$RESULT|$FV_EV_WHAT|$FV_EV_KEY|$FV_EV_COMMAND|$FV_EV_INFO|$FV_EV_MOUSE_X|$FV_EV_WHEEL|${desk_data[Phase]}|$(( ${dlg_data[Options]} == o1 ))|$(( dlg_data[State] & FV_SF_MODAL ))|${desk_data[Current]}"
if [[ $r == 'cmYes|evKeyDown|kbOuter|cmOuter|outer|3|1|phPostProcess|1|0|w2' && $bits_in == "$FV_SF_SELECTED/dlg" ]] \
   && (( w2_data[State] & FV_SF_FOCUSED )); then kt_test_pass "ok"
else kt_test_fail "[$r] inside: w2 bits/current [$bits_in]"; fi

kt_test_start "Valid on the endModal path: a refusal keeps the loop going; asked with each EndState"
VASK='' REFUSE=1
fvw_events 'cmd cmOK' 'cmd cmNo' 'cmd cmOK'
fv.views.execView desk dlg; r=$RESULT
if [[ $r == cmNo && $VASK == 'dlg:cmOK;dlg:cmNo;' && $FVW_EVN == 2 ]]; then kt_test_pass "ok"; else kt_test_fail "result $r valid [$VASK] events read $FVW_EVN"; fi

kt_test_start "endModal from a leaf inside the dialog ends the dialog (FV TopView)"
TEnder.new en 1 1 10 2; en_data[Options]=$FV_OF_SELECTABLE
fv.views.insert dlg en
fvw_events 'key kbEnter'
fv.views.execView desk dlg; r=$RESULT
fv.views.delete dlg en; en.delete
if [[ $r == cmDefault ]]; then kt_test_pass "ok"; else kt_test_fail "result $r"; fi

kt_test_start "modal in modal: the inner dialog's result, then the outer loop goes on with its own events; == a full repaint"
SEEN='' VASK=''
fvw_events 'cmd cmNest' 'key kbB' 'cmd cmYes' 'key kbC' 'cmd cmCancel'
fv.views.execView desk dlg; r=$RESULT
if [[ $r == cmCancel && $NEST == cmYes && $SEEN == 'inner:kbB;inner:cmYes:modal=1:top=inner;dlg:kbC;dlg:cmCancel:modal=1:top=dlg;' && $VASK == 'inner:cmYes;dlg:cmCancel;' ]] \
   && ! fv.views.isView inner && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "result $r nest $NEST seen [$SEEN] valid [$VASK] diff [$FVW_DIFF]"; fi

kt_test_start "one terminal update per event, and still shown at once: the inner dialog of a modal in modal, a handler's drawing before its mouse tracking"
snap() { fvw_outsize; SNAPS+="$REPLY "; }
SNAPS=''
fvw_events 'run snap' 'cmd cmNest' 'run snap' 'cmd cmYes' 'run snap' 'cmd cmTrack' 'run snap' 'move 3 3' 'up 3 3' 'run snap' 'cmd cmOK'
fvw_outsize; s0=$REPLY
fv.views.execView desk dlg; r=$RESULT
read -r s1 s2 s3 s4 s5 <<< "$SNAPS"
dlg_data[Title]=Dialog
# s1: the outer dialog shown; s2: the inner one shown before its first event
# (inside the outer handler); s3: the inner one's removal shown; s4: the
# handler's drawing (a new title) shown before the tracking reads its first
# event; s5: nothing more to send after the tracking
if [[ $r == cmOK ]] && (( s0 < s1 && s1 < s2 && s2 < s3 && s3 < s4 && s4 == s5 )); then kt_test_pass "ok ($s0 $s1 $s2 $s3 $s4 $s5)"
else kt_test_fail "result $r sizes $s0 / $SNAPS"; fi
fv.views.drawView dlg

kt_test_start "no HandleEvent for evNothing: idle ticks cost no dispatch"
fvw_events nothing nothing nothing 'cmd cmOK'
fvw_count_on; FVW_CALLS=0
fv.views.execView desk dlg
n=$FVW_CALLS; fvw_count_off
fvw_events 'cmd cmOK'
fvw_count_on; FVW_CALLS=0
fv.views.execView desk dlg
n1=$FVW_CALLS; fvw_count_off
if [[ $n == "$n1" ]]; then kt_test_pass "the same $n dispatches with and without 3 idle ticks"; else kt_test_fail "$n with idle ticks, $n1 without"; fi

kt_test_start "the end of input: the loop ends with cmCancel without asking Valid; == a full repaint"
VASK=''
fvw_events 'key kbA'
fv.views.execView desk dlg; r="$RESULT|$__FV_VW_EOF|$FVW_EVN"
if [[ $r == 'cmCancel|1|2' && -z $VASK ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] valid [$VASK]"; fi

kt_test_start "the latch: a new execView answers cmCancel at once (no event read, dlg not inserted)"
fvw_events 'cmd cmOK'
FVW_EVN=0
__FV_VW_EOF=1
fv.views.execView desk dlg; r="$?:$RESULT:$FVW_EVN:${dlg_data[Owner]}"
if [[ $r == '0:cmCancel:0:' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "a Valid(cmCancel) that opens a 'save?' box at the end of input cannot spin: the box answers cmCancel at once"
fvw_noevents
fvw_events 'cmd cmCancel'
BOXVALID=1 BOX=''
fv.views.execView desk dlg; r="$RESULT|$BOX|$FVW_EVN"
if [[ $r == 'cmCancel|cmCancel|2' ]] && ! fv.views.isView box; then kt_test_pass "ok (the box returned at once)"; else kt_test_fail "[$r]"; fi
BOXVALID=''

kt_test_start "a failing event source (rc 2) is taken for the end of input: cmCancel, the latch, one debug line"
fvw_noevents
fvw_events 'fail 2'
VERBOSE_KKLASS=debug
fv.views.execView desk dlg 2>"$FVW_TMP/dbg.txt"; r="$RESULT|$__FV_VW_EOF"
VERBOSE_KKLASS=''
d=$(<"$FVW_TMP/dbg.txt")
if [[ $r == 'cmCancel|1' && $d == *'Execute: the event source'*'rc 2'* ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] debug [$d]"; fi
fvw_noevents

kt_test_start "a root group's Execute (no owner: the application) ends with cmQuit at the end of input"
TGroup.new solo 0 0 5 5
fvw_events 'key kbA'
RESULT=''; fv.views._virt solo Execute; r=$RESULT
solo.delete; fvw_noevents
if [[ $r == cmQuit ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "the owner-process rule: execView and Execute inside \$( ) refused (rc 2, one debug line), nothing run"
fvw_events 'cmd cmOK'
out=$(fv.views.execView desk dlg; printf 'rc=%s ' "$?"; fv.views._virt dlg Execute; printf 'rc=%s n=%s' "$?" "$FVW_EVN")
VERBOSE_KKLASS=debug
d=$( fv.views.execView desk dlg 2>&1 )
VERBOSE_KKLASS=''
if [[ $out == 'rc=2 rc=2 n=0' && $d == 'Error: fv.views.execView: refused in a subshell'* && -z ${dlg_data[Owner]} ]]; then kt_test_pass "ok"; else kt_test_fail "[$out] debug [$d]"; fi
fvw_noevents

kt_test_start "a dialog destroying itself in its handler: execView answers cmCancel; the tree and the focus are sound"
fvw_events 'cmd cmSelf'
fv.views.execView desk dlg; r=$RESULT
fvw_tree desk; t=$REPLY
fvw_noevents
if [[ $r == cmCancel && $t == 'desk[bg {w1[w1__fvframe w1l]*w1l} {w2[w2__fvframe w2l]*w2l}]*w2' ]] && ! fv.views.isView dlg && (( w2_data[State] & FV_SF_FOCUSED )) && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "result $r tree [$t] diff [$FVW_DIFF]"; fi
TTDlg.new dlg 10 5 60 18 'Dialog' 0

kt_test_start "modal cmClose on the dialog (TWindow): handled, cmCancel posted (FV PutEvent), which ends it"
fvw_events 'cmd cmClose'
fv.views.execView desk dlg; r="$RESULT|${#__FV_DR_PEND[@]}"
fvw_noevents
if [[ $r == 'cmCancel|0' ]] && fv.views.isView dlg; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "endModal: no modal view above -> rc 1; the app root (sfModal, as fv.app makes it) takes the EndState"
TGroup.new free 0 0 5 5; TView.new fv1 0 0 1 1; fv.views.insert free fv1
fv.views.endModal fv1 cmOK; r1=$?
free.delete
fv.views.endModal w1l cmQuit; r2="$?:${app_data[EndState]}"
app_data[EndState]=''
if [[ $r1 == 1 && $r2 == '0:cmQuit' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2]"; fi

kt_test_start "mouseEvent: the moves come back (rc 0) until the mouse-up (rc 1); keys meanwhile are dropped"
fvw_events 'move 5 5' 'key kbA' 'move 6 7' 'up 6 7'
trk=''
while fv.views.mouseEvent w1 "$FV_EM_MOUSEMOVE"; do trk+="$FV_EV_WHAT@$FV_EV_MOUSE_X,$FV_EV_MOUSE_Y;"; done
trk+="end:$FV_EV_WHAT@$FV_EV_MOUSE_X,$FV_EV_MOUSE_Y"
if [[ $trk == 'evMouseMove@5,5;evMouseMove@6,7;end:evMouseUp@6,7' ]]; then kt_test_pass "ok"; else kt_test_fail "[$trk]"; fi

kt_test_start "mouseEvent at the end of input: rc 1 (FV_EV_WHAT evNothing, latched): the tracking loop ends"
fvw_events 'move 1 1'
n=0
while fv.views.mouseEvent w1 "$FV_EM_MOUSEMOVE"; do n=$(( n + 1 )); if (( n > 5 )); then break; fi; done
r="$n|$FV_EV_WHAT|$__FV_VW_EOF"
fv.views.mouseEvent w1 "$FV_EM_MOUSEMOVE"; r+="|$?"
fvw_noevents
if [[ $r == '1|evNothing|1|1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "execView of a view already in the group: not removed; afterwards its frame inactive again, == a full repaint"
TTDlg.new dlg3 10 5 60 18 'Kept' 0
TView.new dlg3l 1 1 49 12; fv.views.insert dlg3 dlg3l
fv.views.insert desk dlg3
fv.views.select w2
fvw_events 'cmd cmOK'
fv.views.execView desk dlg3; r="$RESULT|${dlg3_data[Owner]}|${desk_data[Current]}|$(( dlg3__fvframe_data[State] & FV_SF_ACTIVE ))"
fvw_noevents
if [[ $r == 'cmOK|desk|w2|0' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
dlg3.delete

kt_test_start "execView G P with P = G or P an owner of G: refused (rc 2, one debug line), nothing changed, no hang"
VERBOSE_KKLASS=debug
fv.views.execView desk desk 2>"$FVW_TMP/d1.txt"; r1="$?|$RESULT|${desk_data[Current]}"
fv.views.execView w2 app 2>"$FVW_TMP/d2.txt"; r2="$?|${w2_data[Current]}"
VERBOSE_KKLASS=''
d1=$(<"$FVW_TMP/d1.txt") d2=$(<"$FVW_TMP/d2.txt")
if [[ $r1 == '2||w2' && $r2 == '2|w2l' && $d1 == *"is 'desk' or one of its owners"* && $d2 == *"'app' is 'w2' or one of its owners"* ]]; then kt_test_pass "ok"
else kt_test_fail "[$r1] [$r2] debug [$d1] [$d2]"; fi

kt_test_start "resetCursor is bounded: a Current chain made into a cycle by hand ends (no hang)"
TGroup.new cy1 0 0 9 9; TGroup.new cy2 0 0 9 9; fv.views.insert cy1 cy2
cy1_data[State]=$(( cy1_data[State] | FV_SF_FOCUSED )) cy2_data[State]=$(( cy2_data[State] | FV_SF_FOCUSED ))
cy2_data[Current]=cy1
timeout_ok=1
fv.views.resetCursor cy2 && timeout_ok=0
cy2_data[Current]=''
cy1.delete
if [[ $timeout_ok == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "rc"; fi

kt_test_start "an event source that leaves FV_EV_WHAT empty: taken for evNothing (no error), the loop goes on"
emptysrc() { if (( FVW_EVN++ < 2 )); then fv.drivers.clearEvent; FV_EV_WHAT=''; return 0; fi; return 1; }
FVW_EVN=0 __FV_VW_GETEVENT=emptysrc
fv.views.execView desk dlg 2>"$FVW_TMP/e.txt"; r="$RESULT|$FVW_EVN"
FV_EV_WHAT=''; fv.views.mouseEvent w1 "$FV_EM_MOUSEMOVE" 2>>"$FVW_TMP/e.txt"; r+="|$?"
FV_EV_WHAT=''; fv.views._virt app HandleEvent 2>>"$FVW_TMP/e.txt"; r+="|$?"
e=$(<"$FVW_TMP/e.txt")
fvw_noevents
if [[ $r == 'cmCancel|3|1|0' && -z $e ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] stderr [$e]"; fi

kt_test_start "an unbalanced unlockScreenUpdate in a modal handler: ignored (one debug line), the loop's hold intact, frames still sent"
class TUnl : TWindow
    public
        override proc HandleEvent
end
TUnl.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmUn ]; then
        fv.views.unlockScreenUpdate; fv.views.unlockScreenUpdate
        Title=Unlocked; fv.views.drawView "$this"; fv.views.endModal "$this" cmOK; fv.views.clearEvent "$this"
    fi
}
build TUnl
TUnl.new ud 10 5 60 18 'Unl' 0
fvw_events 'cmd cmUn' 'run snap'
SNAPS=''
fvw_outsize; s0=$REPLY
VERBOSE_KKLASS=debug
fv.views.execView desk ud 2>"$FVW_TMP/u.txt"; r="$RESULT|$__FV_VW_LSU|$__FV_VW_EH"
VERBOSE_KKLASS=''
u=$(<"$FVW_TMP/u.txt")
fvw_noevents
ud.delete
if [[ $r == 'cmOK|0|0' && $u == *'unlockScreenUpdate: no lockScreenUpdate of yours'* ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] debug [$u] diff [$FVW_DIFF]"; fi

kt_test_start "refusals (rc 2, RESULT ''): execView / endModal / mouseEvent arguments, a non-group, a non-view; execView '' = cmCancel"
r=''
RESULT=x; fv.views.execView desk || r+="$?[$RESULT],"
fv.views.execView w1l dlg || r+="$?,"
fv.views.execView desk nosuch || r+="$?,"
fv.views.endModal dlg || r+="$?,"
fv.views.endModal dlg 'cm X' || r+="$?,"
fv.views.mouseEvent w1 x || r+="$?,"
fv.views.mouseEvent nosuch 1 || r+="$?,"
fv.views.execView desk ''; r+="$RESULT"
if [[ $r == '2[],2,2,2,2,2,2,cmCancel' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

dlg.delete
fvw_untscene
kt_test_log "014_Modal.sh completed"
