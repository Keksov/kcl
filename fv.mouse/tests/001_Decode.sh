#!/usr/bin/env bash
# 001_Decode.sh - mouse reports -> FV_MOUSE_WHAT / BUTTON / X / Y / MODS:
# SGR 1006 (press, release, drag, motion without a button, wheel up / down /
# left / right, extra buttons, Shift / Alt / Ctrl, coordinates past 223) and
# X10 (the same events in one byte each, the 223 clamp), then the reports
# fv.keyboard hands over as the FV_KEY_SEQ of a kbMouse (the test loads
# fv.keyboard; the unit itself does not).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../ktests/ktest.sh"
source "$SCRIPT_DIR/../fv.mouse.sh"
kt_test_init "$(basename "$0" .sh)" "$SCRIPT_DIR" "$@"

kt_test_section "001: decoding SGR and X10 reports"

# chk RAW "WHAT BUTTON X Y MODS" [NOTE]
chk() {
    local v
    printf -v v '%q' "$1"
    kt_test_start "$v -> $2${3:+ ($3)}"
    fv.mouse.decode "$1"; local rc=$?
    local got="$FV_MOUSE_WHAT $FV_MOUSE_BUTTON $FV_MOUSE_X $FV_MOUSE_Y $FV_MOUSE_MODS"
    if [[ $rc == 0 && $got == "$2" && $RESULT == "$FV_MOUSE_WHAT" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc got '$got' RESULT=$RESULT"; fi
}

# --- SGR 1006: ESC [ < b ; x ; y M (press/motion) or m (release), 1-based -------
chk $'\e[<0;10;5M'   'down 1 9 4 0'   'left press'
chk $'\e[<0;10;5m'   'up 1 9 4 0'     'left release'
chk $'\e[<1;1;1M'    'down 2 0 0 0'   'middle press, top-left cell'
chk $'\e[<1;1;1m'    'up 2 0 0 0'     'middle release'
chk $'\e[<2;80;24M'  'down 3 79 23 0' 'right press, bottom-right of 80x24'
chk $'\e[<2;80;24m'  'up 3 79 23 0'   'right release'
chk $'\e[<32;11;5M'  'move 1 10 4 0'  'drag with left held (1002)'
chk $'\e[<33;11;5M'  'move 2 10 4 0'  'drag with middle held'
chk $'\e[<34;11;5M'  'move 3 10 4 0'  'drag with right held'
chk $'\e[<35;11;5M'  'move 0 10 4 0'  'motion, no button (1003)'
chk $'\e[<64;3;3M'   'wheel 4 2 2 0'  'wheel up'
chk $'\e[<65;3;3M'   'wheel 5 2 2 0'  'wheel down'
chk $'\e[<66;3;3M'   'wheel 6 2 2 0'  'wheel left'
chk $'\e[<67;3;3M'   'wheel 7 2 2 0'  'wheel right'
chk $'\e[<64;3;3m'   'up 4 2 2 0'     'a wheel "release" some terminals send'
chk $'\e[<4;1;1M'    'down 1 0 0 1'   'Shift'
chk $'\e[<8;1;1M'    'down 1 0 0 2'   'Alt (Meta)'
chk $'\e[<16;1;1M'   'down 1 0 0 4'   'Ctrl'
chk $'\e[<28;1;1M'   'down 1 0 0 7'   'Ctrl+Alt+Shift'
chk $'\e[<18;2;2m'   'up 3 1 1 4'     'Ctrl + right release'
chk $'\e[<80;3;3M'   'wheel 4 2 2 4'  'Ctrl + wheel up'
chk $'\e[<49;3;3M'   'move 2 2 2 4'   'Ctrl + drag with middle'
chk $'\e[<128;5;5M'  'down 8 4 4 0'   'extra button 8 (back)'
chk $'\e[<129;5;5m'  'up 9 4 4 0'     'extra button 9 release'
chk $'\e[<160;5;5M'  'move 8 4 4 0'   'drag with button 8'
chk $'\e[<0;300;100M' 'down 1 299 99 0' 'SGR goes past column 223'
chk $'\e[<0;99999;99999M' 'down 1 99998 99998 0' 'the largest coordinates read'
chk $'\e[<00;010;05M' 'down 1 9 4 0'  'leading zeros (not octal)'
chk $'\e[<255;1;1M'  'move 11 0 0 7'  'the largest button byte: extra button 11, motion, all modifiers'

# --- X10: ESC [ M Cb Cx Cy, each value + 32, coordinates 1-based ----------------
chk $'\e[M #!'       'down 1 2 0 0'   'left press at column 3, row 1'
chk $'\e[M!!!'       'down 2 0 0 0'   'middle press'
chk $'\e[M"!!'       'down 3 0 0 0'   'right press'
chk $'\e[M#!!'       'up 0 0 0 0'     'X10 release: the button is not named'
chk $'\e[M@!!'       'move 1 0 0 0'   'drag with left held'
chk $'\e[MC!!'       'move 0 0 0 0'   'motion, no button'
chk $'\e[M`!!'       'wheel 4 0 0 0'  'wheel up'
chk $'\e[Ma!!'       'wheel 5 0 0 0'  'wheel down'
chk $'\e[M$!!'       'down 1 0 0 1'   'Shift'
chk $'\e[M(!!'       'down 1 0 0 2'   'Alt'
chk $'\e[M0!!'       'down 1 0 0 4'   'Ctrl'
chk $'\e[M p8'       'down 1 79 23 0' 'bottom-right of 80x24'
chk $'\e[M \xff\xff' 'down 1 222 222 0' 'byte 255: column/row 223, the last one X10 can say (the clamp)'
chk $'\e[M \xc3\xa9' 'down 1 162 136 0' 'coordinate bytes that look like UTF-8'
chk $'\e[M\xa0!!'    'down 8 0 0 0'   'extra button 8 (byte 160)'

# --- X10 byte values from the table (fix round F5) --------------------------------
kt_test_start "every X10 coordinate byte 33-255 reads as its value - 33 (x and y)"
bad=''
for (( i = 33; i < 256; i++ )); do
    printf -v h '%02x' "$i"; printf -v c "\\x$h"
    fv.mouse.decode $'\e[M '"$c$c" || { bad+=" $i:rc"; continue; }
    (( FV_MOUSE_X == i - 33 && FV_MOUSE_Y == i - 33 )) || bad+=" $i:$FV_MOUSE_X"
done
if [[ -z $bad ]]; then kt_test_pass "223 values"; else kt_test_fail "$bad"; fi

kt_test_start "no byte value through printf %d \"'c\" (mbtowc: musl's C locale maps 0x80-0xFF to U+DF80...)"
if grep -nE "printf[^#]*%d[^#]*\"'" "$SCRIPT_DIR/../fv.mouse.sh" | grep -vE '^[0-9]+:[[:space:]]*#'; then kt_test_fail "found"; else kt_test_pass "none"; fi

# --- the caller's nocasematch (fix round F1) -----------------------------------------
shopt -s nocasematch
chk $'\e[<0;10;5M'   'down 1 9 4 0'   'nocasematch on: M is a press, not a release'
chk $'\e[<0;10;5m'   'up 1 9 4 0'     'nocasematch on'
kt_test_start "nocasematch on: \$'\\e[m;5D' is not an X10 report, and nocasematch stays on"
fv.mouse.decode $'\e[m;5D'; rc=$?
if [[ $rc == 1 ]] && shopt -q nocasematch; then kt_test_pass "rc 1"; else kt_test_fail "rc=$rc what=$FV_MOUSE_WHAT"; fi
shopt -u nocasematch

# --- from fv.keyboard: the FV_KEY_SEQ of a kbMouse ---------------------------------
source "$SCRIPT_DIR/../../fv.keyboard/fv.keyboard.sh"
kt_test_start "a byte stream through fv.keyboard: each kbMouse's FV_KEY_SEQ decodes here"
exec {nullfd}</dev/null
FV_KEY_FD=$nullfd
fv.keyboard.flush
fv.keyboard.feed $'\e[<0;10;5Mx\e[<0;10;5m\e[M`\xff\xff\e[<35;200;60M'
got=''
while fv.keyboard.getKeyEvent 0; do
    if [[ $FV_KEY == kbMouse ]]; then
        fv.mouse.decode "$FV_KEY_SEQ"
        got+="$FV_MOUSE_WHAT:$FV_MOUSE_BUTTON:$FV_MOUSE_X:$FV_MOUSE_Y|"
    else
        got+="$FV_KEY|"
    fi
done
exec {nullfd}<&-
if [[ $got == 'down:1:9:4|kbChar|up:1:9:4|wheel:4:222:222|move:0:199:59|' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi

kt_test_start "xterm's NUL coordinate (fv.keyboard stores it as \\xff) decodes as the clamp, 222"
printf '\033[M \000!' > "$(cd "$(kt_fixture_tmpdir)" && pwd)/x10nul.bin"
exec {xfd}< "$(cd "$(kt_fixture_tmpdir)" && pwd)/x10nul.bin"
FV_KEY_FD=$xfd
fv.keyboard.flush
fv.keyboard.getKeyEvent
fv.mouse.decode "$FV_KEY_SEQ"
exec {xfd}<&-
if [[ $FV_KEY == kbMouse && "$FV_MOUSE_WHAT $FV_MOUSE_X $FV_MOUSE_Y" == 'down 222 0' ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_KEY $FV_MOUSE_WHAT $FV_MOUSE_X $FV_MOUSE_Y"; fi

kt_test_start "decode inside \$( ) prints FV_MOUSE_WHAT once; a direct call prints nothing"
v=$(fv.mouse.decode $'\e[<65;1;1M')
fv.mouse.decode $'\e[<0;1;1M' > "$(cd "$(kt_fixture_tmpdir)" && pwd)/direct.out"
n=$(wc -c < "$(cd "$(kt_fixture_tmpdir)" && pwd)/direct.out")
if [[ $v == wheel && $n == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "'$v' direct=$n bytes"; fi

kt_test_log "001_Decode.sh completed"
