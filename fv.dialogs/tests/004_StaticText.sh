#!/usr/bin/env bash
# 004_StaticText.sh - TStaticText / TParamText (FV dialogs.inc, the
# FV_UNICODE TStaticText.Draw; design P3 §2.4):
#   * the wrap: at the last blank when a line's cells reach the width (the
#     blank starts the next line, FV_UNICODE), a word longer than the width
#     cut, a line that exactly fills the width broken at its last blank (FV),
#     CR / LF / CRLF, more lines than rows;
#   * ^C ($'\x03') centres and ^B ($'\x02') right-justifies a line;
#   * wide characters (cells from fv.video), another control character as `?`;
#   * the rows cached: a second draw writes the same, one write per draw;
#   * a GetText override is what Draw shows;
#   * TParamText: printf -v of Text with ParamCount parameters from SetData /
#     fv.dialogs.setData, GetData, a bad format answered silently.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: TStaticText"
fvw_tscene
fv.views.drawView app

# st_rows W H TEXT -> REPLY = the rows of a W x H static text at (0, 0) of
# desk, '|'-joined (narrow text: fvw_cells)
st_rows() {
    local y out=''
    TStaticText.new stx 0 0 "$1" "$2" "$3"
    fv.views.insert desk stx
    for (( y = 0; y < $2; y++ )); do fvw_cells 0 "$y" "$1"; out+="$RESULT|"; done
    REPLY=${out%|}
    fv.views.delete desk stx; stx.delete
}
st_rows 8 3 'Hello world';            fvw_check "wrap at the last blank, the blank starts the next line" 'Hello   | world  |        ' "$REPLY"
st_rows 9 1 $'\x03''abc';             fvw_check "^C centres" '   abc   ' "$REPLY"
st_rows 9 1 $'\x02''abc';             fvw_check "^B right-justifies" '      abc' "$REPLY"
st_rows 5 4 $'ab\r\ncd\ref';          fvw_check "CRLF, CR, LF end lines; the rows below blank" 'ab   |cd   |ef   |     ' "$REPLY"
st_rows 4 3 'abcdefghij';             fvw_check "a word longer than the width is cut" 'abcd|efgh|ij  ' "$REPLY"
st_rows 5 2 'ab cd';                  fvw_check "a line that exactly fills the width breaks at its blank (FV_UNICODE)" 'ab   | cd  ' "$REPLY"
st_rows 6 2 'one two three four';     fvw_check "more lines than rows: the rest is not drawn" 'one   | two  ' "$REPLY"
st_rows 6 2 $'a\x01b';                fvw_check "a control character is fv.video's ?" 'a?b   |      ' "$REPLY"
st_rows 6 2 $'\x03''ab'$'\n'$'\x03''cd'; fvw_check "^C per line" '  ab  |  cd  ' "$REPLY"
st_rows 6 1 '';                       fvw_check "empty text: blank rows" '      ' "$REPLY"

kt_test_start "wide characters: cells from fv.video, the wrap counts them"
TStaticText.new stw 0 0 5 2 '文件 保存'
fv.views.insert desk stw
fvg_row 0; r0=$RESULT; fvg_row 1; r1=$RESULT
if [[ $r0 == '文件 '* && $r1 == ' 保存'* ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$r0] [$r1] $FVW_DIFF"; fi
fv.views.delete desk stw; stw.delete

kt_test_start "the rows are cached: a second draw writes the same rows, one write each"
TStaticText.new stc 0 0 20 3 'Some text that wraps across rows'
fv.views.insert desk stc
fvw_snap; s1=$REPLY
fvw_writes_on; FVW_WRITES=0; fv.views.drawView stc; w=$FVW_WRITES; fvw_writes_off
fvw_snap; s2=$REPLY
if [[ $s1 == "$s2" && $w == 1 && ${__FV_DG_CN[stc]} == 3 ]]; then kt_test_pass "1 write"; else kt_test_fail "writes $w rows ${__FV_DG_CN[stc]-}"; fi
kt_test_start "a changed Text redraws the new rows (the cache key)"
stc_data[Text]='Other'; fv.views.drawView stc
fvw_cells 0 0 20
if [ "$RESULT" = 'Other               ' ] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$RESULT] $FVW_DIFF"; fi
fv.views.delete desk stc; stc.delete

kt_test_start "a GetText override is what Draw shows"
class TMyText : TStaticText
    public
        override func GetText
end
TMyText.GetText() { RESULT="<$Text>"; }
build TMyText
TMyText.new stm 0 0 10 1 'x'
fv.views.insert desk stm
fvw_cells 0 0 10
if [ "$RESULT" = '<x>       ' ]; then kt_test_pass ok; else kt_test_fail "[$RESULT]"; fi
fv.views.delete desk stm; stm.delete

kt_test_section "004: TParamText"
TParamText.new pt 0 0 30 1 'File %s has %d lines' 2
fv.views.insert desk pt
kt_test_start "no parameters yet: printf with empty ones"
fvw_cells 0 0 30
if [ "$RESULT" = 'File  has 0 lines             ' ]; then kt_test_pass ok; else kt_test_fail "[$RESULT]"; fi
kt_test_start "setData through the group: the parameters, redrawn; dataSize 2; getData gives them back"
TGroup.new grp 0 0 1 1
D=(a.txt 42)
fv.views.delete desk pt; fv.views.insert grp pt
fv.dialogs.setData grp D
fv.views.delete grp pt; fv.views.insert desk pt
fvw_cells 0 0 30; t=$RESULT
fv.dialogs.dataSize pt; n=$RESULT
E=(); fv.views.delete desk pt; fv.views.insert grp pt; fv.dialogs.getData grp E
if [[ $t == 'File a.txt has 42 lines       ' && $n == 2 && ${E[*]} == 'a.txt 42' ]]; then kt_test_pass ok; else kt_test_fail "[$t] n $n E ${E[*]}"; fi
fv.views.delete grp pt; fv.views.insert desk pt
kt_test_start "a parameter that is no number for %d: no message, the text printf made"
pt_params=(x y); fv.views.drawView pt
fvw_cells 0 0 30
if [[ $RESULT == 'File x has 0 lines'* || $RESULT == 'File x has '* ]]; then kt_test_pass "[$RESULT]"; else kt_test_fail "[$RESULT]"; fi
kt_test_start "the constructor refuses a PARAMCOUNT that is not digits"
e=$( { TParamText.new ptz 0 0 5 1 'x' two; echo "rc$?"; } 2>&1 )
if [[ $e == *'Error: fv.dialogs: TParamText.Create'*rc2 ]] && ! fv.views.isView ptz; then kt_test_pass ok; else kt_test_fail "[$e]"; fi
ptz.delete 2>/dev/null
fv.views.delete desk pt; pt.delete; grp.delete

fvw_untscene
