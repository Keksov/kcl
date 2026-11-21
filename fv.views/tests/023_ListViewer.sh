#!/usr/bin/env bash
# 023_ListViewer.sh - TListViewer (P3 stage 3b; design P3 §1.2-1.5, §2.2,
# §2.6, §3.3, §5; FV views.inc TListViewer, FPC 2025):
#   * construction (fields, ofFirstClick + ofSelectable, evBroadcast +
#     evMouseWheel; a horizontal bar's SetStep), the refusals before anything
#     is made (NUMCOLS, a bar that is not a TScrollBar);
#   * the rows (a blank, the item's text cut / padded to the column, FPC
#     2025's GetItemColor: focused 3 when selected + active, selected 4 —
#     the focused item or a Marks entry, D26 — else 2); D25's palettes (a
#     plain window: 6 6 7 2 6, marked rows visible; a dialog-sized owner:
#     CListViewer);
#   * the keys (arrows, PgUp / PgDn, Home / End, Ctrl+PgUp / Ctrl+PgDn,
#     WordStar through ctrlToArrow, Space -> SelectItem -> cmListItemSelected,
#     Marks toggled by Space / Ins), rule 4 (one write for Down inside the
#     page), the screen == a full repaint after every action;
#   * TopItem / Range / the bar kept together (FPC 2025 SetRange /
#     SetTopItem / FocusItem), the plain API (listSetRange, listSetTopItem,
#     listFocusItem, listDrawItem) and its refusals;
#   * ShowSBar: the bar follows the list's activity; SetState redraws only
#     the focused row (P3-12);
#   * multi-column (columns, dividers, Left / Right, the bar's Max);
#   * fresh Cyrillic and CJK pages == a full repaint (CJK through writeRows);
#   * 60 000 items: End / Home in one FocusItem each;
#   * the Formatter (one call per visible row, FV's MaxLen), an IsSelected
#     override asked once per drawn row and winning over Marks;
#   * the direct list -> bar link: the bar's cmScrollBarChanged never comes
#     back to the built-in list (one list write per PgDn), but reaches other
#     listeners, and a list class with its own HandleEvent (L7);
#   * ChangeBounds: the bar's page step (FV), then SetRange at the next key;
#   * reserved List / Marks names (_fv*, __fv*: the painters' arrays); an
#     ASCII page through writeLines under any IFS; Space / Ins with Marks
#     paint the marked row once (a handler moving the focus: still
#     painted); the direct link's skip only for the list's vertical bar.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "023: TListViewer"

# key KEY... — each key through the application (TTApp: the user override +
# inherited); REPLY = "Focused TopItem bar-Value" after the last
key() {
    local k
    for k; do
        fv.drivers.clearEvent
        if [ "$k" = space ]; then FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=' '; else FV_EV_WHAT=evKeyDown FV_EV_KEY=$k; fi
        fv.views._virt app HandleEvent
    done
    REPLY="${w2l_data[Focused]} ${w2l_data[TopItem]} ${w2__fvsb1_data[Value]}"
}
# a listener leaf (user HandleEvent: records broadcasts as CMD:INFO;)
class TLis : TView
    public
        override proc HandleEvent
end
TLis.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then LOG+="$FV_EV_COMMAND:$FV_EV_INFO;"; fi; }
build TLis
LOG=''
# a dialog-sized window: CGrayDialog's 32 entries (FV's TDialog palette)
class TGDlg : TWindow
    public
        override func GetPalette
end
TGDlg.GetPalette() { RESULT='32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63'; }
build TGDlg
# the list's paints: CL1..CL2 of each _lvDraw run (wrapped by draws_on)
src=$(declare -f fv.views._lvDraw)
eval "__t_${src}"
DRAWS=''
draws_on() { fv.views._lvDraw() { DRAWS+="$FV_CLIP_Y1-$FV_CLIP_Y2 "; __t_fv.views._lvDraw "$@"; }; DRAWS=''; }
draws_off() { eval "$src"; }

fvw_lscene 80 24
kt_test_start "construction: ofFirstClick + ofSelectable, evBroadcast + evMouseWheel, NumCols 1, the bar linked; Range from listSetRange"
r="$(( w2l_data[Options] & (FV_OF_FIRSTCLICK | FV_OF_SELECTABLE) )) $(( w2l_data[EventMask] & (FV_EM_BROADCAST | FV_EM_MOUSEWHEEL) ))"
r+=" ${w2l_data[NumCols]} ${w2l_data[VScrollBar]} [${w2l_data[HScrollBar]}] ${w2l_data[Range]} ${w2l_data[TopItem]} ${w2l_data[Focused]}"
r+=" ${w2__fvsb1_data[Min]} ${w2__fvsb1_data[Max]} ${w2__fvsb1_data[PgStep]} ${w2__fvsb1_data[ArStep]}"
want="$(( FV_OF_FIRSTCLICK | FV_OF_SELECTABLE )) $(( FV_EM_BROADCAST | FV_EM_MOUSEWHEEL )) 1 w2__fvsb1 [] 100 0 0 0 79 20 1"
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "refusals before anything is made (rc 2, one Error line): NUMCOLS 0 / x / 1025, a bar that is not a TScrollBar; a horizontal bar gets SetStep(SizeX div NumCols, 1)"
r=''
TListViewer.new bad1 0 0 10 5 0 2>"$FVW_TMP/e1" || r+="$?"
TListViewer.new bad2 0 0 10 5 x 2>>"$FVW_TMP/e1" || r+="$?"
TListViewer.new bad3 0 0 10 5 1025 2>>"$FVW_TMP/e1" || r+="$?"
TListViewer.new bad4 0 0 10 5 1 w1l 2>>"$FVW_TMP/e1" || r+="$?"
mapfile -t e < "$FVW_TMP/e1"
fv.views.isView bad1 || r+=",dead"
bad1.delete; bad2.delete; bad3.delete; bad4.delete
TScrollBar.new hz 0 0 20 1
TListViewer.new hl 0 0 30 5 3 hz
r+=",${hz_data[PgStep]} ${hz_data[ArStep]}"
hl.delete; hz.delete
if [[ $r == '2222,dead,10 1' && ${#e[@]} == 4 && ${e[0]} == 'Error: fv.views: TListViewer.Create:'* ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] [${e[*]}]"; fi

fv.views.drawView app
kt_test_start "the first paint: ' item N' padded to the list's 38 cells; the focused row in entry 3 of 6 6 7 2 6 (a plain window, D25), the rest in 2; the bar ▲ ■ ▒ … ▼"
fvw_cells 41 1 38; a="$RESULT|${REPLY:0:3}"
fvw_cells 41 2 38; b="$RESULT|${REPLY:0:3}"
fv.views.getColor w2l 2; c2=$RESULT; fv.views.getColor w2l 3; c3=$RESULT
x=''; for (( y = 1; y <= 21; y++ )); do fv.video.getRow "$y"; x+=${RESULT:79:1}; done
want1=" item 0$(printf '%31s' '')|$c3$c3$c3" want2=" item 1$(printf '%31s' '')|$c2$c2$c2"
if [[ $a == "$want1" && $b == "$want2" && $c2 != "$c3" && $x == '▲■▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▼' ]] && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "[$a] [$b] c2 $c2 c3 $c3 bar [$x] $FVW_DIFF"; fi

kt_test_start "the palettes: 6 6 7 2 6 in a plain window (D25: marked rows in the window's entry 2, owner 2026-11-21), CListViewer 26 26 27 28 29 under a dialog-sized owner (FV)"
TGDlg.new gd 0 0 30 10 G 0
TListViewer.new gl 1 1 29 9
fv.views.insert gd gl
fv.views.getColor gl 2; a=$RESULT; fv.views.getColor gd 26; b=$RESULT
fv.views.getColor gl 4; a+=$RESULT; fv.views.getColor gd 28; b+=$RESULT
fv.views.getColor w2l 2; c=$RESULT; fv.views.getColor w2 6; d=$RESULT
fv.views.getColor w2l 3; c+=$RESULT; fv.views.getColor w2 7; d+=$RESULT
fv.views.getColor w2l 4; c+=$RESULT; fv.views.getColor w2 2; d+=$RESULT
gd.delete
if [[ $a == "$b" && $c == "$d" && ${a:0:1} != "${a:1:1}" && ${c:2:1} != "${c:0:1}" ]]; then kt_test_pass "ok"; else kt_test_fail "dialog [$a] vs [$b], window [$c] vs [$d]"; fi

kt_test_start "keys: Down, PgDn (FocusItem moves TopItem: the item the bottom row), PgUp, End, Home, Ctrl+PgDn / Ctrl+PgUp (the page's last / first), Up at the top; the bar follows TopItem"
r=''
for k in kbDown kbDown kbPgDn kbPgUp kbEnd kbHome kbCtrlPgDn kbCtrlPgUp kbUp; do key "$k"; r+="$REPLY,"; done
if [[ $r == '1 0 0,2 0 0,23 3 3,2 2 2,99 79 79,0 0 0,20 0 0,0 0 0,0 0 0,' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi

kt_test_start "WordStar keys through ctrlToArrow: Ctrl+X Down, Ctrl+E Up, Ctrl+C PgDn, Ctrl+R PgUp, Ctrl+F End, Ctrl+A Home; Left / Right with one column pass the list"
r=''
for k in kbCtrlX kbCtrlX kbCtrlE kbCtrlC kbCtrlR kbCtrlF kbCtrlA; do key "$k"; r+="$REPLY,"; done
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbRight; fv.views._virt w2l HandleEvent; r+="$FV_EV_WHAT"
if [[ $r == '1 0 0,2 0 0,1 0 0,22 2 2,1 1 1,99 79 79,0 0 0,evKeyDown' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] $FVW_DIFF"; fi

kt_test_log "rule 4: Down inside the page = one write (one drawPart over the two rows), 2 dispatches (TTApp + inherited); PgDn = the list's one write (+ the bar's when its indicator moves)"
key kbHome
fvw_budgetw "Down" 2 key kbDown
a=$FVW_LASTW
fvw_budgetw "PgDn" 2 key kbPgDn
b=$FVW_LASTW
kt_test_start "... their write counts: Down 1, PgDn <= 2"
if (( a == 1 && b <= 2 )); then kt_test_pass "Down $a, PgDn $b"; else kt_test_fail "Down $a, PgDn $b"; fi

kt_test_start "Space: SelectItem -> cmListItemSelected to the owner (INFO = the list); with Marks: Space toggles the focused item's mark, Ins toggles and moves down; Ins without Marks passes"
TLis.new lis 0 0 1 1; lis_data[EventMask]=$(( 0xFFFF )); fv.views.insert w2 lis
key kbHome
LOG=''; key space; r="$REPLY|$LOG|"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbIns; fv.views._virt w2l HandleEvent; r+="$FV_EV_WHAT|"
declare -A MK=()
w2l_data[Marks]=MK
marks() { local k; REPLY=''; for k in 0 1 2 3 4 5; do if [[ -n ${MK[$k]-} ]]; then REPLY+=$k; fi; done; }
LOG=''; key space; marks; r+="${w2l_data[Focused]} $REPLY|"
key kbDown kbDown kbIns kbIns; marks; r+="${w2l_data[Focused]} $REPLY|"
key kbUp space; marks; r+="${w2l_data[Focused]} $REPLY|$LOG"
want='0 0 0|cmListItemSelected:w2l;|evKeyDown|0 0|4 023|3 02|'
s='cmListItemSelected:w2l;'
if [[ $r == "$want$s$s$s$s" ]] && fvw_full app; then kt_test_pass "ok"
else kt_test_fail "[$r] want [$want$s$s$s$s] $FVW_DIFF"; fi
kt_test_start "marks show in a plain window (D25, owner 2026-11-21): a marked row in the window's entry 2, unlike a plain row (6); the focused row keeps entry 7 when marked too"
MK[3]=1; fv.views.listDrawItem w2l 3
fv.views.getColor w2l 2; c2=$RESULT; fv.views.getColor w2l 3; c3=$RESULT; fv.views.getColor w2l 4; c4=$RESULT
fv.views.getColor w2 2; wc2=$RESULT
fvw_cells 41 2 1; r1=$REPLY; fvw_cells 41 3 1; r2=$REPLY; fvw_cells 41 4 1; r3=$REPLY
unset 'MK[3]'; fv.views.listDrawItem w2l 3
if [[ $r1 == "$c2" && $r2 == "$c4" && $c4 == "$wc2" && $c4 != "$c2" && $r3 == "$c3" ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "plain [$r1] marked [$r2] focused [$r3]; colours 2 [$c2] 3 [$c3] 4 [$c4] window 2 [$wc2]"; fi

kt_test_start "Space / Ins with Marks paint the marked row once (Space: its row; Ins: the old and the new row in one drawPart, one write); a handler that moves the focus on cmListItemSelected: the marked row still painted"
key kbHome kbDown kbDown kbDown
draws_on; fvw_writes_on; FVW_WRITES=0
key space; r="$DRAWS$FVW_WRITES,"; DRAWS='' FVW_WRITES=0
key kbIns; r+="$DRAWS$FVW_WRITES,"
fvw_writes_off; draws_off
marks; r+="${w2l_data[Focused]} $REPLY,"
# (the listener moves the focus to item 0 when it hears the selection, by
# hand: no paint of its own)
class TMovF : TView
    public
        override proc HandleEvent
end
TMovF.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ] && [ "$FV_EV_COMMAND" = cmListItemSelected ]; then w2l_data[Focused]=0; fi; }
build TMovF
TMovF.new movf 0 0 1 1; movf_data[EventMask]=$(( 0xFFFF )); fv.views.insert w2 movf
key kbDown kbDown kbDown kbDown
draws_on
key kbIns; r+="${w2l_data[Focused]} ${MK[8]-} $DRAWS"
draws_off
unset 'MK[8]'; fv.views.listDrawItem w2l 8
fv.views.delete w2 movf; movf.delete
if [[ $r == '3-4 1,3-5 1,4 02,9 1 8-9 0-1 9-10 ' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] (want 3-4 1,3-5 1,4 02,9 1 8-9 0-1 9-10 ) $FVW_DIFF"; fi

kt_test_start "Marks in a dialog palette: a marked row in colour 4 (≠ 2), the focused one in 3; an IsSelected override (odd items) asked once per drawn row, winning over Marks"
TGDlg.new gd 0 0 30 10 G 0
TListViewer.new gl 1 1 29 9
fv.views.insert gd gl
fvw_items GL 30
declare -A GM=([2]=1 [3]=1)
gl_data[List]=GL gl_data[Marks]=GM
fv.views.listSetRange gl 30
fv.views.insert desk gd
fv.views.getColor gl 2; c2=$RESULT; fv.views.getColor gl 3; c3=$RESULT; fv.views.getColor gl 4; c4=$RESULT
r=''; for y in 1 2 3 4 5; do fv.video.getRow "$y"; r+=${REPLY:2:1}; done
class TLvOdd : TListViewer
    public
        override func IsSelected
end
TLvOdd.IsSelected() { ODDN=$(( ODDN + 1 )); (( $1 % 2 == 1 )); }
build TLvOdd
ODDN=0
TLvOdd.new go 1 1 29 9
fv.views.delete gd gl; gl.delete
fv.views.insert gd go
go_data[List]=GL go_data[Marks]=GM
fv.views.listSetRange go 30
ODDN=0; fvw_count_on; FVW_CALLS=0
fv.views.drawView go
n=$FVW_CALLS
fvw_count_off
s=''; for y in 1 2 3 4 5; do fv.video.getRow "$y"; s+=${REPLY:2:1}; done
# (the focused item of an active list is colour 3 whatever IsSelected says:
# the override is asked for the other 7 rows)
if [[ $c3 != "$c4" && $c2 != "$c4" && $r == "$c3$c2$c4$c4$c2" && $ODDN == 7 && $n == 7 && $s == "$c3$c4$c2$c4$c2" ]]; then kt_test_pass "ok"
else kt_test_fail "marks [$r] want [$c3$c2$c4$c4$c2]; override [$s] want [$c3$c4$c2$c4$c2] asked $ODDN dispatches $n"; fi
fv.views.delete desk gd; gd.delete
w2l_data[Marks]=''

kt_test_start "listSetRange: Focused past N -> 0, TopItem and the bar's Max follow (Max = Min: ▓); back to 100; refusals rc 2"
key kbEnd
fv.views.listSetRange w2l 10; a="${w2l_data[Range]} ${w2l_data[Focused]} ${w2l_data[TopItem]} ${w2__fvsb1_data[Max]}"
fv.video.getRow 2; a+=" ${RESULT:79:1}"
fv.views.listSetRange w2l 100; a+=",${w2__fvsb1_data[Max]}"
r=''
fv.views.listSetRange w2l -1 || r+="$?"
fv.views.listSetRange w2__fvsb1 5 || r+="$?"
fv.views.listSetRange w2l || r+="$?"
if [[ $a == '10 0 0 0 ▓,79' && $r == 222 ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] [$r] $FVW_DIFF"; fi

kt_test_start "listSetTopItem (the focus stays, off the page), listFocusItem (clamped to 0 .. Range-1: the top follows), listDrawItem (off the page: no write)"
fv.views.listSetTopItem w2l 50; a="${w2l_data[Focused]} ${w2l_data[TopItem]} ${w2__fvsb1_data[Value]}"
fv.views.listFocusItem w2l 1000; a+=",${w2l_data[Focused]} ${w2l_data[TopItem]}"
fv.views.listFocusItem w2l -5; a+=",${w2l_data[Focused]} ${w2l_data[TopItem]}"
fvw_writes_on; FVW_WRITES=0
fv.views.listDrawItem w2l 40; a+=",$FVW_WRITES"
FVW_WRITES=0; fv.views.listDrawItem w2l 3; a+=" $FVW_WRITES"
fvw_writes_off
r=''
fv.views.listFocusItem w2l x || r+="$?"
fv.views.listSetTopItem bg 1 || r+="$?"
fv.views.listDrawItem w2l 1 2 || r+="$?"
if [[ $a == '0 50 50,99 79,0 0,0 1' && $r == 222 ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] [$r] $FVW_DIFF"; fi

kt_test_start "ShowSBar: another window selected -> the list loses sfActive, its bar is hidden (the frame shows there) and only its focused row is redrawn (P3-12); back -> shown (the window comes to the front: drawn whole)"
draws_on
fv.views.select w1
a="$(( w2__fvsb1_data[State] & FV_SF_VISIBLE )) $DRAWS"
fv.video.getRow 5; a+="${RESULT:79:1}"
fvw_full app || a+=" diff1 $FVW_DIFF"
DRAWS=''
fv.views.select w2
a+=",$(( w2__fvsb1_data[State] & FV_SF_VISIBLE )) $DRAWS"
fv.video.getRow 5; a+="${RESULT:79:1}"
draws_off
if [[ $a == "0 0-1 │,$FV_SF_VISIBLE 0-21 ▒" ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] $FVW_DIFF"; fi

kt_test_start "the direct link (P3-4): PgDn moves the bar, whose cmScrollBarChanged reaches another listener but never the list (one list paint per PgDn)"
key kbHome
draws_on; LOG=''
key kbPgDn kbPgDn
a=$DRAWS
draws_off
if [[ $a == '0-21 0-21 ' && $LOG == 'cmScrollBarChanged:w2__fvsb1;cmScrollBarChanged:w2__fvsb1;' ]]; then kt_test_pass "ok"; else kt_test_fail "paints [$a] log [$LOG]"; fi

kt_test_start "L7: a list class with its own HandleEvent gets FV's broadcast from its bar (and still draws right)"
class TLvH : TListViewer
    public
        override proc HandleEvent
end
TLvH.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then HLOG+="$FV_EV_COMMAND;"; fi; inherited HandleEvent "$@"; }
build TLvH
HLOG=''
fv.views.delete w2 w2l; w2l.delete
TLvH.new w2l 1 1 39 22 1 '' w2__fvsb1
w2l_data[List]=FVW_L1 w2l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
fv.views.listSetRange w2l 100
fv.views.insert w2 w2l
HLOG=''
key kbPgDn
if [[ $HLOG == *cmScrollBarChanged* && ${w2l_data[TopItem]} == "${w2__fvsb1_data[Value]}" ]] && fvw_full app; then kt_test_pass "ok [$HLOG]"; else kt_test_fail "[$HLOG] $REPLY $FVW_DIFF"; fi
fv.views.delete w2 lis; lis.delete

kt_test_start "the Formatter: called once per visible row with (INDEX, SizeX+1: FV's GetText MaxLen), its RESULT the text; a name that is no function: the items' text (one debug line)"
fmt() { FMTN=$(( FMTN + 1 )); FMTA=$2; RESULT="F$1"; }
w2l_data[Formatter]=fmt
key kbHome
FMTN=0
fv.views.drawView w2l
fvw_cells 41 2 5; a="$FMTN $FMTA $RESULT"
w2l_data[Formatter]=nofmt
FMTN=0
fv.views.drawView w2l
fvw_cells 41 2 7; a+=",$FMTN $RESULT"
w2l_data[Formatter]=''
if [[ $a == '21 39  F1  ,0  item 1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a]"; fi

kt_test_start "reserved List / Marks names (_fv* / __fv*, any case: fv.views' globals, the painters' local arrays _fvw_t _fvw_r ...): no items, no marks — never the painter's own array; Space / Ins leave such a Marks array untouched"
key kbHome
fv.views.drawView w2l
fvw_cells 41 3 8; a="[$RESULT]"
for n in _fvw_r _fvw_x _fvw_t _FVW_A _fvz __fvx __FV_X; do
    eval "$n=(\"\${FVW_L1[@]}\")"
    w2l_data[List]=$n
    fv.views.drawView w2l
    fvw_cells 41 3 8; a+="[$RESULT]"
done
w2l_data[List]=FVW_L1
fv.views.drawView w2l
declare -gA _fvw_s=() _fvw_q=()
w2l_data[Marks]=_fvw_s; key space
w2l_data[Marks]=_fvw_q; key kbIns
a+=" ${#_fvw_s[@]}${#_fvw_q[@]} $REPLY"
w2l_data[Marks]=''
unset _fvw_r _fvw_x _fvw_t _FVW_A _fvz __fvx __FV_X _fvw_s _fvw_q
if [[ $a == "[ item 2 ]$(printf '[%8s]' '' '' '' '' '' '' '') 00 1 0 0" ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] $FVW_DIFF"; fi

kt_test_start "ChangeBounds: the window shrinks, the list with it (gfGrowHiY): the bar's PgStep = SizeY*NumCols (FV); the next SetTopItem sets the range again (LastY): Max = Range - SizeY, PgStep SizeY-1"
fv.views.growTo w2 40 12
a="${w2l_data[SizeY]} ${w2__fvsb1_data[PgStep]}"
key kbPgDn
a+=",${w2__fvsb1_data[Max]} ${w2__fvsb1_data[PgStep]}"
if [[ $a == '10 10,90 9' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] $FVW_DIFF"; fi
fv.views.growTo w2 40 23
fvw_unlscene

kt_test_start "multi-column (3 columns, 30 x 5): blank + text cut to the column + │ (colour 5); the last column's divider past the row; Right / Left by a column, PgDn by 15; the bar's Max (FV: the last columns stay in view)"
fvw_screen 80 24
TGroup.new mc 0 0 80 24; fvw_expose mc
TView.new mbg 0 0 80 24; fv.views.insert mc mbg
TWindow.new mw 0 0 33 8 M 1
fv.views.standardScrollBar mw "$FV_SB_VERTICAL"
TListViewer.new ml 1 1 31 6 3 '' mw__fvsb1
fv.views.insert mw ml
fvw_items ML 50
ml_data[List]=ML
fv.views.listSetRange ml 50
fv.views.insert mc mw
fvw_root mc
fv.views.drawView mc
fvw_cells 1 1 30; a="$RESULT"
fv.views.getColor ml 5; c5=$RESULT
d=${REPLY:10:1}${REPLY:21:1}
mk() { local k; for k; do fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$k; fv.views._virt mc HandleEvent; done; REPLY="${ml_data[Focused]} ${ml_data[TopItem]}"; }
r="${mw__fvsb1_data[Max]}"
mk kbRight; r+=",$REPLY"; mk kbRight kbRight; r+=",$REPLY"; mk kbLeft; r+=",$REPLY"; mk kbPgDn; r+=",$REPLY"; mk kbEnd; r+=",$REPLY"
if [[ $a == ' item 0   │ item 5   │ item 10' && $d == "$c5$c5" && $r == '35,5 0,15 5,10 5,25 15,49 35' ]] && fvw_full mc; then kt_test_pass "ok"
else kt_test_fail "[$a] dividers [$d] want [$c5$c5] [$r] $FVW_DIFF"; fi

kt_test_start "an ASCII page takes writeLines whatever the caller's IFS (newline, tab, empty, default; the rows' join): no writeRows call, several columns and one"
WR=0 WL=0
eval "__t_wr_$(declare -f fv.views.writeRows)"
eval "__t_wl_$(declare -f fv.views.writeLines)"
fv.views.writeRows() { WR=$(( WR + 1 )); __t_wr_fv.views.writeRows "$@"; }
fv.views.writeLines() { WL=$(( WL + 1 )); __t_wl_fv.views.writeLines "$@"; }
r=''
for ifs in $'\n' $'\t' '' $' \t\n'; do
    WR=0 WL=0
    IFS=$ifs; mk kbHome kbPgDn; IFS=$' \t\n'
    r+="$WR:$WL,"
done
mc.delete
fvw_lscene 80 24 400
fv.views.drawView app
for ifs in $'\n' $'\t' '' $' \t\n'; do
    WR=0 WL=0
    IFS=$ifs; key kbPgDn; IFS=$' \t\n'
    r+="$WR:$WL,"
done
eval "$(declare -f __t_wr_fv.views.writeRows | sed 's/^__t_wr_//')"
eval "$(declare -f __t_wl_fv.views.writeLines | sed 's/^__t_wl_//')"
unset -f __t_wr_fv.views.writeRows __t_wl_fv.views.writeLines
if [[ -z ${r//0:[123456789],/} && ${#r} == 32 ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] (writeRows:writeLines per action) $FVW_DIFF"; fi
fvw_unlscene

kt_test_start "fresh Cyrillic pages (writeLines: narrow cells == characters): PgDn x6 over rows never shown, each == a full repaint; the row text"
fvw_lscene 80 24 400 cyr
fv.views.drawView app
bad=''
for i in 1 2 3 4 5 6; do key kbPgDn; fvw_full app || bad+=" [PgDn $i: $FVW_DIFF]"; done
fvw_cells 41 1 12
if [[ -z $bad && $RESULT == ' Отчёт_'"${w2l_data[TopItem]}"* ]]; then kt_test_pass "ok"; else kt_test_fail "$bad [$RESULT]"; fi
fvw_unlscene

kt_test_start "fresh CJK pages (writeRows: wide cells): PgDn x6 and Down at the edge, each == a full repaint; a row holds its 4 CJK characters"
fvw_lscene 80 24 400 cjk
fv.views.drawView app
bad=''
for i in 1 2 3 4 5 6; do key kbPgDn; fvw_full app || bad+=" [PgDn $i: $FVW_DIFF]"; done
key kbCtrlPgDn kbDown kbDown
fvw_full app || bad+=" [Down: $FVW_DIFF]"
fv.video.getRow 21
want=${FVW_L1[${w2l_data[Focused]}]}
if [[ -z $bad && $RESULT == *"${want:0:1}"*"${want:3:1}"* ]]; then kt_test_pass "ok"; else kt_test_fail "$bad [$RESULT] want [$want]"; fi
fvw_unlscene

kt_test_log "60 000 items: End and Home each one FocusItem (one list write, the bar's indicator moved: one more), the bar at Range - SizeY"
fvw_lscene 80 24 60000
fv.views.drawView app
fvw_budgetw "End (60 000 items)" 2 key kbEnd
a="$REPLY $FVW_LASTW"
fvw_budgetw "Home (60 000 items)" 2 key kbHome
a+=",$REPLY $FVW_LASTW"
kt_test_start "... End -> item 59999 at the bottom, the bar at 59979; Home back"
if [[ $a == '59999 59979 59979 2,0 0 0 2' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] $FVW_DIFF"; fi
fvw_unlscene

kt_test_start "the direct link's skip is exact: while the list moves its vertical bar, only THAT bar's cmScrollBarChanged passes it by; its horizontal bar moved meanwhile (by a listener) still reaches the list (FV: drawn)"
fvw_lscene 80 24
fv.views.standardScrollBar w2 "$FV_SB_HORIZONTAL"; hb=$RESULT
fv.views.delete w2 w2l; w2l.delete
TListViewer.new w2l 1 1 39 22 1 "$hb" w2__fvsb1
w2l_data[List]=FVW_L1 w2l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
fv.views.listSetRange w2l 100
fv.views.insert w2 w2l
fv.views.scrollBarSet "$hb" 0 0 10
class TMoveH : TView
    public
        override proc HandleEvent
end
TMoveH.HandleEvent() {
    if [ "$FV_EV_WHAT" = evBroadcast ] && [ "$FV_EV_COMMAND" = cmScrollBarChanged ] && [ "$FV_EV_INFO" = w2__fvsb1 ]; then fv.views.scrollBarSet "$MOVEH" 3; fi
}
build TMoveH
TMoveH.new mh 0 0 1 1; mh_data[EventMask]=$(( 0xFFFF )); fv.views.insert w2 mh
MOVEH=$hb
fv.views.drawView app
eval "__t_bc_$(declare -f fv.views._lvBcast)"
BLOG=''
fv.views._lvBcast() { if [ "$FV_EV_COMMAND" = cmScrollBarChanged ]; then BLOG+="$FV_EV_INFO;"; fi; __t_bc_fv.views._lvBcast "$@"; }
key kbPgDn
eval "$(declare -f __t_bc_fv.views._lvBcast | sed 's/^__t_bc_//')"
unset -f __t_bc_fv.views._lvBcast
MOVEH=''
fvw_cells 41 1 6
if [[ $BLOG == "$hb;" && ${w2l_data[TopItem]} == "${w2__fvsb1_data[Value]}" && $RESULT == ' em 1 ' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$BLOG] want [$hb;] top ${w2l_data[TopItem]} bar ${w2__fvsb1_data[Value]} [$RESULT] $FVW_DIFF"; fi
fvw_unlscene

kt_test_log "023_ListViewer.sh completed"
