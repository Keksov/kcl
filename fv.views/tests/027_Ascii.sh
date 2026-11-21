#!/usr/bin/env bash
# 027_Ascii.sh - the scroll bar and list parts in ASCII mode (P3 stage 3b;
# design P3 §2.7, M8): FV's LowAscii keeps the CP437 shades, which
# fv.video's ASCII mode would show as ?, so the widgets take their glyphs
# from the per-mode table:
#   * a vertical bar ^ : # v (the indicator #), Max = Min #, a horizontal
#     bar < : # >; the screen's mode decides (FV_ASCII=1 at initScreen);
#   * list rows with non-ASCII names go through writeRows: one cell per
#     character, shown as ? (fv.video's ASCII cells), padded to the row;
#     the multi-column divider │ shows as fv.video's |;
#   * the screen == a full repaint after keys, PgDn over fresh pages and a
#     panel switch; the cells == fv.video's own cells for the same text.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "027: lists and bars in ASCII mode"

key() {
    local k
    for k; do fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$k; fv.views._virt app HandleEvent; done
    REPLY="${w2l_data[Focused]} ${w2l_data[TopItem]} ${w2__fvsb1_data[Value]}"
}
col() {
    local y t=''
    for (( y = $2; y < $2 + $3; y++ )); do fv.video.getRow "$y"; t+=${RESULT:$1:1}; done
    RESULT=$t
}

FV_ASCII=1
fvw_lscene 80 24 300 cyr
fv.views.drawView app

kt_test_start "the screen is in ASCII mode (FV_VIDEO_ASCII=1)"
if (( FV_VIDEO_ASCII == 1 )); then kt_test_pass "ok"; else kt_test_fail "FV_VIDEO_ASCII=$FV_VIDEO_ASCII"; fi

kt_test_start "a vertical bar: ^ # : … : v (FV LowAscii's arrows; the area : and the indicator # from the design's table)"
col 79 1 21
C18=$(printf ':%.0s' {1..18})
if [[ $RESULT == "^#${C18}v" ]]; then kt_test_pass "ok"; else kt_test_fail "[$RESULT]"; fi

kt_test_start "the list's Cyrillic rows: one cell per character, shown as ? (fv.video's ASCII cells), padded to the 38 cells"
fvw_cells 41 2 38
want=' ?????_1' want+=$(printf '%30s' '')
if [[ $RESULT == "$want" ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$RESULT] want [$want] $FVW_DIFF"; fi

kt_test_start "the cells equal fv.video's own for the same text (a row written by writeBuf at the same place)"
fv.video.getRow 3; a=${RESULT:41:38}
fv.video.writeStr 42 3 "${FVW_L1[2]}" 1
fv.video.getRow 3; b=${RESULT:42:7}
if [[ ${a:1:7} == "$b" ]]; then kt_test_pass "ok [$b]"; else kt_test_fail "[$a] vs [$b]"; fi
fv.views.drawView w2l

kt_test_start "PgDn over fresh pages, Down, End, Home: each == a full repaint; the bar's indicator moves (# on :)"
bad=''
for k in kbPgDn kbPgDn kbDown kbEnd kbHome kbPgDn; do key "$k"; fvw_full app || bad+=" [$k: $FVW_DIFF]"; done
key kbEnd
col 79 1 21
if [[ -z $bad && $RESULT == "^${C18}#v" ]]; then kt_test_pass "ok"; else kt_test_fail "$bad [$RESULT]"; fi

kt_test_start "a panel switch: the inactive list's bar hidden (the frame's | there), shown again; == a full repaint"
fv.views.select w1
col 79 5 1; a=$RESULT
fvw_full app || a+=" diff [$FVW_DIFF]"
fv.views.select w2
col 79 5 1; a+=$RESULT
if [[ $a == '|:' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$a] $FVW_DIFF"; fi
fvw_unlscene

kt_test_start "Max = Min: the area #; a horizontal bar < : # >"
fvw_screen 40 12
TGroup.new root 0 0 40 12; fvw_expose root
TView.new bg 0 0 40 12; fv.views.insert root bg
TScrollBar.new vb 30 1 31 6; fv.views.insert root vb
TScrollBar.new hb 2 11 12 12; fv.views.insert root hb
fv.views.scrollBarSet hb 0 0 10
fv.views.drawView root
col 30 1 5; a=$RESULT
fvw_cells 2 11 10; b=$RESULT
if [[ $a == '^###v' && $b == '<#::::::::>' || $b == '<#:::::::>' ]] && fvw_full root; then kt_test_pass "ok [$a] [$b]"; else kt_test_fail "[$a] [$b] $FVW_DIFF"; fi
root.delete

kt_test_start "multi-column with CJK names: per column writeRows (one ? per character), the divider │ as fv.video's |"
fvw_screen 80 24
TGroup.new mc 0 0 80 24; fvw_expose mc
TView.new mbg 0 0 80 24; fv.views.insert mc mbg
TWindow.new mw 0 0 33 8 M 1
TListViewer.new ml 1 1 31 6 3
fv.views.insert mw ml
fvw_items ML 50 cjk
ml_data[List]=ML
fv.views.listSetRange ml 50
fv.views.insert mc mw
fvw_root mc
fv.views.drawView mc
fvw_cells 1 1 30
if [[ ${RESULT:0:10} == ' ????_0   ' && ${RESULT:10:1} == '|' && ${RESULT:21:1} == '|' ]] && fvw_full mc; then kt_test_pass "ok [$RESULT]"; else kt_test_fail "[$RESULT] $FVW_DIFF"; fi
mc.delete

kt_test_log "027_Ascii.sh completed"
