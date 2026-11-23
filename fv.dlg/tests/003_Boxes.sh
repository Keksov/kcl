#!/usr/bin/env bash
# 003_Boxes.sh - msgbox / yesno / infobox through fv.dlg.run --fv-headless
# (80 x 24, the scripted terminal, the screen taken while the box runs):
#   * the layout: centred, the title in the frame, the text from cell 2 of
#     row 1, the buttons centred on the row SizeY-3 (FV look: shadows), the
#     auto size (0 0: the text's width + 5, rows + 5), explicit sizes, -1 -1
#     (the screen), clamping, --topleft, --backtitle (row 0, the box below
#     it), --no-shadow, --fv-palette, labels of both tools;
#   * the answers: Enter, Space, Tab, the hot letters (y / n; golden yn_y /
#     yn_n: dialog's behaviour), Alt + a letter, a click on a button, Esc,
#     Ctrl+F4, the close icon, the end of input; --defaultno (golden yn_defno
#     / yn_defno_tab); the exit codes 0 / 1 / 255 and FV_DLG_CMD;
#   * the infobox (P4-10): no loop (no event read), rc 0, the box left in
#     the buffer (the application's Done draws nothing), and with a terminal
#     (fv.video stubbed, in a subshell): initVideo noalt, FV_KBD_PROTO=off
#     unless set, the cursor shown on the last row, doneVideo by fv.dlg;
#     a terminal the caller turned on stays on;
#   * NO_COLOR: the app palette's dialog entries grey / white / black (one
#     fv.app.setAppPalettes call), gray even with --fv-palette blue / cyan;
#   * long titles and labels: the frame cuts the title, labels are clipped
#     (the ~ letter kept): "terminal too small" only for the geometry;
#   * --fv-mouse off (fv.video stubbed): fv.mouse's disable right after the
#     start, a key fv.keyboard already holds still arrives;
#   * nothing left: no view, the application gone, FV_APP ''.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

# answer TITLE RC CMD SPEC... -- ARG... — one test: the box's status and
# command, nothing left behind
answer() {
    local title=$1 rc=$2 cmd=$3
    shift 3
    fvdl_run "$@"
    fvdl_live
    kt_test_start "$title"
    if [[ $FVDL_RC == "$rc" && $FVDL_CMD == "$cmd" && -z $REPLY && -z $FV_APP && -z $FVDL_RES ]]; then kt_test_pass "rc $FVDL_RC $FVDL_CMD"
    else kt_test_fail "rc $FVDL_RC [$FVDL_CMD] RESULT [$FVDL_RES] live [$REPLY] app [$FV_APP], want rc $rc $cmd"; fi
}

kt_test_section "003: the message box"
fvdl_run snap 'key kbEnter' -- --title Hello --msgbox 'Hello, world!\nThis is a one-shot message box.' 0 0
fvdl_box; b=$REPLY
fvdl_row 8; r8=$REPLY
fvdl_find 'Hello, world!'; t=$REPLY
fvdl_find ' OK '; ok=$REPLY
fvdl_row 13; r13=$REPLY
kt_test_start "auto size 0 0: the widest line + 5 columns (frame, blanks), its rows + 5; centred"
if [[ $b == '22 8 58 15' && $t == '24 9' ]]; then kt_test_pass "$b"; else kt_test_fail "box [$b] text at [$t]"; fi
kt_test_start "the title in the frame, the close icon, the OK button centred with its shadow"
if [[ $r8 == *'╔═[■]═'*' Hello '*'═╗'* && $ok == '38 12' && $r13 == *'▀▀▀▀▀▀▀▀▀'* ]]; then kt_test_pass "OK at $ok"; else kt_test_fail "row 8 [$r8] OK at [$ok] row 13 [$r13]"; fi

fvdl_run snap 'key kbEnter' -- --msgbox 'Short' 10 40
fvdl_box; b1=$REPLY
fvdl_run snap 'key kbEnter' -- --msgbox 'Short' -1 -1
fvdl_box; b2=$REPLY
fvdl_run snap 'key kbEnter' -- --msgbox 'Short' 100 200
fvdl_box; b3=$REPLY
fvdl_run snap 'key kbEnter' -- --topleft --msgbox 'Short' 8 30
fvdl_box; b4=$REPLY
kt_test_start "H W 10 40 centred, -1 -1 the screen, 100 200 clamped, --topleft at 0 0"
if [[ $b1 == '20 7 60 17' && $b2 == '0 0 80 24' && $b3 == '0 0 80 24' && $b4 == '0 0 30 8' ]]; then kt_test_pass ok
else kt_test_fail "[$b1] [$b2] [$b3] [$b4]"; fi

fvdl_run snap 'key kbEnter' -- --yesno 'q' 3 10
fvdl_box; b1=$REPLY
fvdl_run 'key kbEnter' -- --fv-size 20x5 --yesno 'q' 0 0 2>"$FVW_TMP/small.err"
r1=$FVDL_RC e1=$(<"$FVW_TMP/small.err")
fvdl_run 'key kbEnter' -- --fv-size 40x4 --msgbox 'q' 0 0 2>"$FVW_TMP/small.err"
r2=$FVDL_RC e2=$(<"$FVW_TMP/small.err")
fvdl_run -- --fv-size 16x3 --infobox 'q' 0 0 2>"$FVW_TMP/small.err"
r3=$FVDL_RC e3=$(<"$FVW_TMP/small.err")
fvdl_live
kt_test_start "the minimum (P4-8, basic): a smaller H W grows to it (yesno 3 10 -> 26 x 5); a screen below it -> 255 + one line; nothing left"
if [[ $b1 == '27 9 53 14' && $r1 == 255 && $e1 == 'fv.dlg.run: terminal too small (need 26x5, have 20x5)' \
      && $r2 == 255 && $e2 == 'fv.dlg.run: terminal too small (need 16x5, have 40x4)' && $r3 == 0 && -z $e3 && -z $REPLY && -z $FV_APP ]]; then kt_test_pass ok
else kt_test_fail "[$b1] [$r1 $e1] [$r2 $e2] [$r3 $e3] live [$REPLY]"; fi

fvdl_run snap 'key kbEnter' -- --backtitle 'Setup wizard' --msgbox 'Short' -1 -1
fvdl_box; b=$REPLY
fvdl_row 0; r0=$REPLY
fvdl_run snap 'key kbEnter' -- --backtitle 'Setup' --topleft --msgbox 'Short' 8 30
fvdl_box; bt=$REPLY
IFS='|' read -r -a at <<< "$FVDL_SNAPA"
kt_test_start "--backtitle on row 0 (a blank, the text, the row's rest) in the desktop's colour; the box below it (-1: the rest; --topleft: row 1)"
if [[ $r0 == ' Setup wizard '*'   ' && ${#r0} == 80 && $b == '0 1 80 24' && $bt == '0 1 30 9' && ${at[0]:3:1} == "${at[20]:70:1}" ]]; then kt_test_pass ok
else kt_test_fail "row 0 [$r0] box [$b] topleft [$bt] colours [${at[0]:3:1}] [${at[20]:70:1}]"; fi

fvdl_run snap 'key kbEnter' -- --ok-button 'Got it' --msgbox 'Short' 0 0
fvdl_find ' Got it '; g=$REPLY
fvdl_run snap 'key kbEnter' -- --ok-label 'Fine' --msgbox 'Short' 0 0
fvdl_find ' Fine '; f=$REPLY
kt_test_start "the OK label: --ok-button (whiptail) and --ok-label (dialog)"
if [[ -n $g && -n $f ]]; then kt_test_pass "$g / $f"; else kt_test_fail "[$g] [$f]"; fi

fvdl_run snap 'key kbEnter' -- --msgbox 'Short' 8 30
IFS='|' read -r -a a1 <<< "$FVDL_SNAPA"
fvdl_run snap 'key kbEnter' -- --no-shadow --msgbox 'Short' 8 30
IFS='|' read -r -a a2 <<< "$FVDL_SNAPA"
kt_test_start "--no-shadow: the cells below the box keep the desktop's colour (FV's shadow: symbol V)"
s1=${a1[16]:27:30} s2=${a2[16]:27:30} d=${a2[20]:27:30}
if [[ $s1 == *V* && $s2 != *V* && $s2 == "$d" ]]; then kt_test_pass "[$s1] / [$s2]"
else kt_test_fail "row 16 shadowed [$s1] / not [$s2] desktop [$d]"; fi

kt_test_start "--fv-palette blue / cyan: the dialog's Palette field (FV_DP_*)"
pal=''
palprobe() { local -n d=${FV_DESKTOP}__fvdlg_data; pal+="${d[Palette]};"; }
fvdl_run 'run palprobe' 'key kbEnter' -- --msgbox t 0 0
fvdl_run 'run palprobe' 'key kbEnter' -- --fv-palette blue --msgbox t 0 0
fvdl_run 'run palprobe' 'key kbEnter' -- --fv-palette cyan --msgbox t 0 0
fvdl_run 'run palprobe' 'key kbEnter' -- --fv-palette gray --msgbox t 0 0
if [[ $pal == "$FV_DP_GRAYDIALOG;$FV_DP_BLUEDIALOG;$FV_DP_CYANDIALOG;$FV_DP_GRAYDIALOG;" ]]; then kt_test_pass "$pal"; else kt_test_fail "$pal"; fi

answer "msgbox: Enter -> 0 (golden msg_enter)" 0 cmOK 'key kbEnter' -- --msgbox t 0 0
answer "msgbox: Space on the focused OK -> 0" 0 cmOK 'char _' -- --msgbox t 0 0
answer "msgbox: Tab, then Enter -> 0 (golden msg_tab)" 0 cmOK 'key kbTab' 'key kbEnter' -- --msgbox t 0 0
answer "msgbox: the hot letter k -> 0" 0 cmOK 'char k' -- --msgbox t 0 0
answer "msgbox: Esc -> 255 (golden msg_esc)" 255 cmCancel 'key kbEsc' -- --msgbox t 0 0
answer "msgbox: Ctrl+F4 -> 255" 255 cmCancel 'key kbCtrlF4' -- --msgbox t 0 0
answer "msgbox: the end of input -> 255" 255 cmCancel -- --msgbox t 0 0
answer "msgbox: a click on OK -> 0" 0 cmOK 'down 39 12' 'up 39 12' -- --title Hello --msgbox 'Hello, world!\nThis is a one-shot message box.' 0 0
answer "msgbox: a click on the close icon -> 255" 255 cmCancel 'down 25 8' 'up 25 8' -- --title Hello --msgbox 'Hello, world!\nThis is a one-shot message box.' 0 0
answer "msgbox: a click on the desktop does nothing (then Enter)" 0 cmOK 'down 2 2' 'up 2 2' 'key kbEnter' -- --msgbox t 0 0

kt_test_section "003: yes / no"
fvdl_run snap 'key kbEnter' -- --yesno 'Proceed?' 0 0
fvdl_find ' Yes '; y=$REPLY
fvdl_find ' No '; n=$REPLY
fvdl_box; b=$REPLY
kt_test_start "yesno 0 0: Yes then No, centred on one row, the box at least the buttons wide"
if [[ -n $y && -n $n && ${y#* } == "${n#* }" && ${y% *} -lt ${n% *} && $b == '27 9 53 15' ]]; then kt_test_pass "Yes $y No $n box $b"
else kt_test_fail "Yes [$y] No [$n] box [$b]"; fi
fvdl_run snap 'key kbEnter' -- --yes-button Ja --no-button Nein --yesno 'q' 0 0
fvdl_find ' Ja '; a=$REPLY; fvdl_find ' Nein '; c=$REPLY
fvdl_run snap 'key kbEnter' -- --yes-label Si --no-label Non --yesno 'q' 0 0
fvdl_find ' Si '; d=$REPLY; fvdl_find ' Non '; e=$REPLY
kt_test_start "the labels: --yes-button / --no-button (golden yn_button) and --yes-label / --no-label (golden yn_label)"
if [[ -n $a && -n $c && -n $d && -n $e ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$c] [$d] [$e]"; fi

answer "yesno: Enter -> 0 (golden yn_enter)" 0 cmYes 'key kbEnter' -- --yesno q 0 0
answer "yesno: Tab, Enter -> 1 (golden yn_tab)" 1 cmNo 'key kbTab' 'key kbEnter' -- --yesno q 0 0
answer "yesno: Esc -> 255 (golden yn_esc)" 255 cmCancel 'key kbEsc' -- --yesno q 0 0
answer "yesno: --defaultno, Enter -> 1 (golden yn_defno)" 1 cmNo 'key kbEnter' -- --defaultno --yesno q 0 0
answer "yesno: --defaultno, Tab, Enter -> 0 (golden yn_defno_tab)" 0 cmYes 'key kbTab' 'key kbEnter' -- --defaultno --yesno q 0 0
answer "yesno: y -> 0 (golden yn_y: dialog 0, whiptail ignores it)" 0 cmYes 'char y' -- --yesno q 0 0
answer "yesno: n -> 1 (golden yn_n: dialog 1)" 1 cmNo 'char n' -- --yesno q 0 0
answer "yesno: Alt+N -> 1" 1 cmNo 'key kbAltN n' -- --yesno q 0 0
answer "yesno: Right (the next button), Space -> 1" 1 cmNo 'key kbRight' 'char _' -- --yesno q 0 0
answer "yesno: a click on No -> 1" 1 cmNo "down $(( ${n% *} + 2 )) ${n#* }" "up $(( ${n% *} + 2 )) ${n#* }" -- --yesno 'Proceed?' 0 0
answer "yesno: the end of input -> 255" 255 cmCancel -- --yesno q 0 0
answer "yesno: custom labels have no hot letter (j does nothing; then Enter)" 0 cmYes 'char j' 'key kbEnter' -- --yes-button Ja --yesno q 0 0

kt_test_section "003: the infobox (P4-10)"
fvdl_run -- --title Info --infobox 'Please wait' 0 0
r=$FVDL_RC c=$FVDL_CMD n=$FVA_N
fvdl_snap
fvdl_find 'Please wait'; t=$REPLY
fvdl_box; b=$REPLY
fvdl_live; l=$REPLY
fvdl_row 10; tr=$REPLY
kt_test_start "infobox: rc 0 at once (no event read), the box stays in the buffer with its title (Info + 16 wide: FV TFrame's room beside the close icon), nothing left alive"
if [[ $r == 0 && $c == cmOK && $n == 0 && -n $t && $b == '30 10 50 13' && $t == '32 11' && $tr == *' Info '* && -z $l && -z $FV_APP ]]; then kt_test_pass "box $b"
else kt_test_fail "rc $r $c events $n text [$t] box [$b] live [$l]"; fi

# the terminal path with fv.video stubbed (a subshell: the stubs stay there)
infostub() {   # PROTO_IN VIDEO_ON -> REPLY "calls|cursor"
    (
        REC=''
        fv.video.initVideo() { if (( ! FV_VIDEO_ON )); then REC+="init:${1-}:${FV_KBD_PROTO-};"; fi; FV_VIDEO_ON=1; return 0; }
        fv.video.doneVideo() { REC+='done;'; FV_VIDEO_ON=0; return 0; }
        fv.drivers.initEvents() { REC+='events;'; return 0; }
        fv.drivers.doneEvents() { return 0; }
        exec {o}>"$FVW_TMP/info.out"
        FV_VIDEO_OUT_FD=$o FV_SCREEN_W=80 FV_SCREEN_H=24 FV_VIDEO_ON=$2
        if [[ -n $1 ]]; then FV_KBD_PROTO=$1; else unset FV_KBD_PROTO; fi
        fv.dlg.run --infobox 'Please wait' 0 0
        printf '%s|%s|%s|%s' "$?" "$REC" "${__FV_VS_CURX-}:${__FV_VS_CURY-}" "${FV_KBD_PROTO-unset}"
    )
}
out=$(infostub '' 0)
kt_test_start "infobox on a terminal: initVideo noalt with FV_KBD_PROTO=off, the cursor shown at (0, 23), doneVideo; the caller's FV_KBD_PROTO untouched"
if [[ $out == '0|init:noalt:off;events;done;|0:23|unset' ]]; then kt_test_pass "$out"; else kt_test_fail "$out"; fi
f=$(<"$FVW_TMP/info.out")
kt_test_start "infobox on a terminal: the last frame ends with the cursor on row 24 shown"
if [[ $f == *$'\e[24;1H'* && $f == *'Please wait'* ]]; then kt_test_pass ok; else kt_test_fail "${f: -80}"; fi
out=$(infostub kitty 0)
kt_test_start "infobox: FV_KBD_PROTO set by the caller wins"
if [[ $out == '0|init:noalt:kitty;events;done;|0:23|kitty' ]]; then kt_test_pass "$out"; else kt_test_fail "$out"; fi
out=$(infostub '' 1)
kt_test_start "infobox: a terminal the caller turned on stays on (no initVideo / doneVideo by fv.dlg)"
if [[ $out == '0|events;|0:23|unset' ]]; then kt_test_pass "$out"; else kt_test_fail "$out"; fi

kt_test_section "003: NO_COLOR"
nc=''
ncprobe() { nc="${__FV_VW_APAL:32:31}"; }
fvdl_run 'run ncprobe' 'key kbEnter' -- --msgbox t 0 0
c0=$nc
NO_COLOR=1 fvdl_run 'run ncprobe' 'key kbEnter' -- --msgbox t 0 0
c1=$nc
syms() {   # the distinct colours behind the app palette's dialog entries
    local i s seen=''
    for (( i = 0; i < ${#1}; i++ )); do s=${1:i:1}; [[ $seen == *"[${__FV_VS_PAL[$s]-}]"* ]] || seen+="[${__FV_VS_PAL[$s]-}]"; done
    REPLY=$seen
}
kt_test_start "NO_COLOR: the dialog entries use only light grey / white / black (FG BG in {0 7 15})"
NCS=''
ncsyms() { syms "${__FV_VW_APAL:31:31}"; NCS=$REPLY; }
NO_COLOR=1 fvdl_run 'run ncsyms' 'key kbEnter' -- --msgbox t 0 0
rest=${NCS//'[7 0 0]'/} rest=${rest//'[15 0 1]'/} rest=${rest//'[0 7 0]'/} rest=${rest//'[15 7 1]'/}
if [[ $c0 != "$c1" && -n $NCS && -z $rest ]]; then kt_test_pass "$NCS"
else kt_test_fail "plain [$c0] no-color [$c1] colours [$NCS]"; fi
kt_test_start "NO_COLOR: the app palette is the default again after the call"
if [[ $__FV_VW_APAL == "$__FV_AP_DEFPAL" ]]; then kt_test_pass ok; else kt_test_fail "$__FV_VW_APAL"; fi
kt_test_start "NO_COLOR with --fv-palette blue / cyan: the gray palette (the mapped entries) all the same"
pal=''
NO_COLOR=1 fvdl_run 'run palprobe' 'key kbEnter' -- --fv-palette blue --msgbox t 0 0
NO_COLOR=1 fvdl_run 'run palprobe' 'key kbEnter' -- --fv-palette cyan --msgbox t 0 0
if [[ $pal == "$FV_DP_GRAYDIALOG;$FV_DP_GRAYDIALOG;" ]]; then kt_test_pass "$pal"; else kt_test_fail "$pal"; fi
kt_test_start "NO_COLOR: one fv.app.setAppPalettes call, no setAppPalette, one resetPalette before the first paint"
NB=0 NS=0 NR=0
fvw_wrap NB fv.app.setAppPalettes
fvw_wrap NS fv.app.setAppPalette
fvw_wrap NR fv.views.resetPalette
NO_COLOR=1 fvdl_run 'key kbEnter' -- --msgbox t 0 0
nb=$NB ns=$NS nr=$NR
fvw_unwrap fv.app.setAppPalettes fv.app.setAppPalette fv.views.resetPalette
NR=0
fvw_wrap NR fv.views.resetPalette
fvdl_run 'key kbEnter' -- --msgbox t 0 0
nr0=$NR
fvw_unwrap fv.views.resetPalette
if [[ $nb == 1 && $ns == 0 && $(( nr - nr0 )) == 1 ]]; then kt_test_pass "batch $nb, single $ns, resets $nr (plain call $nr0)"
else kt_test_fail "batch $nb, single $ns, resets $nr (plain call $nr0)"; fi

kt_test_section "003: long titles and labels (the minimum is geometry, not text)"
printf -v w '%*s' 300 ''; w=${w// /x}
fvdl_run snap 'key kbEnter' -- --title "$w" --msgbox x 0 0
fvdl_box; b1=$REPLY r1=$FVDL_RC
fvdl_run snap 'key kbEnter' -- --title 'A twenty-cell title!' --msgbox x 0 0
fvdl_box; b2=$REPLY
fvdl_run snap 'key kbEnter' -- --title "$w" --msgbox x 8 30
fvdl_box; b3=$REPLY
kt_test_start "a title wider than the screen: the box as wide as the screen (the frame cuts it), rc 0; a shorter one widens the auto box (+16, FV TFrame's room beside the close icon); an explicit W is kept"
if [[ $r1 == 0 && $b1 == '0 '*' 80 '* && $b2 == '22 9 58 15' && $b3 == '25 8 55 16' ]]; then kt_test_pass "[$b1] [$b2] [$b3]"
else kt_test_fail "rc $r1 [$b1] [$b2] [$b3]"; fi
fvdl_run snap 'key kbEnter' -- --title Zt --msgbox hello 0 0
fvdl_box; b1=$REPLY; fvdl_find 'Zt'; t1=$REPLY
fvdl_run snap 'key kbEnter' -- --title Disk --yesno 'Format?' 0 0
fvdl_box; b2=$REPLY; fvdl_find ' Disk '; t2=$REPLY
kt_test_start "a short title shows in the auto box (fixed: a 16-wide box left FV TFrame no room beside the close icon): Zt -> 18 wide; Disk on a yes/no (the buttons make it 26) shows too"
if [[ $b1 == '31 9 49 15' && $t1 == '39 9' && $b2 == '27 9 53 15' && -n $t2 ]]; then kt_test_pass "[$b1] [$b2]"; else kt_test_fail "[$b1] title [$t1] [$b2] title [$t2]"; fi
fvdl_run snap 'key kbEnter' -- --ok-button "$w" --msgbox x 0 0
r1=$FVDL_RC
fvdl_box; b1=$REPLY
fvdl_find ' xxxxxxxxxx'; f1=$REPLY
fvdl_run snap 'key kbEnter' -- --yes-button "~J~a$w" --no-button "$w" --yesno q 0 0
r2=$FVDL_RC c2=$FVDL_CMD
fvdl_box; b2=$REPLY
fvdl_run 'char j' -- --yes-button "~J~a$w" --no-button "$w" --yesno q 0 0
r3=$FVDL_RC
fvdl_run 'key kbEnter' -- --fv-size 30x8 --title "$w" --cancel-button "$w" --inputbox t 0 0 v
r4=$FVDL_RC s4=$FVDL_RES
kt_test_start "labels wider than the screen are clipped (the buttons fit, the ~ letter still works): rc 0, no 'terminal too small'"
if [[ $r1 == 0 && $b1 == '0 '*' 80 '* && -n $f1 && $r2 == 0 && $c2 == cmYes && $b2 == '0 '*' 80 '* && $r3 == 0 && $r4 == 0 && $s4 == v ]]; then kt_test_pass "[$b1] [$b2]"
else kt_test_fail "[$r1 $b1 $f1] [$r2 $c2 $b2] [$r3] [$r4 $s4]"; fi
clip() { fv.dlg._clip "$1" "$2"; fvw_check "$3" "$4" "$RESULT"; }
clip 'Cancel' 3 "_clip: a plain label cut to N cells" 'Can'
clip '~Y~es' 2 "_clip: the ~ marks cost nothing" '~Y~e'
clip '~Yes~' 2 "_clip: an open hot-key span closed" '~Ye~'
clip 'Ab~c~' 2 "_clip: a span the cut leaves empty: its mark dropped" 'Ab'
clip '中文字' 5 "_clip: a wide character that does not fit is left out" '中文'
kt_test_start "a screen narrower than the buttons themselves is still refused (geometry: 26 for Yes / No)"
fvdl_run 'key kbEnter' -- --fv-size 25x8 --yes-button "$w" --yesno q 0 0 2>"$FVW_TMP/small.err"
e=$(<"$FVW_TMP/small.err")
if [[ $FVDL_RC == 255 && $e == 'fv.dlg.run: terminal too small (need 26x5, have 25x8)' ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC [$e]"; fi

kt_test_section "003: --fv-mouse off"
# a terminal with fv.video stubbed (a subshell): the tty is a file, the
# keys come from a file through the real fv.drivers / fv.keyboard; a key the
# start already read (queued in fv.keyboard's buffer after initEvents) must
# survive --fv-mouse off
mousestub() {   # MOUSE -> REPLY "rc|cmd"; $FVW_TMP/tty.out = what went to the tty
    (
        fva_noevents
        exec {kf}<"$FVW_TMP/empty.keys" {tf}>"$FVW_TMP/tty.out" {o}>"$FVW_TMP/m.out"
        fv.video.initVideo() { FV_VIDEO_ON=1 FV_TTY_FD=$tf FV_KEY_FD=$kf; return 0; }
        fv.video.doneVideo() { FV_VIDEO_ON=0 FV_TTY_FD=''; return 0; }
        src=$(declare -f fv.drivers.initEvents)
        eval "__orig_${src}"
        fv.drivers.initEvents() { __orig_fv.drivers.initEvents "$@" || return; __FV_KB_BUF=$'\r' __FV_KB_POS=0; }
        FV_VIDEO_OUT_FD=$o FV_SCREEN_W=80 FV_SCREEN_H=24 FV_VIDEO_ON=0 FV_TTY_FD=''
        fv.dlg.run --fv-mouse "$1" --msgbox t 0 0
        printf '%s|%s' "$?" "$FV_DLG_CMD"
    )
}
: > "$FVW_TMP/empty.keys"
out=$(mousestub off)
tty=$(<"$FVW_TMP/tty.out")
on=$'\e[?1000h\e[?1002h\e[?1006h' off=$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'
noff() { local s=${tty//"$off"/}; REPLY=$(( (${#tty} - ${#s}) / ${#off} )); }
noff
kt_test_start "--fv-mouse off: the queued Enter still arrives (rc 0, cmOK); the tty got the enable, the disable right after the start, the disable at Done"
if [[ $out == '0|cmOK' && $tty == *"$on"*"$off"* && $REPLY == 2 ]]; then kt_test_pass "$out"; else kt_test_fail "$out tty [${tty//$'\e'/^[}]"; fi
out=$(mousestub on)
tty=$(<"$FVW_TMP/tty.out")
noff
kt_test_start "--fv-mouse on (the default): only the disable at Done; the queued Enter arrives"
if [[ $out == '0|cmOK' && $tty == *"$on"* && $REPLY == 1 ]]; then kt_test_pass "$out"; else kt_test_fail "$out tty [${tty//$'\e'/^[}]"; fi

kt_test_section "003: the screen modes (D34, stage 4b)"
# scr SPEC... -- ARG... : a headless call with its frames in a file, then the
# final picture through fv.video's VT model (fvv_vt.sh): SCR = the rows
# ('|' after each), SCR_CUR = "X Y" of the cursor, SCR_RC the status
source "$FVDL_TESTS_DIR/../../fv.video/tests/fvv_vt.sh"
scr() {
    local -a specs=()
    local f=$FVW_TMP/scr.out s='' y x r
    while (( $# )) && [ "$1" != -- ]; do specs+=("$1"); shift; done
    shift
    fvdl_run "${specs[@]}" -- --fv-out "$f" "$@"
    SCR_RC=$FVDL_RC
    { IFS= read -r -d '' s || :; } < "$f"
    vt_init 80 24
    vt_feed "$s" || SCR_RC="vt:$VT_ERR"
    SCR=''
    for (( y = 0; y < 24; y++ )); do r=''; for (( x = 0; x < 80; x++ )); do r+=${VT_C[y * 80 + x]}; done; SCR+="$r|"; done
    SCR_CUR="$VT_X $VT_Y"
}
blank=$(printf '%80s' '')
scr 'key kbEnter' -- --title Zt --msgbox hello 0 0
kt_test_start "default (the alternate screen): the dialog is gone from the last picture (the desktop repainted), the cursor wherever FV left it"
if [[ $SCR_RC == 0 && $SCR != *'╔'* && $SCR != *hello* && $SCR == *'░░░'* ]]; then kt_test_pass "cursor $SCR_CUR"; else kt_test_fail "rc $SCR_RC ${SCR:0:200}"; fi
scr 'key kbEnter' -- --fv-screen main --title Zt --msgbox 'hello there, world' 0 0
kt_test_start "--fv-screen main: the last dialog stays (frame, title, text, its OK button), the desktop around it, the cursor at column 0 of the last row (dialog's endwin)"
if [[ $SCR_RC == 0 && $SCR == *'╔'*' Zt '*'╗'* && $SCR == *'║ hello'* && $SCR == *'OK'* && $SCR == *'░░░'* && $SCR_CUR == '0 23' ]]; then kt_test_pass ok; else kt_test_fail "rc $SCR_RC cur $SCR_CUR ${SCR:0:300}"; fi
scr 'key kbEsc' -- --fv-screen main --yesno 'sure?' 0 0
kt_test_start "--fv-screen main, Esc (255): the dialog stays too"
if [[ $SCR_RC == 255 && $SCR == *'║ sure?'* && $SCR_CUR == '0 23' ]]; then kt_test_pass ok; else kt_test_fail "rc $SCR_RC cur $SCR_CUR"; fi
scr 'char x' 'char y' 'key kbEnter' -- --fv-screen main --inputbox 'Name:' 0 0
kt_test_start "--fv-screen main inputbox: the typed text stays in the line; the answer as usual"
if [[ $SCR_RC == 0 && $FVDL_RES == xy && $SCR == *'Name:'* && $SCR == *' xy'* ]]; then kt_test_pass ok; else kt_test_fail "rc $SCR_RC [$FVDL_RES]"; fi
scr 'key kbDown' 'key kbEnter' -- --fv-screen main --menu 'Pick' 0 0 0 a Apple b Banana
kt_test_start "--fv-screen main menu: the list stays with its focus; the answer b"
if [[ $SCR_RC == 0 && $FVDL_RES == b && $SCR == *'a  Apple'* && $SCR == *'b  Banana'* ]]; then kt_test_pass ok; else kt_test_fail "rc $SCR_RC [$FVDL_RES]"; fi
scr 'key kbEnter' -- --erase-on-exit --msgbox hello 0 0
a="$SCR_RC|$SCR_CUR" e=$SCR
scr 'key kbEnter' -- --fv-screen main --clear --msgbox hello 0 0
b="$SCR_RC|$SCR_CUR" c=$SCR
kt_test_start "--erase-on-exit (= main + cleared) and --fv-screen main --clear: the screen blank at the exit, then the cursor on the last row (golden: ESC [ H ESC [ J, then ESC [ 24 ; 1 H)"
want=''; for (( i = 0; i < 24; i++ )); do want+="$blank|"; done
if [[ $a == '0|0 23' && $b == '0|0 23' && $e == "$want" && $c == "$want" ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi
scr 'key kbEnter' -- --keep-tite --erase-on-exit --msgbox hello 0 0
a=$SCR
scr 'key kbEnter' -- --fv-screen alt --erase-on-exit --msgbox hello 0 0
b=$SCR
scr 'key kbEnter' -- --fv-screen main --keep-tite --msgbox hello 0 0
c="$SCR_CUR" d=$SCR
kt_test_start "precedence: --keep-tite beats --erase-on-exit, --fv-screen beats both (alt: the dialog gone, nothing cleared; main: kept)"
if [[ $a != *hello* && $a == *'░░░'* && $b != *hello* && $b == *'░░░'* && $d == *'║ hello'* && $c == '0 23' ]]; then kt_test_pass ok; else kt_test_fail "a ${a:0:80} b ${b:0:80} c $c"; fi
scr 'key kbEnter' -- --clear --msgbox hello 0 0
kt_test_start "--clear on the alternate screen: nothing extra (the alternate screen goes at the exit; the screen found is back)"
if [[ $SCR != *hello* && $SCR == *'░░░'* ]]; then kt_test_pass ok; else kt_test_fail "${SCR:0:80}"; fi
scr -- --clear --infobox 'Please wait' 0 0
a="$SCR_RC|$SCR_CUR" e=$SCR
scr -- --erase-on-exit --infobox 'Please wait' 0 0
b="$SCR_RC|$SCR_CUR"
kt_test_start "the infobox with --clear / --erase-on-exit: never cleared (P4-10: the box stays), the cursor on the last row"
if [[ $a == '0|0 23' && $b == '0|0 23' && $e == *'Please wait'* ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi

f=$FVW_TMP/small.out
fvdl_run -- --fv-size 20x5 --fv-out "$f" --fv-screen main --yesno 'a long question text here' 0 0 2>"$FVW_TMP/small.err"
a="$FVDL_RC|$(<"$FVW_TMP/small.err")|$(<"$f")"
fvdl_run -- --fv-size 20x5 --fv-out "$f" --erase-on-exit --yesno 'a long question text here' 0 0 2>"$FVW_TMP/small.err"
b="$FVDL_RC|$(<"$f")"
kt_test_start "too small on the main screen: 255 with the refusal line, nothing sent where the frames go (no paint, no clear, no cursor move: the screen as it was found); --erase-on-exit likewise"
if [[ $a == '255|fv.dlg.run: terminal too small (need '*', have 20x5)|' && $b == '255|' ]]; then kt_test_pass ok; else kt_test_fail "[$(printf '%q' "$a")] [$(printf '%q' "$b")]"; fi

kt_test_start "fv.dlg._screen's table: main / clr by the options and the widget"
tab=''
for spec in '' 'screen=main' 'screen=alt' 'keeptite=1' 'erase=1' 'clear=1' 'screen=main clear=1' 'keeptite=1 erase=1' \
            'screen=alt erase=1' 'screen=main keeptite=1' 'w:infobox' 'w:infobox clear=1' 'w:infobox screen=alt' 'w:'; do
    (
        declare -A __fvl_o=()
        __fvl_w=msgbox
        for kv in $spec; do if [[ $kv == w:* ]]; then __fvl_w=${kv#w:}; else __fvl_o[${kv%%=*}]=${kv#*=}; fi; done
        FV_APP_HEADLESS=1
        fv.dlg._screen
        printf '%s%s ' "$__fvl_main" "$__fvl_clr"
    ) > "$FVW_TMP/tab"
    tab+=$(<"$FVW_TMP/tab")
done
if [[ $tab == '00 10 00 00 11 00 11 00 00 10 10 10 10 00 ' ]]; then kt_test_pass "$tab"; else kt_test_fail "$tab"; fi
kt_test_start "fv.dlg._screen: a terminal the caller turned on keeps its screen (main asked, not taken; the infobox neither)"
out=$( declare -A __fvl_o=([screen]=main); __fvl_w=msgbox; unset FV_APP_HEADLESS; FV_VIDEO_ON=1; fv.dlg._screen; printf '%s%s' "$__fvl_main" "$__fvl_clr"
       __fvl_w=infobox; fv.dlg._screen; printf ' %s%s' "$__fvl_main" "$__fvl_clr" )
if [[ $out == '00 00' ]]; then kt_test_pass ok; else kt_test_fail "$out"; fi

# on a terminal (fv.video stubbed, in a subshell): which init / done
modestub() {   # ARG... -> "calls|rc"
    (
        REC=''
        fv.video.initVideo() { if (( ! FV_VIDEO_ON )); then REC+="init:${1-};"; fi; FV_VIDEO_ON=1; return 0; }
        fv.video.doneVideo() { REC+='done;'; FV_VIDEO_ON=0; return 0; }
        fv.drivers.initEvents() { return 0; }
        fv.drivers.doneEvents() { return 0; }
        exec {o}>"$FVW_TMP/mode.out"
        FV_VIDEO_OUT_FD=$o FV_SCREEN_W=80 FV_SCREEN_H=24 FV_VIDEO_ON=0
        unset FV_APP_HEADLESS
        fvdl_events 'key kbEnter'
        fv.dlg.run "$@"
        printf '%s|%s' "$REC" "$?"
    )
}
a=$(modestub --msgbox hi 0 0)
b=$(modestub --fv-screen main --msgbox hi 0 0)
c=$(modestub --erase-on-exit --msgbox hi 0 0)
f=$(<"$FVW_TMP/mode.out")
d=$(modestub --keep-tite --msgbox hi 0 0)
kt_test_start "on a terminal: alt = the application's initVideo (alternate screen) and its doneVideo; main = initVideo noalt and doneVideo by fv.dlg; --erase-on-exit's clear goes to the terminal before the restore"
if [[ $a == 'init:;done;|0' && $b == 'init:noalt;done;|0' && $c == 'init:noalt;done;|0' && $d == 'init:;done;|0' && $f == *$'\e[0m\e[H\e[2J' ]]; then kt_test_pass ok
else kt_test_fail "[$a] [$b] [$c] [$d] tail [${f: -20}]"; fi

kt_test_log "003_Boxes.sh completed"
