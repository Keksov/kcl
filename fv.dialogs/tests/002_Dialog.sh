#!/usr/bin/env bash
# 002_Dialog.sh - TDialog (FV dialogs.inc; design P3 §3.2):
#   * construction: TWindow's with GrowMode 0, Flags wfMove + wfClose,
#     Palette dpGrayDialog, no number, the frame; the three palettes;
#   * the modal loop (fv.views.execView): Esc and Ctrl+F4 -> cmCancel, Enter
#     -> the default button -> cmOK, a cmYes / cmNo command ends it, a
#     modeless dialog ignores them; cmClose (the frame's close icon) ->
#     cmCancel; Valid: cmCancel always valid, a refusing subview keeps the
#     dialog open for cmOK until it agrees; Ctrl+F5 -> the keyboard move
#     (cmResize) while modal; the end of input -> cmCancel;
#   * CalcBounds (FPC 2025's MoveRel): a one-cell growth moves toward the
#     larger margin, else the margins scale (Pascal's Round), GrowMode set ->
#     TWindow's; a resize of the desktop during the modal loop keeps the
#     dialog in proportion and the screen == a full repaint.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: construction"
fvg_scene
fv.views.drawView app
kt_test_start "FV's fields: GrowMode 0, Flags wfMove + wfClose, Palette gray, no number, a frame"
if [[ ${dlg_data[GrowMode]} == 0 && ${dlg_data[Flags]} == $(( FV_WF_MOVE | FV_WF_CLOSE )) && ${dlg_data[Palette]} == 2 \
      && ${dlg_data[Number]} == 0 && ${dlg_data[Frame]} == dlg__fvframe && ${dlg_data[Title]} == Find ]]; then kt_test_pass ok
else kt_test_fail "${dlg_data[GrowMode]} ${dlg_data[Flags]} ${dlg_data[Palette]} ${dlg_data[Number]} ${dlg_data[Frame]}"; fi
kt_test_start "GetPalette: gray 32..63, blue 64..95 (FV's 30th entry 92), cyan 96..127"
RESULT=''; fv.views._virt dlg GetPalette; g=$RESULT
dlg_data[Palette]=0; fv.views._virt dlg GetPalette; b=$RESULT
dlg_data[Palette]=1; fv.views._virt dlg GetPalette; c=$RESULT
dlg_data[Palette]=2
set -- $g; g1="$1 ${32}"; set -- $b; b1="$1 ${29} ${30} ${32}"; set -- $c; c1="$1 ${32} $#"
if [[ $g1 == '32 63' && $b1 == '64 92 92 95' && $c1 == '96 127 32' ]]; then kt_test_pass ok; else kt_test_fail "[$g1] [$b1] [$c1]"; fi
set --

kt_test_section "002: the modal loop"
kt_test_start "Esc -> cmCancel"
fvg_run 'key kbEsc'; a=$FVG_R
if [ "$a" = cmCancel ] && (( FVW_EVN == 2 )); then kt_test_pass ok; else kt_test_fail "$a reads $FVW_EVN"; fi
kt_test_start "Ctrl+F4 -> cmCancel; the end of input -> cmCancel"
fvg_run 'key kbCtrlF4'; a=$FVG_R
fvg_run; b=$FVG_R
if [[ $a.$b == cmCancel.cmCancel ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "Enter -> the default button -> cmOK; the dialog is back out of desk"
fvg_run 'key kbEnter'
if [[ $FVG_R == cmOK && -z ${dlg_data[Owner]} ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVG_R owner ${dlg_data[Owner]} $FVW_DIFF"; fi
kt_test_start "cmYes / cmNo commands end it with themselves"
fvg_run 'cmd cmYes'; a=$FVG_R
fvg_run 'cmd cmNo'; b=$FVG_R
if [[ $a.$b == cmYes.cmNo ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "cmClose (the close icon's command) -> cmCancel"
fvg_run 'cmd cmClose'
if [ "$FVG_R" = cmCancel ]; then kt_test_pass ok; else kt_test_fail "$FVG_R"; fi
kt_test_start "a modeless dialog: Esc posts cmCancel, nobody ends anything"
fv.views.insert desk dlg; fv.views.select dlg; __FV_DR_PEND=()
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbEsc
fv.views._virt app HandleEvent
p=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmOK
fv.views._virt app HandleEvent
if [[ $p == cmCancel && ${dlg_data[EndState]} == '' && $FV_EV_WHAT == evCommand ]]; then kt_test_pass ok; else kt_test_fail "[$p] [${dlg_data[EndState]}] $FV_EV_WHAT"; fi
fv.views.delete desk dlg

kt_test_start "Valid: a subview that refuses cmOK keeps the dialog open; cmCancel is always valid"
class TNo : TView
    public
        override func Valid
end
TNo.Valid() { if [ "$1" = cmOK ] && (( NOK++ < 1 )); then return 1; fi; }
build TNo
TNo.new vno 0 0 1 1; fv.views.insertBefore dlg vno ''
NOK=0
fvg_run 'key kbEnter' 'key kbEnter'; a=$FVG_R:$FVW_EVN
NOK=-5
fvg_run 'key kbEsc'; b=$FVG_R
if [[ $a == cmOK:6 && $b == cmCancel ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
fv.views.delete dlg vno; vno.delete

kt_test_start "Ctrl+F5 while modal: the keyboard move (cmResize), Right then Enter moves it by one"
fvg_run 'key kbCtrlF5' 'key kbRight' 'key kbEnter' 'key kbEsc'
fv.views.getBounds dlg
if [[ $FVG_R == cmCancel && $RESULT == '11 4 71 18' ]]; then kt_test_pass ok; else kt_test_fail "$FVG_R [$RESULT]"; fi
fv.views.moveTo dlg 10 4

kt_test_section "002: CalcBounds (FPC 2025 MoveRel)"
# cb W H DX DY: the dialog's bounds after desk grew by DX DY to W x H
cb() {
    FV_RECT_AX=0
    desk_data[SizeX]=$1 desk_data[SizeY]=$2
    fv.views._virt dlg CalcBounds "$3" "$4"
    REPLY="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
    desk_data[SizeX]=80 desk_data[SizeY]=24
}
fv.views.insert desk dlg
kt_test_start "one column wider: |rA - I| <= 1 moves toward the larger margin (FPC 2025)"
cb 81 24 1 0; a=$REPLY
fv.views.growTo dlg 59 14; cb 81 24 1 0; b=$REPLY; fv.views.growTo dlg 60 14
fv.views.moveTo dlg 5 4; cb 81 24 1 0; c=$REPLY; fv.views.moveTo dlg 10 4
if [[ $a == '10 4 70 18' && $b == '11 4 70 18' && $c == '5 4 65 18' ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b] [$c]"; fi
kt_test_start "a bigger growth scales the margins: 80x24 -> 120x34 keeps it centred-ish"
cb 120 34 40 10
if [ "$REPLY" = '30 8 90 22' ]; then kt_test_pass ok; else kt_test_fail "[$REPLY]"; fi
kt_test_start "Pascal's Round: a half goes to the even number (shrink 80 -> 70: N = round(rA / 2))"
fv.views.moveTo dlg 1 4; cb 70 24 -10 0; a=$REPLY
fv.views.moveTo dlg 3 4; cb 70 24 -10 0; b=$REPLY
fv.views.moveTo dlg 5 4; cb 70 24 -10 0; c=$REPLY
fv.views.moveTo dlg 10 4
if [[ $a == '0 4 60 18' && $b == '2 4 62 18' && $c == '2 4 62 18' ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b] [$c]"; fi
kt_test_start "GrowMode set: TWindow's CalcBounds"
dlg_data[GrowMode]=$FV_GF_GROWALL
cb 90 24 10 0
dlg_data[GrowMode]=0
if [ "$REPLY" = '20 4 80 18' ]; then kt_test_pass ok; else kt_test_fail "[$REPLY]"; fi
fv.views.delete desk dlg
kt_test_start "a desktop resize during the modal loop: the dialog keeps its place in proportion"
grow() { fv.views.changeBounds desk 0 0 100 30; }
fvg_run 'run grow' 'key kbEsc'
fv.views.getBounds desk; d=$RESULT
fv.views.getBounds dlg; b=$RESULT

if [[ $FVG_R == cmCancel && $d == '0 0 100 30' && $b == '20 6 80 20' ]]; then kt_test_pass ok; else kt_test_fail "$FVG_R [$d] [$b]"; fi
fvg_unscene
