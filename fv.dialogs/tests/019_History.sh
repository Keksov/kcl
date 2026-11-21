#!/usr/bin/env bash
# 019_History.sh - THistory, THistoryViewer, THistoryWindow (FV dialogs.inc
# 3740-3990; design P3 §15, D28) over fv.histlist, in a modal dialog with two
# input lines and their history views:
#   * the constructors (fields, options, the refusals), the look `▐v▌` (the
#     v in colour 2; CHistory 22 23), ASCII mode `[v]`, the palettes of the
#     window, its frame, bars and viewer through CHistoryWindow;
#   * Down on the focused link (and Ctrl+X: CtrlToArrow) or a click on the
#     view: the link focused, its text recorded, the window FV's rect (the
#     link one cell wider each side, from the row above it, 7 rows down, cut
#     to the owner, one row shorter; at the owner's edges), modal, the viewer
#     on item 1 (item 0 with a single string); Down while the link is not
#     focused opens nothing;
#   * Enter / a double click -> cmOK: the line's text the selection (CJK,
#     emoji, cut to MaxLen clusters), all of it selected, drawn; Esc and the
#     close icon -> cmCancel: the text kept; after closing == a full repaint;
#   * recording: on the link's focus release (Tab), on a button press (OK by
#     the mouse, the focus staying: both history lines recorded; Esc records
#     only the focused one, released as the dialog closes); a password line
#     never;
#   * the hot-key map: the built-in THistory is called for no key but
#     kbDown / kbCtrlX (typed letters, Tab, arrows: no call; its broadcasts
#     only the two of its row).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "019: the input history"

# the scene: dlg (10 4 70 18) with il (MaxLen ${1:-30}) + hi (id 5), il2 +
# hi2 (id 6), ok (default) and cn; il focused; history 5: alpha beta gamma
scene() {
    fvw_tscene 80 24
    TDialog.new dlg 10 4 70 18 'Find'
    TInputLine.new il 3 2 23 3 "${1:-30}"
    THistory.new hi 23 2 26 3 il 5
    TInputLine.new il2 3 5 23 6 30
    THistory.new hi2 23 5 26 6 il2 6
    TButton.new ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
    TButton.new cn 26 10 38 12 'Cancel' cmCancel
    local v
    for v in il hi il2 hi2 ok cn; do fv.views.insert dlg "$v"; done
    fv.views.select il
    fv.histlist.clearHistory
    for v in alpha beta gamma; do fv.histlist.historyAdd 5 "$v"; done
    fv.views.drawView app
}
unscene() { app.delete; if fv.views.isView dlg; then dlg.delete; fi; }
# probe: inside the event loop, what is open: P_W the window's name and
# "AX AY BX BY" (absolute to the dialog), P_F the viewer's Focused, P_N its
# Range, P_C the dialog's Current, P_T the top view
probe() {
    P_W='' P_F='' P_N='' P_C=${dlg_data[Current]-} P_T=$__FV_VW_TOPVIEW
    if fv.views.isView hi__fvhw1; then
        local -n _w=hi__fvhw1_data _v=hi__fvhw1__fvviewer_data
        P_W="hi__fvhw1 ${_w[OriginX]} ${_w[OriginY]} $(( _w[OriginX] + _w[SizeX] )) $(( _w[OriginY] + _w[SizeY] ))"
        P_F=${_v[Focused]} P_N=${_v[Range]}
    fi
}
hist() { fvh_l=''; local i; fv.histlist.historyCount "$1"; local n=$RESULT; for (( i = 0; i < n; i++ )); do fv.histlist.historyStr "$1" "$i"; fvh_l+="$RESULT|"; done; }

kt_test_section "019: the constructors and the look"
scene
kt_test_start "THistory's fields and options (FV Init): Link, HistoryId, ofPostProcess, evBroadcast, not selectable"
o=${hi_data[Options]} m=${hi_data[EventMask]}
if [[ ${hi_data[Link]} == il && ${hi_data[HistoryId]} == 5 ]] && (( (o & FV_OF_POSTPROCESS) && !(o & FV_OF_SELECTABLE) && (m & FV_EM_BROADCAST) )); then kt_test_pass ok
else kt_test_fail "link ${hi_data[Link]} id ${hi_data[HistoryId]} options $o mask $m"; fi
kt_test_start "the refusals (rc 2, one Error line, nothing made): a bad id, a LINK that is no identifier, a wrong count; the window and the viewer: a bad id"
r=''
for args in '0 0 3 1 il 256' '0 0 3 1 il x' '0 0 3 1 a.b 1' '0 0 3 1 il'; do
    s=0; err=$(THistory.new bh 0 0 3 1 ${args#0 0 3 1 } 2>&1) || s=$?
    [[ $err == 'Error: fv.dialogs: THistory.Create'* ]] && ! fv.views.isView bh && r+="$s "
    declare -F bh.delete >/dev/null && bh.delete 2>/dev/null
done
s=0; err=$(THistoryWindow.new bw 0 0 10 5 300 2>&1) || s=$?
[[ $err == 'Error: fv.dialogs: THistoryWindow.Create'* ]] && ! fv.views.isView bw && r+="$s "
s=0; err=$(THistoryViewer.new bv 0 0 10 5 '' '' -1 2>&1) || s=$?
[[ $err == 'Error: fv.dialogs: THistoryViewer.Create'* ]] && ! fv.views.isView bv && r+="$s"
for v in bw bv; do declare -F $v.delete >/dev/null && $v.delete 2>/dev/null; done
if [[ $r == '2 2 2 2 2 2' ]]; then kt_test_pass ok; else kt_test_fail "[$r]"; fi
fv.views.insert desk dlg; fv.views.select dlg; fv.views.drawView app
fv.views.getColor hi 1; c1=$RESULT; fv.views.getColor hi 2; c2=$RESULT
kt_test_start "the look: ▐v▌ after the line, the v in colour 2 (CHistory 22 23 -> CAppColor 53 54 in a gray dialog)"
fvg_cells 33 6 3
if [[ $RESULT == '▐v▌' && $REPLY == "$c1$c2$c1" && $c1 == "${__FV_VW_APAL:52:1}" && $c2 == "${__FV_VW_APAL:53:1}" ]]; then kt_test_pass ok
else kt_test_fail "[$RESULT] [$REPLY] want $c1$c2$c1 (${__FV_VW_APAL:52:2})"; fi
kt_test_start "a wider history view: the other cells blank in colour 1; == a full repaint"
fv.views.locate hi 23 2 27 3
fvg_cells 33 6 4; a="$RESULT|$REPLY"
fv.views.locate hi 23 2 26 3
if [[ $a == "▐v▌ |$c1$c2$c1$c1" ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] $FVW_DIFF"; fi
fv.views.delete desk dlg
unscene

kt_test_section "019: open, choose, close"
scene
kt_test_start "Down on the focused line: the line's text recorded, FV's rect, modal, item 1 focused; Esc -> cmCancel, the text kept"
fv.dialogs.setText il delta
fvg_run 'key kbDown' 'run probe' 'key kbEsc' 'run probe' 'key kbCtrlF4'
hist 5; fv.dialogs.getText il
# (the rect: il 3 2 23 3 -> 2 1 24 10, cut to 60 x 14: by 10 -> 9)
if [[ $FVG_R == cmCancel && $RESULT == delta && $fvh_l == 'delta|gamma|beta|alpha|' ]]; then kt_test_pass ok
else kt_test_fail "R $FVG_R text [$RESULT] hist [$fvh_l]"; fi
fv.dialogs.setText il delta
fvg_run 'key kbDown' 'run probe' 'key kbEsc' 'key kbCtrlF4'
kt_test_start "the window while open: FV's rect 2 1 24 9, its viewer on item 1 of 4, the window the dialog's Current and the top view"
if [[ $P_W == 'hi__fvhw1 2 1 24 9' && $P_F == 1 && $P_N == 4 && $P_C == hi__fvhw1 && $P_T == hi__fvhw1 ]]; then kt_test_pass ok
else kt_test_fail "[$P_W] F $P_F N $P_N C $P_C T $P_T"; fi
kt_test_start "after Esc: the window destroyed (no view, no data left), == a full repaint"
fv.views.insert desk dlg; fv.views.select dlg
if ! fv.views.isView hi__fvhw1 && ! declare -p hi__fvhw1_data >/dev/null 2>&1 && ! declare -p hi__fvhw1__fvviewer_hist >/dev/null 2>&1 && fvw_full app; then kt_test_pass ok
else kt_test_fail "left: $(compgen -v | grep -c fvhw) $FVW_DIFF"; fi
fv.views.delete desk dlg

kt_test_start "Down, Down, Enter -> cmOK: the line's text the chosen string, all of it selected, drawn; == a full repaint"
fv.dialogs.setText il delta
fvg_run 'key kbDown' 'key kbDown' 'key kbEnter' 'run probe' 'key kbCtrlF4'
fv.dialogs.getText il; t=$RESULT
probe
fv.views.insert desk dlg; fv.views.select dlg
# (the list then: delta gamma beta alpha; item 1 + Down = beta)
if [[ $t == beta && ${il_data[SelStart]} == 0 && ${il_data[SelEnd]} == 4 && ${il_data[CurPos]} == 0 && -z $P_W ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "text [$t] sel ${il_data[SelStart]}-${il_data[SelEnd]} cur ${il_data[CurPos]} [$P_W] $FVW_DIFF"; fi
fv.views.delete desk dlg

h5() { local v; fv.histlist.clearHistory; for v in alpha beta gamma; do fv.histlist.historyAdd 5 "$v"; done; }
kt_test_start "the line drawn with the new text after cmOK (seen inside the dialog's loop)"
h5; fv.dialogs.setText il delta
cells() { fvg_cells 13 6 8; P_X=$RESULT; }
# (delta recorded: delta gamma beta alpha; item 1 = gamma)
fvg_run 'key kbDown' 'key kbEnter' 'run cells' 'key kbCtrlF4'
if [[ $P_X == ' gamma  ' ]]; then kt_test_pass "[$P_X]"; else kt_test_fail "[$P_X]"; fi

kt_test_start "Ctrl+X (CtrlToArrow) opens it too; a click and a double click on a row -> cmOK with that row"
h5; fv.dialogs.setText il ''
# ('' is not recorded: gamma beta alpha; the window 12 5 34 13 on the
# screen, the viewer's rows from y 6: y 8 = item 2, alpha)
fvg_run 'key kbCtrlX' 'run probe' 'down 14 8' 'up 14 8' 'ddown 14 8' 'up 14 8' 'key kbCtrlF4'
fv.dialogs.getText il; t=$RESULT
if [[ $P_W == 'hi__fvhw1 2 1 24 9' && $P_N == 3 && $t == alpha ]]; then kt_test_pass ok; else kt_test_fail "[$P_W] N $P_N [$t]"; fi

kt_test_start "a click on the history view opens it (the line focused first); Esc"
fv.views.select ok
fvg_run 'down 34 6' 'run probe' 'up 34 6' 'key kbEsc' 'key kbCtrlF4'
if [[ $P_W == 'hi__fvhw1 2 1 24 9' && $P_C == hi__fvhw1 ]]; then kt_test_pass ok; else kt_test_fail "[$P_W] [$P_C]"; fi

kt_test_start "Down while the line is not focused opens nothing (the dialog's own Down moves the focus)"
fv.views.select ok
fvg_run 'key kbDown' 'run probe' 'key kbCtrlF4'
if [[ -z $P_W ]]; then kt_test_pass ok; else kt_test_fail "[$P_W]"; fi

kt_test_start "the close icon of the window -> cmCancel, the text kept"
fv.views.select il; fv.dialogs.setText il keep
# (the frame's close icon [■] at the window's x + 2 .. 4 -> screen 14..16, y 5)
fvg_run 'key kbDown' 'down 15 5' 'up 15 5' 'run probe' 'key kbCtrlF4'
fv.dialogs.getText il
if [[ -z $P_W && $RESULT == keep ]]; then kt_test_pass ok; else kt_test_fail "[$P_W] [$RESULT]"; fi

kt_test_start "a single string: the viewer on item 0; Enter takes it"
fv.histlist.clearHistory; fv.dialogs.setText il only
fvg_run 'key kbDown' 'run probe' 'key kbEnter' 'key kbCtrlF4'
fv.dialogs.getText il
if [[ $P_F == 0 && $P_N == 1 && $RESULT == only ]]; then kt_test_pass ok; else kt_test_fail "F $P_F N $P_N [$RESULT]"; fi
unscene

kt_test_section "019: the text after cmOK"
scene 5
kt_test_start "CJK and emoji strings, cut to MaxLen (5) clusters by TInputLine's own path; all selected"
fv.histlist.clearHistory
fv.histlist.historyAdd 5 '中文字符串和更多'
fv.histlist.historyAdd 5 '👨‍👩‍👧 fam ily'
fv.histlist.historyAdd 5 'plain'
fv.dialogs.setText il ''
fvg_run 'key kbDown' 'key kbEnter' 'key kbCtrlF4'
fv.dialogs.getText il; a=$RESULT
sel() { P_S="${il_data[SelStart]}-${il_data[SelEnd]}-${il_data[CurPos]}"; }
fvg_run 'key kbDown' 'key kbDown' 'key kbDown' 'key kbEnter' 'run sel' 'key kbCtrlF4'
fv.dialogs.getText il; b=$RESULT n=${#il_cl[@]} se=$P_S
if [[ $a == '👨‍👩‍👧 fam' && $b == '中文字符串' && $n == 5 && $se == 0-5-0 ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b] $n $se"; fi
kt_test_start "after the CJK text: == a full repaint"
fv.views.insert desk dlg; fv.views.select dlg
if fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
fv.views.delete desk dlg
unscene

kt_test_section "019: placement at the owner's edges"
placed() {   # LINK-BOUNDS... -> P_W
    fvw_tscene 80 24
    TDialog.new dlg 10 4 70 18 'Edge'
    TInputLine.new il "$1" "$2" "$3" "$4" 30
    THistory.new hi "$3" "$2" "$(( $3 + 3 ))" "$4" il 5
    fv.views.insert dlg il; fv.views.insert dlg hi; fv.views.select il
    fv.histlist.clearHistory; fv.histlist.historyAdd 5 a; fv.histlist.historyAdd 5 b
    fvg_run 'key kbDown' 'run probe' 'key kbEsc' 'key kbCtrlF4'
    unscene
}
kt_test_start "a line at the top-left corner: the rect cut at 0 0"
placed 0 0 20 1
if [[ $P_W == 'hi__fvhw1 0 0 21 7' ]]; then kt_test_pass ok; else kt_test_fail "[$P_W]"; fi
kt_test_start "a line near the bottom: cut to the dialog's height, one row shorter"
placed 30 11 56 12
if [[ $P_W == 'hi__fvhw1 29 10 57 13' ]]; then kt_test_pass ok; else kt_test_fail "[$P_W]"; fi
kt_test_start "a line at the right edge: cut to the dialog's width"
placed 40 3 60 4
if [[ $P_W == 'hi__fvhw1 39 2 60 10' ]]; then kt_test_pass ok; else kt_test_fail "[$P_W]"; fi

kt_test_section "019: recording"
scene
kt_test_start "the focus release (Tab) records the line's text; '' is not recorded"
fv.histlist.clearHistory
fv.dialogs.setText il first; fv.dialogs.setText il2 ''
fvg_run 'key kbTab' 'key kbCtrlF4'
hist 5; a=$fvh_l; hist 6; b=$fvh_l
if [[ $a == 'first|' && -z $b ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi
kt_test_start "OK pressed by the mouse (the focus stays in the first line): both history lines recorded (cmRecordHistory)"
fv.histlist.clearHistory
fv.views.select il
fv.dialogs.setText il one; fv.dialogs.setText il2 two
# (ok at dialog 14 10 -> screen 24 14)
fvg_run 'down 26 14' 'run probe' 'up 26 14'
hist 5; a=$fvh_l; hist 6; b=$fvh_l
if [[ $FVG_R == cmOK && $a == 'one|' && $b == 'two|' ]]; then kt_test_pass ok; else kt_test_fail "R $FVG_R [$a] [$b]"; fi
kt_test_start "Enter (the default button) records both too"
fv.histlist.clearHistory
fv.views.select il
fv.dialogs.setText il uno; fv.dialogs.setText il2 dos
fvg_run 'key kbEnter'
hist 5; a=$fvh_l; hist 6; b=$fvh_l
if [[ $FVG_R == cmOK && $a == 'uno|' && $b == 'dos|' ]]; then kt_test_pass ok; else kt_test_fail "R $FVG_R [$a] [$b]"; fi
kt_test_start "Esc (no button): only the focused line, released as the dialog closes"
fv.histlist.clearHistory
fv.views.select il
fvg_run 'key kbEsc'
hist 5; a=$fvh_l; hist 6; b=$fvh_l
if [[ $FVG_R == cmCancel && $a == 'uno|' && -z $b ]]; then kt_test_pass ok; else kt_test_fail "R $FVG_R [$a] [$b]"; fi
kt_test_start "a password line is never recorded: Tab away, a button press, Down (the window still opens)"
fv.histlist.clearHistory
fv.histlist.historyAdd 5 older
il_data[PasswordChar]='*'
fv.views.select il; fv.dialogs.setText il secret
fvg_run 'key kbTab' 'key kbShiftTab' 'key kbDown' 'run probe' 'key kbEsc' 'key kbEnter'
hist 5; a=$fvh_l
il_data[PasswordChar]=''
if [[ $a == 'older|' && $P_W == 'hi__fvhw1 2 1 24 9' ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$P_W]"; fi
unscene

kt_test_section "019: the hot-key map"
# count the built-in body's calls (a shim under the same name: the elision
# table names it)
src=$(declare -f fv.dialogs._hiEvent); eval "${src/fv.dialogs._hiEvent/__t_hiEvent}"
fv.dialogs._hiEvent() { HI_N+=" $FV_EV_WHAT:${FV_EV_KEY:-$FV_EV_COMMAND}"; __t_hiEvent "$@"; }
scene
kt_test_start "typed letters, Left, Home, Tab, Up, Enter on a button: no call of THistory's handler but its broadcasts"
HI_N=''
fvg_run 'char a' 'char b' 'key kbLeft' 'key kbHome' 'key kbTab' 'key kbShiftTab' 'key kbUp' 'key kbCtrlF4'
bad=''; for w in $HI_N; do [[ $w == evBroadcast:cmReleasedFocus || $w == evBroadcast:cmRecordHistory ]] || bad+=" $w"; done
if [[ -z $bad ]]; then kt_test_pass "[$HI_N]"; else kt_test_fail "[$bad]"; fi
kt_test_start "kbDown and kbCtrlX reach it (the map names it by HKK)"
fv.views.select il
HI_N=''
fvg_run 'key kbDown' 'key kbEsc' 'key kbCtrlX' 'key kbEsc' 'key kbCtrlF4'
if [[ $HI_N == *'evKeyDown:kbDown'* && $HI_N == *'evKeyDown:kbCtrlX'* ]]; then kt_test_pass ok; else kt_test_fail "[$HI_N]"; fi
unscene
eval "${src}"

kt_test_section "019: palettes and ASCII mode"
scene
fv.dialogs.setText il p
pals() {
    local w=hi__fvhw1 v i e got='' exp=''
    # (the window's entries 19 19 21 24 25 19 20 into the gray dialog: base 31)
    for i in 1 2 3 4 5; do fv.views.getColor ${w}__fvviewer $i; got+=$RESULT; done
    for e in 19 19 20 19 19; do exp+=${__FV_VW_APAL:e+31-1:1}; done
    for i in 1 2 3 4 5; do fv.views.getColor ${w}__fvframe $i; got+=$RESULT; done
    for e in 19 19 19 19 21; do exp+=${__FV_VW_APAL:e+31-1:1}; done
    for i in 1 2 3; do fv.views.getColor ${w}__fvsb2 $i; got+=$RESULT; done
    for e in 24 25 25; do exp+=${__FV_VW_APAL:e+31-1:1}; done
    P_X="$got|$exp"
}
fvg_run 'key kbDown' 'run pals' 'key kbEsc' 'key kbCtrlF4'
kt_test_start "the viewer (CHistoryViewer 6 6 7 6 6), the frame and the bars through CHistoryWindow in a gray dialog"
if [[ ${P_X%|*} == "${P_X#*|}" ]]; then kt_test_pass ok; else kt_test_fail "$P_X"; fi
unscene
FV_ASCII=1
scene
fv.views.insert desk dlg; fv.views.select dlg; fv.views.drawView app
kt_test_start "ASCII mode: [v]; == a full repaint"
fvg_cells 33 6 3
if [[ $RESULT == '[v]' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$RESULT] $FVW_DIFF"; fi
fv.views.delete desk dlg
kt_test_start "ASCII mode: the window open and closed == a full repaint each"
asc() { fvw_full app && P_X=ok || P_X=$FVW_DIFF; }
fvg_run 'key kbDown' 'run asc' 'key kbEsc' 'key kbCtrlF4'
fv.views.insert desk dlg; fv.views.select dlg
if [[ $P_X == ok ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "open [$P_X] closed [$FVW_DIFF]"; fi
fv.views.delete desk dlg
unscene
unset FV_ASCII

kt_test_log "019_History.sh completed"
