#!/usr/bin/env bash
# 007_Eof.sh - the end of input latches (design §2.1, finding 4):
#   * the end of input ends Run (cmQuit for the application, Valid not
#     asked), __FV_VW_EOF = 1; GetEvent after it is rc 1 without reading;
#   * the "save?" box: a window whose Valid(cmQuit) opens a dialog through
#     execView; cmQuit and then the end of input: the box returns cmCancel at
#     once, Valid says no, and the application ends without asking Valid
#     again (Valid asked once, nothing spins);
#   * execView after the latch: cmCancel at once, no loop;
#   * a failing source (rc 2, fv.drivers' bad fd) counts as the end of input
#     in the loop; a new application resets the latch;
#   * a real terminal end: keys from a file through fv.drivers, then end of
#     file.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "007: the end of input"

kt_test_start "the end of input ends Run without asking Valid; latched; GetEvent after it is rc 1 at once (nothing read)"
class TVQ : TWindow
    public
        override func Valid
end
TVQ.Valid() { VASK+="$1;"; return 1; }
build TVQ
fva_app
TVQ.new vq 10 3 50 13 'Unsaved' 3
fv.views.insert "$FV_DESKTOP" vq
VASK=''
fva_events 'key kbF2'
app.Run
n=$FVA_N
fv.app._getEvent 0; rc=$?
r="$__FV_VW_EOF|$VASK|$rc|$FV_EV_EOF|$(( FVA_N - n ))"
if [[ $r == '1||1|1|0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "execView after the latch: cmCancel at once, no loop, no read"
TWindow.new dlg 20 5 40 10 'D' 0
n=$FVA_N
fv.views.execView "$FV_DESKTOP" dlg
r="$RESULT|$(( FVA_N - n ))|${dlg_data[Owner]}"
dlg.delete
vq.delete
fva_unapp
if [[ $r == 'cmCancel|0|' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "the save? box: Valid(cmQuit) opens a dialog; at the end of input the box answers cmCancel at once, Valid says no, the application ends without asking Valid again"
class TSave : TWindow
    public
        override func Valid
end
TSave.Valid() {
    if [ "$1" = cmQuit ]; then
        TWindow.new box 25 8 55 14 'Save?' 0
        fv.views.execView "$FV_DESKTOP" box
        VASK+="$1>$RESULT;"
        box.delete
        if [ "$RESULT" = cmYes ]; then RESULT=1; else return 1; fi
    else
        inherited Valid "$@" || return
    fi
}
build TSave
fva_app
TSave.new ed 5 2 45 12 'Editor' 4
fv.views.insert "$FV_DESKTOP" ed
VASK=''
fva_events 'cmd cmQuit'
app.Run; rc=$?
r="$rc|$VASK|$__FV_VW_EOF|$FVA_N|${__FV_VW_LIVE[box]-gone}"
if [[ $r == '0|cmQuit>cmCancel;|1|2|gone' ]] && { fva_paint; fvw_full app; }; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
ed.delete
fva_unapp

kt_test_start "a failing source (rc 2) ends the loop as the end of input (a debug line); a new application resets the latch"
fva_app
fva_events 'key kbF2' 'fail 2'
app.Run; rc=$?
r="$rc|$__FV_VW_EOF"
fva_unapp
__FV_VW_EOF=1
fva_app
r+="|$__FV_VW_EOF"
fva_unapp
if [[ $r == '0|1|0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "a real end of file: keys from a file through fv.drivers (F2, a Tab), then end of file ends Run (latched)"
fva_app 80 24 TMyApp
printf '\033OQ\t' > "$FVW_TMP/keys"
exec {kf}<"$FVW_TMP/keys"
FV_KEY_FD=$kf
app.Run
r="$__FV_VW_EOF|$FVA_GOT"
exec {kf}<&-
FV_KEY_FD=0
fva_unapp
if [[ $r == '1|evKeyDown:kbF2;evKeyDown:kbTab;' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_log "007_Eof.sh completed"
