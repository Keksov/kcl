#!/usr/bin/env bash
# 013_Edges.sh - the edges the 2f critic round found (regression tests):
#   * a modal view executed before Run is drawn: the first GetEvent does the
#     application's first paint (the whole application, the dialog in it);
#   * the event driver: Done calls doneEvents when Init called initEvents,
#     also when the caller had turned the terminal on (doneVideo then not);
#   * fv.app.tile / cascade of a plain TGroup too small for its views: no
#     TileError to call, nothing moved, nothing on stderr;
#   * the colours setAppPalette redefined come back at Done (no new
#     application needed);
#   * the live application's name re-created as a view of another class:
#     the next application releases the dead one's state first (its Done
#     then puts fv.views' original hooks back);
#   * the end-of-input latch is put back at Done;
#   * HandleEvent's Alt+digit path keeps RESULT.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "013: edges (2f critic round)"

kt_test_start "a dialog executed before Run: the first GetEvent paints the application with the dialog; Run later paints nothing more"
fva_app 60 16
TWindow.new dlg 10 3 50 12 'About' 0
cap() { fv.video.getRow 3; row=$RESULT; [[ -s $FVW_TMP/screen.out ]] && sent=1; }
row='' sent=0
fva_events 'run cap' 'key kbDown' 'cmd cmCancel'
: > "$FVW_TMP/screen.out"
fv.views.execView "$FV_DESKTOP" dlg
r="$RESULT|$(( (app_data[State] & FV_SF_EXPOSED) != 0 ))|$__FV_AP_SHOWN"
(( sent )) && r+='|sent'
[[ $row == *About* ]] && r+='|about'
fv.video.getRow 0; [[ $RESULT == *░* || $RESULT == *#* ]] && r+='|desk'
declare -F dlg.delete >/dev/null && dlg.delete
if [[ $r == 'cmCancel|1|1|sent|about|desk' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] row3 [$row]"; fi
fva_unapp

kt_test_start "the event driver: initEvents -> doneEvents at Done whoever turned the terminal on; doneVideo only for this Init's terminal"
x=$(
    unset FV_APP_HEADLESS
    fv.video.initVideo() { printf '[iv]'; FV_VIDEO_ON=1 FV_TTY_FD=9; return 0; }
    fv.video.doneVideo() { printf '[dv]'; FV_VIDEO_ON=0; return 0; }
    fv.drivers.initEvents() { printf '[ie]'; return 0; }
    fv.drivers.doneEvents() { printf '[de]'; return 0; }
    exec {o}>/dev/null; FV_VIDEO_OUT_FD=$o
    FV_VIDEO_ON=1 FV_TTY_FD=9
    TApplication.new app; app.delete; printf '|'
    FV_VIDEO_ON=0
    TApplication.new app; app.delete; printf '|'
    fv.drivers.initEvents() { printf '[ie-fail]'; return 1; }
    TApplication.new app; app.delete
)
if [[ $x == '[iv][ie][de]|[iv][ie][de][dv]|[iv][ie-fail][dv]' ]]; then kt_test_pass "ok"; else kt_test_fail "[$x]"; fi

kt_test_start "fv.app.tile / cascade of a plain TGroup in too small a rect: nothing called, nothing moved, rc 0, stderr clean"
fva_app 60 16
TGroup.new g 0 0 20 10
TView.new gv1 0 0 3 2; TView.new gv2 4 0 7 2
gv1_data[Options]=$FV_OF_TILEABLE gv2_data[Options]=$FV_OF_TILEABLE
fv.views.insert g gv1; fv.views.insert g gv2
fv.views.insert "$FV_DESKTOP" g
q=''
fv.app.tile g 0 0 1 1 2>"$FVW_TMP/e13"; q+="$?,"
fv.app.cascade g 0 0 1 1 2>>"$FVW_TMP/e13"; q+="$?,"
fva_b gv1; q+="$REPLY,"; fva_b gv2; q+="$REPLY"
[[ -s $FVW_TMP/e13 ]] && q+='|stderr'
g.delete
if [[ $q == '0,0,0 0 3 2,4 0 7 2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$q] [$(< "$FVW_TMP/e13")]"; fi
fva_unapp

kt_test_start "setAppPalette's redefinitions come back at Done (in place and allocated); a new application is not needed"
fva_app
for (( u = 1; u <= 127; u++ )); do
    s=${__FV_VW_APAL:u-1:1} n=0
    for (( i = 0; i < ${#__FV_VW_APAL}; i++ )); do [ "${__FV_VW_APAL:i:1}" = "$s" ] && n=$(( n + 1 )); done
    (( n == 1 )) && break
done
c0=${__FV_VS_PAL[$s]}
fv.app.setAppPalette "$u" 200 17 1
fv.app.setAppPalette "$u" 201 18 0
fv.app.setAppPalette 2 9 4 0
a=${__FV_VW_APAL:1:1}
r="${__FV_VS_PAL[$s]}|$a"
fva_unapp
r+="|${__FV_VS_PAL[$s]}|${#__FV_AP_SAVED[@]}"
[[ $__FV_VW_APAL == "$__FV_AP_DEFPAL" ]] && r+='|def'
if [[ $r == "201 18 0|X|$c0|0|def" ]]; then kt_test_pass "ok (entry $u, symbol $s)"; else kt_test_fail "[$r] c0 [$c0]"; fi

kt_test_start "the application's name re-created as a TWindow: the next application releases the dead one; its Done puts the original hooks back"
fva_app 40 12
TWindow.new app 0 0 10 5 t 1 2>"$FVW_TMP/e13b"; rc=$?
declare -F app.delete >/dev/null && app.delete
fva_noevents
r="$rc|$FV_APP"
FV_APP_HEADLESS=1 TApplication.new app2
r+="|$FV_APP|$__FV_AP_SGET"
app2.delete
r+="|$__FV_VW_GETEVENT|$__FV_VW_PUTEVENT|$__FV_VW_ERRSYM|[$FV_APP]"
if [[ $r == '1|app|app2|fv.drivers.getEvent|fv.drivers.getEvent|fv.drivers.putEvent|0|[]' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "the end-of-input latch: 1 while the ended application lives, put back (0) at Done"
fva_app 40 12
fva_events 'key kbDown'
app.Run
r="$__FV_VW_EOF"
fva_unapp
r+="|$__FV_VW_EOF"
if [[ $r == '1|0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "HandleEvent's Alt+digit path: the broadcast's answer (the window) does not leak into RESULT (TGroup's handler leaves it '' as in fv.views)"
fva_app 40 12
fva_paint
RESULT=keep
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAlt1
fv.app._progEvent app
r="[$RESULT]|$FV_EV_WHAT"
if [[ $r == '[]|evNothing' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
fva_unapp

kt_test_log "013_Edges.sh completed"
