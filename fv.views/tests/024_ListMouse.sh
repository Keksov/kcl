#!/usr/bin/env bash
# 024_ListMouse.sh - the mouse on lists and their bars (P3 stage 3b; design P3
# §3.3; FV views.inc TListViewer.HandleEvent, TScrollBar.HandleEvent):
#   * the wheel on the list (TopItem by 1, a double wheel event by 4; at the
#     top nothing is drawn) and on its bar (the list follows the bar);
#   * a click focuses the item under the mouse (past the last item: the
#     last; on an inactive window: the window first, then the item);
#   * a double click selects it (SelectItem: cmListItemSelected, Marks); a
#     double click's press is not tracked (FPC trunk), its drag left unread;
#   * a drag moves the focus with the mouse (moves coalesced), past the
#     bottom edge every 4th evMouseAuto moves it one item (FV
#     MouseAutosToSkip); a lost release ended by a key (the key put back); a
#     loop that returned early (its bar destroyed) leaves the next one alone;
#   * the bar's arrows, page parts and indicator move the list (the bar's
#     broadcast reaches the list: it did not move the bar itself);
#   * multi-column: a click picks the column's item;
#   * auto-repeat end to end through fv.drivers (a held press on the bar's
#     arrow read from a file, the clock driven by __FV_DR_NOW).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "024: lists and bars under the mouse"

class TLis : TView
    public
        override proc HandleEvent
end
TLis.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then LOG+="$FV_EV_COMMAND:$FV_EV_INFO;"; fi; }
build TLis
LOG=''
st() { REPLY="${w2l_data[Focused]} ${w2l_data[TopItem]} ${w2__fvsb1_data[Value]}"; }
# ev WHAT X Y [WHEEL [DOUBLE]] SPECS... — one mouse event at X Y delivered to
# the application, SPECS read by the tracking loops after it; REPLY = st
ev() {
    local w=$1 x=$2 y=$3 wh=${4:-0} d=${5:-0}
    shift 5
    fvw_events "$@"
    fv.drivers.clearEvent
    FV_EV_WHAT=$w FV_EV_MOUSE_X=$x FV_EV_MOUSE_Y=$y FV_EV_WHEEL=$wh FV_EV_MOUSE_DOUBLE=$d FV_EV_MOUSE_BUTTONS=1
    fv.views._virt app HandleEvent
    st
    fvw_noevents
}

fvw_lscene 80 24
TLis.new lis 0 0 1 1; lis_data[EventMask]=$(( 0xFFFF )); fv.views.insert w2 lis
fv.views.drawView app

kt_test_start "the wheel on the list: TopItem down / up by 1, a double wheel event by 4; the focus stays; the bar follows; at the top: nothing drawn"
r=''
ev evMouseWheel 50 5 2 0; r+="$REPLY,"
ev evMouseWheel 50 5 2 0; r+="$REPLY,"
ev evMouseWheel 50 5 1 0; r+="$REPLY,"
ev evMouseWheel 50 5 2 1; r+="$REPLY,"
ev evMouseWheel 50 5 1 1; r+="$REPLY,"
ev evMouseWheel 50 5 1 0; r+="$REPLY,"
fvw_writes_on; FVW_WRITES=0
ev evMouseWheel 50 5 1 0; r+="$REPLY $FVW_WRITES"
fvw_writes_off
if [[ $r == '0 1 1,0 2 2,0 1 1,0 5 5,0 1 1,0 0 0,0 0 0 0' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi

kt_test_start "the wheel on the bar: the bar moves by ArStep, its cmScrollBarChanged scrolls the list (the list did not move it); Clicked selects the list"
r=''
ev evMouseWheel 79 10 2 0; r+="$REPLY,"
ev evMouseWheel 79 10 2 0; r+="$REPLY,"
ev evMouseWheel 79 10 1 0; r+="$REPLY"
if [[ $r == '0 1 1,0 2 2,0 1 1' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi

kt_test_start "a click focuses the item under the mouse (row + TopItem); past the last item: the last one"
ev evMouseWheel 50 5 1 0
r=''
ev evMouseDown 50 6 0 0 'up 50 6'; r+="$REPLY,"
ev evMouseDown 41 1 0 0 'up 41 1'; r+="$REPLY,"
fv.views.listSetRange w2l 10
ev evMouseDown 60 15 0 0 'up 60 15'; r+="$REPLY,"
fv.views.listSetRange w2l 100
if [[ $r == '5 0 0,0 0 0,9 0 0,' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi

kt_test_start "a click on the list of an inactive window: the window comes to the front, the focus stays (FV: TWindow has no ofFirstClick, the first click only selects it)"
fv.views.select w1
ev evMouseDown 50 4 0 0 'up 50 4'
if [[ $REPLY == '9 0 0' && ${desk_data[Current]} == w2 ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$REPLY] current ${desk_data[Current]} $FVW_DIFF"; fi

kt_test_start "a double click selects the item: cmListItemSelected (INFO the list), its Marks entry toggled; a single click does not"
declare -A MK=()
w2l_data[Marks]=MK
LOG=''
ev evMouseDown 50 8 0 0 'up 50 8'; r="$REPLY ${!MK[*]} [$LOG]"
ev evMouseDown 50 8 0 1 'up 50 8'; r+=",$REPLY ${!MK[*]} [$LOG]"
w2l_data[Marks]=''
if [[ $r == '7 0 0  [],7 0 0 7 [cmListItemSelected:w2l;]' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi

kt_test_start "a drag: the focus follows the mouse over the rows (the press and the waiting moves, coalesced: two focus changes, two rows each), the release ends it"
fvw_writes_on; FVW_WRITES=0
ev evMouseDown 50 2 0 0 'move 50 4' 'move 50 7' 'move 50 10' 'up 50 10'
fvw_writes_off
r="$REPLY $FVW_WRITES"
if [[ $r == '9 0 0 4' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] (want 9 0 0 4) $FVW_DIFF"; fi

kt_test_start "a drag past the bottom edge: every 4th evMouseAuto moves the focus one item (FV MouseAutosToSkip), the list scrolls; autos inside the list do not count"
ev evMouseDown 50 21 0 0 'move 50 23' 'nothing' 'auto 50 23' 'auto 50 23' 'auto 50 23' 'auto 50 23' 'auto 50 23' 'auto 50 23' 'auto 50 23' 'auto 50 23' 'auto 50 23' 'up 50 23'
a=$REPLY
ev evMouseDown 50 21 0 0 'auto 50 21' 'auto 50 21' 'auto 50 21' 'auto 50 21' 'up 50 21'
b=$REPLY
ev evMouseDown 50 1 0 0 'move 50 0' 'nothing' 'auto 50 0' 'auto 50 0' 'auto 50 0' 'auto 50 0' 'up 50 0'
c=$REPLY
if [[ $a == '22 2 2' && $b == '22 2 2' && $c == '1 1 1' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c] $FVW_DIFF"; fi

kt_test_start "a lost release: a key ends the drag (no auto runs on), the key is put back for the loop, the rest of the queue left"
fvw_events 'move 50 23' 'nothing' 'auto 50 23' 'key kbDown' 'auto 50 23' 'auto 50 23'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=50 FV_EV_MOUSE_Y=5 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent
a="${w2l_data[Focused]} $FV_EV_WHAT ${__FV_DR_PEND[0]-}:${__FV_DR_PEND[1]-} ${#FVW_EVQ[@]}"
fvw_noevents
if [[ $a == '5 evNothing evKeyDown:kbDown 2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a]"; fi

kt_test_start "a double click's press then a drag (FPC trunk: \`If NOT Event.Double Then Repeat\`): no tracking, the item under the press focused and selected at once, the move and the release left unread"
MK=()
w2l_data[Marks]=MK
fv.views.listSetTopItem w2l 0
ev evMouseDown 50 3 0 0 'up 50 3'
fvw_events 'move 50 7' 'up 50 7'
fv.drivers.clearEvent
FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=50 FV_EV_MOUSE_Y=3 FV_EV_MOUSE_BUTTONS=1 FV_EV_MOUSE_DOUBLE=1
fv.views._virt app HandleEvent
a="${w2l_data[Focused]} [${!MK[*]}] ${#FVW_EVQ[@]}"
fvw_noevents
w2l_data[Marks]=''
if [[ $a == '2 [2] 2' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] (want 2 [2] 2) $FVW_DIFF"; fi

kt_test_start "a tracking loop that returns early (its bar destroyed by a listener after the drain met the release) leaves nothing behind: the next drag on the list tracks to its release"
class TKill : TView
    public
        override proc HandleEvent
end
TKill.HandleEvent() {
    if [ "$FV_EV_WHAT" = evBroadcast ] && [ "$FV_EV_COMMAND" = cmScrollBarChanged ] && [ "$FV_EV_INFO" = "$KILLB" ] && fv.views.isView "$FV_EV_INFO"; then
        local -n __k_b=${FV_EV_INFO}_data
        if (( __k_b[Value] > 3 )); then "$FV_EV_INFO.delete"; fi
    fi
}
build TKill
fvw_unlscene
fvw_lscene 80 24
TKill.new kill 0 0 1 1; kill_data[EventMask]=$(( 0xFFFF )); fv.views.insert w2 kill
fv.views.drawView app
KILLB=w2__fvsb1
# (the thumb on row 2: the move and the release both waiting, the drain
# reads the release; the value passes 3, the bar is destroyed in the loop)
ev evMouseDown 79 2 0 0 'move 79 15' 'up 79 15'
a="${__FV_VW_LIVE[w2__fvsb1]-gone}"
fvw_events 'move 50 7' 'up 50 7'
fv.drivers.clearEvent
FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=50 FV_EV_MOUSE_Y=3 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent
a+=" ${w2l_data[Focused]} ${w2l_data[TopItem]} ${#FVW_EVQ[@]}"
fvw_noevents
KILLB=''
if [[ $a == 'gone 6 0 0' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] (want gone 6 0 0) $FVW_DIFF"; fi
# (a fresh scene as the earlier tests left it: the focus on item 5)
fvw_unlscene
fvw_lscene 80 24
TLis.new lis 0 0 1 1; lis_data[EventMask]=$(( 0xFFFF )); fv.views.insert w2 lis
fv.views.listFocusItem w2l 5
fv.views.drawView app

kt_test_start "the bar's arrows / page part / indicator under the mouse scroll the list (its broadcast reaches the list), the focus stays"
ev evMouseWheel 50 5 1 1
r=''
ev evMouseDown 79 21 0 0 'up 79 21'; r+="$REPLY,"
ev evMouseDown 79 21 0 0 'auto 79 21' 'auto 79 21' 'up 79 21'; r+="$REPLY,"
ev evMouseDown 79 15 0 0 'up 79 15'; r+="$REPLY,"
ev evMouseDown 79 1 0 0 'up 79 1'; r+="$REPLY,"
# (the indicator at row 1 + GetPos: drag it to the middle of the bar)
fv.views.listSetTopItem w2l 0
ev evMouseDown 79 2 0 0 'move 79 11' 'up 79 11'; r+="$REPLY"
if [[ $r == '5 1 1,5 4 4,5 24 24,5 23 23,5 38 38' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi

kt_test_start "the elision: the built-in list and bar cost no dispatch of their own (the application's TTApp override + inherited: 2 per event)"
fvw_count_on; FVW_CALLS=0
ev evMouseDown 50 6 0 0 'up 50 6'
a=$FVW_CALLS; FVW_CALLS=0
ev evMouseWheel 50 6 2 0
b=$FVW_CALLS; FVW_CALLS=0
ev evMouseDown 79 21 0 0 'up 79 21'
c=$FVW_CALLS
fvw_count_off
# (the bar's Clicked / Changed broadcasts reach the listener leaf lis in w2:
# one user dispatch each)
if [[ $a == 2 && $b == 3 && $c == 5 ]]; then kt_test_pass "ok"; else kt_test_fail "click $a wheel $b bar $c (want 2 3 5)"; fi
fvw_unlscene

kt_test_start "multi-column: a click picks row + SizeY * (X div ColWidth) + TopItem"
fvw_screen 80 24
TGroup.new mc 0 0 80 24; fvw_expose mc
TView.new mbg 0 0 80 24; fv.views.insert mc mbg
TWindow.new mw 0 0 33 8 M 1
fv.views.standardScrollBar mw "$FV_SB_VERTICAL"
TListViewer.new ml 1 1 31 6 3 '' mw__fvsb1
fv.views.insert mw ml
fvw_items ML 50
ml_data[List]=ML
fv.views.listSetRange ml 50
fv.views.insert mc mw
fvw_root mc
fv.views.drawView mc
mclick() { fvw_events "up $1 $2"; fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$1 FV_EV_MOUSE_Y=$2 FV_EV_MOUSE_BUTTONS=1; fv.views._virt mc HandleEvent; fvw_noevents; REPLY=${ml_data[Focused]}; }
r=''
mclick 25 3; r+="$REPLY,"; mclick 14 1; r+="$REPLY,"; mclick 2 5; r+="$REPLY"
if [[ $r == '12,5,4' ]] && fvw_full mc; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi
mc.delete

kt_test_start "auto-repeat end to end (fv.drivers, the clock __FV_DR_NOW): a press held on the bar's down arrow steps at once, again at 0.44 s and 0.49 s, the release ends it; the list follows"
fvw_lscene 80 24
fv.views.drawView app
eval "fvw24_orig_$(declare -f fv.keyboard.getKeyEvent)"
IDLE=0
fv.keyboard.getKeyEvent() { if (( IDLE )); then FV_KEY_EOF=0 FV_KEY=''; return 1; fi; fvw24_orig_fv.keyboard.getKeyEvent "$@"; }
STEPS=()
gedrv() {
    local s=${STEPS[0]-} rc=0
    if [[ -z $s ]]; then FV_EV_WHAT=evNothing; return 1; fi
    STEPS=("${STEPS[@]:1}")
    __FV_DR_NOW=${s#*@}
    if [[ $s == i@* ]]; then IDLE=1; else IDLE=0; fi
    fv.drivers.getEvent 0 || rc=$?
    IDLE=0
    DRV+="${FV_EV_WHAT#ev} "
    return "$rc"
}
printf '\033[<0;80;22M\033[<0;80;22m' > "$FVW_TMP/m24.bin"
exec {M24}<"$FVW_TMP/m24.bin"
FV_KEY_FD=$M24
fv.keyboard.flush; fv.drivers.doneEvents
DRV=''
STEPS=(r@100.0 i@100.2 i@100.44 i@100.49 i@100.5 r@100.51)
__FV_VW_GETEVENT=gedrv
gedrv
fv.views._virt app HandleEvent
st
a="$REPLY|$DRV"
__FV_VW_GETEVENT=fv.drivers.getEvent __FV_DR_NOW='' __FV_VW_EOF=0
exec {M24}<&-
src=$(declare -f fvw24_orig_fv.keyboard.getKeyEvent); eval "${src#fvw24_orig_}"
if [[ $a == '0 3 3|MouseDown Nothing MouseAuto MouseAuto Nothing MouseUp ' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] $FVW_DIFF"; fi
fvw_unlscene

kt_test_log "024_ListMouse.sh completed"
