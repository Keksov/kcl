#!/usr/bin/env bash
# 003_InputBox.sh - fv.msgbox.inputBox / inputBoxRect as FV's InputBox /
# InputBoxRect (msgbox.inc), in a headless application (80 x 24):
#   * the layout: 60 x 8 centred on the desktop, titled TITLE; the input line
#     (4 + CStrLen(LABEL), 2, SizeX - 3, 3) of LIMIT clusters, the label (2,
#     2, 3 + CStrLen(LABEL), 3) linked to it, OK (bfDefault) and Cancel at
#     FV's places; the input line selected (SelectNext(False)) holding the
#     variable's value, all of it selected; CStrLen in cells (a CJK label);
#     inputBoxRect's rectangle; the cells of one box;
#   * the answers: typing replaces the selected text, Enter (the default
#     button) -> cmOK and the variable set; Esc, Ctrl+F4, the close icon,
#     Cancel (a click, Tab + Enter) and the end of input -> cmCancel with
#     the variable as it was; Alt+K, a click on OK; Alt+N (the label)
#     focuses the line again;
#   * -p: PasswordChar '*' (one '*' cell per cluster on the screen), the
#     variable gets the real text;
#   * LIMIT in clusters: typing stops at LIMIT; a longer initial value
#     (ASCII, CJK, emoji) cut to LIMIT clusters — set on OK, kept on cancel;
#   * the variable: unset (set -u), an indexed array (element 0), a local
#     of the calling function;
#   * after each box: no view of it left, the screen == a full repaint.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

CAP=''
cap() {
    fvx_box
    local d=$FVX_D v
    local -n dd=${d}_data dv=${d}_views
    fv.views.getBounds "$d"
    CAP="owner ${dd[Owner]}; box $RESULT; title ${dd[Title]}; cur ${dd[Current]#"${d}"__fv};"
    for v in "${dv[@]}"; do
        local -n vd=${v}_data
        fv.views.getBounds "$v"
        CAP+=" ${v#"${d}"__fv}[$RESULT]"
        if [[ -n ${vd[MaxLen]+x} ]]; then
            fv.dialogs.getText "$v"
            CAP+="{$RESULT:${vd[MaxLen]}:${vd[SelStart]}-${vd[SelEnd]}:${vd[PasswordChar]}}"
        elif [[ -n ${vd[Link]+x} ]]; then CAP+="{${vd[Text]}:${vd[Link]#"${d}"__fv}}"
        elif [[ -n ${vd[Command]+x} ]]; then CAP+="{${vd[Title]}:${vd[Command]}:${vd[AmDefault]}}"; fi
        unset -n vd
    done
}
# ibox [-p] LABEL VALUE LIMIT SPEC... -- inputBox 'Save as' LABEL v LIMIT with
# v=VALUE and the events; R = RESULT, V = v afterwards
ibox() {
    local p=()
    if [ "$1" = -p ]; then p=(-p); shift; fi
    local l=$1 v=$2 n=$3
    shift 3
    CAP=''
    fvx_events "$@"
    fv.msgbox.inputBox "${p[@]}" 'Save as' "$l" v "$n"
    R=$RESULT V=$v
    fva_noevents; __FV_VW_EOF=0
}
after() {
    kt_test_start "$1: no view of the box left, == a full repaint"
    fvx_live
    if [[ -z $REPLY ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "live [$REPLY] $FVW_DIFF"; fi
}

kt_test_section "003: the layout"
fvx_app 80 24
FR='frame[0 0 60 8]'
OK='ok[36 4 46 6]{O~K~:cmOK:1}' CN='cancel[48 4 58 6]{Cancel:cmCancel:0}'
ibox '~N~ame' 'untitled.txt' 80 'run cap' 'key kbEsc'
fvw_check "60 x 8 centred (10 7), the line after the label, OK / Cancel, the line selected with its text all selected" \
    "owner app__fvdesktop; box 10 7 70 15; title Save as; cur input; $FR input[8 2 57 3]{untitled.txt:80:0-12:} label[2 2 7 3]{~N~ame:input} $OK $CN" "$CAP"
ibox 'A much longer label' '' 255 'run cap' 'key kbEsc'
fvw_check "a longer label (19 cells) moves the line" \
    "owner app__fvdesktop; box 10 7 70 15; title Save as; cur input; $FR input[23 2 57 3]{:255:0-0:} label[2 2 22 3]{A much longer label:input} $OK $CN" "$CAP"
ibox '名前' 'x' 10 'run cap' 'key kbEsc'
fvw_check "a CJK label: CStrLen in cells (4)" \
    "owner app__fvdesktop; box 10 7 70 15; title Save as; cur input; $FR input[8 2 57 3]{x:10:0-1:} label[2 2 7 3]{名前:input} $OK $CN" "$CAP"
CAP=''
v='abc'
fvx_events 'run cap' 'key kbEsc'
fv.msgbox.inputBoxRect 5 3 45 11 'Find' '~T~ext' v 20
fva_noevents
fvw_check "inputBoxRect: the rectangle (40 x 8), the places from its size" \
    "owner app__fvdesktop; box 5 3 45 11; title Find; cur input; frame[0 0 40 8] input[8 2 37 3]{abc:20:0-3:} label[2 2 7 3]{~T~ext:input} ok[16 4 26 6]{O~K~:cmOK:1} cancel[28 4 38 6]{Cancel:cmCancel:0}|cmCancel" "$CAP|$RESULT"
v='abc'
fvx_events 'run cap' 'key kbEsc'
fv.msgbox.inputBoxRect 0 0 30 6 'Tiny' '~L~' v 5
fva_noevents
fvw_check "a small rectangle (30 x 6): OK left of the frame's inside as FV computes it" \
    "owner app__fvdesktop; box 0 0 30 6; title Tiny; cur input; frame[0 0 30 6] input[5 2 27 3]{abc:5:0-3:} label[2 2 4 3]{~L~:input} ok[6 2 16 4]{O~K~:cmOK:1} cancel[18 2 28 4]{Cancel:cmCancel:0}" "$CAP"
after "the layouts"

kt_test_section "003: the cells"
FVX_SNAP=''
v='untitled.txt'
fvx_events 'run fvx_snap' 'key kbEsc'
fv.msgbox.inputBox 'Save as' '~N~ame' v 80
fva_noevents
IFS='|' read -r -a rows <<< "$FVX_SNAP"
got=''
for y in 7 8 9 10 11 12 13 14; do got+="${rows[y]:10:60}|"; done
want='╔═[■]════════════════════ Save as ═════════════════════════╗|'
want+='║                                                          ║|'
want+='║  Name  untitled.txt                                      ║|'
want+='║                                                          ║|'
want+='║                                       OK   ▄    Cancel ▄ ║|'
want+='║                                    ▀▀▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀ ║|'
want+='║                                                          ║|'
want+='╚══════════════════════════════════════════════════════════╝|'
kt_test_start "the box's rows (FV's look)"
if [[ $got == "$want" ]]; then kt_test_pass ok; else kt_test_fail "got [$got] want [$want]"; fi
after "the cells"

kt_test_section "003: answering"
ibox '~N~ame' 'old' 80 'char a' 'char b' 'key kbEnter'
fvw_check "typing replaces the selected text; Enter: cmOK, the variable set" 'cmOK|ab' "$R|$V"
ibox '~N~ame' 'old' 80 'key kbEnd' 'char s' 'key kbEnter'
fvw_check "End, then typing appends" 'cmOK|olds' "$R|$V"
ibox '~N~ame' 'old' 80 'char a' 'key kbEsc'
fvw_check "Esc after typing: cmCancel, the variable as it was" 'cmCancel|old' "$R|$V"
ibox '~N~ame' 'old' 80 'char a' 'key kbCtrlF4'
fvw_check "Ctrl+F4: cmCancel, kept" 'cmCancel|old' "$R|$V"
ibox '~N~ame' 'old' 80 'char a'
fvw_check "the end of input: cmCancel, kept" 'cmCancel|old' "$R|$V"
ibox '~N~ame' 'old' 80 'char a' 'key kbTab' 'key kbTab' 'key kbEnter'
fvw_check "Tab Tab Enter (on Cancel): cmCancel, kept" 'cmCancel|old' "$R|$V"
# (the box at 10 7: OK at 36 4 -> screen x 46..55, y 11; Cancel x 58..67;
# the close icon at 13 7)
ibox '~N~ame' 'old' 80 'char z' 'down 60 11' 'up 60 11'
fvw_check "a click on Cancel: cmCancel, kept" 'cmCancel|old' "$R|$V"
ibox '~N~ame' 'old' 80 'char z' 'down 48 11' 'up 48 11'
fvw_check "a click on OK: cmOK, set" 'cmOK|z' "$R|$V"
ibox '~N~ame' 'old' 80 'char z' 'down 13 7' 'up 13 7'
fvw_check "the close icon: cmCancel, kept" 'cmCancel|old' "$R|$V"
ibox '~N~ame' 'old' 80 'char q' 'alt k'
fvw_check "Alt+K: cmOK, set" 'cmOK|q' "$R|$V"
ibox '~N~ame' 'old' 80 'key kbTab' 'alt n' 'char w' 'key kbEnter'
fvw_check "Alt+N (the label) focuses the line again (its text selected): typing replaces it" 'cmOK|w' "$R|$V"
ibox '~N~ame' 'old' 80 'key kbTab' 'key kbEnter'
fvw_check "Enter on the focused OK: cmOK, the text unchanged" 'cmOK|old' "$R|$V"
after "the answers"

kt_test_section "003: -p (password mode)"
FVX_SNAP=''
ibox -p '~P~assword' 'sec' 64 'run cap' 'run fvx_snap' 'key kbEnd' 'char r' 'char 1' 'key kbEnter'
IFS='|' read -r -a rows <<< "$FVX_SNAP"
fvw_check "-p: PasswordChar '*', the line shows one '*' per cluster; the real text comes back" \
    "input[12 2 57 3]{sec:64:0-3:*}|║  Password  ***  |cmOK|secr1" \
    "$(t=${CAP#* input[}; echo "input[${t%% label*}")|${rows[9]:10:18}|$R|$V"
ibox -p '~P~assword' '中文😀' 64 'run fvx_snap' 'key kbEsc'
IFS='|' read -r -a rows <<< "$FVX_SNAP"
fvw_check "-p with wide clusters: one '*' cell each" '║  Password  ***  |cmCancel|中文😀' "${rows[9]:10:18}|$R|$V"
after "-p"

kt_test_section "003: LIMIT in clusters"
ibox '~N~ame' '' 5 'char a' 'char b' 'char c' 'char d' 'char e' 'char f' 'char g' 'key kbEnter'
fvw_check "typing stops at LIMIT 5" 'cmOK|abcde' "$R|$V"
ibox '~N~ame' 'abcdefgh' 3 'key kbEnter'
fvw_check "a longer initial value: cut to LIMIT on OK" 'cmOK|abc' "$R|$V"
ibox '~N~ame' 'abcdefgh' 3 'key kbEsc'
fvw_check "... and kept whole on cancel" 'cmCancel|abcdefgh' "$R|$V"
ibox '~N~ame' '中文字符串和' 4 'key kbEnter'
fvw_check "CJK: 4 clusters" 'cmOK|中文字符' "$R|$V"
ibox '~N~ame' '' 3 'char 中' 'char 文' 'char 字' 'char 符' 'key kbEnter'
fvw_check "typing CJK stops at 3 clusters" 'cmOK|中文字' "$R|$V"
ibox '~N~ame' $'👨‍👩‍👧x🇩🇪yz' 3 'key kbEnter'
fvw_check "a ZWJ family and a flag count one cluster each" $'cmOK|👨‍👩‍👧x🇩🇪' "$R|$V"
ibox '~N~ame' 'keep' 0 'char a' 'key kbEnter'
fvw_check "LIMIT 0: nothing fits (FV's MaxLen 0)" 'cmOK|' "$R|$V"
after "LIMIT"

kt_test_section "003: the variable"
unset u
set -u
fvx_events 'char n' 'key kbEnter'
fv.msgbox.inputBox 'T' 'L' u 10
fva_noevents
fvw_check "an unset variable under set -u: '' first, set on OK" 'cmOK|n' "$RESULT|${u-unset}"
fvx_events 'key kbEsc'
unset u
fv.msgbox.inputBox 'T' 'L' u 10
fva_noevents
fvw_check "an unset variable stays unset on cancel" 'cmCancel|unset' "$RESULT|${u-unset}"
set +u
arr=(first second)
fvx_events 'run cap' 'key kbEnd' 'char !' 'key kbEnter'
fv.msgbox.inputBox 'T' 'L' arr 10
fva_noevents
fvw_check "an indexed array: element 0 in and out" 'first|first!|second' "$(t=${CAP#*input\[}; t=${t#*\{}; echo "${t%%:*}")|${arr[0]}|${arr[1]}"
f() {
    local mine='loc'
    fvx_events 'key kbEnd' 'char 2' 'key kbEnter'
    fv.msgbox.inputBox 'T' 'L' mine 10
    fva_noevents
    F=$mine
}
mine='global'
f
fvw_check "a local of the calling function is the one read and set" 'loc2|global' "$F|$mine"
fvx_events 'char y' 'key kbEnter'
FV_EV_WHAT=x
fv.msgbox.inputBox 'T' 'L' FV_EV_WHAT 10
fva_noevents
fvw_check "a framework variable the box itself uses (FV_EV_WHAT) gets the answer after the box" 'cmOK|y' "$RESULT|$FV_EV_WHAT"
after "the variable"
fvx_unapp

kt_test_log "003_InputBox.sh completed"
