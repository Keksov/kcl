#!/usr/bin/env bash
# 015_Textbox.sh - --textbox FILE H W (stage 4d, design §5.1, P4-9): the
# file in the scrolling text view (TDlgText) and OK.
#   * the content: tabs expanded to multiples of 8 cells, every CR dropped
#     (CRLF files), other control characters shown as '?', `\n` and \Z in
#     the file NOT applied (literal; also with --colors), one final newline
#     dropped, an empty file (one empty row); the line split (fv.dlg._file:
#     empty lines kept at the start, inside, in runs and at the end, CRLF
#     and a lone CR, the widest line's cells); a pipe as FILE;
#   * the keys: Down / Up / PgDn / PgUp / End / Home scroll (the top row
#     followed in the snap), Up at the top stays, End shows the last row at
#     the bottom; Enter (OK) -> 0 cmOK, Esc -> 255 cmCancel, RESULT '' and
#     nothing printed either way;
#   * long lines NOT wrapped: Left / Right move the column offset (whiptail
#     / dialog scroll a text box sideways), Left at 0 stays, Right stops
#     when the widest line's end is in view; the formatter on wide
#     characters (an offset inside one: a blank);
#   * the cap (__FV_DL_TXCAP, 1 MiB; lowered here): a file of the cap's
#     size shown, one byte more -> 255 + one line, before any screen change;
#     a missing file, a directory -> 255 + one line;
#   * --no-tty=default: 0 (a missing file still 255); the command bin/fvdlg
#     --fv-headless: rc 0, nothing on stdout / stderr.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"
TMP=$FVW_TMP
ROOT="$(cd "$FVDL_TESTS_DIR/../../.." && pwd)"
CMD=$ROOT/bin/fvdlg

kt_test_section "015: the content"
printf 'a\tb\tc\nline2\r\nx\001y\033z\nliteral \\n and \\Zb stay\n\ttab\nab\tc\n' > "$TMP/c.txt"
fvdl_run snap 'key kbEnter' -- --colors --textbox "$TMP/c.txt" 0 0
fvdl_box; b=$REPLY
kt_test_start "tabs to the next multiple of 8, CR dropped, controls as '?', \\n and \\Z literal (even with --colors), the final newline dropped"
ok=1 miss=''
for s in '║ a       b       c ' '║ line2 ' '║ x?y?z ' '║ literal \n and \Zb stay ' '║         tab ' '║ ab      c '; do
    fvdl_find "$s"; if [[ -z $REPLY ]]; then ok=0 miss+="[$s] "; fi
done
fvdl_find ' OK '; okb=$REPLY
if (( ok )) && [[ -n $okb && $FVDL_RC == 0 && $FVDL_CMD == cmOK && -z $FVDL_RES ]]; then kt_test_pass "box $b"
else kt_test_fail "missing $miss OK [$okb] rc $FVDL_RC $FVDL_CMD; snap [${FVDL_SNAP:0:1500}]"; fi

kt_test_start "the auto size: the widest line fits the view (no wrap), the rows + 5 (the blank row above OK)"
# (widest 'literal \n and \Zb stay' = 24 cells: the box 29 wide; 6 rows + 5)
if [[ $b == '25 6 54 17' ]]; then kt_test_pass "$b"; else kt_test_fail "box [$b]"; fi

: > "$TMP/e.txt"
fvdl_run snap 'key kbEnter' -- --textbox "$TMP/e.txt" 0 0
kt_test_start "an empty file: shown (one empty row), OK -> 0"
if [[ $FVDL_RC == 0 && $FVDL_SNAP == *' OK '* ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC"; fi

# the line split, straight (fv.dlg._file's lines and widest line)
printf '\n\nA\r\n\r\n\r\nB\rC\tx\n\n\nZ\n' > "$TMP/s.txt"
__fvl_err=''
fv.dlg._file "$TMP/s.txt"; r=$?
s=$(printf '%s|' "${__DLFV_RAW[@]}") w=$__FV_DL_TXW
printf 'q\n\n' > "$TMP/s3.txt"
fv.dlg._file "$TMP/s3.txt"
s3=$(printf '%s|' "${__DLFV_RAW[@]}")
kt_test_start "the split: empty lines at the start, in runs (CRLF ones and plain ones), at the end kept; CRLF and a lone CR dropped; the tab expanded; the widest line 9 cells"
if [[ $r == 0 && $s == '||A|||BC      x|||Z|' && $w == 9 && $s3 == 'q||' ]]; then kt_test_pass "$s $s3"; else kt_test_fail "rc $r [$s] widest $w [$s3]"; fi
printf 'x\036y\037z\n' > "$TMP/s2.txt"
fv.dlg._file "$TMP/s2.txt"
s=$(printf '%s|' "${__DLFV_RAW[@]}")
__DLFV_RAW=()
kt_test_start "the split's own markers in a file (0x1e, 0x1f): shown as '?', the line not split"
if [[ $s == 'x?y?z|' ]]; then kt_test_pass "$s"; else kt_test_fail "[$s]"; fi

fvdl_run snap 'key kbEnter' -- --textbox <(printf 'from a pipe\n\nline 3\n') 0 0
fvdl_find '║ from a pipe '; r1=$REPLY
fvdl_find '║ line 3 '; r2=$REPLY
kt_test_start "a pipe as FILE (a process substitution): read once, shown, OK -> 0"
if [[ -n $r1 && -n $r2 && $FVDL_RC == 0 ]]; then kt_test_pass "$r1 / $r2"; else kt_test_fail "[$r1] [$r2] rc $FVDL_RC"; fi

kt_test_section "015: the keys"
: > "$TMP/l.txt"
for (( i = 1; i <= 100; i++ )); do printf 'line %d\n' "$i" >> "$TMP/l.txt"; done
T=()
top() { local r; fvdl_snap; fvdl_row 7; r=${REPLY#*║ }; T+=("${r%%  *}"); }
fvdl_run 'run top' 'key kbDown' 'run top' 'key kbPgDn' 'run top' 'key kbEnd' 'run top' 'key kbPgUp' 'run top' \
    'key kbHome' 'run top' 'key kbUp' 'run top' 'key kbEnter' -- --textbox "$TMP/l.txt" 12 40
kt_test_start "Down / PgDn (7 rows) / End (the last row at the bottom) / PgUp / Home / Up at the top: the top row follows; Enter 0"
want='line 1|line 2|line 9|line 94|line 87|line 1|line 1'
got=$(IFS='|'; printf '%s' "${T[*]}")
if [[ $got == "$want" && $FVDL_RC == 0 && $FVDL_CMD == cmOK ]]; then kt_test_pass "$got"
else kt_test_fail "got [$got] want [$want] rc $FVDL_RC"; fi

fvdl_run 'key kbDown' 'key kbEsc' -- --textbox "$TMP/l.txt" 12 40
kt_test_start "Esc -> 255 cmCancel, RESULT ''"
if [[ $FVDL_RC == 255 && $FVDL_CMD == cmCancel && -z $FVDL_RES ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC $FVDL_CMD [$FVDL_RES]"; fi

fvdl_run 'key kbEnd' 'key kbEnter' -- --textbox "$TMP/l.txt" 12 40
kt_test_start "Enter after scrolling: OK still answers (the text view never eats Enter)"
if [[ $FVDL_RC == 0 && $FVDL_CMD == cmOK ]]; then kt_test_pass ok; else kt_test_fail "rc $FVDL_RC $FVDL_CMD"; fi

: > "$TMP/h.txt"
for (( i = 0; i < 10; i++ )); do printf '0123456789' >> "$TMP/h.txt"; done
printf '\nshort\n' >> "$TMP/h.txt"
H=()
hrow() { local r; fvdl_snap; fvdl_row 8; r=${REPLY#*║ }; H+=("${r:0:25}"); }
rights=(); for (( i = 0; i < 80; i++ )); do rights+=('key kbRight'); done
fvdl_run 'run hrow' 'key kbLeft' 'run hrow' 'key kbRight' 'key kbRight' 'key kbRight' 'run hrow' "${rights[@]}" 'run hrow' \
    'key kbLeft' 'run hrow' 'key kbEnter' -- --textbox "$TMP/h.txt" 10 30
got=$(IFS='|'; printf '%s' "${H[*]}")
want='0123456789012345678901234|0123456789012345678901234|3456789012345678901234567|5678901234567890123456789|4567890123456789012345678'
kt_test_start "a 100-character line in a 10 x 30 box (25 cells): not wrapped; Left at 0 stays, Right x3 -> from column 3, Right x80 stops at 75 (the end in view), Left -> 74; Enter 0"
if [[ $got == "$want" && $FVDL_RC == 0 && $FVDL_CMD == cmOK ]]; then kt_test_pass ok; else kt_test_fail "got [$got] want [$want] rc $FVDL_RC"; fi

__DLFV_RAW=('аб漢cd' 'plain text') __FV_DL_TXX=2
fv.dlg._txFmt 0 30; f1=$RESULT
__FV_DL_TXX=3
fv.dlg._txFmt 0 30; f2=$RESULT
fv.dlg._txFmt 1 30; f3=$RESULT
__FV_DL_TXX=0
fv.dlg._txFmt 0 30; f4=$RESULT
__DLFV_RAW=()
kt_test_start "the formatter on wide characters: offset 2 -> 漢cd, offset 3 (inside 漢) -> a blank + cd; ASCII by characters; offset 0 the line"
if [[ $f1 == '漢cd' && $f2 == ' cd' && $f3 == 'in text' && $f4 == 'аб漢cd' ]]; then kt_test_pass ok; else kt_test_fail "[$f1] [$f2] [$f3] [$f4]"; fi

kt_test_section "015: refusals"
cap0=$__FV_DL_TXCAP
__FV_DL_TXCAP=100
printf '%099d\n' 7 > "$TMP/cap.txt"
fvdl_run 'key kbEnter' -- --textbox "$TMP/cap.txt" 0 0 2>"$TMP/r.err"
r1=$FVDL_RC e1=$(<"$TMP/r.err")
printf '%0100d\n' 7 > "$TMP/cap1.txt"
: > "$TMP/r.out"
fv.dlg.run --fv-headless --fv-out "$TMP/r.out" --textbox "$TMP/cap1.txt" 0 0 2>"$TMP/r.err"; r2=$?
mapfile -t e2 < "$TMP/r.err"
__FV_DL_TXCAP=$cap0
fvdl_live
kt_test_start "the cap (lowered to 100 bytes): 100 bytes shown, 101 -> 255 + one line, before any screen change"
if [[ $r1 == 0 && -z $e1 && $r2 == 255 && ${#e2[@]} == 1 && ${e2[0]} == "fv.dlg.run: the file '$TMP/cap1.txt' is larger than 100 bytes (the textbox's cap)" && ! -s $TMP/r.out && -z $REPLY ]]; then kt_test_pass ok
else kt_test_fail "r1 $r1 [$e1] r2 $r2 [${e2[*]}] frame bytes $(wc -c < "$TMP/r.out")"; fi

kt_test_start "the cap's default: 1 MiB"
if [[ $cap0 == 1048576 ]]; then kt_test_pass ok; else kt_test_fail "[$cap0]"; fi

fv.dlg.run --fv-headless --textbox "$TMP/none.txt" 0 0 2>"$TMP/r.err"; r1=$?
mapfile -t e1 < "$TMP/r.err"
fv.dlg.run --fv-headless --textbox "$TMP" 0 0 2>"$TMP/r.err"; r2=$?
mapfile -t e2 < "$TMP/r.err"
kt_test_start "a missing file, a directory: 255, one line each"
if [[ $r1 == 255 && ${#e1[@]} == 1 && ${e1[0]} == "fv.dlg.run: cannot read the file '$TMP/none.txt'" && $r2 == 255 && ${e2[0]-} == "fv.dlg.run: cannot read the file '$TMP'" && ${#e2[@]} == 1 ]]; then kt_test_pass ok
else kt_test_fail "r1 $r1 [${e1[*]}] r2 $r2 [${e2[*]}]"; fi

kt_test_section "015: faces"
FV_TTY=$TMP/none/tty fv.dlg.run --no-tty=default --textbox "$TMP/c.txt" 0 0; r1=$?
FV_TTY=$TMP/none/tty fv.dlg.run --no-tty=default --textbox "$TMP/none.txt" 0 0 2>/dev/null; r2=$?
kt_test_start "--no-tty=default: 0 (no UI); a missing file still 255"
if [[ $r1 == 0 && $r2 == 255 ]]; then kt_test_pass ok; else kt_test_fail "r1 $r1 r2 $r2"; fi

printf '\r' > "$TMP/enter.keys"
"$BASH" "$CMD" --fv-headless --fv-keys "$TMP/enter.keys" --fv-out "$TMP/c.out" --textbox "$TMP/c.txt" 0 0 >"$TMP/c.o" 2>"$TMP/c.e"; r=$?
kt_test_start "the command: fvdlg --fv-headless --textbox FILE, Enter: rc 0, nothing on stdout / stderr"
if [[ $r == 0 && ! -s $TMP/c.o && ! -s $TMP/c.e && -s $TMP/c.out ]]; then kt_test_pass ok
else kt_test_fail "rc $r out [$(<"$TMP/c.o")] err [$(<"$TMP/c.e")]"; fi

kt_test_log "015_Textbox.sh completed"
