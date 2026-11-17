#!/usr/bin/env bash
# 016_Window.sh - the basic TWindow of stage 2c-3 (FV views.inc TWindow:
# Init, InitFrame, GetPalette, GetTitle, SetState, HandleEvent, Close):
#   * the constructor: FV's defaults (sfShadow, ofSelectable + ofTopSelect,
#     gfGrowAll + gfGrowRel, wfMove + wfGrow + wfClose + wfZoom, wpBlueWindow,
#     Title, Number, ZoomRect = the bounds), the frame NAME__fvframe from
#     InitFrame over the whole window, inserted at the back; a non-integer
#     number is wnNoNumber; the guard and a bad bound refuse as TView does;
#   * an InitFrame override that makes no frame;
#   * GetTitle (cut to MaxSize); the frame shows the title and the number;
#   * the palettes: blue / cyan / gray through the frame's colours, after
#     resetPalette;
#   * cmClose: Valid agrees -> the window destroyed (the focus moves on, ==
#     a full repaint); Valid refuses -> kept; without wfClose, or for
#     another window (FV_EV_INFO) -> not handled;
#   * cmSelectWindowNum (a broadcast, FV_EV_INFO = the number): that window
#     selected and the event handled (message answers it); an unknown
#     number: nobody;
#   * Tab handled by the window (the event cleared).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "016: TWindow"

row() {   # X Y W -> REPLY = "text|symbols" of those cells
    fvw_cells "$1" "$2" "$3"
    REPLY="$RESULT|$REPLY"
}

kt_test_start "the constructor: FV's defaults, Title, Number, ZoomRect; the frame from InitFrame, full size, at the back"
TWindow.new w 10 5 50 20 'Files' 3
f=${w_data[Frame]}
r="${w_data[State]}|${w_data[Options]}|${w_data[GrowMode]}|${w_data[Flags]}|${w_data[Palette]}|${w_data[Title]}|${w_data[Number]}|${w_data[ZoomRect]}"
r+="|$f|${w__fvframe_data[Owner]}|${w__fvframe_data[SizeX]}x${w__fvframe_data[SizeY]}|${w_views[*]}"
want="$(( FV_SF_VISIBLE | FV_SF_SHADOW ))|$(( FV_OF_SELECTABLE | FV_OF_TOPSELECT | FV_OF_BUFFERED ))|$(( FV_GF_GROWALL | FV_GF_GROWREL ))|15|0|Files|3|10 5 50 20|w__fvframe|w|40x15|w__fvframe"
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "a number that is not an integer is wnNoNumber (0); no title is ''; the guard and a bad bound refuse as TView does"
TWindow.new w2 0 0 20 10 '' x; r="${w2_data[Number]}|${w2_data[Title]}"
TWindow.new w2 0 0 1 1 2>/dev/null; r+="|$?"
TWindow.new w9 0 0 x 1 2>/dev/null; r+="|$?"
fv.views.isView w2 || r+="|gone"
if [[ $r == '0||1|2|gone' ]] && ! fv.views.isView w9; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
w2.delete 2>/dev/null || :
w9.delete 2>/dev/null || :

kt_test_start "an InitFrame override that makes no frame: Frame '', no subview"
class TBare : TWindow
    public
        override proc InitFrame
end
TBare.InitFrame() { :; }
build TBare
TBare.new bare 0 0 10 5 'Bare' 0
if [[ -z ${bare_data[Frame]} && ${#bare_views[@]} == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "frame [${bare_data[Frame]}] views [${bare_views[*]}]"; fi
bare.delete

kt_test_start "GetTitle MAXSIZE (func): the title cut to MAXSIZE characters; no limit: whole"
RESULT=''; fv.views._virt w GetTitle 3; r1=$RESULT
RESULT=''; fv.views._virt w GetTitle 99; r2=$RESULT
RESULT=''; w.GetTitle 0; r3=$RESULT
if [[ $r1 == Fil && $r2 == Files && -z $r3 ]]; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] [$r3]"; fi

kt_test_start "the frame shows the title (centred) and the number; selected: active (double line, icons)"
fvw_screen 60 24
TGroup.new root 0 0 60 24; TView.new bg 0 0 60 24; fv.views.insert root bg; fvw_root root
fv.views.insert root w
fv.views.drawView root
row 10 5 40; r=$REPLY
if [[ ${r%%|*} == '╔═[■]═══════════ Files ══════════3═[↑]═╗' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "the palettes: blue / cyan / gray (CAppColor 8-15 / 16-23 / 24-31) through the frame's colours, after resetPalette"
fv.views.getColor w__fvframe 3; p0=$RESULT
w_data[Palette]=$FV_WP_CYANWINDOW; fv.views.resetPalette w; fv.views.getColor w__fvframe 3; p1=$RESULT
w_data[Palette]=$FV_WP_GRAYWINDOW; fv.views.resetPalette w; fv.views.getColor w__fvframe 3; p2=$RESULT
fv.views.drawView w; fvw_full root; f=$?
# the frame's entry 3 (CFrame "1 1 2 2 3": 2) -> the window's entry 2 ->
# CAppColor 9 / 17 / 25
want="${__FV_VW_APAL:8:1}${__FV_VW_APAL:16:1}${__FV_VW_APAL:24:1}"
if [[ "$p0$p1$p2" == "$want" && $f == 0 ]]; then kt_test_pass "ok ($want)"; else kt_test_fail "[$p0$p1$p2] want [$want] full $f"; fi
w_data[Palette]=$FV_WP_BLUEWINDOW; fv.views.resetPalette w; fv.views.drawView w

class TCl : TWindow
    public
        override func Valid
end
TCl.Valid() { VASK+="$this:$1;"; if [[ ${VNO:-0} == 1 ]]; then return 1; fi; inherited Valid "$@"; }
build TCl
send() {   # WHAT COMMAND [INFO] -> to root
    fv.drivers.clearEvent
    FV_EV_WHAT=$1 FV_EV_COMMAND=$2 FV_EV_INFO=${3-}
    fv.views._virt root HandleEvent
}

kt_test_start "cmClose, Valid refuses: handled, the window kept"
TCl.new wc 5 3 35 12 'Close me' 1
fv.views.insert root wc
VASK='' VNO=1
send evCommand cmClose
r="$FV_EV_WHAT|$VASK"
fv.views.isView wc && r+="|kept"
if [[ $r == 'evNothing|wc:cmClose;|kept' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "cmClose for another window (FV_EV_INFO) or without wfClose: not handled, kept"
VASK='' VNO=0
send evCommand cmClose w; r1="$FV_EV_WHAT|$VASK"
wc_data[Flags]=$FV_WF_MOVE
send evCommand cmClose; r2="$FV_EV_WHAT|$VASK"
wc_data[Flags]=15
if [[ $r1 == 'evCommand|' && $r2 == 'evCommand|' ]] && fv.views.isView wc; then kt_test_pass "ok"; else kt_test_fail "other [$r1] noflag [$r2]"; fi

kt_test_start "cmClose, Valid agrees (INFO '' or the window): destroyed, its frame too, the focus back on w, == a full repaint"
send evCommand cmClose wc
r="$FV_EV_WHAT|$VASK|${root_data[Current]}"
if [[ $r == 'evNothing|wc:cmClose;|w' ]] && ! fv.views.isView wc && ! fv.views.isView wc__fvframe && (( w_data[State] & FV_SF_FOCUSED )) && fvw_full root; then kt_test_pass "ok"
else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi

kt_test_start "cmSelectWindowNum (broadcast, INFO = the number): that window selected and handled (message answers it); unknown number: nobody"
TWindow.new wn 30 8 55 18 'Two' 2
# (a leaf over its interior: a border-only redraw keeps an uncovered
# interior's colour, the documented 2c-2 deviation that fvw_full would see)
TView.new wnl 1 1 24 9; fv.views.insert wn wnl
fv.views.insert root wn
fv.views.message root evBroadcast cmSelectWindowNum 3; r1="$?|$RESULT|${root_data[Current]}"
fv.views.message root evBroadcast cmSelectWindowNum 7; r2="$?|$RESULT|${root_data[Current]}"
fv.views.message root evBroadcast cmSelectWindowNum ''; r3="$?|${root_data[Current]}"
if [[ $r1 == '0|w|w' && $r2 == '1||w' && $r3 == '1|w' ]] && fvw_full root; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] [$r3] diff [$FVW_DIFF]"; fi

kt_test_start "a hidden window ignores cmSelectWindowNum (the next key does not go to an invisible window)"
fv.views.hide wn
fv.views.message root evBroadcast cmSelectWindowNum 2; r="$?|${root_data[Current]}"
fv.views.show wn; fv.views.select w
if [[ $r == '1|w' ]] && fvw_full root; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi

kt_test_start "an unselectable window ignores cmSelectWindowNum"
wn_data[Options]=$(( wn_data[Options] & ~FV_OF_SELECTABLE ))
fv.views.message root evBroadcast cmSelectWindowNum 2; r="$?|${root_data[Current]}"
wn_data[Options]=$(( wn_data[Options] | FV_OF_SELECTABLE ))
if [[ $r == '1|w' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "Tab in a window without controls: handled by the window (cleared), nothing moves"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbTab
fv.views._virt root HandleEvent
if [[ $FV_EV_WHAT == evNothing && $FV_EV_INFO == w && ${root_data[Current]} == w ]]; then kt_test_pass "ok"; else kt_test_fail "[$FV_EV_WHAT $FV_EV_INFO ${root_data[Current]}]"; fi

kt_test_start "an unknown key and an unknown command pass a window unhandled"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF7; fv.views._virt root HandleEvent; r1=$FV_EV_WHAT
send evCommand cmZoom; r2=$FV_EV_WHAT
if [[ $r1 == evKeyDown && $r2 == evCommand ]]; then kt_test_pass "ok (cmZoom: stage 2d)"; else kt_test_fail "[$r1] [$r2]"; fi

root.delete
kt_test_log "016_Window.sh completed"
