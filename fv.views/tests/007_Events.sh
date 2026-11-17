#!/usr/bin/env bash
# 007_Events.sh - the event dispatch of stage 2c-3 (design §1.8; FV
# TGroup.HandleEvent, TView.HandleEvent, Message):
#   * focused events (evKeyDown, evCommand): phPreProcess to the views with
#     ofPreProcess front to back, phFocused to Current, phPostProcess to the
#     views with ofPostProcess; the group's Phase as each handler sees it;
#   * positional events: the front-most visible view under the point only
#     (hidden ones skipped, a disabled front one swallows it as in FV);
#   * broadcasts: every subview front to back;
#   * FV's EventMask defaults: a view whose mask lacks the event is skipped
#     WITHOUT A CALL (dispatch counter), TView's default handler is not even
#     called for a non-mouse event; disabled views skipped for positional /
#     focused events, not for broadcasts;
#   * the loop stops at evNothing; a view removed or destroyed by an earlier
#     handler is skipped; an unknown event name reaches nobody;
#   * TView's click to focus (D8): a mouse-down selects a selectable view and
#     is consumed, ofFirstClick lets it through;
#   * a nested group's Current gets a focused event (the focus chain);
#   * message: RESULT = the handler (rc 0), rc 1 when unhandled or for a nil
#     receiver, the caller's whole event record restored, refusals rc 2;
#   * clearEvent; RESULT kept and the handler's rc ignored (set -e).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "007: events"

# TRec: a leaf that logs what reaches it ("name/Phase/what:key-or-command;")
# and clears the event when its name is in CLEAR
class TRec : TView
    public
        override proc HandleEvent
end
TRec.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evNothing ]; then LOG+="$this:consumed;"; return 0; fi
    local -n o=${Owner}_data
    LOG+="$this/${o[Phase]}/$FV_EV_WHAT:$FV_EV_KEY$FV_EV_COMMAND;"
    if [[ " $CLEAR " == *" $this "* ]]; then fv.views.clearEvent "$this"; fi
    if [[ -n ${KILL-} ]]; then local k=$KILL; KILL=''; "$k.delete"; fi
    if [[ -n ${DROP-} ]]; then local k=$DROP; DROP=''; fv.views.delete "$Owner" "$k"; fi
    false
}
build TRec
LOG='' CLEAR=''

ev() {   # WHAT KEY-OR-COMMAND [X Y] -> the event record
    fv.drivers.clearEvent
    FV_EV_WHAT=$1
    case $1 in
        evKeyDown) FV_EV_KEY=$2 ;;
        evMouse*) FV_EV_MOUSE_X=$2 FV_EV_MOUSE_Y=$3 ;;
        *) FV_EV_COMMAND=$2 ;;
    esac
}
send() { LOG=''; ev "$@"; fv.views._virt g HandleEvent; }

# g (a root group) > a (back), b, c (front): TRec leaves side by side
mk() {
    local v
    for v in g a b c; do if fv.views.isView "$v"; then "$v.delete"; fi; done
    TGroup.new g 0 0 30 10
    g_data[State]=$(( g_data[State] | FV_SF_SELECTED ))   # (a root as fv.app makes it: selected)
    TRec.new a 0 0 10 10; TRec.new b 10 0 20 10; TRec.new c 20 0 30 10
    for v in a b c; do local -n d=${v}_data; d[Options]=$FV_OF_SELECTABLE; fv.views.insert g "$v"; done
}
mk

kt_test_start "a focused key: Current only (c, the front-most selectable), Phase phFocused"
send evKeyDown kbA
if [[ $LOG == 'c/phFocused/evKeyDown:kbA;' && $FV_EV_WHAT == evKeyDown ]]; then kt_test_pass "ok"; else kt_test_fail "log [$LOG]"; fi

kt_test_start "the phases: preprocess (front to back: c, a), Current (b), postprocess (a); each sees its Phase"
fv.views.select b
a_data[Options]=$(( FV_OF_SELECTABLE | FV_OF_PREPROCESS | FV_OF_POSTPROCESS )) c_data[Options]=$(( FV_OF_SELECTABLE | FV_OF_PREPROCESS ))
send evCommand cmFoo
want='c/phPreProcess/evCommand:cmFoo;a/phPreProcess/evCommand:cmFoo;b/phFocused/evCommand:cmFoo;a/phPostProcess/evCommand:cmFoo;'
if [[ $LOG == "$want" && ${g_data[Phase]} == phPostProcess ]]; then kt_test_pass "ok"; else kt_test_fail "log [$LOG] phase ${g_data[Phase]}"; fi

kt_test_start "the loop stops at evNothing: a preprocess handler that clears it ends the dispatch (FV_EV_INFO = the handler)"
CLEAR='c'
send evKeyDown kbB
CLEAR=''
if [[ $LOG == 'c/phPreProcess/evKeyDown:kbB;' && $FV_EV_WHAT == evNothing && $FV_EV_INFO == c ]]; then kt_test_pass "ok"; else kt_test_fail "log [$LOG] what $FV_EV_WHAT info $FV_EV_INFO"; fi

kt_test_start "the EventMask: a view whose mask lacks evCommand is skipped without a call (dispatches: 2 instead of 4 + 2)"
a_data[EventMask]=$(( FV_EM_KEYDOWN ))
fvw_count_on; FVW_CALLS=0
send evCommand cmBar
n=$FVW_CALLS; fvw_count_off
a_data[EventMask]=$(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND ))
if [[ $LOG == 'c/phPreProcess/evCommand:cmBar;b/phFocused/evCommand:cmBar;' && $n == 4 ]]; then kt_test_pass "ok ($n dispatches: 2 handlers with inherited)"; else kt_test_fail "log [$LOG] dispatches $n"; fi
a_data[Options]=$FV_OF_SELECTABLE c_data[Options]=$FV_OF_SELECTABLE

kt_test_start "a disabled Current gets no key; a disabled view still gets a broadcast"
b_data[State]=$(( b_data[State] | FV_SF_DISABLED ))
b_data[EventMask]=$(( b_data[EventMask] | FV_EM_BROADCAST ))
send evKeyDown kbC; l1=$LOG
send evBroadcast cmHello; l2=$LOG
b_data[State]=$(( b_data[State] & ~FV_SF_DISABLED )) b_data[EventMask]=$(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND ))
if [[ -z $l1 && $l2 == 'b/phFocused/evBroadcast:cmHello;' ]]; then kt_test_pass "ok"; else kt_test_fail "key [$l1] broadcast [$l2]"; fi

kt_test_start "a broadcast reaches every subview front to back (those with evBroadcast in their mask); TView's mask: no call"
for v in a b c; do local_d=${v}_data; declare -n d=$local_d; d[EventMask]=$(( d[EventMask] | FV_EM_BROADCAST )); unset -n d; done
send evBroadcast cmAll; l1=$LOG
for v in a c; do declare -n d=${v}_data; d[EventMask]=$(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND )); unset -n d; done
fvw_count_on; FVW_CALLS=0
send evBroadcast cmAll
n=$FVW_CALLS; fvw_count_off
b_data[EventMask]=$(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND ))
if [[ $l1 == 'c/phFocused/evBroadcast:cmAll;b/phFocused/evBroadcast:cmAll;a/phFocused/evBroadcast:cmAll;' && $LOG == 'b/phFocused/evBroadcast:cmAll;' && $n == 2 ]]; then kt_test_pass "ok"
else kt_test_fail "all [$l1] one [$LOG] dispatches $n"; fi

kt_test_start "built-in views cost no dispatch: a broadcast into a group with a TFrame and plain TViews makes 0 dispatches"
TGroup.new h 0 0 10 10; TFrame.new hf 0 0 10 10; TView.new hv 1 1 2 2
fv.views.insert h hf; fv.views.insert h hv
fvw_count_on; FVW_CALLS=0
ev evBroadcast cmReceivedFocus; fv.views._virt h HandleEvent
ev evMouseDown 50 50; fv.views._virt h HandleEvent
n=$FVW_CALLS; fvw_count_off
h.delete
if [[ $n == 0 ]]; then kt_test_pass "0 dispatches"; else kt_test_fail "$n dispatches"; fi

kt_test_start "positional: the front-most visible view under the point only; nothing outside every view"
c_data[EventMask]=$(( c_data[EventMask] | FV_EM_MOUSEUP | FV_EM_MOUSEMOVE ))
send evMouseUp 25 3; l1=$LOG
send evMouseMove 25 3; l2=$LOG
send evMouseUp 15 3; l3=$LOG
send evMouseUp 40 3; l4=$LOG
if [[ $l1 == 'c/phFocused/evMouseUp:;' && $l2 == 'c/phFocused/evMouseMove:;' && -z $l3 && -z $l4 ]]; then kt_test_pass "ok (b's mask lacks evMouseUp: nobody)"
else kt_test_fail "c [$l1] [$l2] b [$l3] outside [$l4]"; fi

kt_test_start "positional over overlapping views: the front one; a hidden one is skipped; a disabled front one swallows it (FV)"
fv.views.locate a 0 0 30 10   # a, the back one, under everything
a_data[EventMask]=$(( a_data[EventMask] | FV_EM_MOUSEUP ))
send evMouseUp 25 3; l1=$LOG
fv.views.hide c
send evMouseUp 25 3; l2=$LOG
fv.views.show c
c_data[State]=$(( c_data[State] | FV_SF_DISABLED ))
send evMouseUp 25 3; l3=$LOG
c_data[State]=$(( c_data[State] & ~FV_SF_DISABLED ))
if [[ $l1 == 'c/phFocused/evMouseUp:;' && $l2 == 'a/phFocused/evMouseUp:;' && -z $l3 ]]; then kt_test_pass "ok"
else kt_test_fail "front [$l1] hidden front [$l2] disabled front [$l3]"; fi
mk

kt_test_start "click to focus (D8): a mouse-down on a selectable, unselected view selects it and is consumed (FV_EV_INFO = it)"
fv.views.select a
send evMouseDown 15 3
if [[ $LOG == 'b:consumed;' && ${g_data[Current]} == b && $FV_EV_WHAT == evNothing && $FV_EV_INFO == b ]]; then kt_test_pass "ok"
else kt_test_fail "log [$LOG] current ${g_data[Current]} what $FV_EV_WHAT info $FV_EV_INFO"; fi

kt_test_start "click to focus: on the selected view the mouse-down goes on to it; with ofFirstClick the first click selects and goes on"
send evMouseDown 15 3; l1=$LOG
c_data[Options]=$(( FV_OF_SELECTABLE | FV_OF_FIRSTCLICK ))
send evMouseDown 25 3; l2=$LOG
if [[ $l1 == 'b/phFocused/evMouseDown:;' && $l2 == 'c/phFocused/evMouseDown:;' && ${g_data[Current]} == c ]]; then kt_test_pass "ok"
else kt_test_fail "selected [$l1] firstclick [$l2] current ${g_data[Current]}"; fi
c_data[Options]=$FV_OF_SELECTABLE

kt_test_start "a mouse-down on an unselectable or disabled view selects nothing"
b_data[Options]=0
send evMouseDown 15 3; l1="$LOG|${g_data[Current]}"
b_data[Options]=$FV_OF_SELECTABLE b_data[State]=$(( b_data[State] | FV_SF_DISABLED ))
send evMouseDown 15 3; l2="$LOG|${g_data[Current]}"
b_data[State]=$(( b_data[State] & ~FV_SF_DISABLED ))
if [[ $l1 == 'b/phFocused/evMouseDown:;|c' && $l2 == '|c' ]]; then kt_test_pass "ok"; else kt_test_fail "unselectable [$l1] disabled [$l2]"; fi

kt_test_start "a view removed or destroyed by an earlier handler is skipped (the list as it was, each still checked)"
for v in a b c; do declare -n d=${v}_data; d[EventMask]=$(( d[EventMask] | FV_EM_BROADCAST )); unset -n d; done
DROP=b
send evBroadcast cmX; l1=$LOG
mk
for v in a b c; do declare -n d=${v}_data; d[EventMask]=$(( d[EventMask] | FV_EM_BROADCAST )); unset -n d; done
KILL=a
send evBroadcast cmY; l2=$LOG
if [[ $l1 == 'c/phFocused/evBroadcast:cmX;a/phFocused/evBroadcast:cmX;' && $l2 == 'c/phFocused/evBroadcast:cmY;b/phFocused/evBroadcast:cmY;' ]] && ! fv.views.isView a; then kt_test_pass "ok"
else kt_test_fail "removed [$l1] destroyed [$l2]"; fi
mk

kt_test_start "an unknown event name (no EventMask bit) reaches nobody, also as a broadcast-like 'rest' event"
send evMyThing x
if [[ -z $LOG && $FV_EV_WHAT == evMyThing ]]; then kt_test_pass "ok"; else kt_test_fail "log [$LOG]"; fi

kt_test_start "a nested group's Current gets a focused event (g > s > d)"
TGroup.new s 0 0 30 10; TRec.new d 0 0 5 5; d_data[Options]=$FV_OF_SELECTABLE
fv.views.insert s d; fv.views.insert g s
send evKeyDown kbD
if [[ $LOG == 'd/phFocused/evKeyDown:kbD;' && ${g_data[Current]} == s ]]; then kt_test_pass "ok"; else kt_test_fail "log [$LOG] current ${g_data[Current]}"; fi
mk

kt_test_start "RESULT is kept by the dispatch (HandleEvent is a procedure) and a handler's false rc does not stop set -e"
out=$( set -e; LOG=''; ev evKeyDown kbE; RESULT=keep; fv.views._virt g HandleEvent; printf '%s|%s' "$RESULT" "$LOG" )
if [[ $out == 'keep|c/phFocused/evKeyDown:kbE;' ]]; then kt_test_pass "ok"; else kt_test_fail "out [$out]"; fi

kt_test_start "message: RESULT = the handler that cleared it (rc 0); unhandled: rc 1, RESULT ''; nil receiver rc 1"
CLEAR='b' LOG=''
b_data[EventMask]=$(( b_data[EventMask] | FV_EM_BROADCAST ))
fv.views.message g evBroadcast cmPing g; r1="$?|$RESULT|$LOG"
CLEAR=''
LOG=''; fv.views.message g evBroadcast cmPing g; r2="$?|$RESULT|$LOG"
LOG=''; fv.views.message '' evBroadcast cmPing; r3="$?|$RESULT|$LOG"
b_data[EventMask]=$(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND ))
if [[ $r1 == '0|b|b/phFocused/evBroadcast:cmPing;' && $r2 == '1||b/phFocused/evBroadcast:cmPing;' && $r3 == '1||' ]]; then kt_test_pass "ok"
else kt_test_fail "handled [$r1] unhandled [$r2] nil [$r3]"; fi

kt_test_start "message: the caller's whole event record is put back (FV builds a local Event)"
FV_EV_WHAT=evMouseDown FV_EV_KEY=k1 FV_EV_CHAR=c1 FV_EV_COMMAND=cm1 FV_EV_ID=i1 FV_EV_INFO=n1 FV_EV_MOUSE_X=7 FV_EV_MOUSE_Y=8
FV_EV_MOUSE_BUTTONS=1 FV_EV_MOUSE_MODS=2 FV_EV_MOUSE_DOUBLE=1 FV_EV_MOUSE_TRIPLE=0 FV_EV_WHEEL=2 FV_EV_EOF=0
before="$FV_EV_WHAT|$FV_EV_KEY|$FV_EV_CHAR|$FV_EV_COMMAND|$FV_EV_ID|$FV_EV_INFO|$FV_EV_MOUSE_X|$FV_EV_MOUSE_Y|$FV_EV_MOUSE_BUTTONS|$FV_EV_MOUSE_MODS|$FV_EV_MOUSE_DOUBLE|$FV_EV_MOUSE_TRIPLE|$FV_EV_WHEEL|$FV_EV_EOF"
CLEAR='c'
LOG=''; fv.views.message g evCommand cmZap x
CLEAR=''
after="$FV_EV_WHAT|$FV_EV_KEY|$FV_EV_CHAR|$FV_EV_COMMAND|$FV_EV_ID|$FV_EV_INFO|$FV_EV_MOUSE_X|$FV_EV_MOUSE_Y|$FV_EV_MOUSE_BUTTONS|$FV_EV_MOUSE_MODS|$FV_EV_MOUSE_DOUBLE|$FV_EV_MOUSE_TRIPLE|$FV_EV_WHEEL|$FV_EV_EOF"
if [[ $after == "$before" && $LOG == 'c/phFocused/evCommand:cmZap;' && $RESULT == c ]]; then kt_test_pass "ok"; else kt_test_fail "before [$before] after [$after] log [$LOG]"; fi

kt_test_start "refusals (rc 2, RESULT ''): message / clearEvent argument counts, a bad WHAT, not a view"
r=''
RESULT=x; fv.views.message g evBroadcast || r+="$?[$RESULT],"
fv.views.message g 'ev Bad' cmX || r+="$?,"
fv.views.message nosuch evBroadcast cmX || r+="$?,"
fv.views.clearEvent || r+="$?,"
fv.views.clearEvent a b || r+="$?"
if [[ $r == '2[],2,2,2,2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

g.delete
kt_test_log "007_Events.sh completed"
