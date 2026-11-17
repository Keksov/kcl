#!/usr/bin/env bash
# 017_Drag.sh - dragging (P2 stage 2d; FV TView.DragView, TWindow cmResize,
# TFrame's drag by the top row and the grow corner), in the events scene
# (app > desk > w1, w2 in front: TWindows with a TTLeaf each):
#   * the keyboard drag through cmResize: the arrows move, Shift + arrows
#     grow, Ctrl+Left / Ctrl+Right by 8 (Ctrl+Shift grows by 8; Ctrl+Up does
#     nothing, as FV), Home / End / PgUp / PgDn to the limits' edges (Shift +
#     Home is Home), Enter keeps, Esc puts the start bounds back; a grow-only
#     window (wfGrow) ignores the plain arrows;
#   * the limits: one column / row stays inside the owner (FV MoveGrow),
#     dmLimitLoY (the default DragMode) and dmLimitAll, the SizeLimits
#     minimum (MinWinSize 16 x 6) and maximum (the owner's size);
#   * sfDragging while dragging: the frame redrawn border-only (3 writes on
#     the way in, 3 on the way out), single line; cleared after; == a full
#     repaint after every drag;
#   * the mouse drag by the frame's top row (move) and grow corner (grow):
#     the offset of the mouse-down kept, a step per move, the last at the
#     mouse-up; motion coalescing (queued moves read with the event source's
#     timeout 0: the last one wins; a key among them dropped; the mouse-up
#     kept for the end);
#   * the end of input: a keyboard drag ends as Esc, a mouse drag where it is
#     (latched); a cmResizeApp from the event source ends a drag at its
#     bounds clamped into the owner's new extent, no undo (the events after
#     it stay unread);
#   * the event record put back (cmResize, a mouse-down, a direct call),
#     RESULT kept; the owner-process rule inside $( ) (rc 2, nothing read);
#     dragView's refusals;
#   * the dispatch and write counts of one keyboard move step, one mouse move
#     step and a zoom (logged, with limits).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "017: dragging"

fvw_tscene
# (the leaves grow with their windows: a grown window's interior stays
# covered — an uncovered interior keeps the dragging colour after the drag's
# border-only redraw, the documented border-only deviation: invisible on
# blanks, but fvw_full compares symbols)
w1l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY )) w2l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
fv.views.drawView app

send() {   # WHAT COMMAND [INFO] -> to app
    fv.drivers.clearEvent
    FV_EV_WHAT=$1 FV_EV_COMMAND=$2 FV_EV_INFO=${3-}
    fv.views._virt app HandleEvent
}
mdown() {   # X Y -> a mouse-down to app
    fv.drivers.clearEvent
    FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$1 FV_EV_MOUSE_Y=$2 FV_EV_MOUSE_BUTTONS=1
    fv.views._virt app HandleEvent
}
bounds() { fv.views.getBounds "${1:-w2}"; REPLY=$RESULT; }
cap() { bounds; CAP+="$REPLY;"; }
reset() {
    fvw_noevents
    w2_data[DragMode]=$FV_DM_LIMITLOY w2_data[Flags]=15 w2_data[GrowMode]=$(( FV_GF_GROWALL | FV_GF_GROWREL ))
    fv.views.locate w2 30 5 70 22
}
dragging() { REPLY=$(( (w2_data[State] & FV_SF_DRAGGING) | (w2__fvframe_data[State] & FV_SF_DRAGGING) )); }

kt_test_start "keyboard (cmResize): arrows move a step each, Enter keeps; handled; the record put back (cmResize, no key); sfDragging cleared; == a full repaint"
fvw_events 'key kbRight' 'key kbRight' 'key kbDown' 'key kbLeft' 'key kbEnter'
send evCommand cmResize
r="$FV_EV_WHAT|$FV_EV_INFO|$FV_EV_COMMAND|$FV_EV_KEY|$FVW_EVN"
bounds; r+="|$REPLY"
dragging; r+="|$REPLY"
fvw_cells 31 6 1; r+="|$RESULT"
if [[ $r == 'evNothing|w2|cmResize||5|31 6 71 23|0|╔' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
reset

kt_test_start "keyboard: Shift + arrows grow, Ctrl+Shift+Left shrinks by 8, Ctrl+Left / Ctrl+Right move by 8, Ctrl+Up does nothing (FV)"
CAP=''
fvw_events 'key kbShiftRight' 'key kbShiftDown' 'run cap' 'key kbCtrlShiftLeft' 'run cap' 'key kbCtrlLeft' 'run cap' 'key kbCtrlUp' 'run cap' 'key kbCtrlRight' 'key kbEnter'
send evCommand cmResize
bounds
if [[ $CAP == '30 5 71 23;30 5 63 23;22 5 55 23;22 5 55 23;' && $REPLY == '30 5 63 23' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$CAP] [$REPLY] diff [$FVW_DIFF]"; fi
reset

kt_test_start "keyboard: Home / PgDn / End / PgUp to the limits' edges (Shift+Home is Home)"
CAP=''
fvw_events 'key kbHome' 'run cap' 'key kbPgDn' 'run cap' 'key kbEnd' 'run cap' 'key kbPgUp' 'run cap' 'key kbShiftHome' 'run cap' 'key kbEnter'
send evCommand cmResize
if [[ $CAP == '0 5 40 22;0 7 40 24;40 7 80 24;40 0 80 17;0 0 40 17;' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$CAP] diff [$FVW_DIFF]"; fi
reset

kt_test_start "keyboard limits (FV MoveGrow): a column stays inside left (-39) and right (79), dmLimitLoY stops at the top, a row stays inside below (23)"
CAP=''
q=('key kbHome'); for i in 1 2 3 4 5 6; do q+=('key kbCtrlLeft'); done; q+=('run cap' 'key kbEnd')
for i in 1 2 3 4 5 6; do q+=('key kbCtrlRight'); done; q+=('run cap')
for i in 1 2 3 4 5 6; do q+=('key kbUp'); done; q+=('run cap' 'key kbPgDn')
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do q+=('key kbDown'); done; q+=('run cap' 'key kbEsc')
fvw_events "${q[@]}"
send evCommand cmResize
bounds
if [[ $CAP == '-39 5 1 22;79 5 119 22;79 0 119 17;79 23 119 40;' && $REPLY == '30 5 70 22' ]] && fvw_full app; then kt_test_pass "ok (Esc: back)"
else kt_test_fail "[$CAP] [$REPLY] diff [$FVW_DIFF]"; fi
reset

kt_test_start "keyboard limits with dmLimitAll: the window stays wholly inside the owner"
w2_data[DragMode]=$FV_DM_LIMITALL
CAP=''
fvw_events 'key kbHome' 'key kbCtrlLeft' 'run cap' 'key kbEnd' 'key kbCtrlRight' 'run cap' 'key kbPgDn' 'key kbDown' 'run cap' 'key kbEnter'
send evCommand cmResize
if [[ $CAP == '0 5 40 22;40 5 80 22;40 7 80 24;' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$CAP] diff [$FVW_DIFF]"; fi
reset

kt_test_start "keyboard size limits: TWindow's minimum (MinWinSize 16 x 6) and maximum (the owner's 80 x 24)"
CAP=''
q=(); for (( i = 0; i < 30; i++ )); do q+=('key kbShiftLeft' 'key kbShiftUp'); done; q+=('run cap' 'key kbHome' 'key kbPgUp')
for (( i = 0; i < 70; i++ )); do q+=('key kbShiftRight' 'key kbShiftDown'); done; q+=('run cap' 'key kbEsc')
fvw_events "${q[@]}"
send evCommand cmResize
bounds
if [[ $CAP == '30 5 46 11;0 0 80 24;' && $REPLY == '30 5 70 22' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$CAP] [$REPLY] diff [$FVW_DIFF]"; fi
reset

kt_test_start "keyboard: Esc puts the start bounds back (also after growing); == a full repaint"
fvw_events 'key kbLeft' 'key kbShiftDown' 'key kbUp' 'key kbEsc'
send evCommand cmResize
bounds
if [[ $REPLY == '30 5 70 22' && $FVW_EVN == 4 ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$REPLY] reads $FVW_EVN diff [$FVW_DIFF]"; fi
reset

kt_test_start "a grow-only window (wfGrow): cmResize drags with dmDragGrow only, the plain arrows do nothing, Shift + arrows grow"
w2_data[Flags]=$(( FV_WF_GROW | FV_WF_CLOSE | FV_WF_ZOOM ))
fvw_events 'key kbRight' 'key kbShiftRight' 'key kbEnter'
send evCommand cmResize
bounds
if [[ $REPLY == '30 5 71 22' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$REPLY] diff [$FVW_DIFF]"; fi
reset

kt_test_start "sfDragging while dragging: the window and its frame have it, the frame single-lined; border-only redraws: 3 writes in, 3 out, no full frame draw; no dispatch"
CAP=''
seen() { dragging; local d=$REPLY; fvw_cells 30 5 1; CAP="$d:$RESULT:$FVW_WRITES:$FVW_CALLS"; }
fvw_events 'run seen' 'key kbEnter'
fvw_writes_on; fvw_count_on; FVW_WRITES=0 FVW_CALLS=0
send evCommand cmResize
w=$FVW_WRITES c=$FVW_CALLS
fvw_count_off; fvw_writes_off
# (cmResize: app's TTApp override + inherited, then w2's focused leaf sees it
# first (FV's focused phase) and passes it: 3 dispatches before the drag)
if [[ $CAP == "$(( FV_SF_DRAGGING ))":┌:3:3 && $w == 6 && $c == 3 ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "seen [$CAP] writes $w calls $c diff [$FVW_DIFF]"; fi
reset

kt_test_start "the end of input during a keyboard drag: as Esc (the start bounds back), latched, sfDragging cleared"
fvw_events 'key kbRight' 'key kbDown'
send evCommand cmResize
bounds; dragging
if [[ $FV_EV_WHAT == evNothing && "$(bounds; echo "$REPLY")" == '30 5 70 22' && $REPLY == 0 && $__FV_VW_EOF == 1 ]] && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "[$FV_EV_WHAT] dragging $REPLY eof $__FV_VW_EOF diff [$FVW_DIFF]"; fi
reset

shrink() { w1_data[GrowMode]=0; fv.views.changeBounds desk 0 0 50 15; }
unshrink() {
    fv.views.changeBounds desk 0 0 80 24
    w1_data[GrowMode]=$(( FV_GF_GROWALL | FV_GF_GROWREL ))
    fv.views.locate w1 2 1 40 20
}
kt_test_start "a cmResizeApp during a keyboard drag (the source resized the owner first): the drag ends clamped into the new extent (FV MoveGrow), no undo, the next events unread"
w2_data[GrowMode]=0
fvw_events 'key kbRight' 'run shrink' 'cmd cmResizeApp' 'key kbEsc'
send evCommand cmResize
bounds; r1="$REPLY|${#FVW_EVQ[@]}"; dragging; r1+="|$REPLY"
unshrink; fv.views.locate w2 30 5 70 22
w2_data[DragMode]=$FV_DM_LIMITALL
fvw_events 'key kbRight' 'run shrink' 'cmd cmResizeApp' 'key kbEsc'
send evCommand cmResize
bounds; r2="$REPLY|${#FVW_EVQ[@]}"
unshrink
if [[ $r1 == '31 5 71 20|1|0' && $r2 == '10 0 50 15|1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2]"; fi
reset
kt_test_start "after the resized drags: == a full repaint"
if fvw_full app; then kt_test_pass "ok"; else kt_test_fail "diff [$FVW_DIFF]"; fi

# ---- the mouse ---------------------------------------------------------------------
kt_test_start "mouse: a mouse-down on the top row drags the window (the offset kept), the last step at the mouse-up; handled by the frame; the record put back"
fvw_events 'move 45 7' 'up 46 8'
mdown 50 5
r="$FV_EV_WHAT|$FV_EV_INFO|$FV_EV_MOUSE_X|$FV_EV_MOUSE_Y"
bounds; r+="|$REPLY"; dragging; r+="|$REPLY"
if [[ $r == 'evNothing|w2__fvframe|50|5|26 8 66 25|0' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
reset

kt_test_start "motion coalescing: queued moves (read with timeout 0) collapse into the last one, a key among them dropped: 3 steps for 3 moves; a mouse-up met while draining ends the drag after the step"
fvw_wrap FVW_MG fv.views._moveGrow
tsrc() { TOS+="${1-}/"; fvw_getev "$@"; }
FVW_MG=0 TOS=''
fvw_events 'move 51 5' 'move 52 5' 'key kbA' 'move 53 5' 'nothing' 'up 53 5'
__FV_VW_GETEVENT=tsrc
mdown 50 5
bounds; r1="$FVW_MG|$REPLY|$FVW_EVN|$TOS"
reset
FVW_MG=0 TOS=''
fvw_events 'move 51 5' 'up 54 6'
__FV_VW_GETEVENT=tsrc
mdown 50 5
bounds; r2="$FVW_MG|$REPLY|$FVW_EVN"
fvw_unwrap fv.views._moveGrow
# (the first read waits (no timeout argument), the drain passes 0)
if [[ $r1 == '3|33 5 73 22|6|/0/0/0/0//' && $r2 == '3|34 6 74 23|2' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] diff [$FVW_DIFF]"; fi
reset

kt_test_start "mouse: the grow corner grows the window by the mouse (the offset kept)"
fvw_events 'move 60 15' 'up 60 15'
mdown 69 21
bounds
if [[ $REPLY == '30 5 61 16' && $FV_EV_WHAT == evNothing ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$REPLY] diff [$FVW_DIFF]"; fi
reset

kt_test_start "the end of input during a mouse drag: it ends where it is (FV's mouse drag has no undo), latched, sfDragging cleared"
fvw_events 'move 45 7'
mdown 50 5
bounds; r="$REPLY|$__FV_VW_EOF"; dragging; r+="|$REPLY"
if [[ $r == '25 7 65 24|1|0' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
reset

kt_test_start "a cmResizeApp during a mouse drag: ends clamped into the new extent; the mouse-up after it stays unread"
w2_data[GrowMode]=0
fvw_events 'move 45 7' 'run shrink' 'cmd cmResizeApp' 'up 0 0'
mdown 50 5
bounds; r="$REPLY|${#FVW_EVQ[@]}"
unshrink
if [[ $r == '25 7 65 22|1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
reset

# ---- the API -----------------------------------------------------------------------
kt_test_start "fv.views.dragView called directly: the keyboard drag with the given mode and limits; the whole event record and RESULT put back"
fv.drivers.clearEvent
FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF5 FV_EV_CHAR=x FV_EV_ID=7 FV_EV_INFO=i FV_EV_MOUSE_X=3 FV_EV_MOUSE_Y=4 FV_EV_MOUSE_MODS=1
rec() { REPLY="$FV_EV_WHAT|$FV_EV_KEY|$FV_EV_CHAR|$FV_EV_COMMAND|$FV_EV_ID|$FV_EV_INFO|$FV_EV_MOUSE_X|$FV_EV_MOUSE_Y|$FV_EV_MOUSE_BUTTONS|$FV_EV_MOUSE_MODS|$FV_EV_MOUSE_DOUBLE|$FV_EV_MOUSE_TRIPLE|$FV_EV_WHEEL|$FV_EV_EOF"; }
rec; before=$REPLY
fvw_events 'key kbLeft' 'key kbLeft' 'key kbEnter'
RESULT=keep
fv.views.dragView w2 "$(( FV_DM_DRAGMOVE | FV_DM_LIMITALL ))" 29 0 80 24 16 6 "$__FV_VW_HIGH" 24; rc=$? res=$RESULT
bounds
if [[ $rc == 0 && $res == keep && $REPLY == '29 5 69 22' && "$(rec; echo "$REPLY")" == "$before" ]]; then kt_test_pass "ok"; else kt_test_fail "rc $rc RESULT [$res] bounds [$REPLY]"; fi
reset

kt_test_start "the owner-process rule: dragView and a cmResize inside \$( ) refuse (rc 2, one debug line), nothing read, nothing moved"
fvw_events 'key kbRight' 'key kbEnter'
out=$( fv.views.dragView w2 1 0 0 80 24 16 6 80 24; printf '%s:%s' "$?" "$FVW_EVN" )
out2=$( send evCommand cmResize; printf '%s:%s' "$FVW_EVN" "$FV_EV_WHAT" )
err=$( VERBOSE_KKLASS=debug fv.views.dragView w2 1 0 0 80 24 16 6 80 24 2>&1 >/dev/null )
bounds
if [[ $out == 2:0 && $out2 == 0:evNothing && $err == *'subshell'* && $REPLY == '30 5 70 22' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out] [$out2] [$err] [$REPLY]"; fi
reset

kt_test_start "dragView refusals (rc 2, RESULT ''): the argument count, a non-integer, a non-view; FV's high(Sw_Integer) is a maximum"
r=''
RESULT=x; fv.views.dragView w2 1 0 0 80 24 16 6 80; r+="$?:$RESULT,"
RESULT=x; fv.views.dragView w2 1 0 0 80 24 16 6 80 x; r+="$?:$RESULT,"
RESULT=x; fv.views.dragView nosuch 1 0 0 80 24 16 6 80 24; r+="$?:$RESULT,"
fvw_events 'key kbEnter'
fv.views.dragView w2 1 0 0 80 24 16 6 "$__FV_VW_HIGH" "$__FV_VW_HIGH"; r+="$?"
if [[ $r == '2:,2:,2:,0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
reset

# ---- the counts --------------------------------------------------------------------
c0() { FVW_CALLS=0 FVW_WRITES=0; }
c1() { N_CALLS=$FVW_CALLS N_WRITES=$FVW_WRITES; }
# --- critic round (2d) ---
kt_test_start "keyboard: Shift+Enter ends a drag as Enter (kept), Shift+Esc as Esc (start bounds back): FV's KeyCode"
fvw_events 'key kbRight' 'key kbShiftEnter' 'key kbRight' 'key kbEsc'
send evCommand cmResize
bounds; a="$REPLY:$FVW_EVN"
reset
fvw_events 'key kbRight' 'key kbShiftEsc' 'key kbRight' 'key kbEnter'
send evCommand cmResize
bounds; b="$REPLY:$FVW_EVN"
reset
if [[ $a == '31 5 71 22:2' && $b == '30 5 70 22:2' ]]; then kt_test_pass "ok"; else kt_test_fail "ShiftEnter [$a] ShiftEsc [$b]"; fi

kt_test_start "the owner-process rule: a close-icon press inside \$( ) reads nothing and posts nothing; the event handled"
fvw_events 'move 33 5' 'up 33 5'
out=$( mdown 33 5 2>/dev/null; printf '%s:%s:%s' "$FVW_EVN" "${#__FV_DR_PEND[@]}" "$FV_EV_WHAT" )
if [[ $out == 0:0:evNothing && -n ${__FV_VW_LIVE[w2]-} ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi
reset

kt_test_start "counts: one keyboard move step (between two reads) <= 4 dispatches"
fvw_events 'run c0' 'key kbRight' 'run c1' 'key kbEnter'
fvw_count_on; fvw_writes_on
send evCommand cmResize
fvw_writes_off; fvw_count_off
kt_test_log "# calls kbd-step $N_CALLS"
kt_test_log "# writes kbd-step $N_WRITES"
if (( N_CALLS <= 4 )); then kt_test_pass "$N_CALLS dispatches, $N_WRITES writes"; else kt_test_fail "$N_CALLS dispatches > 4 ($N_WRITES writes)"; fi
reset

kt_test_start "counts: one mouse move step (the drain and the step) <= 4 dispatches"
fvw_events 'run c0' 'move 51 5' 'nothing' 'run c1' 'up 51 5'
fvw_count_on; fvw_writes_on
mdown 50 5
fvw_writes_off; fvw_count_off
kt_test_log "# calls mouse-step $N_CALLS"
kt_test_log "# writes mouse-step $N_WRITES"
if (( N_CALLS <= 4 )); then kt_test_pass "$N_CALLS dispatches, $N_WRITES writes"; else kt_test_fail "$N_CALLS dispatches > 4 ($N_WRITES writes)"; fi
reset

kt_test_start "counts: cmZoom and back <= 8 dispatches each; == a full repaint"
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
send evCommand cmZoom
a="$FVW_CALLS $FVW_WRITES"; FVW_CALLS=0 FVW_WRITES=0
fvw_full app; f1=$?
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
send evCommand cmZoom
b="$FVW_CALLS $FVW_WRITES"
fvw_writes_off; fvw_count_off
kt_test_log "# calls zoom ${a% *} unzoom ${b% *}"
kt_test_log "# writes zoom ${a#* } unzoom ${b#* }"
bounds
if (( ${a% *} <= 8 && ${b% *} <= 8 )) && [[ $f1 == 0 && $REPLY == '30 5 70 22' ]] && fvw_full app; then kt_test_pass "zoom [$a] unzoom [$b] (dispatches writes)"
else kt_test_fail "zoom [$a] unzoom [$b] full $f1 bounds [$REPLY] diff [$FVW_DIFF]"; fi

# (last: it destroys w2) the event source closes the window while its close
# icon is pressed: the tracking leaves at once — nothing written into the dead
# frame (no leaked w2__fvframe_data), nothing posted; a new w2 is whole
kt_test_start "the window destroyed by the event source during a close-icon press: the tracking ends, no leaked frame data, nothing posted; a re-created window of the same name == a full repaint"
killw2() { w2.delete; }
fvw_events 'run killw2' 'move 33 5' 'up 33 5'
__FV_DR_PEND=()
mdown 33 5 2>/dev/null
leak=0; if declare -p w2__fvframe_data >/dev/null 2>&1; then leak=1; fi
np=${#__FV_DR_PEND[@]}
fvw_noevents
TWindow.new w2 30 5 70 22 'Again' 2 && fv.views.insert desk w2
fv.views.drawView app
if [[ $leak == 0 && $np == 0 && -n ${__FV_VW_LIVE[w2__fvframe]-} ]] && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "leak $leak pend $np frame [${__FV_VW_LIVE[w2__fvframe]-}] diff [$FVW_DIFF]"; fi

fvw_untscene
kt_test_log "017_Drag.sh completed"
