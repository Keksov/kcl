#!/usr/bin/env bash
# 022_Clipboard.sh - the input line's clipboard (design P3 §4.5, D24; FPC
# 2025 TInputLine.HandleEvent; 018 is the hot-key map's file, so this one
# takes 022):
#   * Ctrl+Ins copies the selection to the internal clipboard FV_CLIPBOARD
#     and by OSC 52 to the system clipboard (the bytes on the screen's fd:
#     ESC ] 52 ; c ; BASE64 BEL), the text unchanged; nothing selected:
#     nothing copied; Shift+Del cuts (copy + delete);
#   * Shift+Ins pastes FV_CLIPBOARD (FV cmPaste), so does an evCommand
#     cmPaste (the Edit menu's);
#   * evCommand cmPasteText (fv.drivers' bracketed paste): the text goes in
#     as typed — newline, CR, Tab and other control characters dropped (FV
#     inserts each character as a key), over the selection, in overwrite
#     mode over as many clusters, MaxLen kept, non-ASCII split as fv.video
#     does (one cluster per character here == fv.video.clusters);
#   * in a modal dialog a pasted newline never presses the default button:
#     the dialog ends by Esc (cmCancel) with the text pasted;
#   * password mode (D29): copy and cut do nothing (no clipboard, no OSC 52,
#     the text kept); paste works;
#   * an unselected line takes no paste (FV: everything under sfSelected).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "022: copy, cut, paste"

scene() {
    fvw_tscene 80 24
    TDialog.new dlg 10 4 70 18 'Edit'
    TInputLine.new il 3 2 33 3 "${1:-40}"
    TButton.new ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
    fv.views.insert dlg il; fv.views.insert dlg ok
    fv.views.select il
    fv.views.insert desk dlg; fv.views.select dlg
    fv.views.drawView app
}
unscene() { app.delete; if fv.views.isView dlg; then dlg.delete; fi; }
k() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-} FV_EV_BASE=''; fv.views._virt dlg HandleEvent; }
cmd() { fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=$1 FV_EV_INFO=${2-}; fv.views._virt dlg HandleEvent; }
# out_mark / out_new -> REPLY = what was written to the screen's fd since the mark
out_mark() { local s; s=$(LC_ALL=C; wc -c < "$FVW_TMP/screen.out"); OUT_AT=${s//[!0-9]/}; }
out_new() { local LC_ALL=C s; s=$(<"$FVW_TMP/screen.out"); REPLY=${s:OUT_AT}; }
txt() { fv.dialogs.getText il; }

scene
FV_CLIPBOARD=''
kt_test_start "Ctrl+Ins: the selection to FV_CLIPBOARD and OSC 52 on the screen's fd; the text unchanged, handled"
fv.dialogs.setText il 'hello world'
fv.dialogs.selectAll il 0; k kbEnd; k kbShiftLeft; k kbShiftLeft; k kbShiftLeft; k kbShiftLeft; k kbShiftLeft
out_mark; k kbCtrlIns; w=$FV_EV_WHAT; out_new
txt
if [[ $FV_CLIPBOARD == world && $REPLY == *$'\e]52;c;d29ybGQ=\a'* && $RESULT == 'hello world' && $w == evNothing ]]; then kt_test_pass ok
else kt_test_fail "clip [$FV_CLIPBOARD] text [$RESULT] $w $(printf '%q' "${REPLY:0:60}")"; fi
kt_test_start "Ctrl+Ins with nothing selected copies nothing"
k kbHome; out_mark; k kbCtrlIns; out_new
if [[ $FV_CLIPBOARD == world && $REPLY != *']52;'* ]]; then kt_test_pass ok; else kt_test_fail "[$FV_CLIPBOARD]"; fi
kt_test_start "Shift+Del cuts: copied (OSC 52 too), deleted, the cursor at the cut"
k kbShiftRight; k kbShiftRight; k kbShiftRight; k kbShiftRight; k kbShiftRight; k kbShiftRight
out_mark; k kbShiftDel; out_new
txt
if [[ $FV_CLIPBOARD == 'hello ' && $RESULT == world && ${il_data[CurPos]} == 0 && $REPLY == *$'\e]52;c;aGVsbG8g\a'* ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "clip [$FV_CLIPBOARD] text [$RESULT] cur ${il_data[CurPos]}"; fi
kt_test_start "Shift+Ins pastes FV_CLIPBOARD (FV cmPaste); an evCommand cmPaste too"
k kbEnd; k kbShiftIns; a=$(txt; printf '%s' "$RESULT")
k kbHome; cmd cmPaste; w=$FV_EV_WHAT
txt
if [[ $a == 'worldhello ' && $RESULT == 'hello worldhello ' && $w == evNothing ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] [$RESULT] $w"; fi
kt_test_start "cmPasteText: control characters dropped (newline, CR, Tab, ESC), inserted at the cursor, the cursor after it"
k kbCtrlY
cmd cmPasteText $'one\ntwo\r\tthree\e'
txt
if [[ $RESULT == onetwothree && ${il_data[CurPos]} == 11 && $FV_EV_WHAT == evNothing ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$RESULT] ${il_data[CurPos]}"; fi
kt_test_start "cmPasteText over a selection replaces it; in overwrite mode it takes as many clusters as it brings"
k kbHome; k kbShiftRight; k kbShiftRight; k kbShiftRight
cmd cmPasteText 'ONE'; a=$(txt; printf '%s' "$RESULT")
k kbIns; k kbHome; cmd cmPasteText 'xy'; k kbIns
txt
if [[ $a == ONEtwothree && $RESULT == xyEtwothree ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$RESULT]"; fi
kt_test_start "cmPasteText with non-ASCII text: its clusters == fv.video's split of the line; MaxLen kept (40 clusters)"
k kbCtrlY
cmd cmPasteText "жи中文😀 $(printf 'x%.0s' {1..50})"
txt; t=$RESULT
fv.video.clusters "$t" CL CW
# (a prefix pattern, not ${t:0:6}: past U+FFFF a Cygwin-family bash counts two characters)
if [[ ${#il_cl[@]} == 40 && "${CL[*]}" == "${il_cl[*]}" && "${CW[*]}" == "${il_cw[*]}" && $t == 'жи中文😀 x'* ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "${#il_cl[@]} [$t] cw [${il_cw[*]}] split [${CW[*]}] $FVW_DIFF"; fi
kt_test_start "an unselected line takes no paste (the button focused): not handled"
fv.views.focus ok
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmPasteText FV_EV_INFO=zzz; fv.views._virt il HandleEvent
txt
if [[ $FV_EV_WHAT == evCommand && $RESULT != *zzz* ]]; then kt_test_pass ok; else kt_test_fail "$FV_EV_WHAT [$RESULT]"; fi
fv.views.focus il
unscene

kt_test_section "022: a paste in a modal dialog"
scene
kt_test_start "a pasted newline never presses the default button: the run ends by Esc with cmCancel, the text pasted"
# (the paste put first: the scripted source reads its specs line by line)
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmPasteText FV_EV_INFO=$'a\nb'; fv.drivers.putEvent
fvg_events 'key kbEsc'
fv.views.execView desk dlg; r=$RESULT
fvw_noevents
txt
if [[ $r == cmCancel && $RESULT == ab ]]; then kt_test_pass ok; else kt_test_fail "$r [$RESULT]"; fi
kt_test_start "the same newline typed as a key (no bracketed paste) presses the default button: cmOK"
fvg_events 'char a' 'key kbEnter'
fv.views.execView desk dlg; r=$RESULT
fvw_noevents
if [[ $r == cmOK ]]; then kt_test_pass ok; else kt_test_fail "$r"; fi
unscene

kt_test_section "022: password mode (D29)"
scene
il_data[PasswordChar]='*'
FV_CLIPBOARD=before
kt_test_start "copy and cut do nothing: no clipboard, no OSC 52, the text kept"
fv.dialogs.setText il secret
out_mark; k kbCtrlIns; k kbShiftDel; out_new
txt
if [[ $FV_CLIPBOARD == before && $RESULT == secret && $REPLY != *']52;'* ]]; then kt_test_pass ok; else kt_test_fail "[$FV_CLIPBOARD] [$RESULT]"; fi
kt_test_start "a paste works (the refused copy collapsed the selection, as FV's tail does after Ctrl+Ins): in at the cursor"
cmd cmPasteText 'new '
txt; t=$RESULT
fvg_cells 13 6 12
if [[ $t == 'new secret' && $RESULT == ' ********** ' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$t] [$RESULT]"; fi
unscene

kt_test_log "022_Clipboard.sh completed"
