#!/usr/bin/env bash
# 007_Sizes.sh - sizes (P4-8, design §3.7, §5.3) and the scrolling text
# (P4-9, TDlgText) through fv.dlg.run --fv-headless:
#   * the auto size per widget (0 0: the text's fit, at most 2/3 of the
#     screen for the text; a list: its widest row + 6, LH rows, the bar's
#     column when the items do not fit; the title and the buttons), -1 -1
#     (the desktop, below a background title), clamping, a smaller H / W
#     grown to the minimum;
#   * the exact minimum per widget (the buttons across + 4, at least 16;
#     down: msgbox / yesno 5, inputbox 7, the lists 8, the infobox 3; + the
#     background title's row): one cell less is refused with 255 and one
#     line "terminal too small (need WxH, have WxH)", nothing left;
#   * TDlgText: text that does not fit (or --scrolltext on a msgbox /
#     yesno) scrolls — its rows the static text's colour (no highlighted
#     focus row), the bar, Down / PgDn / End / Home / Up scroll the top
#     row, Enter still presses the default button; a prompt above an input
#     line or a list scrolls too; text that fits stays a TStaticText (4a-1's
#     layout unchanged);
#   * a resize (cmResizeApp, what fv.drivers gives after SIGWINCH): the box
#     re-centred; a desktop smaller than the box but not than the minimum:
#     the box shrinks to it (the controls by GrowMode, the buttons centred
#     on their row); -1: the box follows the desktop; below the minimum the
#     dialog ends with 255 and the message after the restore (§3.5);
#   * H1: a new size lays the controls out as a build at that size would:
#     a 5-line prompt over LH 3 shrunk to 30 x 9 keeps a list row, its
#     bar and the answer on screen; at the minimum one row each; a static
#     text that no longer fits scrolls (and takes a msgbox's focus); the
#     marks, the focus and the input text survive; growing back gives the
#     screen as built;
#   * L7: an explicit H / -1 gives its spare rows to the list; L3: an empty
#     button label is a blank button; M3: the wrap's rows as 4a-2's
#     (fixtures), long words cut in pieces, a 200 KB line within 60 s.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

# box TITLE WANT SPEC... -- ARG... — the dialog's bounds while it runs
box() {
    local title=$1 want=$2
    shift 2
    fvdl_run snap "$@"
    fvdl_box
    fvw_check "$title" "$want" "$REPLY"
}
# small TITLE SIZE MSG ARG... — refused at --fv-size SIZE with MSG, nothing left
small() {
    local title=$1 size=$2 msg=$3 e
    shift 3
    fvdl_run 'key kbEnter' -- --fv-size "$size" "$@" 2>"$FVW_TMP/small.err"
    e=$(<"$FVW_TMP/small.err")
    fvdl_live
    kt_test_start "$title"
    if [[ $FVDL_RC == 255 && $e == "fv.dlg.run: $msg" && -z $REPLY && -z $FV_APP ]]; then kt_test_pass "$e"
    else kt_test_fail "rc $FVDL_RC [$e] live [$REPLY]"; fi
}
# fits TITLE SIZE ARG... — rc 0 at --fv-size SIZE (Enter)
fits() {
    local title=$1 size=$2
    shift 2
    fvdl_run 'key kbEnter' -- --fv-size "$size" "$@" 2>"$FVW_TMP/small.err"
    kt_test_start "$title"
    if [[ $FVDL_RC == 0 && ! -s $FVW_TMP/small.err ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC [$(<"$FVW_TMP/small.err")]"; fi
}

kt_test_section "007: the auto size per widget"
box "yesno 0 0: the buttons' width + 4 (26), the text row + 5" '27 9 53 15' 'key kbEnter' -- --yesno 'Proceed?' 0 0
box "inputbox 0 0: 26 wide, text + input + blank + buttons + frame (8 rows)" '27 8 53 16' 'key kbEnter' -- --inputbox 'Name:' 0 0
fvdl_run -- --infobox 'Please wait' 0 0; fvdl_snap; fvdl_box
fvw_check "infobox 0 0: the text + 5 (16 at least), 3 rows" '32 10 48 13' "$REPLY"
box "menu 0 0 0: the widest row + 6 (tag, two blanks, item), every item; text + blank + rows + blank + buttons + frame" '27 7 53 16' 'key kbEnter' -- --menu 'Pick' 0 0 0 a Apple b Banana
box "checklist: the mark adds 4 columns to the row" '27 7 53 16' 'key kbEnter' -- --checklist 'Pick' 0 0 0 a Apple on b Banana off
box "a long row widens the box (row + 6)" '14 7 66 16' 'key kbEnter' -- --menu 'Pick' 0 0 0 a 'An item text that is rather long, forty-one' b B
box "LH 3 of 10: three rows, the bar's column" '27 7 53 17' 'key kbEnter' -- --menu 'Pick' 0 0 3 a A b B c C d D e E f F g G h H i I j J
box "LH larger than the items: the items" '27 7 53 16' 'key kbEnter' -- --menu 'Pick' 0 0 50 a A b B
box "a title wider than the text: title + 16 (FV TFrame: W - 16 beside the close icon)" '22 9 57 15' 'key kbEnter' -- --title 'A rather long title' --yesno 'Ok?' 0 0
box "a long text: at most 2/3 of the screen for it (53 + 4)" '11 7 68 16' 'key kbEnter' -- --msgbox "$(printf 'word %.0s' {1..40})" 0 0

kt_test_section "007: -1, clamping, the minimum grown to"
box "menu -1 -1: the desktop" '0 0 80 24' 'key kbEnter' -- --menu 'Pick' -1 -1 0 a A b B
box "checklist -1 -1 below a background title" '0 1 80 24' 'key kbEnter' -- --backtitle Setup --checklist 'Pick' -1 -1 0 a A on
box "radiolist 100 200: clamped" '0 0 80 24' 'key kbEnter' -- --radiolist 'Pick' 100 200 0 a A on
box "menu 3 10: grown to the minimum 26 x 8" '27 8 53 16' 'key kbEnter' -- --menu 'Pick' 3 10 0 a A b B c C
box "inputbox 3 10: grown to 26 x 7" '27 8 53 15' 'key kbEnter' -- --inputbox 'Name:' 3 10
fvdl_run snap 'key kbEnter' -- --menu 'Pick' 10 40 0 a A b B c C d D e E
fvdl_find '▼'; dn=$REPLY
kt_test_start "menu 10 40 with 5 items: three list rows are the room, the bar shows"
if [[ -n $dn && $FVDL_RC == 0 ]]; then kt_test_pass "$dn"; else kt_test_fail "[$dn]"; fi

kt_test_section "007: the exact minimum"
small "msgbox at 15x5" 15x5 'terminal too small (need 16x5, have 15x5)' --msgbox q 0 0
small "msgbox at 16x4" 16x4 'terminal too small (need 16x5, have 16x4)' --msgbox q 0 0
fits "msgbox at 16x5" 16x5 --msgbox q 0 0
small "yesno at 25x5" 25x5 'terminal too small (need 26x5, have 25x5)' --yesno q 0 0
fits "yesno at 26x5" 26x5 --yesno q 0 0
small "inputbox at 26x6" 26x6 'terminal too small (need 26x7, have 26x6)' --inputbox q 0 0
fits "inputbox at 26x7" 26x7 --inputbox q 0 0
small "menu at 26x7" 26x7 'terminal too small (need 26x8, have 26x7)' --menu q 0 0 0 a A b B
small "checklist at 25x8" 25x8 'terminal too small (need 26x8, have 25x8)' --checklist q 0 0 0 a A on
fits "radiolist at 26x8" 26x8 --radiolist q 0 0 0 a A on b B off c C off
fits "menu --nocancel at 16x8 (OK alone)" 16x8 --nocancel --menu q 0 0 0 a A
small "the background title's row counts" 26x8 'terminal too small (need 26x9, have 26x8)' --backtitle B --menu q 0 0 0 a A
fits "infobox at 16x3" 16x3 --infobox q 0 0
small "infobox at 16x2" 16x2 'terminal too small (need 16x3, have 16x2)' --infobox q 0 0
fits "long OK / Cancel labels are clipped to the screen, not refused (4a-1's rule)" 28x8 --ok-button 'Accept it' --cancel-button 'Reject it' --menu q 0 0 0 a A

kt_test_section "007: the scrolling text (TDlgText)"
T=$(printf 'line%d\\n' {1..12})
T=${T%'\n'}
fvdl_run snap 'key kbPgDn' 'key kbEnter' -- --msgbox "$T" 8 30
s0=$FVDL_SNAP
fvdl_row 9; r9=$REPLY
fvdl_find '▲'; up=$REPLY
fvdl_find 'line1'; l1=$REPLY
kt_test_start "msgbox 8 30 with 12 lines: three rows of text (a blank above the button), the bar, from column 2"
if [[ $r9 == *'║ line1'*'▲ ║'* && -n $up && ${l1% *} == 27 ]]; then kt_test_pass "$l1"; else kt_test_fail "[$r9] ▲ [$up] line1 at [$l1]"; fi
declare -a tops=()
fvdl_shot() { fvdl_snap; fvdl_row 9; tops+=("${REPLY:27:6}"); }
fvdl_run 'run fvdl_shot' 'key kbPgDn' 'run fvdl_shot' 'key kbDown' 'run fvdl_shot' 'key kbEnd' 'run fvdl_shot' 'key kbUp' 'run fvdl_shot' 'key kbHome' 'run fvdl_shot' 'key kbEnter' -- --msgbox "$T" 8 30
kt_test_start "the keys scroll the top row: PgDn by the rows, Down by one, End the last page, Up, Home; Enter = OK"
if [[ "${tops[*]}" == 'line1  line4  line5  line10 line9  line1 ' && $FVDL_RC == 0 && $FVDL_CMD == cmOK ]]; then kt_test_pass "${tops[*]}"
else kt_test_fail "[${tops[*]}] rc $FVDL_RC $FVDL_CMD"; fi
fvdl_run snap 'key kbEnter' -- --msgbox "$T" 8 30
fvdl_row 9; ra=$REPLY
IFS='|' read -r -a att <<< "$FVDL_SNAPA"
a9=${att[9]:28:1} a10=${att[10]:28:1}
fvdl_run snap 'key kbEnter' -- --msgbox 'line1\nline2' 8 30
IFS='|' read -r -a att2 <<< "$FVDL_SNAPA"
fvdl_find 'line1'; p=$REPLY
s9=${att2[${p#* }]:$(( ${p% *} + 1 )):1}
kt_test_start "no highlighted focus row: the first and the second row in the static text's colour"
if [[ -n $a9 && $a9 == "$a10" && $a9 == "$s9" ]]; then kt_test_pass "[$a9]"; else kt_test_fail "[$a9] [$a10] static [$s9]"; fi
box "the same text auto-sized fits the screen: a static text" '32 3 48 20' 'key kbEnter' -- --msgbox "$T" 0 0
fvdl_run snap 'key kbEnter' -- --msgbox "$(printf 'l%d\\n' {1..40})" 0 0
fvdl_box; b=$REPLY
fvdl_find '▼'; dn=$REPLY
kt_test_start "40 lines auto-sized: the screen's height, scrolling"
if [[ $b == '32 0 48 24' && -n $dn ]]; then kt_test_pass "$b"; else kt_test_fail "[$b] [$dn]"; fi
fvdl_run snap 'key kbEnter' -- --scrolltext --msgbox 'hi' 8 30
fvdl_find '▲'; up=$REPLY
fvdl_find 'hi'; h=$REPLY
kt_test_start "--scrolltext with a short text: the scrolling view without a bar; Enter = OK (whiptail: Tab Enter)"
if [[ -z $up && -n $h && $FVDL_RC == 0 ]]; then kt_test_pass ok; else kt_test_fail "[$up] [$h] rc $FVDL_RC"; fi
fvdl_run 'key kbTab' 'key kbEnter' -- --yesno "$T" 8 30
kt_test_start "yesno with a long text: the text focused, Tab -> Yes, Enter -> Yes"
if [[ $FVDL_RC == 0 && $FVDL_CMD == cmYes ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC $FVDL_CMD"; fi
fvdl_run 'key kbEnter' -- --defaultno --yesno "$T" 8 30
kt_test_start "yesno --defaultno with a long text: Enter -> No"
if [[ $FVDL_RC == 1 ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC"; fi
fvdl_run snap 'char a' 'key kbEnter' -- --inputbox "$T" 10 30
fvdl_find 'line1'; l=$REPLY
kt_test_start "an inputbox's long prompt scrolls; the input line keeps the focus"
if [[ -n $l && $FVDL_RES == a ]]; then kt_test_pass ok; else kt_test_fail "[$l] [$FVDL_RES]"; fi
fvdl_run snap 'key kbDown' 'key kbEnter' -- --menu "$T" 12 30 3 a A b B c C
fvdl_find 'line1'; l=$REPLY
fvdl_find '▲'; up=$REPLY
kt_test_start "a menu's long prompt scrolls above the list; the list keeps the focus"
if [[ -n $l && -n $up && $FVDL_RES == b ]]; then kt_test_pass ok; else kt_test_fail "[$l] [$up] [$FVDL_RES]"; fi
fvdl_run snap 'key kbEnter' -- --msgbox 'a fairly long line of words that wraps in the box' 6 20
fvdl_row 10; r=$REPLY
kt_test_start "a wrapped text that does not fit: wrapped at the blanks (the blank starts the next row)"
if [[ $r == *'║ a fairly long  ▲ ║'* ]]; then kt_test_pass "[$r]"; else kt_test_fail "[$r]"; fi

kt_test_section "007: resize"
box "a bigger terminal: re-centred" '37 12 63 18' 'resize 100 30' snap 'key kbEnter' -- --yesno 'Proceed?' 0 0
fvdl_run 'resize 30 8' snap 'char x' 'key kbEnter' -- --inputbox 'Name:' 0 60
fvdl_box; b=$REPLY
fvdl_find 'OK'; ok=$REPLY
kt_test_start "smaller than the box, not than the minimum: the box shrinks to the desktop, buttons centred on row h-3; the input still works"
if [[ $b == '0 0 30 8' && ${ok#* } == 5 && $FVDL_RES == x ]]; then kt_test_pass "$b OK at $ok"; else kt_test_fail "[$b] OK [$ok] [$FVDL_RES]"; fi
box "-1 -1: the box follows the desktop" '0 0 100 30' 'resize 100 30' snap 'key kbEnter' -- --menu 'Pick' -1 -1 0 a A b B
box "--topleft stays at the corner" '0 0 30 8' 'resize 100 30' snap 'key kbEnter' -- --topleft --msgbox q 8 30
box "a background title: below it" '37 12 63 18' 'resize 100 30' snap 'key kbEnter' -- --backtitle B --yesno q 0 0
fvdl_run 'resize 20 5' 'key kbEnter' -- --yesno 'Proceed?' 0 0 2>"$FVW_TMP/rz.err"
e=$(<"$FVW_TMP/rz.err")
fvdl_live
kt_test_start "below the minimum: the dialog ends, 255, one line after the restore; nothing left"
if [[ $FVDL_RC == 255 && $e == 'fv.dlg.run: terminal too small (need 26x5, have 20x5)' && -z $FVDL_CMD && -z $REPLY && -z $FV_APP ]]; then kt_test_pass "$e"
else kt_test_fail "rc $FVDL_RC [$e] [$FVDL_CMD] live [$REPLY]"; fi
fvdl_events 'resize 20 5' 'key kbEnter'
fv.dlg.main --fv-headless --menu 'Pick' 0 0 0 a A 2>"$FVW_TMP/rz.err"; r=$?
fva_noevents; __FV_VW_EOF=0
kt_test_start "the command's face: 255, the message on stderr, no answer"
if (( r == 255 )) && [[ $(<"$FVW_TMP/rz.err") == 'fvdlg: terminal too small (need 26x8, have 20x5)' ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$(<"$FVW_TMP/rz.err")]"; fi
fvdl_run 'resize 40 10' snap 'key kbEnter' -- --msgbox "$T" 8 60
fvdl_find 'line1'; l=$REPLY
fvdl_box; b=$REPLY
kt_test_start "the scrolling text after a shrink: re-wrapped in the narrower box"
if [[ $b == '0 1 40 9' && -n $l && $FVDL_RC == 0 ]]; then kt_test_pass "$b"; else kt_test_fail "[$b] [$l] rc $FVDL_RC"; fi
fvdl_run 'resize 100 30' 'resize 100 30' 'key kbEnter' -- --checklist 'Pick' 0 0 0 a A on
kt_test_start "the same size twice: nothing else happens; the answer stays"
if [[ $FVDL_RC == 0 && $FVDL_RES == '"a"' ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC [$FVDL_RES]"; fi


kt_test_section "007: a resize lays the controls out again (H1)"
P5='line1\nline2\nline3\nline4\nline5'
fvdl_run 'resize 30 9' 'key kbDown' snap 'key kbEnter' -- --menu "$P5" 0 0 3 a A b B c C
fvdl_find 'b  B'; fb=$REPLY
fvdl_find 'line1'; l1=$REPLY
fvdl_box; b=$REPLY
kt_test_start "a 5-line prompt over LH 3, shrunk to 30 x 9: the prompt scrolls in one row, the list keeps 2 rows and its bar, Down Enter answers the row on screen"
r='' rt=''
if [[ -n $fb && -n $l1 ]]; then fvdl_row "${fb#* }"; r=$REPLY; fvdl_row "${l1#* }"; rt=$REPLY; fi
if [[ $b == '2 0 28 9' && $FVDL_RES == b && $r == *'b  B'*[▲▼■]' ║'* && $rt == *'line1'*'▲ ║'* ]]; then kt_test_pass "$b"
else kt_test_fail "box [$b] res [$FVDL_RES] text row [$rt] list row [$r]"; fi
fvdl_run 'resize 26 8' 'key kbDown' 'key kbDown' snap 'key kbEnter' -- --menu "$P5" 0 0 3 a A b B c C
fvdl_find 'c  C'; fc=$REPLY
fvdl_find 'line1'; l1=$REPLY
kt_test_start "at the minimum (26 x 8): one text row, one list row; the focused item (moved by Down Down) on screen"
if [[ -n $fc && -n $l1 && $FVDL_RES == c ]]; then kt_test_pass "c at $fc"; else kt_test_fail "c [$fc] line1 [$l1] res [$FVDL_RES]"; fi
fvdl_run snap -- --menu "$P5" 0 0 3 a A b B c C
s0=$FVDL_SNAP
fvdl_run 'resize 30 9' 'resize 80 24' snap 'key kbEnter' -- --menu "$P5" 0 0 3 a A b B c C
kt_test_start "grown back to 80 x 24: the layout as built (static prompt, three rows, no bar)"
if [[ -n $s0 && $FVDL_SNAP == "$s0" && $FVDL_RES == a ]]; then kt_test_pass ok; else kt_test_fail "res [$FVDL_RES] snapshots differ"; fi
fvdl_run 'char _' 'resize 30 9' 'key kbDown' 'key kbDown' 'char _' 'resize 80 24' 'key kbEnter' -- --checklist "$P5" 0 0 3 a A off b B off c C off
kt_test_start "a checklist's marks and focus survive a shrink and a grow"
if [[ $FVDL_RC == 0 && $FVDL_RES == '"a" "c"' ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC [$FVDL_RES]"; fi
fvdl_run 'char a' 'char b' 'resize 30 9' 'char c' 'key kbEnter' -- --inputbox "$P5" 0 0
kt_test_start "an inputbox's typed text and cursor survive a shrink that makes its prompt scroll (no select-all)"
if [[ $FVDL_RC == 0 && $FVDL_RES == abc ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC [$FVDL_RES]"; fi
QB='The quick brown fox jumps over the lazy dog again and again'
fvdl_run snap -- --msgbox "$QB" 0 0
m0=$FVDL_SNAP
fvdl_run 'resize 22 9' snap 'key kbEnter' -- --msgbox "$QB" 0 0
fvdl_find 'The quick brown'; q=$REPLY
fvdl_find '▲'; up=$REPLY
fvdl_box; b=$REPLY
kt_test_start "a msgbox shrunk below its text: the static text turns into the scrolling view (wrapped, its bar)"
if [[ $b == '0 1 22 8' && -n $q && -n $up && ${up#* } == "${q#* }" ]]; then kt_test_pass "$b"; else kt_test_fail "box [$b] text [$q] bar [$up]"; fi
declare -a mt=()
fvdl_mshot() { fvdl_snap; fvdl_row 2; mt+=("$REPLY"); }
fvdl_run 'resize 22 9' 'key kbDown' 'run fvdl_mshot' 'key kbEnter' -- --msgbox "$QB" 0 0
kt_test_start "the scrolling text takes the focus a build gives it: Down scrolls it; Enter still presses OK"
if [[ ${mt[0]-} == *'fox jumps over'* && $FVDL_RC == 0 && $FVDL_CMD == cmOK ]]; then kt_test_pass "[${mt[0]}]"; else kt_test_fail "[${mt[0]-}] rc $FVDL_RC $FVDL_CMD"; fi
fvdl_run 'resize 22 9' 'resize 80 24' snap 'key kbEnter' -- --msgbox "$QB" 0 0
kt_test_start "grown back: the static text as built (the same screen)"
if [[ -n $m0 && $FVDL_SNAP == "$m0" && $FVDL_RC == 0 ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC snapshots differ"; fi

kt_test_section "007: an explicit height gives its spare rows to the list (L7)"
fvdl_run snap 'key kbEnter' -- --menu 'Pick' 20 40 3 a A b B c C d D e E
fvdl_find 'Pick'; p=$REPLY
fvdl_find 'a  A'; fa=$REPLY
fvdl_find 'e  E'; fe=$REPLY
fvdl_find '▼'; dn=$REPLY
kt_test_start "menu 20 40 LH 3 with 5 items: the prompt keeps its row, the list takes the rest (all 5 items, no bar)"
if [[ -n $p && -n $fa && -n $fe && -z $dn && ${fa#* } == $(( ${p#* } + 2 )) && ${fe#* } == $(( ${fa#* } + 4 )) ]]; then kt_test_pass "Pick $p, a $fa, e $fe"
else kt_test_fail "Pick [$p] a [$fa] e [$fe] bar [$dn]"; fi
fvdl_run snap 'key kbEnter' -- --checklist 'Pick' -1 -1 0 a A on b B off
fvdl_find 'Pick'; p=$REPLY
fvdl_find '[X] a'; fa=$REPLY
kt_test_start "-1 -1: the prompt one row, the list right below it (one blank row)"
if [[ -n $p && -n $fa && ${fa#* } == $(( ${p#* } + 2 )) && $FVDL_RES == '"a"' ]]; then kt_test_pass ok; else kt_test_fail "Pick [$p] a [$fa] [$FVDL_RES]"; fi

kt_test_section "007: an empty button label is a blank button (L3)"
fvdl_run snap 'key kbEnter' -- --ok-button '' --msgbox hi 0 0
fvdl_find '▀▀▀▀▀▀▀▀▀'; sh=$REPLY
kt_test_start "msgbox --ok-button '': a blank button of FV's minimum width (its shadow), Enter = OK"
if [[ -n $sh && $FVDL_RC == 0 && $FVDL_CMD == cmOK ]]; then kt_test_pass "$sh"; else kt_test_fail "[$sh] rc $FVDL_RC $FVDL_CMD"; fi
fvdl_run 'key kbTab' 'key kbEnter' -- --yes-button '' --no-button '' --yesno hi 0 0
kt_test_start "yesno with both labels empty: two buttons, Tab Enter = No"
if [[ $FVDL_RC == 1 && $FVDL_CMD == cmNo ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC $FVDL_CMD"; fi
fvdl_run 'key kbEnter' -- --ok-button '' --menu M 0 0 0 a A b B
kt_test_start "menu --ok-button '': Enter presses the blank OK, the answer"
if [[ $FVDL_RC == 0 && $FVDL_RES == a ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC [$FVDL_RES]"; fi
fvdl_run 'key kbTab' 'key kbTab' 'key kbEnter' -- --cancel-button '' --inputbox t 0 0
kt_test_start "inputbox --cancel-button '': the blank Cancel is a button (Tab Tab Enter = 1)"
if [[ $FVDL_RC == 1 ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC"; fi

kt_test_section "007: the wrap (M3): the rows as before, linear"
# wfix TEXT W WANT — fv.dlg._wrap's rows ("[row]" each) equal the 4a-2
# function's (outputs kept from it), in fv.dlg's own locale scope
wfix() {
    local -a __fvl_wl=()
    local s='' r
    fv.video._g fv.dlg._wrap "$1" "$2"
    for r in "${__fvl_wl[@]}"; do s+="[$r]"; done
    kt_test_start "wrap at $2: ${1:0:30}"
    if [[ $s == "$3" ]]; then kt_test_pass "$s"; else kt_test_fail "got [$s] want [$3]"; fi
}
wfix 'a fairly long line of words that wraps in the box' 15 '[a fairly long][ line of words][ that wraps in][ the box]'
wfix '  leading and   multiple   blanks here  ' 10 '[  leading][ and][   multipl][e][   blanks][ here  ]'
wfix 'averyveryverylongwordthatmustbecut and more' 8 '[averyver][yverylon][gwordtha][tmustbec][ut and][ more]'
wfix $'line1\n\nline3 long long long long' 12 '[line1][][line3 long][ long long][ long]'
wfix '漢字漢字漢字漢字漢字 éé word ok' 7 '[漢字漢][字漢字][漢字漢][字 éé][ word][ ok]'
wfix 'Ünïcödé wörds änd ä löng wörd: Donaudampfschifffahrtsgesellschaft' 9 '[Ünïcödé][ wörds][ änd ä][ löng][ wörd:][ Donaudam][pfschifff][ahrtsgese][llschaft]'
wfix 'x y' 1 '[x][ ][y]'
wfix 'abc def      ' 5 '[abc][ def][     ][ ]'
wfix '漢字漢字漢字漢字漢字漢字' 5 '[漢字][漢字][漢字][漢字][漢字][漢字]'
wfix 'exactly ten chars twice tencharsxx' 10 '[exactly][ ten][ chars][ twice][ tencharsx][x]'
wfix '' 5 '[]'
# (a control character in a cut word comes back as '?', as the screen shows
# it; the 4a-2 function kept the byte)
wfix $'tab\there and  two' 6 '[tab?he][re][ and][  two]'
wlong() {   # TEXT W -> REPLY "ROWS FIRSTLEN LASTLEN"
    local -a __fvl_wl=()
    fv.video._g fv.dlg._wrap "$1" "$2"
    REPLY="${#__fvl_wl[@]} ${#__fvl_wl[0]} ${#__fvl_wl[-1]}"
}
printf -v X '%*s' 5000 ''
X=${X// /x}
wlong "$X" 37
kt_test_start "a 5000-character word at 37: 135 rows of 37 and the rest (5), read in pieces"
if [[ $REPLY == '136 37 5' ]]; then kt_test_pass "$REPLY"; else kt_test_fail "$REPLY"; fi
X=''
for (( i = 0; i < 1250; i++ )); do X+='漢字'; done
wlong "$X" 37
kt_test_start "a 2500-character CJK word at 37: rows of 18 (36 cells; a 19th would make 38), the rest 16"
if [[ $REPLY == '139 18 16' ]]; then kt_test_pass "$REPLY"; else kt_test_fail "$REPLY"; fi
X=''
for (( i = 0; i < 40000; i++ )); do X+='word '; done
t0=$EPOCHREALTIME
fvdl_run 'key kbPgDn' 'key kbEnter' -- --msgbox "$X" 0 0
t1=$(( (${EPOCHREALTIME/./} - ${t0/./}) / 1000 ))
kt_test_log "# time msgbox.200KB.oneline $t1 ms"
kt_test_start "a 200 KB one-line msgbox (40 000 words) headless: done within 60 s (4a-2: quadratic, minutes)"
if [[ $FVDL_RC == 0 ]] && (( t1 < 60000 )); then kt_test_pass "$t1 ms"; else kt_test_fail "rc $FVDL_RC, $t1 ms"; fi
unset X

kt_test_log "007_Sizes.sh completed"
