#!/usr/bin/env bash
# 015_Frame.sh - the minimal TFrame (design §1.5, P2-3; FV TFrame.Draw):
#   * FV's look in CFrame's colours through a blue TWindow-like owner: active
#     (double line, `[■]`, the number, the title centred, `[↑]`, the grow
#     corner, icons in colour 5), inactive (single line, no icons), dragging
#     (single line, everything in colour 5), `↕` when the owner is at its
#     SizeLimits maximum, `☼` for FrameMode's clicked bits; an owner without
#     Flags / Title / Number (a plain TGroup): a bare frame in the app
#     palette's colours;
#   * a wide title (cells, not characters), a title cut so that it never
#     reaches an icon, small sizes (W 1, 2, 5; H 1, 2) without errors;
#   * the shape: a full draw = 3 fv.video writes, a border-only redraw = 3
#     (stage 2c-p: both sides in one fillColumns; 4 before);
#     the strings cached per frame and state (no strWidth on a cache hit, a
#     new title or size rebuilds);
#   * through fv.video's VT model: what the terminal shows equals the buffer
#     after the first paint and after border-only redraws, and a border-only
#     redraw leaves the buffer a full repaint would (interior covered, a
#     window overlapping the ring in front); behind a window, the covered
#     parts of the ring are left out (no write, no repaint of the window);
#   * the string cache follows the screen's ASCII mode;
#   * a frame class overriding Draw: the border-only entry draws it whole
#     through its Draw;
#   * stage 2d, the frame's mouse (FPC TFrame.HandleEvent): the close icon's
#     press tracking (☼ while on it, one top-row write per change, cmClose
#     posted on a release on it, nothing off it or at the end of input; the
#     posted event closes the window), the zoom icon (tracked; a double click
#     on the top row posts cmZoom at once), an inactive frame has no icons
#     (the top row drags), the grow corner, a frame class with its own Draw
#     (redrawn through it), quiet for broadcasts.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"
FVV_TMP=$FVW_TMP
source "$FVW_TESTS_DIR/../../fv.video/tests/fvv_vt.sh"

kt_test_section "015: TFrame"

rep() {   # CH N -> REPLY = CH repeated N times
    local s
    printf -v s '%*s' "$2" ''
    REPLY=${s// /"$1"}
}
row() {   # X Y W -> REPLY = "text|symbols" of those cells
    fvw_cells "$1" "$2" "$3"
    REPLY="$RESULT|$REPLY"
}

fvw_classes
fvw_screen 50 22
TGroup.new desk 0 0 50 22
TView.new bg0 0 0 50 22   # (a background: a frameless desk keeps stale cells where nothing is)
fv.views.insert desk bg0
fvw_expose desk
TTWin.new w 2 1 40 20
w_data[Flags]=$(( FV_WF_MOVE | FV_WF_GROW | FV_WF_CLOSE | FV_WF_ZOOM )) w_data[Title]=Files w_data[Number]=1
fv.views._newReserved w frame TFrame 0 0 38 19; f=$RESULT
fv.views.insert w "$f"
fv.views.insert desk w
F=w__fvframe

kt_test_start "the constructor: FV's GrowMode (HiX + HiY), EventMask + evBroadcast, FrameMode 0, GetPalette CFrame"
RESULT=x; fv.views._virt "$F" GetPalette; p=$RESULT
if [[ ${w__fvframe_data[GrowMode]} == 12 && ${w__fvframe_data[EventMask]} == $(( 273 | 512 )) && ${w__fvframe_data[FrameMode]} == 0 && $p == '1 1 2 2 3' ]]; then kt_test_pass "ok"
else kt_test_fail "grow=${w__fvframe_data[GrowMode]} mask=${w__fvframe_data[EventMask]} fm=${w__fvframe_data[FrameMode]} pal=[$p]"; fi

kt_test_start "inactive: single line, the title centred, the number, no icons; frame and title in colour 1 / 2 (blue window: symbol 8)"
fv.views.drawView desk
row 2 1 38; a=$REPLY
row 2 2 38; b=$REPLY
row 2 19 38; c=$REPLY
rep '─' 14; t="┌$REPLY Files "; rep '─' 9; t+="${REPLY}1"; rep '─' 5; t+="$REPLY┐"
rep 8 38; s8=$REPLY
rep ' ' 36; mid="│$REPLY│"
rep '─' 36; bot="└$REPLY┘"
if [[ $a == "$t|$s8" && $b == "$mid|$s8" && $c == "$bot|$s8" ]]; then kt_test_pass "ok"; else kt_test_fail "top [$a] want [$t|$s8]; body [$b]; bottom [$c]"; fi

kt_test_start "active: double line, [■] at 2, the number at W-7, [↑] at W-5, the grow corner; frame 3 (9), icons 5 (A), title 4 (9)"
w__fvframe_data[State]=$(( w__fvframe_data[State] | FV_SF_ACTIVE ))
fv.views.drawView "$F"
row 2 1 38; a=$REPLY
row 2 2 38; b=$REPLY
row 2 19 38; c=$REPLY
rep '═' 10; t="╔═[■]$REPLY Files "; rep '═' 9; t+="${REPLY}1═[↑]═╗"
rep 9 38; s9=$REPLY; ts="${s9:0:3}A${s9:4:30}A${s9:35}"
rep ' ' 36; mid="║$REPLY║"
rep '═' 35; bot="╚$REPLY─┘"; bs="${s9:0:36}AA"
if [[ $a == "$t|$ts" && $b == "$mid|$s9" && $c == "$bot|$bs" ]]; then kt_test_pass "ok"; else kt_test_fail "top [$a] want [$t|$ts]; body [$b]; bottom [$c] want [$bot|$bs]"; fi

kt_test_start "dragging (and active): single line, icons kept, everything in colour 5 (A)"
w__fvframe_data[State]=$(( w__fvframe_data[State] | FV_SF_DRAGGING ))
fv.views.drawView "$F"
row 2 1 38; a=$REPLY
row 2 19 38; c=$REPLY
rep '─' 10; t="┌─[■]$REPLY Files "; rep '─' 9; t+="${REPLY}1─[↑]─┐"
rep A 38; sA=$REPLY
rep '─' 36; bot="└$REPLY┘"
if [[ $a == "$t|$sA" && $c == "$bot|$sA" ]]; then kt_test_pass "ok"; else kt_test_fail "top [$a] want [$t|$sA]; bottom [$c]"; fi
w__fvframe_data[State]=$(( w__fvframe_data[State] & ~FV_SF_DRAGGING ))

kt_test_start "FrameMode fmCloseClicked / fmZoomClicked: ☼ in the icon; the owner at its SizeLimits maximum: ↕"
w__fvframe_data[FrameMode]=$(( FV_FM_CLOSECLICKED | FV_FM_ZOOMCLICKED ))
fv.views.drawView "$F"
fvw_cells 4 1 3; a=$RESULT
fvw_cells 35 1 3; b=$RESULT
w__fvframe_data[FrameMode]=0
fv.views.locate w 0 0 50 22
fvw_cells 45 0 3; z=$RESULT
fv.views.locate w 2 1 40 20
if [[ $a == '[☼]' && $b == '[☼]' && $z == '[↕]' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$z]"; fi
fv.views.drawView desk

kt_test_start "an owner without Flags / Title / Number (a plain TGroup): a bare frame, the app palette's entries 1 (inactive) / 2-3 (active)"
TGroup.new pg 42 1 50 5
TFrame.new pf 0 0 8 4
fv.views.insert pg pf
fv.views.insert desk pg
row 42 1 8; a=$REPLY
pf_data[State]=$(( pf_data[State] | FV_SF_ACTIVE ))
fv.views.drawView pf
row 42 1 8; b=$REPLY
row 42 4 8; c=$REPLY
if [[ $a == '┌──────┐|11111111' && $b == '╔══════╗|22222222' && $c == '╚══════╝|22222222' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi
pg.delete

kt_test_start "a wide title takes its cells (漢字 = 4 cells, centred); a long title is cut before the icons (L = W-10-6-4)"
w_data[Title]='漢字'
fv.views.drawView "$F"
fv.video.getRow 1; wt=${RESULT:2:36} ws=${REPLY:2:38}
w_data[Title]='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
fv.views.drawView "$F"
fvw_cells 2 1 38; lt=$RESULT
rep '═' 11; want_w="╔═[■]$REPLY 漢字 "; rep '═' 9; want_w+="${REPLY}1═[↑]═╗"
rep '═' 4; want_l="╔═[■]$REPLY ABCDEFGHIJKLMNOPQR ══1═[↑]═╗"
if [[ $wt == "$want_w" && ${#ws} == 38 && $lt == "$want_l" ]]; then kt_test_pass "ok"; else kt_test_fail "wide [$wt] want [$want_w] (${#ws} symbols); long [$lt] want [$want_l]"; fi
w_data[Title]=Files

kt_test_start "small frames draw without errors: W 1 / 2 / 5, H 1 / 2"
TGroup.new sg 0 21 50 22
fv.views.insert desk sg
out='' r=''
for b in '0 0 1 1' '2 0 4 1' '5 0 10 1'; do
    TFrame.new sf 0 0 1 1
    read -r ax ay bx by <<< "$b"
    fv.views.insert sg sf
    fv.views.locate sf "$ax" "$ay" "$bx" "$by"
    fv.views.drawView sf 2>&1; out+="$?"
    fvw_cells "$ax" 21 $(( bx - ax )); r+=$RESULT
    sf.delete
done
# (each frame read before its delete: the delete repaints its cells from below)
TGroup.new sg2 44 6 50 8
TFrame.new sf2 0 0 6 2
fv.views.insert sg2 sf2; fv.views.insert desk sg2
row 44 6 6; h2a=$REPLY; row 44 7 6; h2b=$REPLY
if [[ $out == 000 && $r == '┘└┘└───┘' && $h2a == '┌────┐|111111' && $h2b == '└────┘|111111' ]]; then kt_test_pass "ok"; else kt_test_fail "rc [$out] row [$r] [$h2a] [$h2b]"; fi
sg.delete; sg2.delete

kt_test_start "the shape: a full frame draw = 3 writes, a border-only redraw = 3 writes (both sides one fillColumns), no dispatch"
TTWin.new w5 0 0 20 6
w5_data[Flags]=$FV_WF_CLOSE w5_data[Title]=t
fv.views._newReserved w5 frame TFrame 0 0 20 6
fv.views.insert w5 w5__fvframe
fv.views.insert desk w5
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
fv.views.drawView w5__fvframe
a="$FVW_WRITES $FVW_CALLS"
FVW_WRITES=0 FVW_CALLS=0
w5__fvframe_data[State]=$(( w5__fvframe_data[State] | FV_SF_ACTIVE ))
fv.views._frameBorder w5__fvframe
b="$FVW_WRITES $FVW_CALLS"
fvw_writes_off; fvw_count_off
if [[ $a == '3 0' && $b == '3 0' ]]; then kt_test_pass "ok"; else kt_test_fail "full [$a] border [$b]"; fi

kt_test_start "the strings are cached per frame and state: a redraw makes no strWidth call; a new title or size rebuilds; active and inactive each built once"
fvw_wrap FVW_SW fv.video.strWidth; FVW_SW=0
fv.views.drawView w5__fvframe; a=$FVW_SW
w5_data[Title]=tt; fv.views.drawView w5__fvframe; b=$FVW_SW
fv.views.growTo w5 22 6; c=$FVW_SW
fv.views.drawView w5__fvframe; d=$FVW_SW
# a focus change back and forth: each state built once, then both cached
for i in 1 2 3 4; do w5__fvframe_data[State]=$(( w5__fvframe_data[State] ^ FV_SF_ACTIVE )); fv.views._frameBorder w5__fvframe; done; e=$FVW_SW
fvw_unwrap fv.video.strWidth
fvw_cells 0 0 22; t=$RESULT
if [[ $a == 0 && $b == 1 && $c == 2 && $d == 2 && $e == 3 && $t == '╔═[■]════ tt ════════╗' ]]; then kt_test_pass "ok"; else kt_test_fail "strWidth calls $a $b $c $d $e top [$t]"; fi
w5.delete

kt_test_start "the string cache follows the screen's mode: after initScreen in ASCII mode a wide title is rebuilt (2 cells, '?'), and back"
TTWin.new w6 0 0 20 4
w6_data[Title]='漢字'
fv.views._newReserved w6 frame TFrame 0 0 20 4
fv.views.insert w6 w6__fvframe
fv.views.insert desk w6
fvw_cells 0 0 18; a=$RESULT   # (20 cells: the wide title takes 4 cells in 2 characters)
FV_ASCII=1 fv.video.initScreen
fv.views.drawView w6
fvw_cells 0 0 20; b=$RESULT
unset FV_ASCII; fv.video.initScreen
fv.views.drawView w6
fvw_cells 0 0 18; c=$RESULT
if [[ $a == '┌────── 漢字 ──────┐' && $b == '+------- ?? -------+' && $c == "$a" ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi
w6.delete

# the VT model and border-only == full repaint
snap() {
    local y s=''
    for (( y = 0; y < FV_SCREEN_H; y++ )); do fv.video.getRow "$y"; s+="$RESULT|$REPLY"$'\n'; done
    REPLY=$s
}
kt_test_start "VT model: the terminal shows the buffer after the first paint and after border-only redraws; border-only == a full repaint"
desk.delete
fvw_screen 60 20
TGroup.new desk 0 0 60 20
TView.new bg 0 0 60 20
fv.views.insert desk bg
for n in 1 2; do
    TTWin.new "v$n" $(( n * 14 - 12 )) $(( n * 3 - 2 )) $(( n * 14 + 22 )) $(( n * 3 + 12 ))
    local_d="v${n}_data"
    declare -n vd=$local_d
    vd[Flags]=$(( FV_WF_CLOSE | FV_WF_ZOOM | FV_WF_GROW )) vd[Title]="Win $n" vd[Number]=$n
    vd[State]=$(( vd[State] | FV_SF_SHADOW ))
    unset -n vd
    fv.views._newReserved "v$n" frame TFrame 0 0 34 14
    fv.views.insert "v$n" "v${n}__fvframe"
    TView.new "v${n}in" 1 1 33 13
    fv.views.insert "v$n" "v${n}in"
    fv.views.insert desk "v$n"
done
v2__fvframe_data[State]=$(( v2__fvframe_data[State] | FV_SF_ACTIVE ))
fvw_expose desk
vt_init 60 20
bad=''
vt_capture fv.views.drawView desk; vt_feed "$VT_OUT" || bad+=" feed1:$VT_ERR"; vt_cmp || bad+=" cmp1:$VT_ERR"
# Tab-like: v1 becomes active, v2 inactive (v2 in front overlaps v1's ring)
v1__fvframe_data[State]=$(( v1__fvframe_data[State] | FV_SF_ACTIVE ))
v2__fvframe_data[State]=$(( v2__fvframe_data[State] & ~FV_SF_ACTIVE ))
fv.views.lockScreenUpdate
fv.views._frameBorder v1__fvframe
fv.views._frameBorder v2__fvframe
vt_capture fv.views.unlockScreenUpdate; vt_feed "$VT_OUT" || bad+=" feed2:$VT_ERR"; vt_cmp || bad+=" cmp2:$VT_ERR"
snap; s_border=$REPLY
fv.video.clearScreen
fv.views.drawView desk
snap; s_full=$REPLY
vt_capture fv.video.updateScreen; vt_feed "$VT_OUT" || bad+=" feed3:$VT_ERR"; vt_cmp || bad+=" cmp3:$VT_ERR"
if [[ -z $bad && $s_border == "$s_full" ]]; then kt_test_pass "ok"
else
    d=''
    if [[ $s_border != "$s_full" ]]; then
        mapfile -t x <<< "$s_border"; mapfile -t y <<< "$s_full"
        for i in "${!x[@]}"; do [[ ${x[i]} == "${y[i]-}" ]] || d+=" row $i: [${x[i]}] vs [${y[i]-}]"; done
    fi
    kt_test_fail "vt:[$bad] diff:$d"
fi

kt_test_start "border-only behind a window: the covered parts of the ring are left out (4 pieces, 4 writes), the window in front is not painted again"
# v1 2,1-36,15; v2 16,4-50,18 in front: top row and left column whole, the
# bottom row cut to x 2..15, the right column to rows 2..3
v1__fvframe_data[State]=$(( v1__fvframe_data[State] ^ FV_SF_ACTIVE ))
fvw_wrap FVW_P fv.views._paint; FVW_P=0
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
fv.views._frameBorder v1__fvframe
a="$FVW_WRITES $FVW_CALLS $FVW_P"
fvw_writes_off; fvw_count_off; fvw_unwrap fv.views._paint
snap; s_border=$REPLY
fv.video.clearScreen; fv.views.drawView desk
snap; s_full=$REPLY
if [[ $a == '4 0 0' && $s_border == "$s_full" ]]; then kt_test_pass "ok"; else kt_test_fail "writes/dispatches/paints [$a], same as full: $([[ $s_border == "$s_full" ]] && echo yes || echo no)"; fi

class TMyFrame : TFrame
    public
        override proc Draw
end
TMyFrame.Draw() { MYF=$(( ${MYF:-0} + 1 )); inherited Draw; }
build TMyFrame
kt_test_start "a frame class overriding Draw: the border-only entry draws it whole through its Draw (1 Draw + inherited)"
TGroup.new mg 0 0 10 4
TMyFrame.new mf 0 0 10 4
fv.views.insert mg mf; fv.views.insert desk mg
MYF=0
fvw_count_on; FVW_CALLS=0
fv.views._frameBorder mf
n=$FVW_CALLS
fvw_count_off
fvw_cells 0 0 10; t=$RESULT
if [[ $MYF == 1 && $n == 2 && $t == '┌────────┐' ]]; then kt_test_pass "ok"; else kt_test_fail "Draws=$MYF calls=$n top [$t]"; fi

desk.delete

# ---- stage 2d: the frame's mouse (FPC TFrame.HandleEvent) ----------------------------
fvw_screen 50 22
TGroup.new d2 0 0 50 22; TView.new bg2 0 0 50 22; fv.views.insert d2 bg2
TWindow.new mw 4 2 34 14 'Mouse' 1
TView.new mwl 1 1 29 11; fv.views.insert mw mwl
fv.views.insert d2 mw
fvw_root d2
fv.views.drawView d2
MF=mw__fvframe
down() {   # X Y [DOUBLE] -> a mouse-down through d2's dispatch
    fv.drivers.clearEvent
    FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$1 FV_EV_MOUSE_Y=$2 FV_EV_MOUSE_BUTTONS=1 FV_EV_MOUSE_DOUBLE=${3:-0}
    fv.views._virt d2 HandleEvent
}
cap() { fvw_cells 4 2 30; CAP+="${mw__fvframe_data[FrameMode]}:${RESULT:2:3};"; }
pend() { REPLY="${__FV_DR_PEND[0]-}:${__FV_DR_PEND[3]-}:${__FV_DR_PEND[5]-}"; }

kt_test_start "2d: the close icon: pressed (☼, FrameMode fmCloseClicked) while on it, released on it: cmClose posted for the window (FV PutEvent); handled; the record put back; one top-row write per change; == a full repaint"
CAP=''
fvw_events 'run cap' 'move 8 2' 'run cap' 'up 7 2'
fvw_writes_on; FVW_WRITES=0
down 6 2
w=$FVW_WRITES
fvw_writes_off
r="$FV_EV_WHAT|$FV_EV_INFO|$FV_EV_MOUSE_X|${mw__fvframe_data[FrameMode]}"
pend; p=$REPLY
fvw_cells 4 2 30; t=${RESULT:2:3}
if [[ $CAP == '1:[☼];1:[☼];' && $r == "evNothing|$MF|6|0" && $p == 'evCommand:cmClose:mw' && $w == 2 && $t == '[■]' ]] && fvw_full d2; then kt_test_pass "ok"
else kt_test_fail "cap [$CAP] [$r] pend [$p] writes $w top [$t] diff [$FVW_DIFF]"; fi

kt_test_start "2d: the posted cmClose, read and dispatched, closes the window"
fvw_getev; fv.views._virt d2 HandleEvent
if ! fv.views.isView mw && fvw_full d2; then kt_test_pass "ok"; else kt_test_fail "window still there / diff [$FVW_DIFF]"; fi
fvw_noevents
TWindow.new mw 4 2 34 14 'Mouse' 1
TView.new mwl 1 1 29 11; fv.views.insert mw mwl
fv.views.insert d2 mw

kt_test_start "2d: the close icon, moved off it and released off it: the icon back to ■ while off, nothing posted"
CAP=''
fvw_events 'run cap' 'move 12 3' 'run cap' 'move 7 2' 'run cap' 'up 20 2'
down 7 2
pend; p=$REPLY
if [[ $CAP == '1:[☼];0:[■];1:[☼];' && $p == '::' && ${mw__fvframe_data[FrameMode]} == 0 ]] && fv.views.isView mw && fvw_full d2; then kt_test_pass "ok"
else kt_test_fail "cap [$CAP] pend [$p] diff [$FVW_DIFF]"; fi
fvw_noevents

kt_test_start "2d: the zoom icon: pressed (☼, fmZoomClicked) and released on it: cmZoom posted for the window"
CAP=''
zc() { fvw_cells 29 2 3; CAP+="${mw__fvframe_data[FrameMode]}:$RESULT;"; }
fvw_events 'run zc' 'up 30 2'
down 30 2
pend; p=$REPLY
fvw_cells 29 2 3; t=$RESULT
if [[ $CAP == '2:[☼];' && $p == 'evCommand:cmZoom:mw' && $t == '[↑]' && $FV_EV_WHAT == evNothing ]]; then kt_test_pass "ok"; else kt_test_fail "cap [$CAP] pend [$p] top [$t]"; fi
fvw_noevents

kt_test_start "2d: a double click on the top row (the title): cmZoom posted at once, no event read, no redraw"
fvw_events 'up 16 2'
fvw_writes_on; FVW_WRITES=0
down 16 2 1
w=$FVW_WRITES
fvw_writes_off
pend; p=$REPLY
if [[ $p == 'evCommand:cmZoom:mw' && $FVW_EVN == 0 && $w == 0 && $FV_EV_WHAT == evNothing ]]; then kt_test_pass "ok"; else kt_test_fail "pend [$p] reads $FVW_EVN writes $w"; fi
fvw_noevents

kt_test_start "2d: the end of input while an icon is pressed: nothing posted, FrameMode 0, the icon drawn back"
fvw_events 'move 7 2'
down 7 2
pend; p=$REPLY
fvw_cells 4 2 30; t=${RESULT:2:3}
if [[ $p == '::' && ${mw__fvframe_data[FrameMode]} == 0 && $t == '[■]' && $__FV_VW_EOF == 1 ]] && fvw_full d2; then kt_test_pass "ok"; else kt_test_fail "pend [$p] top [$t] eof $__FV_VW_EOF"; fi
fvw_noevents

kt_test_start "2d: an inactive frame has no icons: a click at X 2..4 of the top row drags the window (wfMove); without wfMove: not handled"
mw__fvframe_data[State]=$(( mw__fvframe_data[State] & ~FV_SF_ACTIVE ))
fvw_events 'up 9 4'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=7 FV_EV_MOUSE_Y=2 FV_EV_MOUSE_BUTTONS=1
fv.views._virt "$MF" HandleEvent
fv.views.getBounds mw; r1="$RESULT|$FV_EV_WHAT"
pend; p=$REPLY
mw_data[Flags]=$(( FV_WF_CLOSE | FV_WF_ZOOM | FV_WF_GROW ))
fvw_events 'up 9 4'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=12 FV_EV_MOUSE_Y=4 FV_EV_MOUSE_BUTTONS=1
fv.views._virt "$MF" HandleEvent; r2="$FV_EV_WHAT|$FVW_EVN"
mw_data[Flags]=15
mw__fvframe_data[State]=$(( mw__fvframe_data[State] | FV_SF_ACTIVE ))
fvw_noevents
fv.views.moveTo mw 4 2
if [[ $r1 == '6 4 36 16|evNothing' && $p == '::' && $r2 == 'evMouseDown|0' ]] && fvw_full d2; then kt_test_pass "ok"; else kt_test_fail "[$r1] pend [$p] [$r2] diff [$FVW_DIFF]"; fi

kt_test_start "2d: the grow corner (active, X >= W-2, bottom row) grows the window by the mouse; elsewhere on the bottom row and the sides: not handled"
fvw_events 'move 36 15' 'up 36 15'
down 33 13
fv.views.getBounds mw; r1="$RESULT|$FV_EV_WHAT"
fvw_events 'up 20 13'
down 20 13; r2="$FV_EV_WHAT|$FVW_EVN"
fvw_events 'up 4 6'
down 4 6; r3="$FV_EV_WHAT|$FVW_EVN"
fvw_noevents
fv.views.growTo mw 30 12
if [[ $r1 == '4 2 37 16|evNothing' && $r2 == 'evMouseDown|0' && $r3 == 'evMouseDown|0' ]] && fvw_full d2; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] [$r3] diff [$FVW_DIFF]"; fi

kt_test_start "2d: a frame class overriding Draw: the icon tracking redraws it through its Draw (one per FrameMode change)"
class TMyFrame2 : TFrame
    public
        override proc Draw
end
TMyFrame2.Draw() { MYF=$(( ${MYF:-0} + 1 )); inherited Draw; }
build TMyFrame2
class TMyWin2 : TWindow
    public
        override proc InitFrame
end
TMyWin2.InitFrame() { fv.views._newReserved "$this" frame TMyFrame2 0 0 "$SizeX" "$SizeY" && Frame=$RESULT; }
build TMyWin2
TMyWin2.new mw2 10 4 40 16 'Mine' 2
fv.views.insert d2 mw2
MYF=0
fvw_events 'up 13 4'
down 13 4
pend; p=$REPLY
fvw_noevents
if [[ $MYF == 2 && $p == 'evCommand:cmClose:mw2' ]] && fvw_full d2; then kt_test_pass "ok"; else kt_test_fail "Draws=$MYF pend [$p] diff [$FVW_DIFF]"; fi
mw2.delete

kt_test_start "2d: TFrame's HandleEvent is quiet for broadcasts (no dispatch: the focus broadcasts stay a walk) and the dispatch skips it for keys and commands"
fvw_count_on; FVW_CALLS=0
fv.views.message d2 evBroadcast cmReceivedFocus mw; r="$?"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF9; fv.views._virt d2 HandleEvent
n=$FVW_CALLS
fvw_count_off
if [[ $r == 1 && $n == 0 && $FV_EV_WHAT == evKeyDown ]]; then kt_test_pass "ok"; else kt_test_fail "message rc $r, $n dispatches, [$FV_EV_WHAT]"; fi

d2.delete
kt_test_log "015_Frame.sh completed"
