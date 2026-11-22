#!/usr/bin/env bash
# 004_Input.sh - inputbox / passwordbox through fv.dlg.run --fv-headless
# (80 x 24, the scripted terminal):
#   * the layout: the text, the input line on the row SizeY-5 (from cell 2 to
#     SizeX-2), OK / Cancel centred below; --nocancel (no Cancel button),
#     the labels;
#   * INIT: shown and selected, Enter answers it (golden in_init); the first
#     typed key replaces it (FV's rule; the real tools append: golden
#     in_init_type -> "initx", reached here with End first); Tab Enter = OK
#     (golden in_tab1), Tab Tab Enter = Cancel -> 1 and nothing (golden
#     in_tab2), Esc -> 255 and nothing (golden in_esc), the end of input ->
#     255; typing without INIT (golden in_abc), an empty answer (golden
#     in_empty), blanks kept (golden in_spaces), Cyrillic and wide text
#     (golden in_cyr), a bracketed paste, MaxLen 1024 clusters;
#   * the passwordbox: '*' per character (D38; golden pw_*: whiptail '*',
#     dialog nothing), --fv-echo none (blanks, no cursor), INIT (golden
#     pw_init), the answer is the typed text.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

# ans TITLE RC WANT SPEC... -- ARG... — one test: the status and RESULT
ans() {
    local title=$1 rc=$2 want=$3
    shift 3
    fvdl_run "$@"
    fvdl_live
    kt_test_start "$title"
    if [[ $FVDL_RC == "$rc" && $FVDL_RES == "$want" && -z $REPLY && -z $FV_APP ]]; then kt_test_pass "rc $FVDL_RC [$FVDL_RES]"
    else kt_test_fail "rc $FVDL_RC RESULT [$FVDL_RES] live [$REPLY], want rc $rc [$want]"; fi
}

kt_test_section "004: the input box"
fvdl_run snap 'key kbEnter' -- --title Login --inputbox 'Your name:' 0 0 'Ann Lee'
fvdl_box; b=$REPLY
fvdl_find 'Your name:'; t=$REPLY
fvdl_find 'Ann Lee'; i=$REPLY
fvdl_find ' OK '; o=$REPLY
fvdl_find ' Cancel '; c=$REPLY
kt_test_start "the layout: the text, the input line (INIT shown) two rows below it, OK / Cancel centred"
if [[ $b == '27 8 53 16' && $t == '29 9' && $i == '30 11' && ${o#* } == 13 && ${c#* } == 13 && ${o% *} -lt ${c% *} ]]; then kt_test_pass "box $b"
else kt_test_fail "box [$b] text [$t] init [$i] OK [$o] Cancel [$c]"; fi
il=''
ilprobe() { il=${FV_DESKTOP}__fvdlg__fvinput; local -n d=${il}_data; SEL="${d[SelStart]}-${d[SelEnd]}:${d[CurPos]}"; }
fvdl_run 'run ilprobe' 'key kbEnter' -- --inputbox 'N' 0 0 'init'
kt_test_start "INIT selected (all of it), the cursor at its start (FV SelectAll)"
if [[ $SEL == '0-4:0' ]]; then kt_test_pass "$SEL"; else kt_test_fail "$SEL"; fi

ans "Enter answers INIT (golden in_init)" 0 init 'key kbEnter' -- --inputbox 'Name:' 8 40 init
ans "the first key replaces INIT (FV; golden in_init_type: the tools append)" 0 x 'char x' 'key kbEnter' -- --inputbox 'Name:' 8 40 init
ans "End first, then the key: appended (the tools' result)" 0 initx 'key kbEnd' 'char x' 'key kbEnter' -- --inputbox 'Name:' 8 40 init
ans "Tab, Enter: OK (golden in_tab1)" 0 init 'key kbTab' 'key kbEnter' -- --inputbox 'Name:' 8 40 init
ans "Tab, Tab, Enter: Cancel -> 1, nothing (golden in_tab2)" 1 '' 'key kbTab' 'key kbTab' 'key kbEnter' -- --inputbox 'Name:' 8 40 init
ans "typing, then Esc -> 255, nothing (golden in_esc)" 255 '' 'char a' 'char b' 'key kbEsc' -- --inputbox 'Name:' 8 40 init
ans "the end of input -> 255, nothing" 255 '' 'char a' -- --inputbox 'Name:' 8 40 init
ans "typing without INIT (golden in_abc)" 0 abc 'char a' 'char b' 'char c' 'key kbEnter' -- --inputbox 'Name:' 8 40
ans "an empty answer (golden in_empty)" 0 '' 'key kbEnter' -- --inputbox 'Name:' 8 40
ans "blanks kept (golden in_spaces)" 0 '  a b  ' 'key kbEnter' -- --inputbox 'Name:' 8 40 '  a b  '
ans "Cyrillic and wide characters (golden in_cyr)" 0 'жк中' 'char ж' 'char к' 'char 中' 'key kbEnter' -- --inputbox 'Name:' 0 0
ans "Backspace edits" 0 'ab' 'key kbEnd' 'key kbBack' 'key kbEnter' -- --inputbox 'Name:' 0 0 abc
ans "a bracketed paste replaces the selection" 0 'pasted' 'cmd cmPasteText pasted' 'key kbEnter' -- --inputbox 'Name:' 0 0 old
long=''; for (( k = 0; k < 1100; k++ )); do long+=x; done
ans "MaxLen 1024 clusters (a 1100-character INIT is cut)" 0 "${long:0:1024}" 'key kbEnter' -- --inputbox 'Name:' 0 0 "$long"
ans "a click on Cancel -> 1" 1 '' 'down 42 13' 'up 42 13' -- --title Login --inputbox 'Your name:' 0 0 'Ann Lee'
ans "Alt+K (OK's hot letter) -> 0" 0 'v' 'key kbAltK k' -- --inputbox 'Name:' 0 0 v
fvdl_run snap 'key kbTab' 'key kbEnter' -- --nocancel --inputbox 'Name:' 0 0 val
fvdl_find 'Cancel'; nc=$REPLY
kt_test_start "--nocancel: no Cancel button; Tab, Enter is OK (golden in_nocancel)"
if [[ -z $nc && $FVDL_RC == 0 && $FVDL_RES == val ]]; then kt_test_pass ok; else kt_test_fail "Cancel at [$nc] rc $FVDL_RC [$FVDL_RES]"; fi
fvdl_run snap 'key kbEnter' -- --ok-button Save --cancel-label Back --inputbox 'Name:' 0 0
fvdl_find ' Save '; s=$REPLY; fvdl_find ' Back '; k=$REPLY
kt_test_start "the labels --ok-button / --cancel-label"
if [[ -n $s && -n $k ]]; then kt_test_pass ok; else kt_test_fail "[$s] [$k]"; fi

kt_test_section "004: the password box"
fvdl_run 'char s' 'char e' 'char c' snap 'key kbEnter' -- --passwordbox 'Password:' 0 0
fvdl_find '***'; p=$REPLY
fvdl_find 'sec'; q=$REPLY
kt_test_start "'*' per typed character (D38), the answer is the text"
if [[ -n $p && -z $q && $FVDL_RC == 0 && $FVDL_RES == sec ]]; then kt_test_pass "stars at $p"; else kt_test_fail "stars [$p] text [$q] rc $FVDL_RC [$FVDL_RES]"; fi
cur=''
curprobe() { local -n d=${FV_DESKTOP}__fvdlg__fvinput_data; cur=$(( d[State] & FV_SF_CURSORVIS )); }
fvdl_run 'char s' 'char e' 'char c' snap 'run curprobe' 'key kbEnter' -- --fv-echo none --passwordbox 'Password:' 0 0
fvdl_find '*'; p=$REPLY
fvdl_find 'sec'; q=$REPLY
kt_test_start "--fv-echo none: nothing shown, no cursor; the answer is the text"
if [[ -z $p && -z $q && $cur == 0 && $FVDL_RC == 0 && $FVDL_RES == sec ]]; then kt_test_pass ok; else kt_test_fail "stars [$p] text [$q] cursor [$cur] rc $FVDL_RC [$FVDL_RES]"; fi
fvdl_run 'char s' snap 'key kbEnter' -- --fv-echo star --passwordbox 'Password:' 0 0
fvdl_find '*'; p=$REPLY
kt_test_start "--fv-echo star is the default's '*'"
if [[ -n $p && $FVDL_RES == s ]]; then kt_test_pass ok; else kt_test_fail "[$p] [$FVDL_RES]"; fi
ans "INIT answered by Enter (golden pw_init)" 0 sec 'key kbEnter' -- --passwordbox 'Password:' 8 40 sec
ans "typing, then Esc -> 255, nothing (golden pw_esc)" 255 '' 'char p' 'char w' 'key kbEsc' -- --passwordbox 'Password:' 8 40
ans "--insecure is accepted and changes nothing" 0 pw 'char p' 'char w' 'key kbEnter' -- --insecure --passwordbox 'Password:' 8 40

kt_test_log "004_Input.sh completed"
