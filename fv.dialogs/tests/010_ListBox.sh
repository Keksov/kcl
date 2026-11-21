#!/usr/bin/env bash
# 010_ListBox.sh - TListBox (FV dialogs.inc TListBox; design P3 §1.2, §4.6,
# §5) on fv.views' TListViewer:
#   * the constructor: TListViewer's with no horizontal bar and the given
#     vertical one, NUMCOLS, Range 0 (FV SetRange(0)); its HandleEvent is
#     TListViewer's (elided);
#   * fv.dialogs.newList LB ARRAY [FMT] (FV NewList): List, Formatter, the
#     range, item 0 focused, drawn (== a full repaint); a new list replaces
#     it; '' = no items; the NewList alias (D16); refusals (not a list box,
#     a bad or associative array name, a wrong count) with RESULT '';
#   * the data: DataSize 1, GetData = Focused, SetData focuses the item (kept
#     in the range) and draws; through fv.dialogs.getData / setData in a
#     dialog with an input line (FV's order);
#   * the long checklist (D29): Marks set, Space toggles the focused item's
#     mark (SelectItem -> cmListItemSelected to the owner), Ins toggles and
#     moves down; the marked rows in colour 4; getData answers Focused, the
#     marks stay in the caller's array; a formatter's rows; 10 000 items.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "010: TListBox"

# a dialog with a list box (one column, its own vertical bar) and an input line
scene() {
    fvw_tscene 80 24
    TDialog.new dlg 10 3 70 20 'Pick'
    TScrollBar.new sb 30 2 31 12
    TListBox.new lb 2 2 30 12 1 sb
    TInputLine.new il 33 2 55 3 20
    fv.views.insert dlg sb; fv.views.insert dlg lb; fv.views.insert dlg il
    fv.views.select lb
    fv.views.insert desk dlg; fv.views.select dlg
    fv.views.drawView app
}
unscene() { app.delete; if fv.views.isView dlg; then dlg.delete; fi; }
k() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-} FV_EV_BASE=''; fv.views._virt dlg HandleEvent; }

scene
kt_test_start "the constructor: TListViewer's fields, no horizontal bar, the vertical one, Range 0; HandleEvent is TListViewer's built-in"
o=TListBox_class_method_owner
if [[ ${lb_data[NumCols]} == 1 && -z ${lb_data[HScrollBar]} && ${lb_data[VScrollBar]} == sb && ${lb_data[Range]} == 0 && -z ${lb_data[List]} ]] \
   && [ "${TListBox_class_method_owner[HandleEvent]}" = TListViewer ] && [ "${__FV_VW_IMPL[TListViewer.HandleEvent]}" = fv.views._lvEvent ]; then kt_test_pass ok
else kt_test_fail "numcols ${lb_data[NumCols]} hsb [${lb_data[HScrollBar]}] vsb [${lb_data[VScrollBar]}] range ${lb_data[Range]}"; fi
kt_test_start "newList: List and Formatter set, the range its length, item 0 focused, drawn (== a full repaint); RESULT kept"
FRUIT=(apple banana cherry date elderberry fig grape)
RESULT=keep; fv.dialogs.newList lb FRUIT; r=$RESULT
if [[ $r == keep && ${lb_data[List]} == FRUIT && ${lb_data[Range]} == 7 && ${lb_data[Focused]} == 0 ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "result $r list ${lb_data[List]} range ${lb_data[Range]}"; fi
kt_test_start "the rows show the items; Down moves the focus (rule 4)"
k kbDown
fvg_cells 12 6 8; a=$RESULT
if [[ ${lb_data[Focused]} == 1 && $a == ' banana ' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "${lb_data[Focused]} [$a]"; fi
kt_test_start "a formatter's rows (FMT INDEX WIDTH -> RESULT); a new list replaces the old (focus back to 0); '' = no items"
fmt() { RESULT="#$1 ${FRUIT[$1]^^}"; }
fv.dialogs.newList lb FRUIT fmt
fvg_cells 12 5 10; a=$RESULT
fv.dialogs.newList lb ''; b="${lb_data[Range]}:${lb_data[List]}"
fv.dialogs.newList lb FRUIT
if [[ $a == ' #0 APPLE ' && $b == '0:' && ${lb_data[Formatter]} == '' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] $b"; fi
kt_test_start "the NewList alias (D16)"
SHORT=(one two); lb.NewList SHORT
if [[ ${lb_data[Range]} == 2 && ${lb_data[List]} == SHORT ]]; then kt_test_pass ok; else kt_test_fail "${lb_data[Range]}"; fi
fv.dialogs.newList lb FRUIT
kt_test_start "refusals: not a list box, a bad name, an associative array, a wrong count -> rc 2, RESULT ''"
declare -A AS=([a]=1)
r=''
RESULT=x; fv.dialogs.newList il FRUIT || r+="$?$RESULT"
RESULT=x; fv.dialogs.newList lb 'bad name' || r+="$?$RESULT"
RESULT=x; fv.dialogs.newList lb __fvx || r+="$?$RESULT"
RESULT=x; fv.dialogs.newList lb AS || r+="$?$RESULT"
RESULT=x; fv.dialogs.newList lb || r+="$?$RESULT"
if [[ $r == 22222 && ${lb_data[List]} == FRUIT ]]; then kt_test_pass ok; else kt_test_fail "$r"; fi

kt_test_section "010: data"
kt_test_start "DataSize 1; GetData = Focused; SetData focuses (kept in the range) and draws"
fv.dialogs.dataSize lb; a=$RESULT
k kbDown; k kbDown
D=(); fv.views._virt lb GetData D 0; b=${D[0]}
D=(5); fv.views._virt lb SetData D 0; c=${lb_data[Focused]}
D=(99); fv.views._virt lb SetData D 0; d=${lb_data[Focused]}
D=(x); fv.views._virt lb SetData D 0; e=${lb_data[Focused]}
if [[ $a == 1 && $b == 2 && $c == 5 && $d == 6 && $e == 0 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$a $b $c $d $e"; fi
kt_test_start "getData / setData of the dialog: the list box's Focused and the input line's text in FV's order"
D=(3 'tea time'); fv.dialogs.setData dlg D
D=(); fv.dialogs.getData dlg D
if [[ ${D[0]} == 3 && ${D[1]} == 'tea time' && ${#D[@]} == 2 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "${D[*]}"; fi
unscene

kt_test_section "010: the long checklist (D29)"
scene
LOG=''
class TLog : TView
    public
        override proc HandleEvent
end
TLog.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then LOG+="$FV_EV_COMMAND:$FV_EV_INFO;"; fi; }
build TLog
TLog.new log 0 0 1 1; log_data[EventMask]=$(( 0xFFFF )); fv.views.insert dlg log
ITEMS=(); for (( i = 0; i < 10000; i++ )); do ITEMS[i]="item $i"; done
declare -A MARK=()
fv.dialogs.newList lb ITEMS
lb_data[Marks]=MARK
fv.views.focus lb
fv.views.getColor lb 4; c4=$RESULT
kt_test_start "Space toggles the focused item's mark and broadcasts cmListItemSelected (FV SelectItem); drawn in colour 4 once unfocused"
k kbDown; k kbChar ' '; k kbDown
fvg_cells 13 6 5
if [[ ${MARK[1]-} == 1 && $LOG == *'cmListItemSelected:lb;'* && ${REPLY:0:1} == "$c4" ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "mark [${MARK[1]-}] log [$LOG] [$REPLY]"; fi
kt_test_start "Space again unmarks; Ins toggles and moves down (twice: items 1 and 2)"
k kbUp; k kbChar ' '; a=${MARK[1]-unset}
k kbIns; k kbIns
if [[ $a == unset && ${MARK[1]-} == 1 && ${MARK[2]-} == 1 && ${lb_data[Focused]} == 3 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$a ${MARK[*]} ${lb_data[Focused]}"; fi
kt_test_start "End over 10 000 items, Ins on the last: marked, the focus stays on it; getData answers Focused, the marks stay in MARK"
k kbEnd; k kbIns
D=(); fv.dialogs.getData dlg D
if [[ ${MARK[9999]-} == 1 && ${lb_data[Focused]} == 9999 && ${D[0]} == 9999 && ${#MARK[@]} == 3 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "${lb_data[Focused]} ${D[*]} ${!MARK[*]}"; fi
unscene

kt_test_log "010_ListBox.sh completed"
