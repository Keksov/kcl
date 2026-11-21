#!/usr/bin/env bash
# 017_Palette.sh - the widgets' palettes resolved through TDialog's
# (design P3 §2.6, FV dialogs.inc): each built-in GetPalette (CButton,
# CStaticText, CLabel, CCluster, the frame's CFrame) through CGrayDialog
# (32..63), CBlueDialog (64..95, FV's 30th entry 92) and CCyanDialog
# (96..127) gives exactly CAppColor's entries; 3d: CInputLine, CListViewer
# (a TListBox in a dialog) (fv.views' app palette
# string, checked against fv.video's table by fv.views' 019).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "017: palettes in a dialog"
fvg_modeless
# (P3 3d) an input line and a list box in the dialog too
TInputLine.new pil 3 8 30 9 20; fv.views.insert dlg pil
TListBox.new plb 32 7 56 9 1; fv.views.insert dlg plb
# want V IDX... : the app entries V's palette entries resolve to (base added)
want() {
    local v=$1 b=$2 i=1 e got='' exp=''
    shift 2
    for e; do
        fv.views.getColor "$v" "$i"; got+=$RESULT
        if (( b == 63 && e == 30 )); then exp+=${__FV_VW_APAL:91:1}; else exp+=${__FV_VW_APAL:e+b-1:1}; fi
        i=$(( i + 1 ))
    done
    fvw_check "$v in dialog palette $b: $*" "$exp" "$got"
}
for pal in 2 0 1; do
    dlg_data[Palette]=$pal; fv.views.resetPalette dlg
    case $pal in 2) b=31 ;; 0) b=63 ;; 1) b=95 ;; esac
    want ok "$b" 10 11 12 13 14 14 14 15
    want st "$b" 6 7 8 9
    want l1 "$b" 7 8 9 9
    want opts "$b" 16 17 18 18 31 6
    want dlg__fvframe "$b" 1 1 2 2 3
    want pil "$b" 19 19 20 21 14
    want plb "$b" 26 26 27 28 29
done
dlg_data[Palette]=2; fv.views.resetPalette dlg
kt_test_start "the dialog redrawn after a palette change == a full repaint"
fv.views.drawView dlg
if fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
fvg_unscene
