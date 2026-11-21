#!/usr/bin/env bash
# 016_Elision.sh - every built-in virtual of fv.dialogs runs without a
# dispatch (registered in fv.views' elision table) and, overridden by a class
# of yours with `inherited`, keeps its behaviour at one dispatch per use:
#   * a dialog of subclasses that override every virtual with `inherited`
#     gives the same screens, data and results as the built-in dialog for the
#     same keys (Tab, Space, a radio move, hot keys, Enter -> cmOK);
#   * the built-in dialog: 0 dispatches for those keys;
#   * a widget whose HandleEvent is overridden is never skipped by the
#     hot-key map (called for every key in its phases);
#   * the func answers: GetPalette / GetText / GetHelpCtx / DataSize answer
#     through the override, Mark / Valid by rc.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "016: overrides with inherited"
class XDialog : TDialog
    public
        override proc HandleEvent
        override func GetPalette
        override func Valid
        override proc CalcBounds
end
XDialog.HandleEvent() { inherited HandleEvent "$@"; }
XDialog.GetPalette() { inherited GetPalette "$@"; }
XDialog.Valid() { inherited Valid "$@"; }
XDialog.CalcBounds() { inherited CalcBounds "$@"; }
build XDialog
class XButton : TButton
    public
        override proc Draw
        override proc HandleEvent
        override func GetPalette
        override proc SetState
        override proc Press
end
XButton.Draw() { inherited Draw "$@"; }
XButton.HandleEvent() { XBH=$(( ${XBH:-0} + 1 )); inherited HandleEvent "$@"; }
XButton.GetPalette() { inherited GetPalette "$@"; }
XButton.SetState() { inherited SetState "$@"; }
XButton.Press() { inherited Press "$@"; }
build XButton
class XText : TStaticText
    public
        override proc Draw
        override func GetPalette
        override func GetText
end
XText.Draw() { inherited Draw "$@"; }
XText.GetPalette() { inherited GetPalette "$@"; }
XText.GetText() { inherited GetText "$@"; }
build XText
class XLabel : TLabel
    public
        override proc Draw
        override func GetPalette
        override proc HandleEvent
end
XLabel.Draw() { inherited Draw "$@"; }
XLabel.GetPalette() { inherited GetPalette "$@"; }
XLabel.HandleEvent() { inherited HandleEvent "$@"; }
build XLabel
class XCheck : TCheckBoxes
    public
        override proc Draw
        override proc HandleEvent
        override func GetPalette
        override proc SetState
        override func GetHelpCtx
        override func Mark
        override proc Press
        override proc MovedTo
        override func DataSize
        override proc GetData
        override proc SetData
end
XCheck.Draw() { inherited Draw "$@"; }
XCheck.HandleEvent() { inherited HandleEvent "$@"; }
XCheck.GetPalette() { inherited GetPalette "$@"; }
XCheck.SetState() { inherited SetState "$@"; }
XCheck.GetHelpCtx() { inherited GetHelpCtx "$@"; }
XCheck.Mark() { inherited Mark "$@"; }
XCheck.Press() { inherited Press "$@"; }
XCheck.MovedTo() { inherited MovedTo "$@"; }
XCheck.DataSize() { inherited DataSize "$@"; }
XCheck.GetData() { inherited GetData "$@"; }
XCheck.SetData() { inherited SetData "$@"; }
build XCheck
class XRadio : TRadioButtons
    public
        override proc Draw
        override func Mark
        override proc Press
        override proc MovedTo
        override proc SetData
end
XRadio.Draw() { inherited Draw "$@"; }
XRadio.Mark() { inherited Mark "$@"; }
XRadio.Press() { inherited Press "$@"; }
XRadio.MovedTo() { inherited MovedTo "$@"; }
XRadio.SetData() { inherited SetData "$@"; }
build XRadio

# mk PREFIX DLGCLASS BTN TEXT LABEL CHECK RADIO: the test dialog's layout
mk() {
    local p=$1
    "$2.new" "${p}dlg" 10 4 70 18 'Find'
    "$4.new" "${p}st" 3 1 57 3 $'\x03''Search options'
    "$5.new" "${p}l1" 2 3 14 4 '~T~ext' "${p}opts"
    "$6.new" "${p}opts" 3 4 30 7 '~C~ase sensitive' '~W~hole words' 'Re~g~ex'
    "$5.new" "${p}l2" 32 3 46 4 '~D~irection' "${p}dir"
    "$7.new" "${p}dir" 32 4 56 6 '~F~orward' '~B~ackward'
    "$3.new" "${p}ok" 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
    "$3.new" "${p}cn" 26 10 38 12 'Cancel' cmCancel
    "$3.new" "${p}hp" 40 10 50 12 '~H~elp' cmHelp
    local v
    for v in st l1 opts l2 dir ok cn hp; do fv.views.insert "${p}dlg" "$p$v"; done
    fv.views.select "${p}opts"
}
fvw_tscene
fv.views.drawView app
# play PREFIX: the keys through the modal loop, counted; S = screen + data
play() {
    fvg_events 'key kbTab' 'key kbShiftTab' 'char _' 'key kbDown' 'char _' 'alt b' 'key kbUp' 'alt h' 'key kbTab' 'key kbEnter'
    fvw_count_on; FVW_CALLS=0
    fv.views.execView desk "${1}dlg"; R=$RESULT
    C=$FVW_CALLS; fvw_count_off
    fvw_noevents
    local -a d=(); fv.dialogs.getData "${1}dlg" d
    S="$R ${d[*]}"
}
mk '' TDialog TButton TStaticText TLabel TCheckBoxes TRadioButtons
mk x XDialog XButton XText XLabel XCheck XRadio
kt_test_start "the built-in dialog: cmOK, data, no dispatch of its own (2: the windows' stand-ins redrawn when it closes)"
play ''; s1=$S c1=$C
if [[ $s1 == 'cmOK 3 0' && $c1 == 2 ]]; then kt_test_pass "$s1"; else kt_test_fail "[$s1] $c1 dispatches"; fi
kt_test_start "the overriding dialog: the same result and data, dispatches only from the overrides"
XBH=0
play x; s2=$S c2=$C
if [[ $s2 == "$s1" ]] && (( c2 > c1 )); then kt_test_pass "$c2 dispatches"; else kt_test_fail "[$s2] vs [$s1] $c2"; fi
kt_test_start "the same picture: each dialog drawn alone == the other's cells"
fv.views.insert desk dlg; fvw_snap; a=$REPLY; fv.views.delete desk dlg
fv.views.insert desk xdlg; fvw_snap; b=$REPLY; fv.views.delete desk xdlg
if [[ $a == "$b" ]]; then kt_test_pass ok; else kt_test_fail "screens differ"; fi
kt_test_start "an overridden HandleEvent is never skipped by the hot-key map: XButton called for unnamed keys"
fv.views.insert desk xdlg; fv.views.select xdlg; fv.views.focus xopts
XBH=0
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF9; fv.views._virt xdlg HandleEvent
# (three XButtons, each in the pre and the post phase)
if (( XBH == 6 )); then kt_test_pass "$XBH calls"; else kt_test_fail "$XBH calls"; fi
kt_test_start "func answers through overrides: GetPalette, GetText, GetHelpCtx, DataSize; Mark / Valid by rc"
RESULT=''; fv.views._virt xok GetPalette; a=$RESULT
fv.views._virt xst GetText; b=$RESULT
xopts_data[HelpCtx]=10 xopts_data[Sel]=1; fv.views._virt xopts GetHelpCtx; c=$RESULT
fv.views._virt xopts DataSize; d=$RESULT
xopts_data[Value]=2
m1=0; fv.views._virt xopts Mark 1 || m1=$?
m0=0; fv.views._virt xopts Mark 0 || m0=$?
v=0; fv.views._virt xdlg Valid cmCancel || v=$?
if [[ $a == '10 11 12 13 14 14 14 15' && $b == $'\x03Search options' && $c == 11 && $d == 1 && $m1$m0$v == 010 ]]; then kt_test_pass ok
else kt_test_fail "[$a] [$b] $c $d $m1$m0$v"; fi
fv.views.delete desk xdlg
xdlg.delete; dlg.delete
fvw_untscene
