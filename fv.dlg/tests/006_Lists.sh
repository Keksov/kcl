#!/usr/bin/env bash
# 006_Lists.sh - --menu / --checklist / --radiolist through fv.dlg.run
# --fv-headless (80 x 24, the scripted terminal; design §5.1, D37; the golden
# table p4/golden (4a-1) and p4/golden2 (4a-2): whiptail 0.52.25 and dialog
# 1.3-20250116 on Debian 13):
#   * the layout: the text, a blank, the list (marks [X] / [ ], (*) / ( ),
#     the tags padded, two blanks, the items), a blank, OK / Cancel; the
#     bar only when the items do not fit; --notags / --noitem; --nocancel;
#   * the keys: Enter = OK with the focused / marked tags, Tab Enter = OK,
#     Tab Tab Enter = Cancel (whiptail), Esc 255, Down / PgDn (by LH) / End,
#     --default-item (menu: both tools; checklist: dialog), Space and Ins in
#     a checklist (Ins: FV's D29, both tools do nothing), Space in a menu
#     does nothing (both), radio exclusivity (Space on the marked one keeps
#     it; Down Space Space moves it: both), two `on` (the last: whiptail);
#   * the letter jumps (dialog's rule: every list, any printable character,
#     the next item after the focused one, wrapping, case-insensitive both
#     ways; tags only, the items with --notags; no match: nothing, never a
#     button's hot key) — each golden2 row named with both tools' answers;
#   * a double click: menu = OK with the clicked item, checklist = toggle,
#     radiolist = mark;
#   * the answer (D37): menu / radiolist the tag bare (also with
#     --separate-output / --single-quoted), checklist whiptail's quoted form
#     by default (nothing escaped), --separate-output one tag + newline
#     each, --single-quoted dialog's form (golden2's escaping rows),
#     --fv-output lines | quoted | single, nothing checked: '' with rc 0;
#     FV_DLG_TAGS; the command's face writes it to stderr, no newline;
#   * 10 000 items: built, End, Enter; the arrays empty after the call;
#   * nothing left: no view, the application gone, FV_APP ''.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

# lt TITLE RC RESULT SPEC... -- ARG... — one test: status, RESULT, nothing left
lt() {
    local title=$1 rc=$2 res=$3
    shift 3
    fvdl_run "$@"
    fvdl_live
    kt_test_start "$title"
    if [[ $FVDL_RC == "$rc" && $FVDL_RES == "$res" && -z $REPLY && -z $FV_APP ]]; then kt_test_pass "rc $FVDL_RC [$FVDL_RES]"
    else kt_test_fail "rc $FVDL_RC [$FVDL_RES] cmd $FVDL_CMD live [$REPLY] app [$FV_APP], want rc $rc [$res]"; fi
}
M=(a Apple b Banana 'my app' 'My App')
FRUIT=(apple Apple banana Banana cherry Cherry)

kt_test_section "006: the layout"
fvdl_run snap 'key kbEnter' -- --title Pick --checklist 'Choose some:' 0 0 0 a Apple on b Banana off 'my app' 'My App' on
fvdl_box; b=$REPLY
fvdl_row 8; r8=$REPLY
fvdl_row 10; r10=$REPLY
fvdl_row 11; r11=$REPLY
fvdl_row 12; r12=$REPLY
fvdl_find ' OK '; ok=$REPLY
fvdl_find 'Cancel'; ca=$REPLY
kt_test_start "auto size: text, blank, the rows (widest row + 6, no bar: the items fit), blank, buttons; centred"
if [[ $b == '27 7 53 17' && $r8 == *'║ Choose some:'* && $r10 == *'║  [X] a       Apple     ║'* && $r11 == *'║  [ ] b       Banana    ║'* \
      && $r12 == *'║  [X] my app  My App    ║'* && ${ok#* } == 14 && ${ca#* } == 14 ]]; then kt_test_pass "$b"
else kt_test_fail "box [$b] [$r8] [$r10] [$r11] [$r12] OK [$ok] Cancel [$ca]"; fi

fvdl_run snap 'key kbEnter' -- --radiolist 'Pick one' 0 0 2 a A on b B off c C off d D off
fvdl_box; b=$REPLY
fvdl_row 10; r10=$REPLY
fvdl_row 11; r11=$REPLY
fvdl_row 12; r12=$REPLY
kt_test_start "LH 2 of 4 items: two rows and the bar (one column more), (*) / ( )"
if [[ $b == '27 7 53 16' && $r10 == *'║  (*) a  A            ▲ ║'* && $r11 == *'║  ( ) b  B'*'║'* && $r12 == *'║                        ║'* ]]; then kt_test_pass "$b"
else kt_test_fail "box [$b] [$r10] [$r11] [$r12]"; fi

fvdl_run snap 'key kbEnter' -- --notags --menu 'Pick' 0 0 0 1 apple 2 banana
fvdl_find 'apple'; a1=$REPLY
fvdl_row "${a1#* }"; r1=$REPLY
fvdl_run snap 'key kbEnter' -- --noitem --nocancel --menu 'Pick' 0 0 0 1 apple 2 banana
fvdl_find 'apple'; a2=$REPLY
fvdl_find 'Cancel'; c2=$REPLY
fvdl_find ' 1 '; t2=$REPLY
kt_test_start "--notags shows the items only, --noitem the tags only; --nocancel: OK alone"
if [[ -n $a1 && $r1 != *' 1 '* && -z $a2 && -z $c2 && -n $t2 ]]; then kt_test_pass ok; else kt_test_fail "[$a1] [$r1] [$a2] [$c2] [$t2]"; fi

fvdl_run snap 'key kbEnter' -- --menu 'Pick' 10 40 3 a A b B c C d D e E f F g G
fvdl_box; b=$REPLY
fvdl_find '▼'; dn=$REPLY
kt_test_start "explicit H W 10 40 with LH 3 of 7: the box as asked, three rows, the bar's ▼ on the third"
if [[ $b == '20 7 60 17' && $dn == "57 12" ]]; then kt_test_pass "$b"; else kt_test_fail "box [$b] ▼ [$dn]"; fi

kt_test_section "006: the menu (golden: menu_*)"
lt "Enter: the first tag (menu_enter: a, both)" 0 a 'key kbEnter' -- --menu 'Pick' 15 40 4 "${M[@]}"
lt "Down Down Enter: 'my app' bare (menu_down2: both)" 0 'my app' 'key kbDown' 'key kbDown' 'key kbEnter' -- --menu 'Pick' 15 40 4 "${M[@]}"
lt "a tag with a quote, bare (menu_quote: x\"y, both)" 0 'x"y' 'key kbDown' 'key kbEnter' -- --menu 'Pick' 15 40 4 a Apple 'x"y' Quote
lt "a tag with a backslash and a blank, bare (golden2 menu_bs: both)" 0 'a\b c' 'key kbEnter' -- --menu 'Pick' 15 40 4 'a\b c' A
lt "--default-item b (menu_default: b, both)" 0 b 'key kbEnter' -- --default-item b --menu 'Pick' 15 40 4 a Apple b Banana c Cherry
lt "--default-item that no tag has: the first" 0 a 'key kbEnter' -- --default-item zz --menu 'Pick' 15 40 4 a Apple b Banana
lt "Tab Enter: OK (menu_tab1: whiptail a; dialog Cancel)" 0 a 'key kbTab' 'key kbEnter' -- --menu 'Pick' 15 40 4 a Apple b Banana
lt "Tab Tab Enter: Cancel, rc 1, nothing (menu_cancel: whiptail)" 1 '' 'key kbTab' 'key kbTab' 'key kbEnter' -- --menu 'Pick' 15 40 4 a Apple b Banana
lt "Esc: 255, nothing" 255 '' 'key kbEsc' -- --menu 'Pick' 15 40 4 a Apple b Banana
lt "the end of input: 255" 255 '' -- --menu 'Pick' 15 40 4 a Apple b Banana
lt "Space does nothing (golden2 menu_space: a, both)" 0 a 'char _' 'key kbEnter' -- --menu 'Pick' 15 40 4 a Apple b Banana
lt "Down Space Enter: b (golden2 menu_space_down: both)" 0 b 'key kbDown' 'char _' 'key kbEnter' -- --menu 'Pick' 15 40 4 a Apple b Banana c Cherry
lt "PgDn moves by LH (golden2 menu_pgdn: d, both)" 0 d 'key kbPgDn' 'key kbEnter' -- --menu 'Pick' 10 40 3 a A b B c C d D e E f F g G
lt "End: the last (golden2 menu_end2: g, both)" 0 g 'key kbEnd' 'key kbEnter' -- --menu 'Pick' 10 40 3 a A b B c C d D e E f F g G
lt "a tag after -- (menu_dashtags: --title, whiptail)" 0 --title 'key kbDown' 'key kbEnter' -- --menu 'Pick' 15 40 4 -- - Dash --title Title

kt_test_section "006: the letter jumps (golden2)"
lt "b -> banana (menu_letter: both)" 0 banana 'char b' 'key kbEnter' -- --menu 'Pick' 15 40 4 "${FRUIT[@]}"
lt "B on lower-case tags -> banana (menu_upper: both)" 0 banana 'char B' 'key kbEnter' -- --menu 'Pick' 15 40 4 "${FRUIT[@]}"
lt "b on capitalised tags -> Banana (menu_lower_on_upper: both)" 0 Banana 'char b' 'key kbEnter' -- --menu 'Pick' 15 40 4 Apple Apple Banana Banana Cherry Cherry
lt "b b -> the second b tag (menu_repeat: blue, both)" 0 blue 'char b' 'char b' 'key kbEnter' -- --menu 'Pick' 15 40 4 apple A banana B blue C cherry D
lt "the next after the focused one, wrapping (menu_wrap: dialog avocado; whiptail apple)" 0 avocado 'char a' 'key kbEnter' -- --default-item cherry --menu 'Pick' 15 40 4 apple A banana B cherry C avocado D
lt "wrapping past the end (menu_wrap2: banana, both)" 0 banana 'char b' 'key kbEnter' -- --default-item cherry --menu 'Pick' 15 40 4 apple A banana B cherry C
lt "no tag starts with it: nothing (menu_nomatch: apple, both)" 0 apple 'char z' 'key kbEnter' -- --menu 'Pick' 15 40 4 "${FRUIT[@]}"
lt "a letter of OK's hot key no tag has does not press OK (k), Down still works" 0 banana 'char k' 'char K' 'key kbDown' 'key kbEnter' -- --menu 'Pick' 15 40 4 "${FRUIT[@]}"
lt "a digit (menu_digit: dialog 2; whiptail no jump)" 0 2 'char 2' 'key kbEnter' -- --menu 'Pick' 15 40 4 1 One 2 Two 3 Three
lt "the items are not matched (menu_item_letter: 1, both)" 0 1 'char b' 'key kbEnter' -- --menu 'Pick' 15 40 4 1 apple 2 banana 3 cherry
lt "--notags: the items shown are matched (menu_notags_letter: 2, both)" 0 2 'char b' 'key kbEnter' -- --notags --menu 'Pick' 15 40 4 1 apple 2 banana 3 cherry
lt "Cyrillic (menu_cyr: dialog б; whiptail no jump)" 0 'б' 'char б' 'key kbEnter' -- --menu 'Pick' 15 40 4 а A б B в C
lt "in a checklist, then Space (check_letter: dialog banana; whiptail apple)" 0 '"banana"' 'char b' 'char _' 'key kbEnter' -- --checklist 'Chk' 15 50 5 apple A off banana B off cherry C off
lt "in a radiolist, then Space (radio_letter: dialog cherry; whiptail apple)" 0 cherry 'char c' 'char _' 'key kbEnter' -- --radiolist 'Rad' 15 50 5 apple A on banana B off cherry C off

kt_test_section "006: the checklist (golden: check_*)"
lt "the default answer: whiptail's quoted form, nothing escaped (check_enter: whiptail)" 0 "\"a\" \"my app\" \"it's\" \"x\"y\"" 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A on b B off 'my app' M on "it's" Q on 'x"y' X on
lt "--separate-output: a tag and a newline each (check_sep: both)" 0 $'a\nmy app\nit\'s\nx"y\n' 'key kbEnter' -- --separate-output --checklist 'Chk' 15 50 5 a A on b B off 'my app' M on "it's" Q on 'x"y' X on
lt "--single-quoted: dialog's form (check_single: dialog)" 0 "a 'my app' 'it\\'s' x\"y" 'key kbEnter' -- --single-quoted --checklist 'Chk' 15 50 5 a A on b B off 'my app' M on "it's" Q on 'x"y' X on
lt "backslashes: kept in the default form (golden2 check_bs: whiptail)" 0 '"a\b" "x y\z" "plain"' 'key kbEnter' -- --checklist 'Chk' 15 50 5 'a\b' A on 'x y\z' B on plain P on
lt "backslashes doubled with --single-quoted (golden2 check_bs_single: dialog)" 0 "'a\\\\b' 'x y\\\\z' plain" 'key kbEnter' -- --single-quoted --checklist 'Chk' 15 50 5 'a\b' A on 'x y\z' B on plain P on
lt "an empty tag: \"\" / '' (golden2 check_emptytag: whiptail; _single: dialog)" 0 '"" "a"' 'key kbEnter' -- --checklist 'Chk' 15 50 5 '' E on a A on
lt "an empty tag with --single-quoted" 0 "'' a" 'key kbEnter' -- --single-quoted --checklist 'Chk' 15 50 5 '' E on a A on
lt "shell characters and a tab quoted, not escaped, with --single-quoted (golden2 check_special_single: dialog)" 0 $'\'a*b\' \'c$d\' \'e;f\' \'g(h\' \'t\tx\' \'u~v\'' 'key kbEnter' -- --single-quoted --checklist 'Chk' 15 50 5 'a*b' A on 'c$d' C on 'e;f' E on 'g(h' G on $'t\tx' T on 'u~v' U on
lt "the default form leaves them alone (golden2 check_special: whiptail)" 0 $'"a*b" "c$d" "t\tx"' 'key kbEnter' -- --checklist 'Chk' 15 50 5 'a*b' A on 'c$d' C on $'t\tx' T on
lt "--single-quoted: ' escaped, \" bare, a blank quoted (golden2 check_quote_single2: dialog)" 0 "'it\\'s' x\"y 'a b'" 'key kbEnter' -- --single-quoted --checklist 'Chk' 15 50 5 "it's" Q on 'x"y' X on 'a b' S on
lt "--fv-output lines wins over --single-quoted" 0 $'a b\nc\n' 'key kbEnter' -- --single-quoted --fv-output lines --checklist 'Chk' 15 50 5 'a b' A on c C on
lt "--fv-output single" 0 "'a b' c" 'key kbEnter' -- --fv-output single --checklist 'Chk' 15 50 5 'a b' A on c C on
lt "--fv-output quoted wins over --separate-output" 0 '"a b" "c"' 'key kbEnter' -- --separate-output --fv-output quoted --checklist 'Chk' 15 50 5 'a b' A on c C on
lt "Space Down Space Enter (check_space: whiptail \"a\" \"b\")" 0 '"a" "b"' 'char _' 'key kbDown' 'char _' 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A off b B off c C off
lt "nothing checked: '' with rc 0 (check_none: both)" 0 '' 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A off b B off
lt "Space Space: toggled twice (golden2 check_twice: both)" 0 '' 'char _' 'char _' 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A off b B off
lt "OFF / Off are off (golden2 check_off_upper: both)" 0 '"c"' 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A OFF b B Off c C on
lt "Ins toggles and moves down (FV D29; golden2 check_ins: both tools do nothing)" 0 '"a" "b"' 'key kbIns' 'key kbIns' 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A off b B off c C off
lt "--default-item b, Space (golden2 check_default: dialog b; whiptail ignores it)" 0 '"b"' 'char _' 'key kbEnter' -- --default-item b --checklist 'Chk' 15 50 5 a A off b B off c C off
lt "duplicate tags: both written (golden2 check_dupe: both)" 0 '"a" "a"' 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A on a B on
lt "Cancel: rc 1, nothing (check_cancel: whiptail)" 1 '' 'key kbTab' 'key kbTab' 'key kbEnter' -- --checklist 'Chk' 15 50 5 a A on b B off
fvdl_run 'key kbEnter' -- --checklist 'Chk' 0 0 0 'my app' A on b B off c C on
kt_test_start "FV_DLG_TAGS: the checked tags as an array"
if (( ${#FV_DLG_TAGS[@]} == 2 )) && [[ ${FV_DLG_TAGS[0]} == 'my app' && ${FV_DLG_TAGS[1]} == c ]]; then kt_test_pass ok; else kt_test_fail "[${FV_DLG_TAGS[*]}]"; fi
fvdl_run 'key kbEsc' -- --checklist 'Chk' 0 0 0 a A on
kt_test_start "FV_DLG_TAGS empty after Esc / Cancel; after a box"
t1=${#FV_DLG_TAGS[@]}
fvdl_run 'key kbEnter' -- --msgbox 'x' 0 0
if (( t1 == 0 && ${#FV_DLG_TAGS[@]} == 0 )); then kt_test_pass ok; else kt_test_fail "$t1 ${#FV_DLG_TAGS[@]}"; fi

kt_test_section "006: the radiolist (golden: radio_*)"
lt "Enter: the marked tag bare (radio_enter: both)" 0 'my app' 'key kbEnter' -- --radiolist 'Rad' 15 50 5 a A off 'my app' M on c C off
lt "Down Down Space Enter: c (radio_space: both)" 0 c 'key kbDown' 'key kbDown' 'char _' 'key kbEnter' -- --radiolist 'Rad' 15 50 5 a A on b B off c C off
lt "Space on the marked one keeps it (golden2 radio_space_marked: both)" 0 a 'char _' 'key kbEnter' -- --radiolist 'Rad' 15 50 5 a A on b B off
lt "Down Space Space: the new one stays (golden2 radio_space_twice: both)" 0 b 'key kbDown' 'char _' 'char _' 'key kbEnter' -- --radiolist 'Rad' 15 50 5 a A on b B off
lt "two on: the last (radio_twoon: whiptail b; dialog a)" 0 b 'key kbEnter' -- --radiolist 'Rad' 15 50 5 a A on b B on
lt "none on: '' with rc 0 (radio_none: both)" 0 '' 'key kbEnter' -- --radiolist 'Rad' 15 50 5 a A off b B off
lt "--separate-output: bare, no newline (radio_sep: whiptail)" 0 'my app' 'key kbEnter' -- --separate-output --radiolist 'Rad' 15 50 5 a A off 'my app' M on
lt "--single-quoted: bare (radio_single: dialog)" 0 'my app' 'key kbEnter' -- --single-quoted --radiolist 'Rad' 15 50 5 a A off 'my app' M on
lt "Ins marks and moves down; one mark" 0 b 'key kbIns' 'key kbIns' 'key kbEnter' -- --radiolist 'Rad' 15 50 5 a A off b B off c C off
fvdl_run 'char _' 'key kbDown' 'char _' 'snap' 'key kbEnter' -- --radiolist 'Rad' 0 0 0 a A off b B off c C off
fvdl_find '(*)'; m1=$REPLY
fvdl_find '(*) b'; m2=$REPLY
kt_test_start "one mark on the screen after it moved (the old row repainted)"
if [[ -n $m2 && $m1 == "$m2" && $FVDL_RES == b ]]; then kt_test_pass "$m2"; else kt_test_fail "[$m1] [$m2] [$FVDL_RES]"; fi

kt_test_section "006: the mouse"
# (the rows of '--menu Pick 0 0 0 a A b B c C': the list from row 10; the
# items' text from column 37)
fvdl_run snap -- --menu 'Pick' 0 0 0 a A b B c C
fvdl_find ' b  B'; at=$REPLY
lt "a double click on a menu item: OK with it" 0 b "dbl $(( ${at% *} + 1 )) ${at#* }" -- --menu 'Pick' 0 0 0 a A b B c C
fvdl_run snap -- --checklist 'Chk' 0 0 0 a A off b B off c C off
fvdl_find '[ ] b'; at=$REPLY
lt "a double click in a checklist toggles; Enter" 0 '"b"' "dbl $(( ${at% *} + 1 )) ${at#* }" "up $(( ${at% *} + 1 )) ${at#* }" 'key kbEnter' -- --checklist 'Chk' 0 0 0 a A off b B off c C off
fvdl_run snap -- --radiolist 'Rad' 0 0 0 a A on b B off c C off
fvdl_find '( ) c'; at=$REPLY
lt "a double click in a radiolist marks; Enter" 0 c "dbl $(( ${at% *} + 1 )) ${at#* }" "up $(( ${at% *} + 1 )) ${at#* }" 'key kbEnter' -- --radiolist 'Rad' 0 0 0 a A on b B off c C off
lt "a single click focuses (menu): Enter answers it" 0 c "down $(( ${at% *} + 1 )) ${at#* }" "up $(( ${at% *} + 1 )) ${at#* }" 'key kbEnter' -- --menu 'Pick' 0 0 0 a A b B c C

kt_test_section "006: the command's face and 10 000 items"
fvdl_events 'key kbEnter'
fv.dlg.main --fv-headless --checklist 'Chk' 0 0 0 'a b' A on c C on 2>"$FVW_TMP/m.err"; r=$?
fva_noevents; __FV_VW_EOF=0
e=$(<"$FVW_TMP/m.err"); n=$(( $(wc -c < "$FVW_TMP/m.err") ))
kt_test_start "fv.dlg.main: the checklist's answer on stderr, no newline"
if (( r == 0 && n == 9 )) && [[ $e == '"a b" "c"' ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$e] $n bytes"; fi
fvdl_events 'key kbDown' 'key kbEnter'
fv.dlg.main --fv-headless --stdout --menu 'Pick' 0 0 0 a A b B > "$FVW_TMP/m.out" 2>"$FVW_TMP/m.err"; r=$?
fva_noevents; __FV_VW_EOF=0
kt_test_start "fv.dlg.main --stdout: the menu's tag on stdout, stderr empty"
if (( r == 0 )) && [[ $(<"$FVW_TMP/m.out") == b && ! -s $FVW_TMP/m.err ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$(<"$FVW_TMP/m.out")] [$(<"$FVW_TMP/m.err")]"; fi

BIG=()
for (( i = 0; i < 10000; i++ )); do BIG+=("t$i" "item number $i" off); done
lt "10 000 items: End Space Enter -> the last tag" 0 '"t9999"' 'key kbEnd' 'char _' 'key kbEnter' -- --checklist 'Big' 0 0 0 "${BIG[@]}"
lt "10 000 items: a letter jump wraps through them (t -> t1)" 0 '"t1"' 'char t' 'char _' 'key kbEnter' -- --checklist 'Big' 0 0 0 "${BIG[@]}"
# (4b fix L9: the UI path left the list's arrays filled until the next call)
sz() { REPLY="${#__DLFV_TAGS[@]} ${#__DLFV_ROWS[@]} ${#__DLFV_MARKS[@]} ${#__DLFV_FIRST[@]} ${#__DLFV_NEXT[@]} ${#__FV_DL_JUMP[@]} ${#__DLFV_TEXT[@]}"; }
sz; a=$REPLY
fvdl_run 'char _' 'key kbEnter' -- --checklist 'Big' 0 0 0 "${BIG[@]}"
sz; b=$REPLY r=$FVDL_RC
kt_test_start "after a 10 000-item call the list's arrays are empty again (tags, rows, marks, jumps, the text's lines; the answer kept in RESULT)"
if [[ $a == '0 0 0 0 0 0 0' && $b == '0 0 0 0 0 0 0' && $r == 0 && $FVDL_RES == '"t0"' ]]; then kt_test_pass "[$a] -> [$b]"; else kt_test_fail "before [$a] after [$b] rc $r [$FVDL_RES]"; fi
unset BIG

kt_test_log "006_Lists.sh completed"
