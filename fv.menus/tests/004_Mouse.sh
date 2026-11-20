#!/usr/bin/env bash
# 004_Mouse.sh - TStatusLine's press tracking (FV HandleEvent evMouseDown:
# repeat ItemMouseIsIn / DrawSelect until NOT MouseEvent(evMouseMove)),
# reached through the application's positional dispatch, with the scripted
# event source: the pressed item drawn in CSelect (palette 4 / 6), a
# disabled one in CSelDisabled (5); a release on an enabled item posts its
# command; moving to another item, off the items, off the row; a press on
# the blank part (nothing drawn, nothing posted, handled); a key-only item
# takes no cells; the end of input during a press (the loop ends, nothing
# posted, the latch set); the event record put back after the inner loop
# (then handled: evNothing, FV_EV_INFO = the line); the line drawn plain
# again only when an item was shown pressed; the writes per press and the
# dispatches; the screen equals a full repaint afterwards.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: the mouse"

fvm_scene
fvm_draw
fvm_st; NORMAL=$REPLY
# ' Alt+X Exit ' 0..11, ' F10 Menu ' 12..21, ' F5 Zoom ' 22..30 (the key-only
# F6 item between Menu and Zoom takes no cells)
fvw_check "the line before (cmZoom enabled: a window is selected)" \
    " Alt+X Exit  F10 Menu  F5 Zoom |244444222222244422222224422222222" "$(fvm_st; printf '%s|%s' "${RESULT:0:31}" "${REPLY:0:33}")"

SNAP=''
snap() { fvm_st; SNAP+="${REPLY:0:31},"; }
press() {   # X Y EVENTS... — a mouse-down at X Y, the rest from the queue
    local x=$1 y=$2
    shift 2
    fvw_events "$@"
    SNAP='' FVW_GOT=''
    __FV_DR_PEND=()
    fv.drivers.clearEvent
    FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$x FV_EV_MOUSE_Y=$y FV_EV_MOUSE_BUTTONS=1
    fv.views._virt app HandleEvent
    local IFS=,
    PEND="${__FV_DR_PEND[*]-}"
}

press 3 23 "run snap" "up 3 23"
fvm_st
fvw_check "press + release on 'Alt+X Exit': drawn pressed (5 / 7), cmQuit posted, handled by the line, drawn plain again" \
    "5777775555552444222222244222222,|evCommand,,,cmQuit,,,0,0,0,0,0,0,0,0|evNothing st|$NORMAL" \
    "$SNAP|$PEND|$FV_EV_WHAT $FV_EV_INFO|$REPLY"

press 3 23 "run snap" "move 15 23" "run snap" "move 16 23" "run snap" "up 16 23"
fvw_check "moving to 'F10 Menu' (and within it: no redraw) then release: cmMenu" \
    "5777775555552444222222244222222,2444442222225777555555244222222,2444442222225777555555244222222,|evCommand,,,cmMenu,,,0,0,0,0,0,0,0,0" "$SNAP|$PEND"

press 25 23 "up 25 23"
fvw_check "'F5 Zoom' starts at 22 (the key-only item takes no cells): cmZoom" "evCommand,,,cmZoom,,,0,0,0,0,0,0,0,0" "$PEND"

FVW_WRITES=0; fvw_writes_on
press 3 23 "move 50 23" "run snap" "up 50 23"
fvw_writes_off
fvm_st
fvw_check "moved off the items before the release: drawn plain at once, nothing posted, no extra redraw (2 writes)" \
    "2444442222222444222222244222222,||evNothing st|2|$NORMAL" "$SNAP|$PEND|$FV_EV_WHAT $FV_EV_INFO|$FVW_WRITES|$REPLY"

FVW_WRITES=0; fvw_writes_on
press 3 23 "move 3 22" "run snap" "up 3 22"
fvw_writes_off
fvw_check "moved off the row: no item, nothing posted" "2444442222222444222222244222222,||2" "$SNAP|$PEND|$FVW_WRITES"

FVW_WRITES=0; fvw_writes_on
press 60 23 "move 61 23" "up 61 23"
fvw_writes_off
fvw_check "a press on the blank part: nothing drawn, nothing posted, handled, the record put back (X of the press)" \
    "0||evNothing st|60|$NORMAL" "$FVW_WRITES|$PEND|$FV_EV_WHAT $FV_EV_INFO|$FV_EV_MOUSE_X|$(fvm_st; printf '%s' "$REPLY")"

# FV_EV_BASE (P3 3L) is part of the record put back: the inner loop's events clear it
fvw_events "move 61 23" "up 61 23"
__FV_DR_PEND=()
fv.drivers.clearEvent
FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=60 FV_EV_MOUSE_Y=23 FV_EV_MOUSE_BUTTONS=1 FV_EV_BASE=q
fv.menus._track st
fvw_check "the press tracking puts FV_EV_BASE back with the rest of the record" "q|60|evNothing" "$FV_EV_BASE|$FV_EV_MOUSE_X|$FV_EV_WHAT"
FV_EV_BASE=''

fv.views.disableCommands cmMenu
press 15 23 "run snap" "up 15 23"
fvw_check "a disabled item pressed: CSelDisabled (6), nothing posted on release" \
    "2444442222226666666666244222222,|" "$SNAP|$PEND"
fv.views.enableCommands cmMenu

press 3 23 "run snap"
fvw_check "the end of input during a press: the loop ends, nothing posted, the latch set, the line plain" \
    "5777775555552444222222244222222,||1|evNothing st|$NORMAL" "$SNAP|$PEND|$__FV_VW_EOF|$FV_EV_WHAT $FV_EV_INFO|$(fvm_st; printf '%s' "$REPLY")"
fvw_noevents

kt_test_start "the press's dispatches: the app's override + inherited, the line elided"
fvw_events "up 3 23"
fvw_count_on; FVW_CALLS=0
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=3 FV_EV_MOUSE_Y=23 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent
n=$FVW_CALLS; fvw_count_off
kt_test_log "# calls press->command $n"
if (( n == 2 )); then kt_test_pass "$n"; else kt_test_fail "$n dispatches"; fi
fvw_noevents

kt_test_start "the screen after the presses equals a full repaint"
if fvw_full app; then kt_test_pass "ok"; else kt_test_fail "$FVW_DIFF"; fi

# a press on the line through the modal loop: the posted command arrives
# as the next event (FV PutEvent) and goes to the focused leaf
fvw_events "down 15 23" "up 15 23"
__FV_DR_PEND=() FVW_GOT=''
fv.views._virt app Execute
fvw_check "Execute: a click on 'F10 Menu' -> cmMenu posted -> the next event reaches the focused leaf" "w2l:evCommand:cmMenu;" "$FVW_GOT"
fvw_noevents

fvm_unscene
kt_test_log "004_Mouse.sh completed"
