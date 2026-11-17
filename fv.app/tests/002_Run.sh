#!/usr/bin/env bash
# 002_Run.sh - TProgram / TApplication Init and Run (design §2.1, §4), headless:
#   * Init: the tree FV makes (desktop with its background, the status line in
#     front, Current = the desktop), FV_APP / FV_DESKTOP / FV_STATUSLINE, the
#     State bits (sfExposed only at Run), the hooks, nothing drawn, ErrorAttr's
#     symbol; a user InitStatusLine / InitMenuBar / InitDesktop; TProgram
#     alone; a second application refused; no terminal -> rc 1, nothing made;
#   * Run: the first paint (== a full repaint), keys from a file through
#     fv.drivers until Alt+X; the event source: the TIMEOUT argument passed
#     on, the put event first (no Idle for it), a GetEvent override
#     dispatched; Idle on evNothing (the status line's Update, the
#     cmCommandSetChanged broadcast and the flag cleared);
#   * the counts (logged): an idle tick 0 dispatches, Alt+2, a key routed to
#     the focused leaf, the first paint of the small app.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: Init and Run"

kt_test_start "Init: the tree (desktop > background, the status line in front), Current, the globals, the State bits (no sfExposed yet), the hooks"
fva_app
fvw_tree app
r="$REPLY|$FV_APP|$FV_DESKTOP|$FV_STATUSLINE|${FV_MENUBAR}|$(( app_data[State] ))|${app_data[Options]}|$__FV_VW_GETEVENT|$__FV_VW_PUTEVENT|$__FV_VW_OWNER/$__FV_AP_OWNER"
want="app[{app__fvdesktop[app__fvdesktop__fvbg {w1[w1__fvframe w1l]*w1l} {w2[w2__fvframe w2l]*w2l}]*w2} app__fvstatus]*app__fvdesktop|app|app__fvdesktop|app__fvstatus||$(( FV_SF_VISIBLE | FV_SF_SELECTED | FV_SF_FOCUSED | FV_SF_MODAL ))|0|fv.app._getEvent|fv.app._putEvent|$BASHPID/$BASHPID"
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "Init: the desktop over rows 0..H-2 (no menu bar in P2), the status line on the last row, the background over the desktop, FV's grow modes"
fva_b app__fvdesktop; r=$REPLY; fva_b app__fvstatus; r+="|$REPLY"; fva_b app__fvdesktop__fvbg; r+="|$REPLY"
r+="|${app__fvdesktop_data[GrowMode]}|${app__fvdesktop__fvbg_data[GrowMode]}|${app__fvdesktop_data[Background]}|${app__fvdesktop__fvbg_data[Pattern]}"
if [[ $r == "0 0 80 23|0 23 80 24|0 0 80 23|12|12|app__fvdesktop__fvbg|░" ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "Init and the inserts after it draw nothing (the first paint is Run's); ErrorAttr has a symbol of its own (W, white on bright red)"
fvw_outsize
if [[ $REPLY == 0 && $__FV_VW_ERRSYM == W && ${__FV_VS_PAL[W]} == '15 9 0' ]]; then kt_test_pass "ok"; else kt_test_fail "out $REPLY errsym $__FV_VW_ERRSYM [${__FV_VS_PAL[W]-}]"; fi

kt_test_start "Run: the first paint (== a full repaint: background, frames, shadows, the status line), keys from a file through fv.drivers, Alt+X -> cmQuit ends Run (rc 0, RESULT kept)"
printf '\033x' > "$FVW_TMP/keys"
exec {kf}<"$FVW_TMP/keys"
FV_KEY_FD=$kf
RESULT=keep
app.Run; rc=$?
fv.video.getRow 23; st=$RESULT
fv.video.getRow 0; r0=$RESULT
r="$rc|$RESULT|$__FV_VW_EOF|$(( app_data[State] & FV_SF_EXPOSED ))"
exec {kf}<&-
if [[ $r == "0|${r0}|0|$FV_SF_EXPOSED" && $st == ' Alt-X Exit '* && $r0 == '░░░░'* ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] [$st] [$r0] diff [$FVW_DIFF]"; fi
fva_unapp

kt_test_start "the event source: each loop read passes no TIMEOUT (fv.drivers' 0.05 s), a read with 0 passes it on; the put event comes first and gets no Idle"
fva_app
fva_paint
fvw_wrap FVA_IDLE fv.app._progIdle
FVA_IDLE=0
fva_events 'nothing' 'key kbF2'
fv.app._getEvent; r="$FV_EV_WHAT/$FVA_IDLE"
fv.app._getEvent 0; r+="|$FV_EV_WHAT/$FV_EV_KEY/$FVA_IDLE"
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmFoo; fv.app._putEvent
fv.app._getEvent; r+="|$FV_EV_WHAT/$FV_EV_COMMAND/$FVA_IDLE|$FVA_TO"
fvw_unwrap fv.app._progIdle
if [[ $r == 'evNothing/1|evKeyDown/kbF2/1|evCommand/cmFoo/1|/0/0/' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "Idle: the status line's Update follows the focused view's HelpCtx (FV: TopView's GetHelpCtx), with no dispatch (the first tick's cmCommandSetChanged done before)"
w2l_data[HelpCtx]=150
fva_events nothing nothing
fvw_count_on; FVW_CALLS=0
fv.app._getEvent
n=$FVW_CALLS
fvw_count_off
r="${app__fvstatus_data[HelpCtx]}|$n"
w2l_data[HelpCtx]=0
fv.app._getEvent
r+="|${app__fvstatus_data[HelpCtx]}"
if [[ $r == '150|0|0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
kt_test_start "Idle: a changed command set -> cmCommandSetChanged broadcast to the application (the status line greys a disabled item), the flag cleared"
fv.views.disableCommands cmQuit
fva_events nothing nothing
fv.app._getEvent
fv.video.getRow 23
r="$FV_COMMANDSETCHANGED|${REPLY:1:5}"
fv.views.enableCommands cmQuit
fv.app._getEvent
fv.video.getRow 23
r+="|$FV_COMMANDSETCHANGED|${REPLY:1:5}"
fv.views.getColor app__fvstatus 2; g=$RESULT; fv.views.getColor app__fvstatus 1; n1=$RESULT
if [[ $r == "0|$g$g$g$g$g|0|${REPLY:1:5}" && ${REPLY:1:1} != "$g" ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] grey $g normal $n1"; fi

kt_test_start "a GetEvent override is dispatched by the event source (inherited reaches the built-in: Idle, the latch)"
fva_unapp
class TGE : TApplication
    public
        override func GetEvent
end
TGE.GetEvent() { GECALLS+="${1-}/"; inherited GetEvent "$@" || return; }
build TGE
GECALLS=''
fva_app 80 24 TGE
fva_events 'key kbF2' 'cmd cmQuit'
app.Run
r="$GECALLS|$__FV_VW_EOF|$FVA_N"
if [[ $r == '//|0|2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
fva_unapp

kt_test_log "budgets (logged): an idle tick 0 dispatches, Alt+1 selecting the covered window (TMyApp + inherited + its leaf's Draw) and a key to the focused leaf through the application"
fva_app 80 24 TMyApp
fva_paint
fva_events 'nothing' 'nothing'
fv.app._getEvent
fvw_budget idle 0 fv.app._getEvent
fvw_writes_on; FVW_WRITES=0; fva_events 'nothing'; fv.app._getEvent; kt_test_log "# writes idle $FVW_WRITES"; fvw_writes_off
alt2() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAlt1; fv.views._virt app HandleEvent; }
fvw_budget alt1 3 alt2
fvw_writes_on; FVW_WRITES=0; fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAlt2; fv.views._virt app HandleEvent; kt_test_log "# writes alt2 $FVW_WRITES"; fvw_writes_off
kt_test_start "Alt+1 / Alt+2 select the window with that number (cmSelectWindowNum broadcast to the desktop), the key handled; == a full repaint"
r="${app__fvdesktop_data[Current]}"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAlt1; fv.views._virt app HandleEvent
r+="|${app__fvdesktop_data[Current]}|$FV_EV_WHAT"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAlt9; fv.views._virt app HandleEvent
r+="|${app__fvdesktop_data[Current]}|$FV_EV_WHAT"
if [[ $r == 'w2|w1|evNothing|w1|evKeyDown' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
down() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbDown; fv.views._virt app HandleEvent; }
fvw_budget key-to-leaf 3 down
fvw_writes_on; FVW_WRITES=0; down; kt_test_log "# writes key-to-leaf $FVW_WRITES"; fvw_writes_off
fva_unapp

kt_test_log "budget (logged): the first paint of the small app (status line + desktop + 2 windows): the two leaves' Draws"
fva_app
FVW_CALLS=0
fvw_budget first-paint 2 fva_paint
fva_unapp
fva_app
fvw_writes_on; FVW_WRITES=0; fva_paint; kt_test_log "# writes first-paint $FVW_WRITES"; fvw_writes_off
fva_unapp

kt_test_start "a user InitStatusLine (its own line, FV_STATUSLINE set) and InitMenuBar (a one-row view, FV_MENUBAR set): inserted in FV's order, the desktop between them"
class TIA : TApplication
    public
        override proc InitStatusLine
        override proc InitMenuBar
end
TIA.InitStatusLine() { TStatusLine.new mysl 0 $(( SizeY - 1 )) "$SizeX" "$SizeY" '~F3~ Open' kbF3 cmOpen; FV_STATUSLINE=mysl; }
TIA.InitMenuBar() { TView.new mybar 0 0 "$SizeX" 1; FV_MENUBAR=mybar; }
build TIA
fva_app 80 24 TIA
fvw_tree app; r=${REPLY//\{*\}/D}
fva_b "$FV_DESKTOP"; r+="|$REPLY|$FV_STATUSLINE|$FV_MENUBAR"
fva_unapp
r+="|${__FV_VW_LIVE[mysl]-gone}${__FV_VW_LIVE[mybar]-gone}"
if [[ $r == 'app[D mysl mybar]*app__fvdesktop|0 1 80 23|mysl|mybar|gonegone' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "an InitDesktop override that makes none: no desktop (FV_DESKTOP ''), Alt+digit / cmTile do nothing, Run still runs"
class TND : TApplication
    public
        override proc InitDesktop
end
TND.InitDesktop() { :; }
build TND
FV_APP_HEADLESS=1 TND.new app
fvw_tree app; r="$REPLY|$FV_DESKTOP"
fva_events 'key kbAlt1' 'cmd cmTile' 'cmd cmQuit'
app.Run; r+="|$__FV_VW_EOF|$FVA_N"
fva_unapp
if [[ $r == 'app[app__fvstatus]||0|3' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "TProgram alone (no terminal part): the same tree and hooks; Done puts them back"
FV_APP_HEADLESS='' TProgram.new prog; rc=$?
r="$rc|$FV_APP|$FV_DESKTOP|$FV_STATUSLINE|$__FV_VW_GETEVENT|$__FV_AP_VIDEO"
prog.delete
r+="|$FV_APP|$__FV_VW_GETEVENT"
if [[ $r == '0|prog|prog__fvdesktop|prog__fvstatus|fv.app._getEvent|0||fv.drivers.getEvent' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "one application at a time: a second TApplication / TProgram is refused (rc 1, one Error line), the first untouched"
fva_app
TApplication.new two 2>"$FVW_TMP/e2"; r1=$?
TProgram.new three 2>>"$FVW_TMP/e2"; r2=$?
mapfile -t el < "$FVW_TMP/e2"
r="$r1 $r2 ${#el[@]} $FV_APP ${__FV_VW_LIVE[two]-none} ${__FV_VW_LIVE[app__fvdesktop]-}"
two.delete 2>/dev/null; three.delete 2>/dev/null
if [[ $r == '1 1 2 app none 1' && ${el[0]} == 'Error: fv.app: TProgram.Create: '* ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] [${el[*]}]"; fi

kt_test_start "re-creating the live application by name: TView's guard repairs and refuses (rc 1, one Error line); the hooks and globals go as at Done"
TApplication.new app 2>"$FVW_TMP/e3"; rc=$?
mapfile -t el < "$FVW_TMP/e3"
r="$rc|${#el[@]}|$FV_APP|$__FV_VW_GETEVENT|${__FV_VW_LIVE[app__fvdesktop]-gone}|${__FV_VW_LIVE[w1]-gone}"
app.delete
if [[ $r == '1|1||fv.drivers.getEvent|gone|gone' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] [${el[*]}]"; fi

kt_test_start "no terminal (not headless, FV_TTY a missing file): TApplication.new is rc 1, nothing made, the hooks untouched"
FV_APP_HEADLESS='' FV_TTY=$FVW_TMP/no-such-tty TApplication.new app; rc=$?
r="$rc|$FV_APP|$__FV_VW_GETEVENT|${__FV_VW_LIVE[app]-none}|${FV_VIDEO_ON:-0}"
app.delete 2>/dev/null
if [[ $r == '1||fv.drivers.getEvent|none|0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_log "002_Run.sh completed"
