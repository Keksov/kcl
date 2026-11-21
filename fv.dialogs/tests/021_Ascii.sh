#!/usr/bin/env bash
# 021_Ascii.sh - the widgets in ASCII mode (FV_ASCII=1 at initScreen; design
# P3 §2.7): a button without shadow characters (blanks in colour 8, FV's
# monochrome look), its pressed look; check / radio marks as in UTF-8 mode;
# a label and a static text with a non-ASCII text one `?` cell per
# character, as fv.video counts them there; cluster columns from those
# cells; every scene == a full repaint.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "021: ASCII mode"
FV_ASCII=1
fvg_modeless
kt_test_start "the screen is in ASCII mode"
if [ "${FV_VIDEO_ASCII:-0}" = 1 ]; then kt_test_pass ok; else kt_test_fail "FV_VIDEO_ASCII=${FV_VIDEO_ASCII-}"; fi
fvg_cells 24 14 10; a=$RESULT; fvg_cells 24 15 10; b=$RESULT
fvw_check "a button: no shadow characters" '    OK    |          ' "$a|$b"
fvg_cells 13 8 9
fvw_check "check boxes as in UTF-8 mode" ' [ ] Case' "$RESULT"
kt_test_start "the pressed look"
fv.dialogs._btnState ok 1
fvg_cells 24 14 10; a=$RESULT
fv.dialogs._btnState ok 0
if [ "$a" = '     OK   ' ] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] $FVW_DIFF"; fi
kt_test_start "a Cyrillic label: one ? cell per character; == a full repaint"
fv.dialogs.setLabel l1 '~Т~екст'
fvg_cells 12 7 8
if [ "$RESULT" = ' ?????  ' ] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$RESULT] $FVW_DIFF"; fi
kt_test_start "a CJK static text: one cell per character, wrapped by those cells"
fv.dialogs.setLabel st $'\x03''文件保存'
fvg_cells 13 5 54
if [[ $RESULT == *' ????'* ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$RESULT] $FVW_DIFF"; fi
kt_test_start "cluster items with CJK text: columns from the ASCII cells"
fv.dialogs.setItems opts '文件' 'b' 'c'
TRadioButtons.new rcj 2 7 40 8 '文件' '保存文件' 'x'
fv.views.insert dlg rcj
fvg_cells 12 11 28
if [ "$RESULT" = ' (*) ??  ( ) ????  ( ) x    ' ] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$RESULT] $FVW_DIFF"; fi
fvg_unscene
