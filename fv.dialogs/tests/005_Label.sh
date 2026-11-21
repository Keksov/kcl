#!/usr/bin/env bash
# 005_Label.sh - TLabel (FV dialogs.inc; design P3 §2.4, §3.1, §14):
#   * the look: a blank, the text with its `~` letter (colours 1 / 3), Light
#     (2 / 4) while the link is focused; cut to the width; rows below blank;
#   * Light follows the focus broadcasts and redraws only when it changes
#     (P3-12: a Tab between two other controls draws no label);
#   * hot keys focus the link: Alt + the letter, the plain letter only in the
#     owner's post-process phase, a Cyrillic hot letter on its own key, a
#     Latin hot letter through the base-layout key (FV_EV_BASE) and through
#     the layout tables for a plain Cyrillic letter; a typed match wins over
#     a base match (the map's two passes);
#   * a click focuses the link; a label without a link does nothing.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "005: TLabel"
fvg_modeless
fv.views.getColor l1 1; c1=$RESULT; fv.views.getColor l1 2; c2=$RESULT
fv.views.getColor l1 3; c3=$RESULT; fv.views.getColor l1 4; c4=$RESULT
# l1 at dialog (2, 3) 12 wide -> screen (12, 7); opts is focused: Light
fvg_cells 12 7 12
fvw_check "the light label (link focused): ' Text' in 2, the T in 4" " Text       |$c2$c4$c2$c2$c2$c2$c2$c2$c2$c2$c2$c2" "$RESULT|$REPLY"
fvg_cells 42 7 14
fvw_check "the other label: ' Direction' in 1, the D in 3" " Direction    |$c1$c3$c1$c1$c1$c1$c1$c1$c1$c1$c1$c1$c1$c1" "$RESULT|$REPLY"

kt_test_start "Tab to dir: l1 goes dark, l2 light (one write each), == a full repaint"
fvw_writes_on; FVW_WRITES=0
fv.views.focus dir
w=$FVW_WRITES; fvw_writes_off
if [[ ${l1_data[Light]}${l2_data[Light]} == 01 ]] && fvw_full app; then kt_test_pass "writes $w"; else kt_test_fail "${l1_data[Light]}${l2_data[Light]} $FVW_DIFF"; fi
kt_test_start "P3-12: a focus change between two buttons draws no label"
fv.views.focus ok
LBL=0; fvw_wrap LBL fv.dialogs._lblDraw
fv.views.focus cn; fv.views.focus hp
n=$LBL; fvw_unwrap fv.dialogs._lblDraw
if (( n == 0 )) && [[ ${l1_data[Light]}${l2_data[Light]} == 00 ]] && fvw_full app; then kt_test_pass "0 label draws"; else kt_test_fail "$n label draws, Light ${l1_data[Light]}${l2_data[Light]}"; fi
kt_test_section "005: hot keys"
fv.views.focus ok
hk() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=$2 FV_EV_BASE=${3-}; fv.views._virt dlg HandleEvent; }
kt_test_start "Alt+T focuses opts (the label's link); Alt+D focuses dir"
hk kbAltT t; a=${dlg_data[Current]}
hk kbAltD d; b=${dlg_data[Current]}
if [[ $a.$b == opts.dir ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "the plain letter t in the post-process phase (a button focused): opts"
fv.views.focus ok
hk kbChar t; a=${dlg_data[Current]}
if [ "$a" = opts ]; then kt_test_pass ok; else kt_test_fail "$a"; fi
kt_test_start "the plain letter with the focused cluster: the cluster takes its own letters first, not t"
hk kbChar t; a=${dlg_data[Current]}:${FV_EV_WHAT}
if [ "$a" = opts:evNothing ]; then kt_test_pass ok; else kt_test_fail "$a"; fi
kt_test_start "a Cyrillic hot letter: '~Н~аправление' takes Alt+н (typed) and Alt+Н"
fv.dialogs.setLabel l2 '~Н~аправление'
fv.views.focus ok
hk kbAltY н y; a=${dlg_data[Current]}
fv.views.focus ok
hk kbAltY Н y; b=${dlg_data[Current]}
if [[ $a.$b == dir.dir ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "a Latin hot letter through the base key: Alt+е (Russian, base t) focuses opts"
fv.views.focus ok
hk kbAltT е t; a=${dlg_data[Current]}
if [ "$a" = opts ]; then kt_test_pass ok; else kt_test_fail "$a"; fi
kt_test_start "the plain Cyrillic letter е in post-process: the layout tables give t"
fv.views.focus ok
hk kbChar е; a=${dlg_data[Current]}
if [ "$a" = opts ]; then kt_test_pass ok; else kt_test_fail "$a"; fi
kt_test_start "typed wins over base: '~Т~екст' on l1 and ~T~ via base: Alt+т (base n) focuses opts, not via n"
fv.dialogs.setLabel l1 '~Т~екст'
fv.dialogs.setLabel l2 '~N~ext'
fv.views.focus ok
hk kbAltN т n; a=${dlg_data[Current]}
if [ "$a" = opts ]; then kt_test_pass ok; else kt_test_fail "$a"; fi
fv.dialogs.setLabel l1 '~T~ext'; fv.dialogs.setLabel l2 '~D~irection'

kt_test_section "005: the mouse"
kt_test_start "a click on l2 focuses dir"
fv.views.focus ok
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=44 FV_EV_MOUSE_Y=7 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent
if [[ ${dlg_data[Current]} == dir && $FV_EV_WHAT == evNothing ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "${dlg_data[Current]} $FV_EV_WHAT"; fi
kt_test_start "a label without a link: a click is handled, nothing focused"
l2_data[Link]=''
fv.views.focus ok
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=44 FV_EV_MOUSE_Y=7 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent
if [[ ${dlg_data[Current]} == ok && $FV_EV_WHAT == evNothing ]]; then kt_test_pass ok; else kt_test_fail "${dlg_data[Current]} $FV_EV_WHAT"; fi
l2_data[Link]=dir
kt_test_start "the text cut to the width; a 2-row label's second row blank"
TLabel.new lw 2 7 8 9 'Longer text' dir
fv.views.insert dlg lw
fvg_cells 12 11 6; a=$RESULT; fvg_cells 12 12 6; b=$RESULT
if [[ $a == ' Longe' && $b == '      ' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi
fvg_unscene
