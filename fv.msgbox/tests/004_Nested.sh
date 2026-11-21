#!/usr/bin/env bash
# 004_Nested.sh - boxes inside running modal loops (design P3 §6: each call
# builds, runs and destroys its dialog under a reserved name; nested boxes
# take a depth suffix):
#   * from a Valid: a dialog class whose Valid(cmOK) asks a Yes / No box —
#     No keeps the dialog open, Yes lets it end with cmOK; an input line's
#     Validator (FV's validators show an error box) refusing with a box;
#   * two levels: a message box opened while an input box runs (by the event
#     source: a `run` spec) takes ${FV_DESKTOP}__fvmsgbox2, both drawn, the
#     input box goes on after it with the screen == a full repaint; three
#     levels; the family's first name free again afterwards;
#   * the end-of-input latch: a box after the end of input answers cmCancel
#     at once (nothing made, nothing written, the variable kept); the end of
#     input inside a level-2 box ends both with cmCancel;
#   * no view of any box left, the screen == a full repaint.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

after() {
    kt_test_start "$1: no view of a box left, == a full repaint"
    fvx_live
    if [[ -z $REPLY ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "live [$REPLY] $FVW_DIFF"; fi
}

kt_test_section "004: a box from a Valid"
class TAskDlg : TDialog
    public
        override func Valid
end
ASKS=''
TAskDlg.Valid() {
    if [ "$1" = cmOK ]; then
        fvx_boxes; ASKS+="[$REPLY"
        fv.msgbox.messageBox 'Really close?' $(( FV_MF_CONFIRMATION | FV_MF_YESBUTTON | FV_MF_NOBUTTON ))
        ASKS+="$RESULT]"
        [ "$RESULT" = cmYes ] || return 1
    fi
    inherited Valid "$@"
}
build TAskDlg
fvx_app 80 24
mkask() {
    TAskDlg.new adlg 5 2 45 12 'Ask'
    TButton.new aok 5 6 15 8 'O~K~' cmOK "$FV_BF_DEFAULT"
    TButton.new acn 17 6 27 8 'Cancel' cmCancel
    fv.views.insert adlg aok; fv.views.insert adlg acn
    fv.views.select aok
}
mkask
fvx_events 'key kbEnter' 'key kbTab' 'key kbEnter' 'key kbEnter' 'key kbEnter'
fv.views.execView "$FV_DESKTOP" adlg; R=$RESULT
fva_noevents; __FV_VW_EOF=0
fvw_check "Enter -> Valid asks: No (Tab Enter) keeps the dialog; Enter again -> Yes: cmOK; each box the family's first name" \
    "cmOK|[cmNo][cmYes]|live" "$R|${ASKS//app__fvdesktop__fvmsgbox/X}|$(fv.views.isView adlg && echo live)"
fvx_events 'key kbEsc'
fv.views.execView "$FV_DESKTOP" adlg; R=$RESULT
fva_noevents; __FV_VW_EOF=0
fvw_check "Esc: cmCancel is always valid (no box)" "cmCancel|[cmNo][cmYes]" "$R|${ASKS//app__fvdesktop__fvmsgbox/X}"
adlg.delete
after "from a Valid"

digits() {
    [[ $1 == *[0123456789]* ]] && return 0
    fv.msgbox.messageBox 'Digits please: %s' $(( FV_MF_ERROR | FV_MF_OKBUTTON )) -- "$1"
    VB+="$RESULT;"
    return 1
}
TDialog.new vdlg 5 2 50 12 'Number'
TInputLine.new vin 3 2 40 3 20
TButton.new vok 5 6 15 8 'O~K~' cmOK "$FV_BF_DEFAULT"
fv.views.insert vdlg vin; fv.views.insert vdlg vok; fv.views.select vin
vin_data[Validator]=digits
VB=''
fvx_events 'char a' 'key kbEnter' 'key kbEnter' 'char 7' 'key kbEnter'
fv.views.execView "$FV_DESKTOP" vdlg; R=$RESULT
fva_noevents; __FV_VW_EOF=0
fv.dialogs.getText vin
fvw_check "a Validator refusing with a box (Enter closes it), then a valid text: cmOK" "cmOK|cmOK;|a7" "$R|$VB|$RESULT"
vdlg.delete
after "a Validator's box"

kt_test_section "004: two and three levels"
L2=''
inner() {
    fvx_boxes; L2="before[$REPLY]"
    fv.msgbox.messageBox 'Inner' "$(( FV_MF_WARNING | FV_MF_OKCANCEL ))"
    L2+=" got[$RESULT]"
}
seen() { fvx_boxes; L2+=" seen[$REPLY]"; fvx_box; local -n bd=${FVX_D}2_data; L2+=" owner[${bd[Owner]}]"; }
full() { if fvw_full app; then L2+=' full'; else L2+=" notfull[$FVW_DIFF]"; fi; }
v='start'
fvx_events 'run inner' 'run seen' 'key kbTab' 'key kbEnter' 'run full' 'key kbEnd' 'char X' 'key kbEnter'
fv.msgbox.inputBox 'Outer' '~V~alue' v 30; R=$RESULT
fva_noevents; __FV_VW_EOF=0
L2=${L2//app__fvdesktop__fvmsgbox/X}
fvw_check "a box inside an input box: X2 while X runs, inserted into the desktop; Cancel; the input box goes on, == a full repaint; its answer" \
    "before[X ] seen[X X2 ] owner[app__fvdesktop] got[cmCancel] full|cmOK|startX" \
    "$L2|$R|$v"
after "two levels"

L3=''
lvl2() { fv.msgbox.messageBox 'Two' "$FV_MF_OKBUTTON"; L3+="2:$RESULT "; }
lvl3() { fvx_boxes; L3+="live[${REPLY//app__fvdesktop__fvmsgbox/X}] "; fv.msgbox.messageBox 'Three' "$FV_MF_YESNOCANCEL"; L3+="3:$RESULT "; }
fvx_events 'run lvl2' 'run lvl3' 'char n' 'key kbEnter' 'key kbEsc'
fv.msgbox.messageBox 'One' "$FV_MF_OKCANCEL"; L3+="1:$RESULT"
fva_noevents; __FV_VW_EOF=0
fvw_check "three levels (each opened by the source while the one below runs): the answers innermost first" \
    "live[X X2 ] 3:cmNo 2:cmOK 1:cmCancel" "$L3"
fvx_events 'run cap1' 'key kbEsc'
cap1() { fvx_boxes; C1=$REPLY; }
fv.msgbox.messageBox 'Again' "$FV_MF_OKBUTTON"
fva_noevents
fvw_check "afterwards the family's first name is free again" "${FV_DESKTOP}__fvmsgbox " "$C1"
after "three levels"

kt_test_section "004: the end-of-input latch"
fvw_outsize; s0=$REPLY
__FV_VW_EOF=1
v='kept'
RESULT=x
fv.msgbox.messageBox 'Late' "$FV_MF_YESNOCANCEL"; r1=$RESULT
fv.msgbox.inputBox 'Late' 'L' v 10; r2=$RESULT
fv.msgbox.messageBoxRect 1 1 41 10 'Late' "$(( FV_MF_OKBUTTON | FV_MF_INSERTINAPP ))"; r3=$RESULT
fvw_outsize; s1=$REPLY
fvx_live
fvw_check "after the end of input: cmCancel at once, nothing written, nothing left, the variable kept" \
    "cmCancel cmCancel cmCancel|$s0||kept" "$r1 $r2 $r3|$s1|$REPLY|$v"
__FV_VW_EOF=0
L2=''
inner2() { fv.msgbox.messageBox 'Inner' "$FV_MF_OKBUTTON"; L2+="in:$RESULT "; }
v='kept'
fvx_events 'char z' 'run inner2' 'key kbTab'
fv.msgbox.inputBox 'Outer' 'L' v 10; L2+="out:$RESULT"
fva_noevents
fvw_check "the end of input inside a level-2 box ends both with cmCancel; the variable kept" "in:cmCancel out:cmCancel|kept|1" "$L2|$v|$__FV_VW_EOF"
__FV_VW_EOF=0
after "the latch"
fvx_unapp

kt_test_log "004_Nested.sh completed"
