#!/usr/bin/env bash
# 012_CallerState.sh - the caller's shell state neither changes what this
# stage's calls do nor is changed by them: one scripted scene (views whose
# names differ only in case: Win / win, Lab / lab; insert, insertBefore,
# makeFirst, putInFrontOf, the navigation, locate / moveTo / growTo,
# changeBounds with GrowMode, makeLocal / makeGlobal / mouseInView,
# GetHelpCtx, refusals on every return path, delete and .delete; the
# drawing of stage 2c-2: a frame with a Cyrillic title cut to its room, a
# shadowed window, drawView, a move, a resize under lock / unlock, the
# border-only redraw under lockScreenUpdate, hide / show, drawPart with the
# writers, getColor, a refused writer, screen cells read back; and at the
# end the constructor guard: a live leaf re-created -> refused with its Error
# line, the tree repaired, insert refusing the bare instance, .delete)
# runs in a child shell under each setup - nocasematch, failglob, nullglob,
# noglob, extglob on and off, globasciiranges off, odd IFS values (digits,
# '-', letters, empty), set -eu with pipefail, a C locale, all at once - and
# must give the reference output; the setup's options, IFS and locale are the
# same after the scene as before. The views are created before the setup
# (kklass's own `.new` is not part of this unit; under an IFS of letters it
# crashes bash, a kklass finding), the calls run after it; the guard part
# needs `.new` and is skipped (and left out of the comparison) under the
# IFS of letters only.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "012: the caller's shell state"

UNIT="$FVW_TESTS_DIR/../fv.views.sh"
STATE='printf "%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}"'
MAKE='
TGroup.new desk 0 1 80 24
TGroup.new Win 0 0 40 20
TGroup.new win 40 0 80 20
TView.new Lab 1 1 10 2
TView.new lab 2 2 12 3
TView.new st 0 22 80 23
TFrame.new frm 0 0 1 1
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=$FVO FV_SCREEN_W=80 FV_SCREEN_H=24; fv.video.initScreen
pf12() {
    fv.views.writeStr 0 0 "Part" 1; fv.views.writeCStr 4 0 "~ok~" 1 2; fv.views.fill 6 0 2 1 "#" 3
    # (D21 stage E: the second row lies past the one-row view; an associative array refused)
    local -a t12=("Ж" "below") a12=(4 55555); local -A m12=([k]=v)
    fv.views.writeLines 8 0 t12 a12; r+="wl$?.$RESULT,"
    fv.views.writeLines 8 0 m12 a12 || r+="wa$?,"
}
cut12() { local LC_ALL=C.UTF-8; fv.video.getRow "$1"; r+="${RESULT:$2:$3}|${REPLY:$2:$3}$4"; }   # (cells of row Y, sliced in UTF-8 whatever the setup)
'
SCENE='
r=""
Win_data[GrowMode]=$FV_GF_GROWALL win_data[GrowMode]=$(( FV_GF_GROWLOX | FV_GF_GROWHIY | FV_GF_GROWREL ))
lab_data[Options]=$FV_OF_SELECTABLE lab_data[HelpCtx]=17
fv.views.insert desk Win; fv.views.insert desk win; fv.views.insertBefore desk st ""
fv.views.insert Win Lab; fv.views.insert Win lab
fvw_tree desk; r+="$REPLY;"
fv.views.makeFirst Win; fv.views.putInFrontOf win Win; fv.views.putInFrontOf Lab lab
fvw_tree desk; r+="$REPLY;"
fv.views.first desk; r+="$RESULT,"; fv.views.last desk; r+="$RESULT,"
fv.views.next Win; r+="$RESULT,"; fv.views.prev Win; r+="$RESULT,"
fv.views.nextView st || r+="nil$?,"; fv.views.prevView win || r+="nil$?;"
fv.views.locate Win -3 2 30 18; fv.views.moveTo Win 1 2; fv.views.growTo Win 33 17
fv.views.changeBounds desk 0 1 120 40
for v in Win win Lab lab st; do fv.views.getBounds "$v"; r+="$v=$RESULT,"; done
r+="abs=${__FV_VW_AX[lab]}:${__FV_VW_AY[lab]}:${__FV_VW_C3[lab]}:${__FV_VW_C4[lab]};"
fv.views.makeLocal lab 20 20; r+="$RESULT,"; fv.views.makeGlobal Lab 0 0; r+="$RESULT,"
if fv.views.mouseInView lab "${__FV_VW_AX[lab]}" "${__FV_VW_AY[lab]}"; then r+=in,; fi
if ! fv.views.mouseInView Lab 0 0; then r+=out,; fi
RESULT=x; Win.GetHelpCtx; r+="help=$RESULT;"
fv.views.insert desk Lab || r+="$?,"
fv.views.insert nosuch Lab || r+="$?,"
fv.views.delete win Lab || r+="$?,"
fv.views.moveTo Win "1*" 2 || r+="$?,"
fv.views.locate Win "a[0]" 0 0 0 || r+="$?,"
fv.views.putInFrontOf Lab win || r+="$?,"
fv.views.first st || r+="$?;"
fv.views.delete Win lab; fvw_tree desk; r+="$REPLY;"
lab.delete; Win.delete
fvw_tree desk; r+="$REPLY"
# the drawing (stage 2c-2): a frame in win (shadowed), the first paint, a
# move, a resize under lock, the border-only redraw under lockScreenUpdate,
# hide / show, drawPart with the writers, getColor, a refused writer, the
# screen cells read back
desk_data[State]=$(( desk_data[State] | FV_SF_EXPOSED )) win_data[State]=$(( win_data[State] | FV_SF_SHADOW ))
win_data[Title]="Кейсы окна" win_data[Flags]=15 win_data[Number]=2
fv.views.locate frm 0 0 20 34; fv.views.insertBefore win frm ""
frm_data[State]=$(( frm_data[State] | FV_SF_ACTIVE ))
fv.views.drawView desk
fv.views.moveTo win 50 2; fv.views.lock desk; fv.views.growTo win 25 18; fv.views.unlock desk
fv.views.lockScreenUpdate; frm_data[State]=$(( frm_data[State] & ~FV_SF_ACTIVE )); fv.views._frameBorder frm; fv.views.unlockScreenUpdate
fv.views.hide st; fv.views.show st; fv.views.drawPart st pf12 0 1 || r+="dp$?,"
fv.views.getColor frm 3; r+="|D=$RESULT,"
fv.views.writeStr 0 0 x 1 || r+="$?,"
cut12 3 48 29 ,
cut12 21 50 27 ,
cut12 23 0 9 ""
# the constructor guard: st (a live leaf in desk) re-created -> refused, the
# tree repaired, insert refuses the bare instance, .delete frees it. Not run
# where the .new of kklass cannot (NOKKNEW: an IFS of letters, see the header)
if [[ -z ${NOKKNEW-} ]]; then
    r+="|G="
    TView.new st 0 0 1 1 2>"$GERR" || r+="$?,"
    IFS= read -r l < "$GERR" || :
    if [[ $l == "Error: fv.views: TView.Create: "?st?" is a live view"* ]]; then r+="E,"; fi
    fvw_tree desk; r+="$REPLY,"
    fv.views.insert desk st 2>/dev/null || r+="$?,"
    if st.delete; then r+=del; fi
    fv.views.isView st || r+=",gone"
fi
printf "%s" "$r"
'
TREEFN=$(declare -f fvw_tree)
run() {   # SETUP -> OUT = before-state # scene output # after-state
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
$TREEFN
GERR='$FVW_TMP/guard.err'
source '$UNIT'
$MAKE
$1
$STATE
printf '#'
$SCENE
printf '#'
$STATE" 2>&1)
}

run ''
ref=${OUT#*#} ref=${ref%#*}
kt_test_start "reference run: the scene as expected"
# win: gfGrowLoX + gfGrowHiY + gfGrowRel: AX (40*120 + 80 shr 1) div 80 = 60,
# BY (20*39 + 23 shr 1) div 23 = 34; Win: gfGrowAll, +40 / +16
want='desk[st {Win[Lab lab]*lab} {win[]}]*win;desk[st {Win[lab Lab]*lab} {win[]}]*win;win,st,st,win,nil1,nil1;'
want+='Win=41 18 74 35,win=60 0 80 34,Lab=1 1 10 2,lab=2 2 12 3,st=0 22 80 23,abs=43:21:53:22;-23 -1,42 20,in,out,help=17;'
want+='1,2,1,2,2,1,2;desk[st {Win[Lab]} {win[]}]*win;desk[st {win[]}]*winwl0.5,wa2,'
# the drawing: getColor frm 3 (win has no palette: app entry 2), the refused
# writer; row 3 = win's top row after the move and the resize (inactive after
# the border-only redraw; the title cut to L = 25-10-6-4 = 5 characters,
# centred; the cells beside it stale: desk has no background); row 21 = win's
# bottom shadow row (its characters kept, symbol V); row 23 = st after
# drawPart (Part, ~ok~ in colours 1 / 2, ## in colour 3, Ж by writeLines in 4)
want+='|D=2,2,  ┌──────── Кейсы ──2─────┐  |00111111111111111111111111122,║                  ║       |22VVVVVVVVVVVVVVVVVVVVVVVVV,'
want+='Partok##Ж|111122334|G=1,E,desk[{win[frm]}]*win,2,del,gone'
if [[ $ref == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$ref] want [$want]"; fi

# (an IFS of letters: kklass's .new crashes bash, so that setup skips the
# guard part (NOKKNEW) and is compared without it)
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' 'shopt -u extglob' \
    'shopt -u globasciiranges' "IFS='0123456789 '" "IFS='-'" "NOKKNEW=1; IFS='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_.'" 'IFS=' \
    'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='-0123456789Ww'; export LC_ALL=C"; do
    kt_test_start "same output and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    want=$ref
    if [[ $setup == NOKKNEW=1* ]]; then want=${ref%|G=*}; fi
    if [[ $got == "$want" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs [$want]; state before [$before] after [$after]"; fi
done


# ---- stage 2c-3: the events scene ------------------------------------------
# root2 > desk2 > bg2, two TWindows whose names differ only in case (Wa, wa)
# with a leaf each, a dialog class (TQDlg): the focus chain and its bits,
# select, a broadcast through message, Tab, a click, the commands, the
# cursor, a modal view ended by a command and one ended by the end of input,
# (stage 2d) cmZoom and back with the zoom icon, a keyboard drag by
# cmResize, a mouse drag by the frame, the close icon's posted cmClose,
# cmClose, screen cells read back. Made before the setup (kklass's .new),
# run after it; under the IFS of letters the dialog's handler calls the
# built-in body instead of kklass's `inherited` (a kklass limit, see 2c-2).
MAKE2='
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=$FVO FV_SCREEN_W=60 FV_SCREEN_H=20; fv.video.initScreen
class TQDlg : TWindow
    public
        override proc HandleEvent
end
TQDlg.HandleEvent() {
    # (kklass: `inherited` fails under an IFS holding letters: that setup
    # (NOINH) calls the built-in body directly)
    if [[ -n ${NOINH-} ]]; then fv.views._windowEvent "$this"; else inherited HandleEvent "$@"; fi
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmYes ]; then fv.views.endModal "$this" cmYes; fv.views.clearEvent "$this"; fi
}
build TQDlg
TGroup.new root2 0 0 60 20; TGroup.new desk2 0 0 60 20; TView.new bg2 0 0 60 20
TWindow.new Wa 1 1 30 12 "Upper" 1; TView.new Wal 1 1 28 10
TWindow.new wa 20 4 58 18 "lower" 2; TView.new wal 1 1 37 13
TQDlg.new qd 10 3 40 12 "Ask" 0
cut2() { local LC_ALL=C.UTF-8; fv.video.getRow "$1"; r+="${RESULT:$2:$3}|${REPLY:$2:$3}$4"; }
'
SCENE2='
r=""
Wal_data[Options]=$FV_OF_SELECTABLE wal_data[Options]=$FV_OF_SELECTABLE
fv.views.insert Wa Wal; fv.views.insert wa wal
fv.views.insert desk2 bg2; fv.views.insert desk2 Wa; fv.views.insert desk2 wa
fv.views.insert root2 desk2
root2_data[State]=$(( root2_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState root2 "$FV_SF_FOCUSED" 1
fv.views.drawView root2
fvw_tree root2; r+="$REPLY;"
fv.views.select Wa; fvw_tree desk2; r+="$REPLY;s=${Wa_data[State]},${wa_data[State]},${Wal_data[State]};"
fv.views.message root2 evBroadcast cmSelectWindowNum 2; r+="m=$?:$RESULT:${desk2_data[Current]};"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbTab; fv.views._virt root2 HandleEvent; r+="t=$FV_EV_WHAT;"
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=3 FV_EV_MOUSE_Y=2 FV_EV_MOUSE_BUTTONS=1; fv.views._virt root2 HandleEvent
r+="c=$FV_EV_WHAT:${desk2_data[Current]};"
fv.views.disableCommands cmAbc; fv.views.getCommands; r+="k=$RESULT;"; fv.views.enableCommands cmAbc
fv.views.setCursor Wal 3 2; fv.views.blockCursor Wal; fv.views.showCursor Wal; r+="u=${__FV_VS_CURX}:${__FV_VS_CURY}:${__FV_VS_CURT};"
fv.views.hideCursor Wal
fvw_events "key kbA" "cmd cmYes"
fv.views.execView desk2 qd; r+="x=$RESULT;"
fvw_events "key kbA"
fv.views.execView desk2 qd; r+="e=$RESULT:$__FV_VW_EOF;"
__FV_VW_EOF=0 __FV_VW_GETEVENT=fv.drivers.getEvent
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmZoom; fv.views._virt root2 HandleEvent
fv.views.getBounds Wa; r+="z=$RESULT:${Wa_data[ZoomRect]};"
cut2 0 55 5 ";"
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmZoom; fv.views._virt root2 HandleEvent
fvw_events "key kbRight" "key kbShiftDown" "key kbEnter"
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmResize; fv.views._virt root2 HandleEvent
fv.views.getBounds Wa; r+="d=$RESULT;"
fvw_events "move 12 3" "nothing" "up 12 3"
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=10 FV_EV_MOUSE_Y=1 FV_EV_MOUSE_BUTTONS=1; fv.views._virt root2 HandleEvent
fv.views.getBounds Wa; r+="g=$RESULT:$FV_EV_WHAT;"
fvw_events "up 7 3"
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=7 FV_EV_MOUSE_Y=3 FV_EV_MOUSE_BUTTONS=1; fv.views._virt root2 HandleEvent
r+="p=${__FV_DR_PEND[3]-}:${__FV_DR_PEND[5]-};"
__FV_DR_PEND=() __FV_VW_EOF=0 __FV_VW_GETEVENT=fv.drivers.getEvent
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmClose; fv.views._virt root2 HandleEvent
fv.views.isView Wa || r+="closed;"
fvw_tree root2; r+="$REPLY;"
cut2 0 20 10 ,
cut2 4 19 23 ""
printf "%s" "$r"
'
EVFN=$(declare -f fvw_getev fvw_events)
run2() {   # SETUP -> OUT
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
$TREEFN
$EVFN
source '$UNIT'
$MAKE2
$1
$STATE
printf '#'
$SCENE2
printf '#'
$STATE" 2>&1)
}

run2 ''
ref2=${OUT#*#} ref2=${ref2%#*}
kt_test_start "events scene, reference run: as expected"
want='root2[{desk2[bg2 {Wa[Wa__fvframe Wal]*Wal} {wa[wa__fvframe wal]*wal}]*wa}]*desk2;'
want+='desk2[bg2 {wa[wa__fvframe wal]*wal} {Wa[Wa__fvframe Wal]*Wal}]*Wa;s=121,9,113;'
want+='m=0:wa:wa;t=evNothing;c=evNothing:Wa;k=cmAbc;u=5:4:2;x=cmYes;e=cmCancel:1;'
want+='z=0 0 60 20:1 1 30 12;[↕]═╗|9A999;d=2 1 31 13;g=4 3 33 15:evNothing;p=cmClose:Wa;closed;'
want+='root2[{desk2[bg2 {wa[wa__fvframe wal]*wal}]*wa}]*desk2;'
want+='          |1111111111, ╔═[■]══════════ lower |1999A999999999999999999'
if [[ $ref2 == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$ref2] want [$want]"; fi

for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' \
    'shopt -u globasciiranges' "IFS='0123456789 '" "IFS='-'" "NOINH=1; IFS='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_.'" 'IFS=' \
    'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='-0123456789Ww'; export LC_ALL=C"; do
    kt_test_start "events scene: same output and the state kept: $setup"
    run2 "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref2" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs [$ref2]; state before [$before] after [$after]"; fi
done
kt_test_log "012_CallerState.sh completed"
