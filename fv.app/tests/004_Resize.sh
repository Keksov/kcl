#!/usr/bin/env bash
# 004_Resize.sh - cmResizeApp (design §2.3), headless with the scripted
# terminal (what fv.drivers gives after a SIGWINCH):
#   * handled at once inside GetEvent (TApplication's resize: the screen
#     reallocated, ChangeBounds by GrowMode: desktop gfGrowHiX|HiY, status
#     line gfGrowLoY|HiX|HiY, windows gfGrowAll|Rel with their ZoomRect),
#     one full redraw (== a full repaint), counted in __FV_VW_RESIZES; the
#     loop gets evNothing (FV clears it) and Idle runs; the application's
#     HandleEvent override sees it once;
#   * the same size: nothing redrawn; a bad size: ignored;
#   * mid-modal: the dialog keeps running at its new bounds;
#   * mid-drag (keyboard drag through cmResize, a mouse drag by the frame):
#     the drag ends, the window clamped into the new extent, no undo, the
#     next events unread by the drag;
#   * the counts (logged): one resize 80x24 -> 120x40.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: resize"

kt_test_start "cmResizeApp from the terminal is handled inside GetEvent: screen, application, desktop, status line and windows by GrowMode, one full redraw; the loop gets evNothing, Idle runs; TMyApp saw it once"
fva_app 80 24 TMyApp
fva_paint
fvw_wrap FVA_IDLE fv.app._progIdle
FVA_IDLE=0 FVA_GOT=''
rz=$__FV_VW_RESIZES
fva_events 'resize 120 40'
fv.app._getEvent; rc=$?
r="$rc|$FV_EV_WHAT|$FVA_IDLE|$(( __FV_VW_RESIZES - rz ))|$FV_SCREEN_W x $FV_SCREEN_H|${__FV_VS_W}x$__FV_VS_H"
fva_b app; r+="|$REPLY"; fva_b app__fvdesktop; r+="|$REPLY"; fva_b app__fvstatus; r+="|$REPLY"; fva_b app__fvdesktop__fvbg; r+="|$REPLY"
fva_b w1; r+="|$REPLY"; fva_b w2; r+="|$REPLY|${w2_data[ZoomRect]}|$FVA_GOT"
fvw_unwrap fv.app._progIdle
want='0|evNothing|1|1|120 x 40|120x40|0 0 120 40|0 0 120 39|0 39 120 40|0 0 120 39|3 2 60 34|45 8 105 37|45 8 105 37|evCommand:cmResizeApp;evBroadcast:cmCommandSetChanged;'
if [[ $r == "$want" ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want] diff [$FVW_DIFF]"; fi

kt_test_start "the status line is drawn on the new last row (FV look), the desktop's background fills the rest"
fv.video.getRow 39; r1=${RESULT:0:12}
fv.video.getRow 0; r2=${RESULT:0:3}
if [[ $r1 == ' Alt-X Exit ' && $r2 == '░░░' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2]"; fi

kt_test_start "a resize to the same size redraws nothing (FV ResizeApplication compares); a bad size is ignored (a debug line)"
fvw_writes_on; FVW_WRITES=0
fva_events 'resize 120 40' 'resize x 40' 'resize 0 9'
fv.app._getEvent; fv.app._getEvent; fv.app._getEvent
n=$FVW_WRITES
fvw_writes_off
fva_b app
if [[ $n == 0 && $REPLY == '0 0 120 40' ]]; then kt_test_pass "ok"; else kt_test_fail "writes $n bounds [$REPLY]"; fi

kt_test_log "budget (logged): one resize 120x40 -> 80x24 (dispatches: TMyApp + inherited + the leaves' Draws)"
fva_events 'resize 80 24'
fvw_budget resize 6 fv.app._getEvent
fva_events 'resize 120 40'
fvw_writes_on; FVW_WRITES=0; fv.app._getEvent; kt_test_log "# writes resize $FVW_WRITES"; fvw_writes_off
kt_test_start "after the resizes back and forth: == a full repaint"
if fvw_full app; then kt_test_pass "ok"; else kt_test_fail "diff [$FVW_DIFF]"; fi
fva_unapp

# ---- mid-modal ----------------------------------------------------------------
class TRzApp : TApplication
    public
        override proc HandleEvent
end
TRzApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbF7 ]; then
        TWindow.new dz 20 5 60 15 'Dialog' 0
        fv.views.execView "$FV_DESKTOP" dz
        RZLOG+="dz=$RESULT;"
        dz.delete
        fv.views.clearEvent "$this"
    fi
}
build TRzApp
rzlog() { fva_b dz; RZLOG+="dz@$REPLY;"; }
kt_test_start "mid-modal: a resize while a dialog runs is handled at once; the dialog goes on at its new bounds (gfGrowAll + gfGrowRel), ends at the end of input"
fva_app 80 24 TRzApp
RZLOG=''
fva_events 'key kbF7' 'run rzlog' 'resize 160 48' 'run rzlog' 'nothing'
fva_paint
app.Run
r="$RZLOG|$__FV_VW_EOF"
fva_b app__fvdesktop; r+="|$REPLY"
if [[ $r == 'dz@20 5 60 15;dz@40 10 120 31;dz=cmCancel;|1|0 0 160 47' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
fva_unapp

# ---- mid-drag -----------------------------------------------------------------
kt_test_start "mid-drag (keyboard, cmResize): a resize ends the drag, the window clamped into the new extent, no undo; the key after it goes to the loop"
fva_app 80 24 TMyApp
fva_paint
w2_data[GrowMode]=0
FVA_GOT=''
fva_events 'cmd cmResize' 'key kbRight' 'resize 50 20' 'key kbEsc' 'cmd cmQuit'
app.Run
fva_b w2
r="$REPLY|${w2_data[State]}|$__FV_VW_EOF|${#FVA_Q[@]}|$FVA_GOT"
if [[ $r == "31 5 71 22|$(( w2_data[State] & ~FV_SF_DRAGGING ))|0|0|evCommand:cmResize;evCommand:cmResizeApp;evBroadcast:cmCommandSetChanged;evKeyDown:kbEsc;evCommand:cmQuit;" ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
fva_unapp

kt_test_start "mid-drag (mouse, by the frame's top row): a resize met while draining (timeout 0) ends the drag clamped; the mouse-up after it is the loop's"
fva_app 80 24 TMyApp
fva_paint
w2_data[GrowMode]=0
FVA_GOT=''
fva_events 'down 50 5' 'move 45 7' 'resize 50 20' 'up 0 0' 'cmd cmQuit'
app.Run
fva_b w2
r="$REPLY|$__FV_VW_EOF|${#FVA_Q[@]}|$FVA_GOT|$FVA_TO"
if [[ $r == '25 7 65 24|0|0|evMouseDown:;evCommand:cmResizeApp;evBroadcast:cmCommandSetChanged;evMouseUp:;evCommand:cmQuit;|//0///' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
fva_unapp

kt_test_log "004_Resize.sh completed"
