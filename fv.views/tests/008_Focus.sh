#!/usr/bin/env bash
# 008_Focus.sh - the focus chain of stage 2c-3 (design §1.8; FV Select,
# SetCurrent, Focus, FocusNext / SelectNext, SetState, ResetCursor) in the
# events scene (fvw_tscene: app > desk > bg, w1, w2 TWindows with a TTLeaf
# each):
#   * the state bits along the chain: sfSelected (Current in its owner),
#     sfFocused (on the chain from the focused root), sfActive (the selected
#     window, its frame and contents);
#   * select of the back window: brought to the front, the bits moved, the
#     screen equal to a full repaint, its list drawn once (it was covered);
#     side by side: only the two frame borders and the new front window's
#     shadow (no list drawn);
#   * the focus broadcasts cmReleasedFocus / cmReceivedFocus to the owner
#     (FV_EV_INFO = the view), in FV's order;
#   * sfActive propagation: each subview gets it, a frame's border is
#     redrawn (3 fv.video writes since 2c-p: both sides in one fillColumns),
#     a leaf is not redrawn;
#   * Tab in a window (TWindow: kbTab / kbDown / kbRight next, kbShiftTab /
#     kbUp / kbLeft previous; hidden, disabled, unselectable views skipped);
#   * click to focus the back window through the whole chain (consumed;
#     the next click reaches the leaf);
#   * resetCursor: the focused leaf's cursor (position, underline / block),
#     hidden when not visible, outside, covered or not focused;
#   * focus with an ofValidate Current that refuses cmReleasedFocus;
#   * focusNext / selectNext and their refusals;
#   * setState is virtual-aware (an override sees each change and keeps the
#     behaviour with inherited); show / hide / sfShadow through it;
#   * delete / hide of the focused window: the focus moves on (and
#     cmReleasedFocus reaches the owner); insert into an active group passes
#     sfActive (FV InsertBefore); select of a window already in front makes
#     it Current (a deviation from FV's MakeFirst no-op);
#   * stage 2c-p, quiet broadcasts: a broadcast that no handler would see is
#     not delivered (no dispatch), the Phase a delivery sets is set the same
#     way; a listening user leaf breaks the quiet and hears what it heard;
#     the dispatch's skips (EventMask, removed views) apply to the walk.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "008: focus"

bits() {   # V... -> REPLY = "v:SEL FOC ACT" flags per view (s f a or -)
    local v o=''
    for v; do
        local -n d=${v}_data
        o+="$v:"
        (( d[State] & FV_SF_SELECTED )) && o+=s || o+=-
        (( d[State] & FV_SF_FOCUSED )) && o+=f || o+=-
        (( d[State] & FV_SF_ACTIVE )) && o+=a || o+=-
        o+=' '
    done
    REPLY=${o% }
}
ev() {   # WHAT KEY-OR-COMMAND [X Y] -> the event to app
    fv.drivers.clearEvent
    FV_EV_WHAT=$1
    case $1 in
        evKeyDown) FV_EV_KEY=$2 ;;
        evMouse*) FV_EV_MOUSE_X=$2 FV_EV_MOUSE_Y=$3 FV_EV_MOUSE_BUTTONS=1 ;;
        *) FV_EV_COMMAND=$2 ;;
    esac
    fv.views._virt app HandleEvent
}

# a hidden broadcast listener (FV: TLabel listens to the focus broadcasts)
class TLsn : TView
    public
        override proc HandleEvent
end
TLsn.HandleEvent() { HEARD+="$Owner<$FV_EV_COMMAND:$FV_EV_INFO;"; }
build TLsn
lsn() {   # NAME GROUP
    TLsn.new "$1" 0 0 1 1
    local -n d=${1}_data
    d[State]=0 d[EventMask]=$(( d[EventMask] | FV_EM_BROADCAST ))
    fv.views.insertBefore "$2" "$1" ''
}

fvw_tscene
fv.views.drawView app

kt_test_start "the chain after the scene: app focused; desk, w2, w2l selected + focused; w2 active (and its frame); w1 neither"
bits app desk w1 w2 w1l w2l w1__fvframe w2__fvframe
if [[ $REPLY == 'app:sf- desk:sf- w1:--- w2:sfa w1l:s-- w2l:sfa w1__fvframe:--- w2__fvframe:--a' ]]; then kt_test_pass "ok"; else kt_test_fail "[$REPLY]"; fi

kt_test_start "select w1 (covered by w2): brought to the front, the bits moved, == a full repaint, its list drawn once, w2's not"
FVW_DRAWS=()
fv.views.select w1
fvw_tree desk; t=$REPLY
bits w1 w2 w1l w2l w1__fvframe w2__fvframe; b=$REPLY
d1=${FVW_DRAWS[w1l]:-0} d2=${FVW_DRAWS[w2l]:-0}
if fvw_full app && [[ $t == 'desk[bg {w2[w2__fvframe w2l]*w2l} {w1[w1__fvframe w1l]*w1l}]*w1' && $b == 'w1:sfa w2:--- w1l:sfa w2l:s-- w1__fvframe:--a w2__fvframe:---' && $d1 == 1 && $d2 == 0 ]]; then kt_test_pass "ok"
else kt_test_fail "tree [$t] bits [$b] draws $d1/$d2 diff [$FVW_DIFF]"; fi

kt_test_start "the focus broadcasts in FV's order (each view's to its owner before its Current's; released before received; a broadcast to the desktop goes on into the windows), FV_EV_INFO = the view"
lsn ld desk; lsn l1 w1; lsn l2 w2
HEARD=''
fv.views.select w2
want='w2<cmReleasedFocus:w1;w1<cmReleasedFocus:w1;desk<cmReleasedFocus:w1;w1<cmReleasedFocus:w1l;'
want+='w2<cmReceivedFocus:w2;w1<cmReceivedFocus:w2;desk<cmReceivedFocus:w2;w2<cmReceivedFocus:w2l;'
if [[ $HEARD == "$want" ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "heard [$HEARD] diff [$FVW_DIFF]"; fi
for v in ld l1 l2; do "$v.delete"; done

kt_test_start "sfActive: each subview gets it, the frame's border is redrawn (3 writes: top, bottom, both sides in one fillColumns), the leaf is not redrawn, no dispatch"
FVW_DRAWS=()
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
fv.views.setState w2 "$FV_SF_ACTIVE" 0
n=$FVW_CALLS w=$FVW_WRITES
fvw_writes_off; fvw_count_off
bits w2 w2l w2__fvframe; b=$REPLY
fv.views.setState w2 "$FV_SF_ACTIVE" 1
if [[ $n == 0 && $w == 3 && $b == 'w2:sf- w2l:sf- w2__fvframe:---' && ${FVW_DRAWS[w2l]:-0} == 0 ]] && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "dispatches $n writes $w bits [$b] draws ${FVW_DRAWS[w2l]:-0} diff [$FVW_DIFF]"; fi

kt_test_start "side by side: selecting the other window redraws the two frame borders and its shadow only (no list drawn, 0 dispatches)"
fvw_untscene
fvw_tscene 80 24 side
fv.views.drawView app
FVW_DRAWS=()
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
fv.views.select w1
n=$FVW_CALLS w=$FVW_WRITES
fvw_writes_off; fvw_count_off
kt_test_log "# writes select-side $w (2 borders x 3 + the shadow strips)"
if [[ $n == 0 && ${FVW_DRAWS[w1l]:-0} == 0 && ${FVW_DRAWS[w2l]:-0} == 0 ]] && (( w <= 12 )) && fvw_full app; then kt_test_pass "ok ($w writes)"
else kt_test_fail "dispatches $n writes $w draws ${FVW_DRAWS[w1l]:-0}/${FVW_DRAWS[w2l]:-0} diff [$FVW_DIFF]"; fi
fvw_untscene

kt_test_start "Tab in a window: kbTab / kbDown / kbRight go to the next control (insertion order), kbShiftTab / kbUp / kbLeft back; handled"
fvw_screen
TGroup.new root 0 0 80 24; fvw_root root
TWindow.new tw 0 0 40 10 'Tab' 0
for v in c1 c2 c3 c4 c5; do TView.new "$v" 1 1 2 2; declare -n d=${v}_data; d[Options]=$FV_OF_SELECTABLE; unset -n d; fv.views.insert tw "$v"; done
c3_data[Options]=0
c4_data[State]=$(( c4_data[State] | FV_SF_DISABLED ))
fv.views.insert root tw
fv.views.select c1
seq=''
for k in kbTab kbTab kbDown kbRight kbShiftTab kbUp kbLeft; do
    fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$k
    fv.views._virt root HandleEvent
    seq+="${tw_data[Current]}:$FV_EV_WHAT,"
done
bits c1 c2 c5; b=$REPLY
if [[ $seq == 'c2:evNothing,c5:evNothing,c1:evNothing,c2:evNothing,c1:evNothing,c5:evNothing,c2:evNothing,' && $b == 'c1:--a c2:sfa c5:--a' ]]; then kt_test_pass "ok (c3 unselectable, c4 disabled skipped)"
else kt_test_fail "seq [$seq] bits [$b]"; fi

kt_test_start "focusNext / selectNext: FORWARDS 1 is FV's Next (the view behind), 0 the one in front; rc 0 when there is none"
fv.views.focusNext tw 1; r1="$?:${tw_data[Current]}"
fv.views.selectNext tw 0; r2="$?:${tw_data[Current]}"
TGroup.new lone 0 0 5 5; TView.new only 0 0 1 1; only_data[Options]=$FV_OF_SELECTABLE; fv.views.insert lone only
fv.views.focusNext lone 0; r3="$?:${lone_data[Current]}"
fv.views.focusNext only 0; r4=$?; fv.views.selectNext tw 2; r5=$?; fv.views.focusNext tw; r6=$?
lone.delete
if [[ $r1 == '0:c1' && $r2 == '0:c2' && $r3 == '0:only' && $r4 == 2 && $r5 == 2 && $r6 == 2 ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] [$r3] $r4 $r5 $r6"; fi

kt_test_start "focus: an ofValidate Current whose Valid(cmReleasedFocus) says no keeps the focus (rc 1); yes moves it (rc 0)"
class TVal : TView
    public
        override func Valid
end
TVal.Valid() { VASKED+="$1;"; if [[ ${VNO:-0} == 1 ]]; then return 1; fi; inherited Valid "$@"; }
build TVal
TVal.new cv 1 1 2 2; cv_data[Options]=$(( FV_OF_SELECTABLE | FV_OF_VALIDATE ))
fv.views.insert tw cv
VASKED='' VNO=1
fv.views.focus c1; r1="$?:${tw_data[Current]}:$VASKED"
VNO=0
fv.views.focus c1; r2="$?:${tw_data[Current]}"
if [[ $r1 == '1:cv:cmReleasedFocus;' && $r2 == '0:c1' ]]; then kt_test_pass "ok"; else kt_test_fail "no [$r1] yes [$r2]"; fi
root.delete

kt_test_start "click to focus the back window through the chain: brought to the front, consumed, == a full repaint; the next click reaches the leaf"
fvw_tscene
fv.views.drawView app
ev evMouseDown 3 3
r1="${desk_data[Current]}:$FV_EV_WHAT:$FVW_GOT"
FVW_GOT=''
ev evMouseDown 5 5
r2="$FV_EV_WHAT:$FVW_GOT"
if [[ $r1 == 'w1:evNothing:' && $r2 == 'evMouseDown:w1l:evMouseDown:;' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "first [$r1] second [$r2] diff [$FVW_DIFF]"; fi

kt_test_start "a click on the frame of the front window (not selectable) and on the background: nothing changes"
ev evMouseDown 2 1; r1="${desk_data[Current]}:${w1_data[Current]}"
ev evMouseDown 79 0; r2="${desk_data[Current]}"
if [[ $r1 == 'w1:w1l' && $r2 == w1 ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2]"; fi

kt_test_start "resetCursor: the focused leaf's cursor at its CursorX / CursorY (underline; block with sfCursorIns), hidden by hideCursor"
cur() { REPLY="${__FV_VS_CURX}:${__FV_VS_CURY}:${__FV_VS_CURT}"; }
fv.views.setCursor w1l 4 2; fv.views.showCursor w1l; cur; r1=$REPLY
fv.views.blockCursor w1l; cur; r2=$REPLY
fv.views.normalCursor w1l; fv.views.hideCursor w1l; cur; r3=$REPLY
# w1 at (2,1), w1l at (1,1) in it: the cell (7,4)
if [[ $r1 == '7:4:1' && $r2 == '7:4:2' && ${r3##*:} == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] [$r3]"; fi

kt_test_start "resetCursor hides it when the cell is outside the leaf, covered by a view in front, or the leaf is not focused"
fv.views.showCursor w1l
fv.views.setCursor w1l 80 2; cur; r1=$REPLY
fv.views.setCursor w1l 34 6; cur; r2=$REPLY        # (35+2, 6+1+1) = (37, 8): visible, w1 in front
fv.views.select w2; cur; r3=$REPLY                 # w2 (30..70, 5..22) in front now covers it
fv.views.select w1; cur; r4=$REPLY
fv.views.setState app "$FV_SF_FOCUSED" 0; fv.views.resetCursor w1l; cur; r5=$REPLY
fv.views.setState app "$FV_SF_FOCUSED" 1; cur; r6=$REPLY
if [[ ${r1##*:} == 0 && $r2 == '37:8:1' && ${r3##*:} == 0 && $r4 == '37:8:1' && ${r5##*:} == 0 && $r6 == '37:8:1' ]]; then kt_test_pass "ok"
else kt_test_fail "outside [$r1] visible [$r2] covered [$r3] back [$r4] unfocused [$r5] refocused [$r6]"; fi
fv.views.hideCursor w1l

kt_test_start "setState is virtual-aware: an override sees each bit change of a select (FV's order) and keeps the behaviour with inherited"
class TSeen : TWindow
    public
        override proc SetState
end
TSeen.SetState() { SEEN+="$this:$1=$2,"; inherited SetState "$@"; }
build TSeen
TSeen.new w3 10 2 30 8 'Seen' 3
fv.views.insert desk w3
SEEN=''
fv.views.select w1
want="w3:$FV_SF_FOCUSED=0,w3:$FV_SF_SELECTED=0,w3:$FV_SF_ACTIVE=0,"
bits w3 w1; b=$REPLY
if [[ $SEEN == "$want" && $b == 'w3:--- w1:sfa' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "seen [$SEEN] want [$want] bits [$b] diff [$FVW_DIFF]"; fi

kt_test_start "hide the focused window: the focus moves on (FV ResetCurrent), == a full repaint; show + sfShadow off / on redraw right"
fv.views.hide w1
r1="${desk_data[Current]}"; bits w3; r1+=" $REPLY"
fv.views.show w1
fvw_full app; f1=$?
fv.views.setState w3 "$FV_SF_SHADOW" 0; fvw_full app; f2=$?
fv.views.setState w3 "$FV_SF_SHADOW" 1; fvw_full app; f3=$?
if [[ $r1 == 'w3 w3:sfa' && $f1$f2$f3 == 000 ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] full $f1$f2$f3 [$FVW_DIFF]"; fi

kt_test_start "delete of the focused window: the focus moves on, cmReleasedFocus reaches the owner first, == a full repaint"
fv.views.select w3
lsn ld desk
HEARD=''
fv.views.delete desk w3
r1="${desk_data[Current]}:$HEARD"
bits w3; r1+=" $REPLY"
ld.delete
if [[ $r1 == 'w1:desk<cmReleasedFocus:w3;desk<cmReceivedFocus:w1; w3:---' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r1] diff [$FVW_DIFF]"; fi
w3.delete

kt_test_start "insert into an active group passes sfActive (FV InsertBefore); into an inactive one not"
TView.new extra 5 5 6 6; TView.new extra2 5 5 6 6
fv.views.insert w1 extra; fv.views.insert w2 extra2
bits extra extra2; b=$REPLY
extra.delete; extra2.delete
if [[ $b == 'extra:--a extra2:---' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$b] diff [$FVW_DIFF]"; fi

kt_test_start "select of an ofTopSelect window already in front while another view is Current makes it Current (FV's MakeFirst would not: a deviation)"
TView.new nv 0 23 5 24; nv_data[Options]=$FV_OF_SELECTABLE
fv.views.insertBefore desk nv bg
fv.views.select nv; r1=${desk_data[Current]}
fv.views.select w1; r2="${desk_data[Current]}:${desk_views[-1]}"
fv.views.delete desk nv; nv.delete
if [[ $r1 == nv && $r2 == 'w1:w1' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] diff [$FVW_DIFF]"; fi

kt_test_start "select of a hidden or disabled window in front does not make it Current (FV leaves it unselected)"
TView.new nv2 0 23 5 24; nv2_data[Options]=$FV_OF_SELECTABLE
fv.views.insertBefore desk nv2 bg
fv.views.select nv2
w1_data[State]=$(( w1_data[State] & ~FV_SF_VISIBLE ))
fv.views.select w1; r1="${desk_data[Current]}"
w1_data[State]=$(( (w1_data[State] | FV_SF_VISIBLE) | FV_SF_DISABLED ))
fv.views.select w1; r2="${desk_data[Current]}"
w1_data[State]=$(( w1_data[State] & ~FV_SF_DISABLED ))
fv.views.select w1; r3="${desk_data[Current]}"
fv.views.delete desk nv2; nv2.delete
if [[ $r1 == nv2 && $r2 == nv2 && $r3 == w1 ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "hidden [$r1] disabled [$r2] visible [$r3] diff [$FVW_DIFF]"; fi

kt_test_start "refusals (rc 2): select / focus / setState / setCursor / resetCursor / show- / hideCursor with bad arguments"
r=''
fv.views.select || r+="$?,"; fv.views.select nosuch || r+="$?,"
fv.views.focus || r+="$?,"; fv.views.setState w1 x 1 || r+="$?,"; fv.views.setState w1 1 2 || r+="$?,"
fv.views.setCursor w1l 1 || r+="$?,"; fv.views.setCursor w1l a 1 || r+="$?,"; fv.views.resetCursor || r+="$?,"
fv.views.showCursor || r+="$?,"; fv.views.hideCursor nosuch || r+="$?"
if [[ $r == '2,2,2,2,2,2,2,2,2,2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

# --- stage 2c-p: a focus broadcast that no handler would see is not delivered ---
kt_test_start "quiet broadcasts (2c-p): a window switch among built-in views and plain leaves costs no dispatch, the desktop's Phase is set as the dispatch sets it, the windows' is not"
fv.views.select w1
desk_data[Phase]=phX w1_data[Phase]=phY w2_data[Phase]=phY
fvw_count_on; FVW_CALLS=0
fv.views._quiet desk cmReleasedFocus; q1=$?
fv.views._quiet w1 cmReleasedFocus; q2=$?
fv.views._quiet desk cmSelectWindowNum; q3=$?
n=$FVW_CALLS
fvw_count_off
r="$q1 $q2 $q3 $n ${desk_data[Phase]} ${w1_data[Phase]} ${w2_data[Phase]}"
if [[ $r == '0 0 1 0 phFocused phY phY' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "quiet broadcasts: a listening leaf (EventMask + evBroadcast, an override) makes its window and the desktop not quiet; it hears every focus broadcast as before"
class TQListen : TView
    public
        override proc HandleEvent
end
TQListen.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then QHEARD+="$this<$FV_EV_COMMAND:$FV_EV_INFO;"; fi; }
build TQListen
TQListen.new ql 30 1 35 2
ql_data[EventMask]=$(( ql_data[EventMask] | FV_EM_BROADCAST ))
fv.views.insert w1 ql
QHEARD=''
fv.views._quiet w1 cmReleasedFocus; q1=$?
fv.views._quiet desk cmReleasedFocus; q2=$?
fv.views._quiet w2 cmReleasedFocus; q3=$?
fv.views.select w2
fv.views.select w1
want='ql<cmReleasedFocus:w1;ql<cmReleasedFocus:w1l;ql<cmReceivedFocus:w2;ql<cmReleasedFocus:w2;ql<cmReceivedFocus:w1;ql<cmReceivedFocus:w1l;'
if [[ "$q1 $q2 $q3" == '1 1 0' && $QHEARD == "$want" ]] && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "quiet [$q1 $q2 $q3] heard [$QHEARD] want [$want] diff [$FVW_DIFF]"; fi

kt_test_start "quiet broadcasts: a listener with an EventMask without evBroadcast, a destroyed one, and a hidden one in the list follow the dispatch's rules"
ql_data[EventMask]=$(( ql_data[EventMask] & ~FV_EM_BROADCAST ))
fv.views._quiet w1 cmReleasedFocus; q1=$?
ql_data[EventMask]=$(( ql_data[EventMask] | FV_EM_BROADCAST ))
fv.views.hide ql
fv.views._quiet w1 cmReleasedFocus; q2=$?
fv.views.show ql
fv.views.delete w1 ql; ql.delete
fv.views._quiet w1 cmReleasedFocus; q3=$?
if [[ "$q1 $q2 $q3" == '0 1 0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$q1 $q2 $q3] (masked quiet, hidden still reached, removed quiet)"; fi

# (critic round: the walk into quiet subgroups must leave no Phase behind when a
# later subview makes the answer "not quiet" and a listener in front handles the
# broadcast before the dispatch reaches those groups)
kt_test_start "quiet broadcasts: a walk that ends not quiet leaves the Phase of the quiet subgroups it looked into untouched (message and dispatch)"
class TQClear : TView
    public
        override proc HandleEvent
end
TQClear.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then QGOT+="$this;"; fv.views.clearEvent "$this"; fi; }
build TQClear
TGroup.new qr 0 0 40 12; TGroup.new qg2 0 0 10 5; TGroup.new qg3 0 0 5 3; TGroup.new qg4 0 0 2 2
fv.views.insert qg3 qg4; fv.views.insert qg2 qg3; fv.views.insert qr qg2
TQClear.new qlc 20 1 25 2
qlc_data[EventMask]=$(( qlc_data[EventMask] | FV_EM_BROADCAST ))
fv.views.insert qr qlc
qr_data[Phase]=phPostProcess qg2_data[Phase]=phPostProcess qg3_data[Phase]=phPostProcess qg4_data[Phase]=phPostProcess
QGOT=''
fv.views.message qr evBroadcast cmSomething ''; rc=$?
r1="$rc $RESULT $QGOT ${qr_data[Phase]} ${qg2_data[Phase]} ${qg3_data[Phase]} ${qg4_data[Phase]}"
qr_data[Phase]=phPostProcess qg2_data[Phase]=phPostProcess qg3_data[Phase]=phPostProcess
TGroup.new qtop 0 0 40 12; fv.views.insert qtop qr
fv.drivers.clearEvent; FV_EV_WHAT=evBroadcast FV_EV_COMMAND=cmOther
QGOT=''
fv.views._virt qtop HandleEvent
r2="$FV_EV_WHAT $QGOT ${qtop_data[Phase]-} ${qr_data[Phase]} ${qg2_data[Phase]} ${qg3_data[Phase]}"
fv.drivers.clearEvent
qtop.delete   # (a group's delete takes its subviews with it)
if [[ $r1 == '0 qlc qlc; phFocused phPostProcess phPostProcess phPostProcess' && $r2 == 'evNothing qlc; phFocused phFocused phPostProcess phPostProcess' ]]; then kt_test_pass "ok"
else kt_test_fail "message [$r1] dispatch [$r2]"; fi

fvw_untscene
kt_test_log "008_Focus.sh completed"
