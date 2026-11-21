#!/usr/bin/env bash
# 011_ZeroFork.sh - fv.views never forks (PLAN.md rule 1; design §1.3: every
# plain function is fork-free):
#   * with PATH='' (no external command can run): both stages' paths —
#     construction, the tree, navigation, geometry with GrowMode, the
#     elision through a user override, the guard and its repair, .delete,
#     and the drawing (a frame with a shadowed owner, drawView, redraw, a
#     move, lock / unlock, the border-only redraw, hide / show, drawPart
#     with every writer, getColor), and stage 2c-3's (a TWindow, the focus
#     chain, select / focusNext / selectNext, message, a key through the
#     dispatch, commands, the cursor, a modal view with a scripted event
#     source ending at the end of input, mouseEvent, endModal, cmClose)
#     and stage 2d's (cmZoom twice, a keyboard drag by cmResize, a mouse
#     drag by the frame's top row with the drain, the close icon, dragView)
#     — and (P3 3b) scroll bars and lists;
#     works and prints no "command not found";
#   * the static scan (fv.video's 006 scanner): no $( ), backtick, process
#     substitution, pipe, ( ) subshell, & or coproc on any code line of
#     fv.views.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: no forks"

# (stage 2c-3's part, sourced by the child after PATH='')
cat > "$FVW_TMP/ev011.sh" <<'EOF'
desk_data[State]=$(( desk_data[State] | FV_SF_SELECTED | FV_SF_MODAL )); fv.views.setState desk "$FV_SF_FOCUSED" 1
TWindow.new tw 40 2 70 12 Ev 2; TView.new tl 1 1 29 9; tl_data[Options]=$FV_OF_SELECTABLE
fv.views.insert tw tl; fv.views.insert desk tw
q=()
ge() {
    if (( ! ${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    local s=${q[0]}
    q=("${q[@]:1}")
    FV_EV_WHAT=${s%%:*} s=${s#*:}
    FV_EV_KEY=$s FV_EV_COMMAND=${s%%:*} FV_EV_INFO=${s#*:} FV_EV_MOUSE_X=${s%%:*} FV_EV_MOUSE_Y=${s#*:}
}
__FV_VW_GETEVENT=ge
fv.views.select w1; fv.views.select tw; fv.views.focusNext desk 0; fv.views.selectNext desk 1
fv.views.message desk evBroadcast cmSelectWindowNum 2; e="|$RESULT"
FV_EV_WHAT=evKeyDown FV_EV_KEY=kbTab; fv.views._virt desk HandleEvent; e+=",$FV_EV_WHAT"
fv.views.disableCommands cmX; fv.views.enableCommands cmX; fv.views.commandEnabled cmQuit; fv.views.setCommands cmZoom; fv.views.getCommands; e+=",$RESULT"
fv.views.setCursor tl 2 3; fv.views.showCursor tl; fv.views.blockCursor tl; e+=",$__FV_VS_CURX:$__FV_VS_CURY:$__FV_VS_CURT"
fv.views.hideCursor tl; fv.views.normalCursor tl
TWindow.new dl 5 5 30 15 Dlg 0
q=(evKeyDown:kbTab evCommand:cmClose: evMouseDown:45:5)
fv.views.execView desk dl; e+=",$RESULT"
__FV_VW_EOF=0
q=(evMouseMove:46:6 evKeyDown:kbA evMouseUp:46:6)
fv.views.mouseEvent tw "$FV_EM_MOUSEMOVE"; e+=",$?:$FV_EV_MOUSE_X"
fv.views.mouseEvent tw "$FV_EM_MOUSEMOVE" || e+=",$?"
fv.views.endModal tw cmQuit; e+=",${desk_data[EndState]}"
FV_EV_WHAT=evCommand FV_EV_COMMAND=cmClose FV_EV_INFO=''; fv.views._virt desk HandleEvent
fv.views.isView tw || e+=",closed"
dl.delete
r+=$e
# stage 2d: cmZoom twice, a keyboard drag by cmResize, a mouse drag by the
# frame's top row (with the drain), the close icon, dragView called directly
TWindow.new zw 10 3 40 13 Z 3; fv.views.insert desk zw
__FV_VW_EOF=0
FV_EV_WHAT=evCommand FV_EV_COMMAND=cmZoom FV_EV_INFO=''; fv.views._virt desk HandleEvent; e="|${zw_data[SizeX]}"
FV_EV_WHAT=evCommand FV_EV_COMMAND=cmZoom FV_EV_INFO=''; fv.views._virt desk HandleEvent; e+=",${zw_data[SizeX]}"
q=(evKeyDown:kbRight evKeyDown:kbShiftDown evKeyDown:kbEnter)
FV_EV_WHAT=evCommand FV_EV_COMMAND=cmResize FV_EV_INFO=''; fv.views._virt desk HandleEvent; fv.views.getBounds zw; e+=",$RESULT"
q=(evMouseMove:26:6 evMouseUp:26:6)
FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=25 FV_EV_MOUSE_Y=4 FV_EV_MOUSE_DOUBLE=0; fv.views._virt desk HandleEvent; fv.views.getBounds zw; e+=",$RESULT"
q=(evMouseUp:15:6)
FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=15 FV_EV_MOUSE_Y=6; fv.views._virt desk HandleEvent; e+=",${__FV_DR_PEND[3]-}"
__FV_DR_PEND=()
q=(evKeyDown:kbEnter); fv.views.dragView zw 1 0 0 80 23 16 6 80 23; e+=",$?"
zw.delete
r+=$e
EOF

kt_test_start "PATH='': the stage's whole path works, no external command is looked for"
out=$("$BASH" -c "
source '$FVW_TESTS_DIR/../fv.views.sh'
class TU : TView
    public
        override proc SizeLimits
end
TU.SizeLimits() { inherited SizeLimits; FV_MIN_X=4; }
build TU
PATH=''
r=''
TGroup.new desk 0 1 80 24; r+=\$?
TGroup.new w1 0 0 40 20; TU.new u 1 1 2 2; TView.new v 0 0 3 3
w1_data[GrowMode]=\$FV_GF_GROWALL u_data[GrowMode]=\$(( FV_GF_GROWHIX | FV_GF_GROWREL ))
fv.views.insert desk w1; fv.views.insert w1 u; fv.views.insertBefore w1 v ''; r+=\$?
fv.views.makeFirst v; fv.views.putInFrontOf v ''; fv.views.first w1; r+=\$RESULT
fv.views.next u; fv.views.prev u; fv.views.nextView u; fv.views.prevView u || :
fv.views.locate u 0 0 1 1; fv.views.getBounds u; r+=\"|\$RESULT\"
fv.views.moveTo w1 5 5; fv.views.growTo w1 30 15; fv.views.changeBounds desk 0 1 100 30
fv.views.getBounds w1; r+=\"|\$RESULT\"
fv.views.makeLocal u 9 9; fv.views.makeGlobal u 0 0; fv.views.mouseInView u 0 0 || :
w1.GetHelpCtx; fv.views.delete w1 v
exec {o}>/dev/null; FV_VIDEO_OUT_FD=\$o; fv.video.initScreen
desk_data[State]=\$(( desk_data[State] | FV_SF_EXPOSED )) w1_data[State]=\$(( w1_data[State] | FV_SF_SHADOW ))
w1_data[Title]=Zero w1_data[Flags]=15 w1_data[Number]=3
TFrame.new fr 0 0 30 15; fv.views.insertBefore w1 fr ''
fr_data[State]=\$(( fr_data[State] | FV_SF_ACTIVE ))
pf() { fv.views.writeStr 0 0 'part' 1; fv.views.fill 0 0 1 1 '#' 2; fv.views.writeCStr 0 0 'a~b~' 1 2; fv.views.writeLine 0 0 1 x 1; local -a t=(x) a=(1); fv.views.writeLines 0 0 t a; fv.views.writeChar 0 0 y 1; }
fv.views.drawView desk; fv.views.redraw w1; fv.views.moveTo w1 6 6
fv.views.lock desk; fv.views.growTo w1 31 16; fv.views.unlock desk
fv.views.lockScreenUpdate; fv.views._frameBorder fr; fv.views.unlockScreenUpdate
fv.views.hide w1; fv.views.show w1; fv.views.makeFirst u; fv.views.drawPart u pf 0 1
fv.views.getColor fr 5; r+=\"|\$RESULT\"
fv.video.getRow 7; r+=\"|\${RESULT:6:9}|\${REPLY:6:9}\"
source '$FVW_TMP/ev011.sh'
TView.new u 0 0 1 1 2>/dev/null || r+=\"|guard\$?\"
TView.new x__fvy 0 0 1 1 2>/dev/null || r+=\"|res\$?\"
fv.views._newReserved w1 frame TView 0 0 1 1; r+=\"|\$RESULT\"
u.delete; v.delete; x__fvy.delete; desk.delete
printf '%s' \"\$r\"" 2>&1)
want='00u|0 0 4 1|25 11 55 26|3|ybrt]════|121122222|tw,evNothing,cmZoom,43:7:2,cmCancel,0:46,1,cmQuit,closed|100,30,11 3 41 14,12 5 42 16,cmClose,0|guard1|res2|w1__fvframe'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "PATH='' (P3 3b): scroll bars and lists — standardScrollBar, scrollBarSet, keys, the wheel, a click with a drag and auto-repeat, the bar's mouse, Marks, a formatter, multi-column, CJK rows (writeRows), ctrlToArrow"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVW_TESTS_DIR/../fv.views.sh'
exec {o}>/dev/null; FV_VIDEO_OUT_FD=\$o FV_SCREEN_W=80 FV_SCREEN_H=24; fv.video.initScreen
TGroup.new root 0 0 80 24; TView.new bg 0 0 80 24; fv.views.insert root bg
root_data[State]=\$(( root_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState root \"\$FV_SF_FOCUSED\" 1
PATH=''
r=''
TWindow.new w 0 0 40 23 L 1; fv.views.standardScrollBar w \"\$FV_SB_VERTICAL\"; sb=\$RESULT
TListViewer.new l 1 1 39 22 1 '' \"\$sb\"; r+=\$?
A=(); for (( i = 0; i < 300; i++ )); do A[i]=\"n\$i\"; done
declare -A M=([3]=1)
l_data[List]=A l_data[Marks]=M; fv.views.listSetRange l 300; fv.views.insert w l; fv.views.insert root w
fv.views.drawView root
q=()
ge() {
    if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    local s=\${q[0]}; q=(\"\${q[@]:1}\")
    fv.drivers.clearEvent
    FV_EV_WHAT=\${s%%:*} s=\${s#*:}; FV_EV_MOUSE_X=\${s%%:*} FV_EV_MOUSE_Y=\${s#*:} FV_EV_MOUSE_BUTTONS=1
}
__FV_VW_GETEVENT=ge
k() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=\$1 FV_EV_CHAR=\${2-}; fv.views._virt root HandleEvent; }
m() { local w=\$1 x=\$2 y=\$3; shift 3; q=(\"\$@\"); fv.drivers.clearEvent; FV_EV_WHAT=\$w FV_EV_MOUSE_X=\$x FV_EV_MOUSE_Y=\$y FV_EV_WHEEL=2 FV_EV_MOUSE_BUTTONS=1; fv.views._virt root HandleEvent; __FV_VW_EOF=0; }
k kbDown; k kbPgDn; k kbCtrlX; k kbChar ' '; k kbIns; k kbEnd; k kbHome; k kbCtrlPgDn; r+=\",\${l_data[Focused]}:\${l_data[TopItem]}\"
m evMouseWheel 10 5; m evMouseDown 10 3 evMouseMove:10:8 evMouseAuto:10:24 evMouseAuto:10:24 evMouseUp:10:24
r+=\",\${l_data[Focused]}:\${l_data[TopItem]}\"
m evMouseDown 39 21 evMouseAuto:39:21 evMouseUp:39:21; m evMouseDown 39 2 evMouseMove:39:12 evMouseUp:39:12
r+=\",\${l_data[TopItem]}\"
fv.views.scrollBarSet \"\$sb\" setValue 5; fv.views.listSetTopItem l 7; fv.views.listFocusItem l 9; fv.views.listDrawItem l 9
f() { RESULT=\"F\$1\"; }; l_data[Formatter]=f; fv.views.drawView l; l_data[Formatter]=''
TWindow.new w2 40 0 80 23 C 2; TListViewer.new l2 1 1 39 22 3; fv.views.insert w2 l2; fv.views.insert root w2
B=(报告文件_1 数据项目_2 系统管理_3); l2_data[List]=B; fv.views.listSetRange l2 3
TListViewer.new l3 1 1 39 22; C=(报告 文件); l3_data[List]=C; fv.views.listSetRange l3 2
fv.views.delete w2 l2; fv.views.insert w2 l3; fv.views.drawView root
fv.views.ctrlToArrow kbCtrlE; r+=\",\$RESULT\"
printf '%s' \"\$r\"" 2>&1)
want='0,20:0,8:1,146,kbUp'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "the scanner flags a fork construct in a sample line and passes the safe ones"
bad=''
for s in 'x=$(cmd)' 'x=`cmd`' 'a | b' '( cd x )' 'cmd &' 'coproc cat'; do fvw_forks "$s" || bad+=" missed:[$s]"; done
for s in '(( a | b ))' 'x="$(( 1 + 2 ))"' '[[ a || b ]]' 'f() {' 'a=( 1 2 )' 'x >&2'; do if fvw_forks "$s"; then bad+=" false:[$s]"; fi; done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "fv.views.sh: no fork construct on any code line"
bad='' n=0 fn=''
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^([A-Za-z_][A-Za-z0-9_.]*)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if fvw_forks "$l"; then bad+=" $n(${fn:-file}):[$l]"; fi
done < "$FVW_TESTS_DIR/../fv.views.sh"
if [[ -z $bad ]] && (( n > 300 )); then kt_test_pass "$n lines clean"; else kt_test_fail "${bad:-only $n lines}"; fi

kt_test_log "011_ZeroFork.sh completed"
