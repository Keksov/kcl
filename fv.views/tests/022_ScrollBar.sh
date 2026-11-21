#!/usr/bin/env bash
# 022_ScrollBar.sh - TScrollBar (P3 stage 3b; design P3 §1.2-1.5, §2.3, §2.7,
# §3.3; FV views.inc TScrollBar):
#   * construction: the fields, GrowMode by orientation, EventMask + the
#     wheel; FV's look (▲ ▒ ■ ▼, ◄ ►, ▓ when Max = Min) in CScrollBar's
#     colours, the indicator at FV's GetPos, short bars;
#   * fv.views.scrollBarSet in every form (SetParams, SetValue, VALUE MIN MAX,
#     setValue / setRange / setStep), the clamping, the refusals, RESULT kept;
#   * P3-4: a value change that keeps the indicator's cell draws nothing, a
#     moved indicator one drawPart (one write), a range change the whole bar;
#     the screen == a full repaint;
#   * ScrollDraw: cmScrollBarChanged to the owner when the value changed
#     (FV_EV_INFO the bar, FV_EV_ID its Id; the steps a handler sees are the
#     old ones), cmIdCommunicate to the top view for an Id (another bar with
#     that Id follows; a bar ignores its own; an integer FV_EV_INFO is the
#     value), Clicked (cmScrollBarClicked) on keys, the wheel and the mouse;
#   * keys of a bar with ofPostProcess (vertical, horizontal, WordStar through
#     fv.views.ctrlToArrow), a hidden bar ignores them; the wheel (a double
#     wheel event: 6 when ArStep is 1);
#   * the mouse: the arrows, the page parts, evMouseAuto repeating while the
#     mouse stays on the part, the indicator dragged (inside / outside), a
#     lost release ended by a key (the key put back);
#   * overrides of ScrollStep (func) / ScrollDraw reached through the
#     elision (2 dispatches each use), the built-ins 0;
#   * fv.views.standardScrollBar (FV TWindow.StandardScrollBar);
#   * a caller in the C locale gets the same cells as a UTF-8 one (the
#     horizontal row cut before its glyphs go in), in both video modes.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "022: TScrollBar"

# col X Y H -> RESULT = the column's characters on rows Y .. Y+H-1, REPLY = symbols
col() {
    local y t='' s=''
    for (( y = $2; y < $2 + $3; y++ )); do fv.video.getRow "$y"; t+=${RESULT:$1:1}; s+=${REPLY:$1:1}; done
    RESULT=$t REPLY=$s
}
# a listener: a leaf whose HandleEvent (an override) records each broadcast /
# command as CMD:INFO:ID:value-of-the-sender:its-PgStep;
class TSbL : TView
    public
        override proc HandleEvent
end
TSbL.HandleEvent() {
    if [ "$FV_EV_WHAT" = evBroadcast ] || [ "$FV_EV_WHAT" = evCommand ]; then
        local v='' p=''
        if fv.views.isView "$FV_EV_INFO"; then
            local -n __l_s=${FV_EV_INFO}_data
            v=${__l_s[Value]-} p=${__l_s[PgStep]-}
        fi
        SBLOG+="$FV_EV_COMMAND:$FV_EV_INFO:$FV_EV_ID:$v:$p;"
    fi
}
build TSbL
SBLOG=''
# nmsg CMD -> REPLY = how many CMD entries SBLOG holds
nmsg() { local t=${SBLOG//"$1"/#}; t=${t//[!#]/}; REPLY=${#t}; }

fvw_screen 40 12
TGroup.new root 0 0 40 12
TView.new bg 0 0 40 12; fv.views.insert root bg
fvw_expose root
TScrollBar.new vb 30 1 31 11
TScrollBar.new hb 2 11 22 12
fv.views.insert root vb
fv.views.insert root hb

kt_test_start "construction: Value Min Max 0, PgStep ArStep 1, Id 0; GrowMode by orientation (FV); EventMask + evMouseWheel"
r="${vb_data[Value]} ${vb_data[Min]} ${vb_data[Max]} ${vb_data[PgStep]} ${vb_data[ArStep]} ${vb_data[Id]} ${vb_data[GrowMode]} ${hb_data[GrowMode]} ${vb_data[EventMask]}"
want="0 0 0 1 1 0 $(( FV_GF_GROWLOX | FV_GF_GROWHIX | FV_GF_GROWHIY )) $(( FV_GF_GROWLOY | FV_GF_GROWHIX | FV_GF_GROWHIY )) $(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND | FV_EM_MOUSEWHEEL ))"
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

fv.views.drawView root
kt_test_start "Max = Min: ▲ ▓ … ▼ (arrows colour 2, the area colour 1: CScrollBar 4 5 5 -> the app palette's 5 / 4); horizontal ◄ ▓ … ►"
col 30 1 10; a="$RESULT|$REPLY"
fvw_cells 2 11 20; b="$RESULT|$REPLY"
if [[ $a == '▲▓▓▓▓▓▓▓▓▼|5444444445' && $b == '◄▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓►|54444444444444444445' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi

kt_test_start "the indicator at FV's GetPos ((Value-Min)*(Size-3) + Range/2) div Range + 1, in colour 3; every value of 0..100 on both bars"
bad=''
for v in 0 7 14 15 50 57 92 93 99 100; do
    fv.views.scrollBarSet vb "$v" 0 100
    fv.views.scrollBarSet hb "$v" 0 100
    p=$(( (v * 7 + 50) / 100 + 1 )) q=$(( (v * 17 + 50) / 100 + 1 ))
    want='▲▒▒▒▒▒▒▒▒▼' want=${want:0:p}■${want:p+1} wa=5444444445 wa=${wa:0:p}5${wa:p+1}
    col 30 1 10
    [[ "$RESULT|$REPLY" == "$want|$wa" ]] || bad+=" [v$v vb $RESULT|$REPLY want $want|$wa]"
    want='◄▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒►' want=${want:0:q}■${want:q+1}
    fvw_cells 2 11 20
    [[ $RESULT == "$want" && ${REPLY:q:1} == 5 ]] || bad+=" [v$v hb $RESULT|$REPLY]"
done
if [[ -z $bad ]] && fvw_full root; then kt_test_pass "ok"; else kt_test_fail "$bad $FVW_DIFF"; fi

kt_test_start "short bars: a 2-row vertical bar draws ▲ and the area row (FV's size 3 minimum), a 2-wide horizontal one ◄ and its area (Max = Min)"
TScrollBar.new sb2 34 1 35 3; fv.views.insert root sb2
TScrollBar.new sb3 36 1 38 2; fv.views.insert root sb3
fv.views.scrollBarSet sb2 0 0 5
col 34 1 2; a=$RESULT
fvw_cells 36 1 2; b=$RESULT
if [[ $a == '▲■' && $b == '◄▓' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi
fv.views.delete root sb2; sb2.delete; fv.views.delete root sb3; sb3.delete

kt_test_start "scrollBarSet forms: SB V (SetValue), SB V MIN MAX, SB V MIN MAX PG AR (SetParams), setValue / setRange / setStep; RESULT kept"
RESULT=keep
fv.views.scrollBarSet vb 5 0 50 7 2; a="${vb_data[Value]} ${vb_data[Min]} ${vb_data[Max]} ${vb_data[PgStep]} ${vb_data[ArStep]}"
fv.views.scrollBarSet vb 9; a+=",${vb_data[Value]}"
fv.views.scrollBarSet vb 3 1 20; a+=",${vb_data[Value]} ${vb_data[Min]} ${vb_data[Max]} ${vb_data[PgStep]}"
fv.views.scrollBarSet vb setValue 12; a+=",${vb_data[Value]}"
fv.views.scrollBarSet vb setRange 0 10; a+=",${vb_data[Value]} ${vb_data[Max]}"
fv.views.scrollBarSet vb setStep 4 3; a+=",${vb_data[PgStep]} ${vb_data[ArStep]} $RESULT"
if [[ $a == '5 0 50 7 2,9,3 1 20 7,12,10 10,4 3 keep' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a]"; fi

kt_test_start "clamping (FV SetParams): MAX below MIN -> MIN, VALUE into MIN..MAX; refusals rc 2 with RESULT '' (not a bar, not integers, a count)"
fv.views.scrollBarSet vb 99 10 5; a="${vb_data[Value]} ${vb_data[Min]} ${vb_data[Max]}"
fv.views.scrollBarSet vb -4 0 8; a+=",${vb_data[Value]}"
r=''
fv.views.scrollBarSet root 1 || r+="$?[$RESULT]"
fv.views.scrollBarSet vb x || r+="$?[$RESULT]"
fv.views.scrollBarSet vb 1 2 || r+="$?"
fv.views.scrollBarSet vb setRange 1 || r+="$?"
fv.views.scrollBarSet nosuch 1 || r+="$?"
if [[ $a == '10 10 10,0' && $r == '2[]2[]222' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$r]"; fi

kt_test_start "P3-4: the indicator kept -> nothing drawn; moved -> one write (a drawPart over its rows); a range change -> the bar whole; == a full repaint"
fv.views.scrollBarSet vb 0 0 1000 1 1
fvw_writes_on; FVW_WRITES=0
fv.views.scrollBarSet vb 50; a=$FVW_WRITES
FVW_WRITES=0; fv.views.scrollBarSet vb 400; a+=" $FVW_WRITES"
FVW_WRITES=0; fv.views.scrollBarSet vb 1000; a+=" $FVW_WRITES"
FVW_WRITES=0; fv.views.scrollBarSet vb 1000 0 2000; a+=" $FVW_WRITES"
fvw_writes_off
if [[ $a == '0 1 1 1' ]] && fvw_full root; then kt_test_pass "writes [$a]"; else kt_test_fail "writes [$a] (want 0 1 1 1) $FVW_DIFF"; fi

kt_test_start "ScrollDraw: cmScrollBarChanged to the owner on a value change only (INFO = the bar, ID = Id, the old PgStep seen); none for a range change that keeps the value"
TSbL.new lis 0 0 1 1; lis_data[EventMask]=$(( 0xFFFF )); fv.views.insert root lis
fv.views.scrollBarSet vb 0 0 100 1 1
SBLOG=''
fv.views.scrollBarSet vb 30 0 100 9 1; a=$SBLOG
SBLOG=''; fv.views.scrollBarSet vb 30 0 200; b=$SBLOG
vb_data[Id]=4
SBLOG=''; fv.views.scrollBarSet vb 31; c=$SBLOG
vb_data[Id]=0
if [[ $a == 'cmScrollBarChanged:vb:0:30:1;' && -z $b && $c == 'cmScrollBarChanged:vb:4:31:9;' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi

kt_test_start "cmIdCommunicate (Id 7): the top view's other bar with Id 7 follows (ofPostProcess), the sender ignores its own; an integer INFO is the value"
fvw_root root
TScrollBar.new vc 32 1 33 11; fv.views.insert root vc
vb_data[Id]=7 vc_data[Id]=7
vb_data[Options]=$(( vb_data[Options] | FV_OF_POSTPROCESS )) vc_data[Options]=$(( vc_data[Options] | FV_OF_POSTPROCESS ))
fv.views.scrollBarSet vc 0 0 100
fv.views.scrollBarSet vb 0 0 100
fv.views.scrollBarSet vb 40; a="${vb_data[Value]} ${vc_data[Value]}"
fv.views._message root evCommand cmIdCommunicate 25 7; a+=",$? ${vb_data[Value]} ${vc_data[Value]}"
fv.views._message root evCommand cmIdCommunicate 60 8 || a+=",nobody ${vb_data[Value]}"
if [[ $a == '40 40,0 25 25,nobody 25' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a]"; fi
vb_data[Id]=0 vc_data[Id]=0 vb_data[Options]=0 vc_data[Options]=0
fv.views.delete root vc; vc.delete

# keys: KEY... through the root's dispatch (the bar gets keys in phPostProcess)
keys() {
    local k
    REPLY=''
    for k; do
        fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$k
        fv.views._virt root HandleEvent
        REPLY+="${!KB}"
        if [ "$FV_EV_WHAT" = evKeyDown ]; then REPLY+='p'; fi
        REPLY+=' '
    done
    REPLY=${REPLY% }
}
kt_test_start "keys of a vertical bar (ofPostProcess): Up / Down by ArStep, PgUp / PgDn by PgStep, Ctrl+PgUp / Ctrl+PgDn to Min / Max, WordStar E X R C; Left passes; Clicked each time"
vb_data[Options]=$FV_OF_POSTPROCESS
fv.views.scrollBarSet vb 5 0 20 3 1
KB='vb_data[Value]'
SBLOG=''
keys kbDown kbDown kbUp kbPgDn kbPgUp kbPgUp kbCtrlPgDn kbCtrlPgUp kbCtrlX kbCtrlC kbCtrlE kbCtrlR kbLeft kbRight
k=$REPLY
nmsg cmScrollBarClicked
if [[ $k == '6 7 6 9 6 3 20 0 1 4 3 0 0p 0p' && $REPLY == 12 && $SBLOG == cmScrollBarClicked:vb:0:5:* ]]; then kt_test_pass "ok"; else kt_test_fail "[$k] clicks $REPLY [${SBLOG:0:80}]"; fi
kt_test_start "keys of a horizontal bar: Left / Right, Ctrl+Left / Ctrl+Right (page), Home / End, WordStar S D A F; Up passes; a hidden bar takes none"
vb_data[Options]=0 hb_data[Options]=$FV_OF_POSTPROCESS
fv.views.scrollBarSet hb 5 0 20 4 2
KB='hb_data[Value]'
keys kbRight kbLeft kbLeft kbCtrlRight kbCtrlLeft kbEnd kbHome kbCtrlD kbCtrlF kbCtrlS kbCtrlA kbUp
a=$REPLY
fv.views.hide hb
keys kbRight
b=$REPLY
fv.views.show hb
if [[ $a == '7 5 3 7 3 20 0 2 20 18 0 0p' && $b == '0p' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi
hb_data[Options]=0

kt_test_start "fv.views.ctrlToArrow: FV's eleven WordStar keys, anything else unchanged"
r=''
for k in kbCtrlS kbCtrlD kbCtrlE kbCtrlX kbCtrlA kbCtrlF kbCtrlG kbCtrlV kbCtrlR kbCtrlC kbCtrlH kbCtrlB kbDown ''; do fv.views.ctrlToArrow "$k"; r+="$RESULT,"; done
fv.views.ctrlToArrow || r+="$?"
if [[ $r == 'kbLeft,kbRight,kbUp,kbDown,kbHome,kbEnd,kbDel,kbIns,kbPgUp,kbPgDn,kbBack,kbCtrlB,kbDown,,2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

# mouse V EVENT X Y [SPECS...] — the scripted events SPECS queued, the event
# delivered to the root at X Y; REPLY = the bar's Value
wheel() {
    fvw_events
    fv.drivers.clearEvent; FV_EV_WHAT=evMouseWheel FV_EV_MOUSE_X=$2 FV_EV_MOUSE_Y=$3 FV_EV_WHEEL=$4 FV_EV_MOUSE_DOUBLE=${5:-0}
    fv.views._virt root HandleEvent
    REPLY+="${!KB}"
    if [ "$FV_EV_WHAT" != evNothing ]; then REPLY+='p'; fi
    REPLY+=' '
}
kt_test_start "the wheel: down / up by ArStep, a double wheel event by 6 when ArStep is 1 (FV), by ArStep otherwise; Clicked"
KB='vb_data[Value]'
fv.views.scrollBarSet vb 20 0 50 5 1
REPLY='' SBLOG=''
wheel vb 30 5 2; wheel vb 30 5 1; wheel vb 30 5 1; wheel vb 30 5 2 1; wheel vb 30 5 1 1
fv.views.scrollBarSet vb setStep 5 3
wheel vb 30 5 2 1
k=$REPLY
nmsg cmScrollBarClicked
fvw_noevents
if [[ $k == '21 20 19 25 19 22 ' && $REPLY == 6 ]]; then kt_test_pass "ok"; else kt_test_fail "[$k] clicks $REPLY"; fi

# click X Y SPECS... — a mouse-down at X Y delivered to the root, the specs
# after it read by the bar's tracking loop; REPLY = Value, FVW_EVN = reads
click() {
    local x=$1 y=$2
    shift 2
    fvw_events "$@"
    fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$x FV_EV_MOUSE_Y=$y FV_EV_MOUSE_BUTTONS=1
    fv.views._virt root HandleEvent
    REPLY=${!KB}
    if [ "$FV_EV_WHAT" != evNothing ]; then REPLY+='p'; fi
    fvw_noevents
}
kt_test_start "the mouse on the arrows and the page parts: one step at the press (FV), PgStep beside the indicator, Clicked at the press and the release"
fv.views.scrollBarSet vb 50 0 100 10 1
r=''
SBLOG=''; click 30 10 'up 30 10'; r+="$REPLY "; nmsg cmScrollBarClicked; r+="$REPLY "
click 30 1 'up 30 1'; r+="$REPLY "
click 30 1 'up 30 1'; r+="$REPLY "
click 30 9 'up 30 9'; r+="$REPLY "
click 30 2 'up 30 2'; r+="$REPLY"
if [[ $r == '51 2 50 49 59 49' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "evMouseAuto repeats the step while the mouse stays on the part (the auto events' place), none off it; the release ends it"
fv.views.scrollBarSet vb 50 0 100 10 1
click 30 10 'auto 30 10' 'auto 30 10' 'auto 30 5' 'auto 30 10' 'up 30 10'; a="$REPLY:$FVW_EVN"
click 30 1 'move 31 3' 'auto 30 1' 'up 30 1'; b="$REPLY:$FVW_EVN"
if [[ $a == '54:5' && $b == '52:3' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] (want 54:5 52:3)"; fi

kt_test_start "the indicator dragged: Value = (I*(Max-Min) + Size/2) div Size + Min at the mouse's cell inside the bar; outside it stays; Clicked when it changed"
fv.views.scrollBarSet vb 0 0 100 10 1
SBLOG=''
click 30 2 'move 30 6' 'nothing' 'move 30 8' 'up 30 8'; a=$REPLY; nmsg cmScrollBarClicked; a+=" $REPLY"; nmsg cmScrollBarChanged; a+=" $REPLY"
click 30 7 'move 35 4' 'up 35 4'; b=$REPLY
click 30 7 'move 30 3' 'nothing' 'up 30 3'; c=$REPLY
if [[ $a == '70 2 2' && $b == '70' && $c == '20' ]] && fvw_full root; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c] $FVW_DIFF"; fi

kt_test_start "a lost release: a key ends the tracking (the arrow stops repeating), the key is put back for the loop, the rest of the queue left"
fv.views.scrollBarSet vb 50 0 100 10 1
fvw_events 'auto 30 10' 'key kbA' 'auto 30 10' 'auto 30 10'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=30 FV_EV_MOUSE_Y=10 FV_EV_MOUSE_BUTTONS=1
fv.views._virt root HandleEvent
a="${vb_data[Value]} $FV_EV_WHAT ${__FV_DR_PEND[0]-}:${__FV_DR_PEND[1]-} ${#FVW_EVQ[@]}"
fvw_noevents
if [[ $a == '52 evNothing evKeyDown:kbA 2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a]"; fi

kt_test_start "the move coalescing: moves already waiting are drained, the last one counts (one value change for three moves), the release ends it"
fv.views.scrollBarSet vb 0 0 100 10 1
SBLOG=''
click 30 2 'move 30 4' 'move 30 5' 'move 30 7' 'up 30 7'
a=$REPLY
nmsg cmScrollBarChanged
if [[ $a == 60 && $REPLY == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] changes $REPLY [$SBLOG]"; fi

fv.views.delete root lis; lis.delete
kt_test_start "the elision: a built-in bar costs 0 dispatches for a key, the wheel, a click, a draw"
vb_data[Options]=$FV_OF_POSTPROCESS
fvw_count_on; FVW_CALLS=0
keys kbDown; wheel vb 30 5 2; click 30 10 'up 30 10'; fv.views.drawView vb
n=$FVW_CALLS
fvw_count_off
vb_data[Options]=0
if (( n == 0 )); then kt_test_pass "ok"; else kt_test_fail "$n dispatches"; fi

kt_test_start "overrides: ScrollStep (func, x5 of the inherited step) drives the keys and the arrows; ScrollDraw runs on each value change; 2 dispatches per use"
class TSb5 : TScrollBar
    public
        override func ScrollStep
        override proc ScrollDraw
end
TSb5.ScrollStep() { inherited ScrollStep "$@"; RESULT=$(( RESULT * 5 )); }
TSb5.ScrollDraw() { SDLOG+="$Value,"; inherited ScrollDraw; }
build TSb5
SDLOG=''
TSb5.new vs 26 1 27 11; fv.views.insert root vs
vs_data[Options]=$FV_OF_POSTPROCESS
fv.views.scrollBarSet vs 50 0 100 10 1
KB='vs_data[Value]'
fvw_count_on; FVW_CALLS=0
keys kbDown
n=$FVW_CALLS
fvw_count_off
a=$REPLY
keys kbPgUp; a+=" $REPLY"
click 26 10 'up 26 10'; a+=" $REPLY"
if [[ $a == '55 5 10' && $n == 4 && $SDLOG == '50,55,5,10,' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] calls $n log [$SDLOG]"; fi
fv.views.delete root vs; vs.delete

kt_test_start "standardScrollBar (FV): vertical on the right frame column rows 1..H-2, horizontal on the bottom row columns 2..W-3; names W__fvsb1, 2; sbHandleKeyboard -> ofPostProcess"
TWindow.new w 2 0 32 10 Win 1
fv.views.standardScrollBar w "$FV_SB_VERTICAL"; n1=$RESULT
fv.views.getBounds "$n1"; a="$n1 $RESULT $(( ${w__fvsb1_data[Options]} & FV_OF_POSTPROCESS ))"
fv.views.standardScrollBar w "$(( FV_SB_HORIZONTAL | FV_SB_HANDLEKEYBOARD ))"; n2=$RESULT
fv.views.getBounds "$n2"; a+=",$n2 $RESULT $(( ${w__fvsb2_data[Options]} & FV_OF_POSTPROCESS ))"
fvw_tree w; a+=",$REPLY"
r=''
fv.views.standardScrollBar vb 1 || r+="$?"
fv.views.standardScrollBar w x || r+="$?"
fv.views.standardScrollBar w || r+="$?"
if [[ $a == "w__fvsb1 29 1 30 9 0,w__fvsb2 2 9 28 10 $FV_OF_POSTPROCESS,w[w__fvframe w__fvsb1 w__fvsb2]" && $r == 222 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$r]"; fi
w.delete

root.delete

# lbars SETUP -> REPLY = the cells of a vertical and a horizontal bar (drawn,
# then each moved by scrollBarSet: the indicator's drawPart) in a fresh bash
# whose caller runs SETUP first; read back in a UTF-8 scope
lbars() {
    REPLY=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
source '$FVW_TESTS_DIR/../fv.views.sh'
$1
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_SCREEN_W=40 FV_SCREEN_H=12; fv.video.initScreen
TGroup.new root 0 0 40 12; root_data[State]=\$(( root_data[State] | FV_SF_EXPOSED ))
TView.new bg 0 0 40 12; fv.views.insert root bg
TScrollBar.new vb 30 1 31 11; fv.views.insert root vb
TScrollBar.new hb 2 11 32 12; fv.views.insert root hb
TScrollBar.new nb 2 0 12 1; fv.views.insert root nb
fv.views.scrollBarSet vb 7 0 20 5 1; fv.views.scrollBarSet hb 7 0 20 5 1
fv.views.drawView root
fv.views.scrollBarSet vb 13; fv.views.scrollBarSet hb 13
f() { local LC_ALL=C.UTF-8 y t='' s=''; for (( y = 1; y < 11; y++ )); do fv.video.getRow \$y; t+=\${RESULT:30:1} s+=\${REPLY:30:1}; done
  fv.video.getRow 11; t+=,\${RESULT:2:30} s+=,\${REPLY:2:30}; fv.video.getRow 0; printf '%s|%s' \"\$t,\${RESULT:2:10}\" \"\$s,\${REPLY:2:10}\"; }
f" 2>&1)
}
kt_test_start "a caller in the C locale: the same cells as a UTF-8 caller (vertical, horizontal, Max = Min; the indicator moved by scrollBarSet to 13 of 0..20: cells 6 and 19), in both video modes"
lbars ''; a=$REPLY
lbars 'export LC_ALL=C'; b=$REPLY
lbars 'FV_ASCII=1'; c=$REPLY
lbars 'FV_ASCII=1; export LC_ALL=C'; d=$REPLY
want='▲▒▒▒▒▒■▒▒▼,◄▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒■▒▒▒▒▒▒▒▒▒►,◄▓▓▓▓▓▓▓▓►|5444445445,544444444444444444454444444445,5444444445'
if [[ $a == "$want" && $b == "$a" && $c == '^:::::#::v,<::::::::::::::::::#:::::::::>,<########>|5444445445,544444444444444444454444444445,5444444445' && $d == "$c" ]]; then kt_test_pass "ok"
else kt_test_fail "UTF-8 [$a] C [$b] ASCII [$c] ASCII+C [$d]"; fi

kt_test_log "022_ScrollBar.sh completed"
