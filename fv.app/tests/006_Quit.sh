#!/usr/bin/env bash
# 006_Quit.sh - ending the application (FV TProgram.HandleEvent, Done):
#   * Alt+X through the default status line -> cmQuit -> EndModal(cmQuit):
#     Run returns, the event handled; cmQuit put with PutEvent and sent as a
#     command; the last key is not read;
#   * a window whose Valid says no to cmQuit keeps the application running
#     (FV Execute asks Valid(EndState)); the next cmQuit after it agrees ends;
#   * Done (app.delete): the desktop, status line and windows destroyed
#     without drawing, fv.views' hooks and the owner back as before Init,
#     FV_APP / FV_DESKTOP / FV_STATUSLINE / FV_MENUBAR '', the app palette and
#     ErrorAttr back to the defaults; a new application after it works;
#     TProgram's Done body on a dead name is a no-op.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "006: quit and Done"

kt_test_start "Alt+X (the default status line's key) -> cmQuit -> Run returns; the key after it is not read"
fva_app 80 24 TMyApp
fva_events 'key kbF2' 'key kbAltX' 'key kbF3'
app.Run
r="$__FV_VW_EOF|${#FVA_Q[@]}|$FVA_GOT|${app_data[EndState]}"
if [[ $r == '0|1|evKeyDown:kbF2;evKeyDown:kbAltX;evCommand:cmQuit;|' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "cmQuit put with PutEvent before Run, and sent as a command: each ends Run"
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmQuit; fv.app._putEvent
fva_events 'key kbF2'
FVA_GOT=''
app.Run
r="$__FV_VW_EOF|${#FVA_Q[@]}|$FVA_GOT"
fva_events 'cmd cmQuit' 'key kbF2'
app.Run
r+="|$__FV_VW_EOF|${#FVA_Q[@]}"
if [[ $r == '0|1|evCommand:cmQuit;|0|1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
fva_unapp

kt_test_start "a window whose Valid refuses cmQuit keeps the application running (Valid asked once per cmQuit); it agrees the second time"
class TVW : TWindow
    public
        override func Valid
end
TVW.Valid() { VASK+="$1;"; if [ "$1" = cmQuit ] && (( ++VN < 2 )); then return 1; fi; inherited Valid "$@" || return; }
build TVW
fva_app
TVW.new vw 10 3 50 13 'Unsaved' 3
fv.views.insert "$FV_DESKTOP" vw
VASK='' VN=0
fva_events 'key kbAltX' 'key kbF2' 'key kbAltX' 'key kbF3'
app.Run
r="$VASK|$__FV_VW_EOF|${#FVA_Q[@]}"
if [[ $r == 'cmQuit;cmQuit;|0|1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "Done: nothing drawn, every view destroyed, the hooks and the owner back, the globals '', the app palette and ErrorAttr back"
fva_paint
fv.app.setAppPalette 5 200 17 1
p=$__FV_VW_APAL
fvw_outsize; s0=$REPLY
app.delete
fvw_outsize
r="$(( REPLY - s0 ))|${__FV_VW_LIVE[app]-x}${__FV_VW_LIVE[app__fvdesktop]-x}${__FV_VW_LIVE[app__fvstatus]-x}${__FV_VW_LIVE[app__fvdesktop__fvbg]-x}${__FV_VW_LIVE[vw]-x}${__FV_VW_LIVE[w1]-x}"
r+="|$__FV_VW_GETEVENT|$__FV_VW_PUTEVENT|$__FV_VW_OWNER|$FV_APP|$FV_DESKTOP|$FV_STATUSLINE|$FV_MENUBAR|$__FV_VW_ERRSYM"
[[ $__FV_VW_APAL == "$__FV_AP_DEFPAL" && $p != "$__FV_AP_DEFPAL" ]] && r+='|pal'
if [[ $r == "0|xxxxxx|fv.drivers.getEvent|fv.drivers.putEvent|$BASHPID|||||0|pal" ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "hooks set by the caller before Init (a scripted source) are put back by Done; a new application after Done works; TProgram's Done body on a dead name is a no-op"
myget() { fv.drivers.getEvent "$@"; }
__FV_VW_GETEVENT=myget
fva_app
r="$__FV_VW_GETEVENT"
fva_events 'cmd cmQuit'
app.Run
app.delete
r+="|$__FV_VW_GETEVENT"
fv.app._progDone app; r+="|$?"
__FV_VW_GETEVENT=fv.drivers.getEvent
fva_unapp
if [[ $r == 'fv.app._getEvent|myget|0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_log "006_Quit.sh completed"
