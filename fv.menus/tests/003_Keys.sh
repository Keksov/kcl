#!/usr/bin/env bash
# 003_Keys.sh - TStatusLine's keys (FV HandleEvent evKeyDown): through the
# application's dispatch (the line has ofPreProcess, so it sees a key
# before the focused view): a key of the current def whose command is
# enabled -> evCommand CMD posted (PutEvent: the posted record has the key
# and mouse fields cleared, InfoPtr nil) and the key handled (ClearEvent:
# evNothing, FV_EV_INFO = the line); a disabled command -> the key goes on
# to the focused view; a key used twice in a def (the first disabled ->
# the second); another def's keys after a HelpCtx change; a key-only item;
# an empty key; the posted command through the modal loop (F6 -> cmNext ->
# the next window, as the design's Tab action); RESULT kept, the Phase the
# dispatch left; the dispatch and write counts of a key mapped to a command.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: keys"

fvm_scene
fvm_draw

key() { fv.drivers.clearEvent; __FV_DR_PEND=(); FVW_GOT=''; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=x FV_EV_MOUSE_X=7 RESULT=keep; fv.views._virt app HandleEvent; }
pend() { local IFS=,; REPLY="${__FV_DR_PEND[*]-}"; }

key kbF10; pend
fvw_check "F10 (cmMenu, enabled): handled by the line, cmMenu posted with the other fields cleared, the leaf saw nothing, RESULT kept" \
    "evNothing st|evCommand,,,cmMenu,,,0,0,0,0,0,0,0,0||keep|phPreProcess" "$FV_EV_WHAT $FV_EV_INFO|$REPLY|$FVW_GOT|$RESULT|${app_data[Phase]}"

fv.views.disableCommands cmMenu
key kbF10; pend
fvw_check "F10 with cmMenu disabled: nothing posted, the key goes on to the focused leaf" \
    "|w2l:evKeyDown:kbF10;" "$REPLY|$FVW_GOT"
fv.views.enableCommands cmMenu

key kbF6; pend
fvw_check "a key-only item (no text): F6 -> cmNext" "evNothing|evCommand,,,cmNext,,,0,0,0,0,0,0,0,0" "$FV_EV_WHAT|$REPLY"

key kbF1; pend
fvw_check "F1 belongs to def 100..199, not to the current def 0..99: not the line's" "|w2l:evKeyDown:kbF1;" "$REPLY|$FVW_GOT"

w2l_data[HelpCtx]=150
fv.menus.update st
key kbF1; pend; a=$REPLY
key kbF10; pend
fvw_check "after a HelpCtx change (150, Update): F1 -> cmHelp; F10 no longer the line's" \
    "1|evCommand,,,cmHelp,,,0,0,0,0,0,0,0,0||w2l:evKeyDown:kbF10;" "${__FV_MN_CUR[st]}|$a|$REPLY|$FVW_GOT"
w2l_data[HelpCtx]=0
fv.menus.update st

key ''; pend
fvw_check "an empty key: nobody's" "evKeyDown|" "$FV_EV_WHAT|$REPLY"

# a key used twice in a def: the first item whose command is enabled
TStatusLine.new sd 0 0 40 1 'one' kbF2 cmOne 'two' kbF2 cmTwo
fv.views.disableCommands cmOne
fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF2; fv.views._virt sd HandleEvent; pend
fvw_check "a key twice in a def, the first command disabled: the second item's command" "evCommand,,,cmTwo,,,0,0,0,0,0,0,0,0" "$REPLY"
fv.views.disableCommands cmTwo
fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF2; fv.views._virt sd HandleEvent; pend
fvw_check "both disabled: the key is not handled" "evKeyDown|" "$FV_EV_WHAT|$REPLY"
fv.views.enableCommands cmOne cmTwo
fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evKeyDown FV_EV_KEY=kbf2; fv.views._virt sd HandleEvent; pend
fvw_check "key names are case-sensitive (kbf2 is not kbF2), also under nocasematch" "evKeyDown|" "$FV_EV_WHAT|$REPLY"
shopt -s nocasematch
fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evKeyDown FV_EV_KEY=kbf2; fv.views._virt sd HandleEvent; pend
shopt -u nocasematch
fvw_check "  (nocasematch)" "evKeyDown|" "$FV_EV_WHAT|$REPLY"
sd.delete

# the counts of a key mapped to a command (the app's override + inherited;
# the line's handler is elided: no dispatch, nothing drawn)
fvw_budget "key->command" 2 key kbF10
FVW_WRITES=0; fvw_writes_on; key kbF10; fvw_writes_off
kt_test_log "# writes key->command $FVW_WRITES"
fvw_check "a key mapped to a command writes nothing" 0 "$FVW_WRITES"

# through the modal loop: F6 -> the line posts cmNext -> the next event is
# cmNext -> TTApp's handler focuses the other window
fvw_events "key kbF6"
__FV_DR_PEND=()
fv.views._virt app Execute; r=$RESULT
fvw_check "Execute: F6 -> cmNext posted -> the next event -> w1 selected; the end of input ends the loop" \
    "cmQuit|w1|3" "$r|${desk_data[Current]}|$FVW_EVN"
fvw_noevents

kt_test_start "the screen after the window switch equals a full repaint"
if fvw_full app; then kt_test_pass "ok"; else kt_test_fail "$FVW_DIFF"; fi

fvm_unscene
kt_test_log "003_Keys.sh completed"
