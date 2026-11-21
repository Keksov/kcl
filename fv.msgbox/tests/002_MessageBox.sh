#!/usr/bin/env bash
# 002_MessageBox.sh - fv.msgbox.messageBox / messageBoxRect as FV's
# MessageBox / MessageBoxRect (msgbox.inc), in a headless application
# (80 x 24: the desktop 80 x 23 above the status line):
#   * every flag set: the title (OPTIONS & 3), the buttons of OPTIONS in FV's
#     order with FV's labels, 10 x 2 each, 2 cells apart, centred ((SizeX -
#     X) shr 1) on row SizeY - 3; the text at (3, 2, SizeX - 2, SizeY - 3);
#     the 40 x 9 box centred on the desktop ((Size - 40) div 2), on the
#     application with FV_MF_INSERTINAPP (80 x 25 tells them apart: the
#     desktop's centre row 7, the application's 8), inserted there;
#     messageBoxRect's explicit rectangle (a narrow one: FV's arithmetic
#     puts the buttons left of the box);
#   * the cells of one box (the rows as FV draws them);
#   * the first button selected (the dialog's Current, the default look);
#     Enter presses it; Tab + Enter the second; Esc, Ctrl+F4, the close icon
#     and the end of input answer cmCancel; Alt + a hot letter and the
#     plain letter (post-process); a mouse click on a button;
#   * FormatStr: PARAMS through printf -v after `--` (%s %d %x, a width,
#     %%), a surplus parameter ignored (printf would repeat the format), a
#     missing one empty; without `--` MSG is shown as it is; ^C centres;
#   * translations: FV_MSGBOX_TITLES / FV_MSGBOX_BUTTONS elements replace
#     the defaults, an unset or empty element keeps the default;
#   * after each box: no view of it left, the screen == a full repaint.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

# cap: the box as it runs (a `run cap` spec) -> CAP = its owner, bounds,
# title, Current and every subview's role, bounds and Title / Text
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
        if [[ -n ${vd[Text]+x} ]]; then CAP+="{${vd[Text]}}"; fi
        if [[ -n ${vd[Command]+x} ]]; then CAP+="{${vd[Title]}:${vd[Command]}:${vd[AmDefault]}}"; fi
        unset -n vd
    done
}
# box OPTIONS SPEC... -- messageBox 'Hello' OPTIONS with the events; R = RESULT
box() {
    local o=$1
    shift
    CAP=''
    fvx_events "$@"
    fv.msgbox.messageBox 'Hello' "$o"
    R=$RESULT
    fva_noevents; __FV_VW_EOF=0
}
after() {
    kt_test_start "$1: no view of the box left, == a full repaint"
    fvx_live
    if [[ -z $REPLY ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "live [$REPLY] $FVW_DIFF"; fi
}

kt_test_section "002: the flags (title, buttons, placement)"
fvx_app 80 24
FR='frame[0 0 40 9]'
TX='text[3 2 38 6]{Hello}'
B0='{~Y~es:cmYes' B1='{~N~o:cmNo' B2='{O~k~:cmOK' B3='{Cancel:cmCancel'
want_title=(Warning Error Information Confirm)
for t in 0 1 2 3; do
    box "$(( t | FV_MF_OKBUTTON ))" 'run cap' 'key kbEsc'
    fvw_check "title of OPTIONS & 3 = $t" "${want_title[t]}" "$(t=${CAP#*title }; echo "${t%%;*}")"
done
# (one button: X = 10, (40 - 10) shr 1 = 15; two: X = 22 -> 9, 21; three:
# 34 -> 3, 15, 27; four: 46 -> -3, 9, 21, 33 (FV: left of the frame))
box "$FV_MF_OKBUTTON" 'run cap' 'key kbEsc'
fvw_check "OK alone: the box centred on the desktop (20 7), the text, the button at 15" \
    "owner app__fvdesktop; box 20 7 60 16; title Warning; cur btn2; $FR $TX btn2[15 6 25 8]$B2:1}" "$CAP"
box "$FV_MF_YESNOCANCEL" 'run cap' 'key kbEsc'
fvw_check "Yes No Cancel: FV's order, 3 15 27, the first (Yes) selected and default" \
    "owner app__fvdesktop; box 20 7 60 16; title Warning; cur btn0; $FR $TX btn0[3 6 13 8]$B0:1} btn1[15 6 25 8]$B1:0} btn3[27 6 37 8]$B3:0}" "$CAP"
box "$FV_MF_OKCANCEL" 'run cap' 'key kbEsc'
fvw_check "OK Cancel: 9 21, OK selected" \
    "owner app__fvdesktop; box 20 7 60 16; title Warning; cur btn2; $FR $TX btn2[9 6 19 8]$B2:1} btn3[21 6 31 8]$B3:0}" "$CAP"
box "$(( FV_MF_YESNOCANCEL | FV_MF_OKBUTTON | FV_MF_CONFIRMATION ))" 'run cap' 'key kbEsc'
fvw_check "all four: -3 9 21 33 (FV's arithmetic), Confirm" \
    "owner app__fvdesktop; box 20 7 60 16; title Confirm; cur btn0; $FR $TX btn0[-3 6 7 8]$B0:1} btn1[9 6 19 8]$B1:0} btn2[21 6 31 8]$B2:0} btn3[33 6 43 8]$B3:0}" "$CAP"
box "$(( FV_MF_NOBUTTON | FV_MF_CANCELBUTTON ))" 'run cap' 'key kbEsc'
fvw_check "No Cancel: No selected" \
    "owner app__fvdesktop; box 20 7 60 16; title Warning; cur btn1; $FR $TX btn1[9 6 19 8]$B1:1} btn3[21 6 31 8]$B3:0}" "$CAP"
box "$FV_MF_INFORMATION" 'run cap' 'key kbEsc'
fvw_check "no button: only the frame and the text; Esc answers" "owner app__fvdesktop; box 20 7 60 16; title Information; cur ; $FR $TX|cmCancel" "$CAP|$R"
box "$(( FV_MF_OKBUTTON | 4096 | 16 ))" 'run cap' 'key kbEsc'
fvw_check "bits FV does not read are ignored" "owner app__fvdesktop; box 20 7 60 16; title Warning; cur btn2; $FR $TX btn2[15 6 25 8]$B2:1}" "$CAP"
after "the flag boxes"
fvx_unapp

fvx_app 80 25
box "$(( FV_MF_OKBUTTON | FV_MF_INSERTINAPP ))" 'run cap' 'key kbEsc'
fvw_check "FV_MF_INSERTINAPP: centred on the application (20 8), inserted into it" \
    "owner app; box 20 8 60 17; title Warning; cur btn2; $FR $TX btn2[15 6 25 8]$B2:1}" "$CAP"
box "$FV_MF_OKBUTTON" 'run cap' 'key kbEsc'
fvw_check "without it: centred on the desktop (80 x 24: row 7)" \
    "owner app__fvdesktop; box 20 7 60 16; title Warning; cur btn2; $FR $TX btn2[15 6 25 8]$B2:1}" "$CAP"
after "80 x 25"
fvx_unapp

fvx_app 80 24
CAP=''
fvx_events 'run cap' 'key kbEsc'
fv.msgbox.messageBoxRect 5 3 45 12 'Rect' "$FV_MF_YESNOCANCEL"; R=$RESULT
fva_noevents
fvw_check "messageBoxRect: the given rectangle, the same layout" \
    "owner app__fvdesktop; box 5 3 45 12; title Warning; cur btn0; $FR text[3 2 38 6]{Rect} btn0[3 6 13 8]$B0:1} btn1[15 6 25 8]$B1:0} btn3[27 6 37 8]$B3:0}|cmCancel" "$CAP|$R"
fvx_events 'run cap' 'key kbEsc'
fv.msgbox.messageBoxRect 0 0 20 7 'Narrow' "$(( FV_MF_YESNOCANCEL | FV_MF_ERROR ))"
fva_noevents
fvw_check "a narrow rectangle: the text (3, 2, 18, 4), buttons from (20 - 34) shr 1 = -7, row 4" \
    "owner app__fvdesktop; box 0 0 20 7; title Error; cur btn0; frame[0 0 20 7] text[3 2 18 4]{Narrow} btn0[-7 4 3 6]$B0:1} btn1[5 4 15 6]$B1:0} btn3[17 4 27 6]$B3:0}" "$CAP"
fvx_events 'run cap' 'key kbEsc'
fv.msgbox.messageBoxRect -4 -2 36 7 'Off' "$(( FV_MF_OKBUTTON | FV_MF_INSERTINAPP ))"
fva_noevents
fvw_check "a rectangle partly off the owner (negative corners), in the application" \
    "owner app; box -4 -2 36 7; title Warning; cur btn2; $FR text[3 2 38 6]{Off} btn2[15 6 25 8]$B2:1}" "$CAP"
after "messageBoxRect"

kt_test_section "002: the cells"
FVX_SNAP=''
fvx_events 'run fvx_snap' 'key kbEsc'
fv.msgbox.messageBox 'File not found: %s' "$(( FV_MF_ERROR | FV_MF_YESNOCANCEL ))" -- /etc/x
fva_noevents
fvx_rows 0 24; base=$REPLY
kt_test_start "the box's rows (FV's look: frame, title, text, three buttons with shadows)"
IFS='|' read -r -a rows <<< "$FVX_SNAP"
got=''
for y in 7 8 9 10 11 12 13 14 15; do got+="${rows[y]:20:40}|"; done
want='╔═[■]═══════════ Error ════════════════╗|'
want+='║                                      ║|'
want+='║  File not found: /etc/x              ║|'
want+='║                                      ║|'
want+='║                                      ║|'
want+='║                                      ║|'
want+='║     Yes   ▄      No   ▄    Cancel ▄  ║|'
want+='║   ▀▀▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀  ║|'
want+='╚══════════════════════════════════════╝|'
if [[ $got == "$want" ]]; then kt_test_pass ok; else kt_test_fail "got [$got] want [$want]"; fi
kt_test_start "the box's colours: the selected (default) button differs from the others"
fvx_events 'run cap' 'run fvsym' 'key kbEsc'
fvsym() { fv.video.getRow 13; SYM=$REPLY; }
fv.msgbox.messageBox 'x' "$FV_MF_YESNOCANCEL"
fva_noevents
if ! [ "${SYM:23:1}" = "${SYM:35:1}" ] && [ "${SYM:35:1}" = "${SYM:47:1}" ]; then kt_test_pass "${SYM:20:40}"; else kt_test_fail "${SYM:20:40}"; fi
after "the cells"

kt_test_section "002: answering"
box "$FV_MF_YESNOCANCEL" 'key kbEnter'
fvw_check "Enter presses the selected first button" cmYes "$R"
box "$FV_MF_YESNOCANCEL" 'key kbTab' 'key kbEnter'
fvw_check "Tab + Enter: the second" cmNo "$R"
box "$FV_MF_YESNOCANCEL" 'key kbShiftTab' 'key kbEnter'
fvw_check "Shift+Tab + Enter: the last" cmCancel "$R"
box "$FV_MF_OKCANCEL" 'key kbEnter'
fvw_check "OK Cancel, Enter: cmOK" cmOK "$R"
box "$FV_MF_OKCANCEL" 'key kbTab' 'char _'
fvw_check "Space on the focused Cancel" cmCancel "$R"
box "$FV_MF_YESNOCANCEL" 'key kbEsc'
fvw_check "Esc: cmCancel" cmCancel "$R"
box "$FV_MF_YESNOCANCEL" 'key kbCtrlF4'
fvw_check "Ctrl+F4: cmCancel" cmCancel "$R"
box "$FV_MF_YESNOCANCEL"
fvw_check "the end of input: cmCancel" cmCancel "$R"
box "$FV_MF_YESNOCANCEL" 'alt n'
fvw_check "Alt+N: cmNo" cmNo "$R"
box "$FV_MF_YESNOCANCEL" 'char n'
fvw_check "the plain letter n (post-process): cmNo" cmNo "$R"
box "$FV_MF_YESNOCANCEL" 'char Y'
fvw_check "Y: cmYes" cmYes "$R"
box "$FV_MF_OKCANCEL" 'key kbTab' 'char k'
fvw_check "k (O~k~) from Cancel: cmOK" cmOK "$R"
box "$FV_MF_OKCANCEL" 'char x' 'key kbF9' 'key kbEnter'
fvw_check "keys nobody takes change nothing: Enter still cmOK" cmOK "$R"
# (the box at 20 7; No at 15 6: its cells x 35..44 on screen row 13)
box "$FV_MF_YESNOCANCEL" 'down 37 13' 'up 37 13'
fvw_check "a click on No" cmNo "$R"
box "$FV_MF_YESNOCANCEL" 'down 37 13' 'up 70 20' 'key kbEnter'
fvw_check "a press on No released elsewhere presses nothing (Enter: Yes)" cmYes "$R"
box "$FV_MF_YESNOCANCEL" 'down 23 7' 'up 23 7'
fvw_check "a click on the close icon: cmCancel" cmCancel "$R"
box "$FV_MF_YESNOCANCEL" 'cmd cmYes'
fvw_check "a cmYes command (an application's): ends the box with it" cmYes "$R"
after "the answers"

kt_test_section "002: FormatStr"
fmt() {
    local m=$1
    shift
    fvx_events 'run cap' 'key kbEsc'
    fv.msgbox.messageBox "$m" "$FV_MF_OKBUTTON" "$@"
    fva_noevents
    local t=${CAP#*text\[3 2 38 6\]\{}
    F=${t%%\}*}
}
fmt 'File %s has %d lines' -- a.txt 12;            fvw_check "%s %d" 'File a.txt has 12 lines' "$F"
fmt 'File %s has %d lines' -- a.txt 12 surplus 7;  fvw_check "surplus parameters ignored (no repeated format)" 'File a.txt has 12 lines' "$F"
fmt 'File %s has %d lines' -- a.txt;               fvw_check "a missing parameter: printf's empty / 0" 'File a.txt has 0 lines' "$F"
fmt 'Hex %x, [%5s], [%-4s], 100%%' -- 255 ab cd;   fvw_check "%x, widths, %%" 'Hex ff, [   ab], [cd  ], 100%' "$F"
fmt '100% sure, %s stays';                         fvw_check "no --: MSG as it is" '100% sure, %s stays' "$F"
fmt '100%% sure' --;                                fvw_check "-- with no parameters: formatted (%% -> %)" '100% sure' "$F"
fmt 'Bad %d end' -- notanumber;                    fvw_check "a refused conversion: what printf made, no message" 'Bad 0 end' "$F"
fmt '-x %s' -- y;                                  fvw_check "a format starting with -" '-x y' "$F"
fmt 'Жук %s 中文' -- 'ёж';                          fvw_check "non-ASCII format and parameter" 'Жук ёж 中文' "$F"
FVX_SNAP=''
fvx_events 'run fvx_snap' 'key kbEsc'
fv.msgbox.messageBox $'\x03''Centred' "$FV_MF_OKBUTTON"
fva_noevents
IFS='|' read -r -a rows <<< "$FVX_SNAP"
fvw_check "^C centres the line in the text's 35 cells ((35 - 7) div 2 + the margin)" '║                Centred               ║' "${rows[9]:20:40}"
fvx_events 'run fvx_snap' 'key kbEsc'
fv.msgbox.messageBox 'A long message that wraps over more than one line of the box at its blanks' "$FV_MF_OKBUTTON"
fva_noevents
IFS='|' read -r -a rows <<< "$FVX_SNAP"
fvw_check "a long message wraps at its blanks (TStaticText: the blank starts the next line)" \
    '║  A long message that wraps over      ║|║   more than one line of the box at   ║|║   its blanks                         ║' \
    "${rows[9]:20:40}|${rows[10]:20:40}|${rows[11]:20:40}"
after "FormatStr"

kt_test_section "002: translations"
sv_t=("${FV_MSGBOX_TITLES[@]}") sv_b=("${FV_MSGBOX_BUTTONS[@]}")
FV_MSGBOX_TITLES[1]='Ошибка' FV_MSGBOX_BUTTONS[0]='~Д~а' FV_MSGBOX_BUTTONS[1]='' FV_MSGBOX_BUTTONS[3]='Отмена'
box "$(( FV_MF_ERROR | FV_MF_YESNOCANCEL ))" 'run cap' 'key kbEsc'
fvw_check "a replaced title and buttons; an empty element keeps the default" \
    "owner app__fvdesktop; box 20 7 60 16; title Ошибка; cur btn0; $FR $TX btn0[3 6 13 8]{~Д~а:cmYes:1} btn1[15 6 25 8]$B1:0} btn3[27 6 37 8]{Отмена:cmCancel:0}" "$CAP"
box "$(( FV_MF_ERROR | FV_MF_YESNOCANCEL ))" 'char д'
fvw_check "the translated hot letter д presses Yes" cmYes "$R"
unset 'FV_MSGBOX_TITLES[1]'
box "$(( FV_MF_ERROR | FV_MF_OKBUTTON ))" 'run cap' 'key kbEsc'
fvw_check "an unset element: the default title" Error "$(t=${CAP#*title }; echo "${t%%;*}")"
FV_MSGBOX_TITLES=("${sv_t[@]}") FV_MSGBOX_BUTTONS=("${sv_b[@]}")
fvw_check "the defaults (FV's resourcestrings)" 'Warning Error Information Confirm|~Y~es ~N~o O~k~ Cancel O~K~ Cancel' \
    "${FV_MSGBOX_TITLES[*]}|${FV_MSGBOX_BUTTONS[*]}"
after "translations"
fvx_unapp

kt_test_log "002_MessageBox.sh completed"
