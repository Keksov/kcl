#!/usr/bin/env bash
# 002_Store.sh - FV HistList's lists (histlist.inc HistoryAdd / HistoryCount /
# HistoryStr / ClearHistory):
#   * newest first; a repeated string moves to the front (FV deletes the old
#     copy); '' is never added; the newest added again keeps the list and
#     the size (it only becomes the store's youngest record: 003);
#   * ids are independent (0 and 255, the ends of FV's Byte); "007" is 7;
#   * historyStr past the end: rc 1, RESULT ''; clearHistory empties every
#     list and the store's count;
#   * strings kept byte-exact: blanks, tabs, newlines, globs, backslashes,
#     `~`, Cyrillic, CJK, emoji; equal-looking strings that differ in case
#     are two strings (also under nocasematch);
#   * the refusals (rc 2, RESULT '', a debug line): ID 256, -1, x, '', a
#     wrong argument count, INDEX not digits; RESULT kept by the procedures.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvh_testlib.sh"
fvh_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: the lists"

fv.histlist.clearHistory
for s in alpha beta gamma; do fv.histlist.historyAdd 1 "$s"; done
fvh_list 1
kt_test_start "newest first"
if [[ $REPLY == $'gamma\x1fbeta\x1falpha\x1f' ]]; then kt_test_pass ok; else kt_test_fail "[$REPLY]"; fi

kt_test_start "a repeated string moves to the front, once (FV: the old copy deleted)"
fv.histlist.historyAdd 1 alpha; fvh_list 1; a=$REPLY
fv.histlist.historyAdd 1 beta; fvh_list 1; b=$REPLY
if [[ $a == $'alpha\x1fgamma\x1fbeta\x1f' && $b == $'beta\x1falpha\x1fgamma\x1f' ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi

kt_test_start "the newest added again: the list and the store's size unchanged"
u=$__FV_HL_USED
fv.histlist.historyAdd 1 beta; fvh_list 1
if [[ $REPLY == "$b" && $u == "$__FV_HL_USED" ]]; then kt_test_pass ok; else kt_test_fail "[$REPLY] $u/$__FV_HL_USED"; fi

kt_test_start "'' is never added (FV)"
fv.histlist.historyAdd 1 ''; fv.histlist.historyCount 1
if [[ $RESULT == 3 ]]; then kt_test_pass ok; else kt_test_fail "$RESULT"; fi

kt_test_start "ids are independent: 0 and 255, a string in two lists, '007' is 7"
fv.histlist.historyAdd 0 zero; fv.histlist.historyAdd 255 top; fv.histlist.historyAdd 255 alpha
fv.histlist.historyAdd 007 seven; fv.histlist.historyStr 7 0; s7=$RESULT
fvh_list 0; l0=$REPLY; fvh_list 255; l255=$REPLY; fvh_list 1; l1=$REPLY
if [[ $l0 == $'zero\x1f' && $l255 == $'alpha\x1ftop\x1f' && $l1 == "$b" && $s7 == seven ]]; then kt_test_pass ok; else kt_test_fail "[$l0] [$l255] [$l1] [$s7]"; fi

kt_test_start "historyStr past the end: rc 1, RESULT ''; an empty list: count 0"
RESULT=x; r1=0; fv.histlist.historyStr 1 3 || r1=$?; a=$RESULT
r2=0; fv.histlist.historyStr 9 0 || r2=$?
fv.histlist.historyCount 9
if [[ $r1 == 1 && -z $a && $r2 == 1 && $RESULT == 0 ]]; then kt_test_pass ok; else kt_test_fail "$r1 [$a] $r2 $RESULT"; fi

kt_test_start "strings kept byte-exact (blanks, tab, newline, globs, backslash, ~, Cyrillic, CJK, emoji)"
texts=('  two  blanks ' $'a\tb' $'line1\nline2' '*?[x]' 'back\slash\\' '~h~ot' 'жук' '中文字' '👍🏽 ok')
for t in "${texts[@]}"; do fv.histlist.historyAdd 20 "$t"; done
bad=''
for (( i = 0; i < ${#texts[@]}; i++ )); do
    fv.histlist.historyStr 20 "$(( ${#texts[@]} - 1 - i ))"
    [ "$RESULT" = "${texts[i]}" ] || bad+=" $i"
done
if [[ -z $bad ]]; then kt_test_pass ok; else kt_test_fail "differ:$bad"; fi

kt_test_start "case matters: 'Abc' and 'abc' are two strings, also under nocasematch"
fv.histlist.historyAdd 21 abc
shopt -s nocasematch
fv.histlist.historyAdd 21 Abc; fv.histlist.historyAdd 21 abc
shopt -u nocasematch
fvh_list 21
if [[ $REPLY == $'abc\x1fAbc\x1f' ]]; then kt_test_pass ok; else kt_test_fail "[$REPLY]"; fi

kt_test_start "clearHistory: every list empty, the store back to 1 byte used; adding works after it"
fv.histlist.clearHistory
c=''; for id in 0 1 7 20 21 255; do fv.histlist.historyCount $id; c+=$RESULT; done
u=$__FV_HL_USED
fv.histlist.historyAdd 1 again; fvh_list 1
if [[ $c == 000000 && $u == 1 && $REPLY == $'again\x1f' ]]; then kt_test_pass ok; else kt_test_fail "$c $u [$REPLY]"; fi

kt_test_start "the refusals: rc 2, RESULT '', a debug line; ID 256 / -1 / x / '' / ' 1', wrong counts, INDEX not digits"
log="$FVH_TMP/debug.txt"
r=''
for id in 256 -1 x '' ' 1' 1000; do
    RESULT=keep; s=0; VERBOSE_KKLASS=debug fv.histlist.historyAdd "$id" t 2>>"$log" || s=$?; r+="$s${RESULT:-_} "
done
s=0; fv.histlist.historyAdd 1 2>/dev/null || s=$?; r+="$s "
s=0; fv.histlist.historyCount 2>/dev/null || s=$?; r+="$s "
s=0; fv.histlist.historyCount 1 2 2>/dev/null || s=$?; r+="$s "
s=0; fv.histlist.historyStr 1 2>/dev/null || s=$?; r+="$s "
s=0; fv.histlist.historyStr 1 -1 2>/dev/null || s=$?; r+="$s "
s=0; fv.histlist.historyStr 1 x 2>/dev/null || s=$?; r+="$s "
s=0; fv.histlist.clearHistory x 2>/dev/null || s=$?; r+="$s"
fv.histlist.historyCount 1
n=0; while IFS= read -r l; do [[ $l == *'Error: fv.histlist.historyAdd'* ]] && n=$(( n + 1 )); done < "$log"
if [[ $r == '2_ 2_ 2_ 2_ 2_ 2_ 2 2 2 2 2 2 2' && $n == 6 && $RESULT == 1 ]]; then kt_test_pass ok; else kt_test_fail "[$r] debug lines $n count $RESULT"; fi

kt_test_start "the procedures keep RESULT (historyAdd, clearHistory)"
RESULT=mine; fv.histlist.historyAdd 1 x; a=$RESULT
fv.histlist.historyAdd 1 ''; b=$RESULT
fv.histlist.clearHistory; c=$RESULT
if [[ $a$b$c == mineminemine ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b] [$c]"; fi

kt_test_log "002_Store.sh completed"
