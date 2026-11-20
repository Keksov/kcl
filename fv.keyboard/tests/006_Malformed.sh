#!/usr/bin/env bash
# 006_Malformed.sh - sequences that are not keys must end, consume only what
# is theirs and leave the next key intact: an overlong CSI (read on to its
# final byte, at most 256 bytes: P3 3L), a CSI / SS3 /
# Linux-console sequence cut by the next ESC, a control byte or a high byte,
# and mouse reports of both kinds consumed exactly — X10 bytes that look like
# ESC, controls or UTF-8 leads included, so the decoder must count bytes, not
# characters. Every stream ends with a marker key that must survive.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "006: malformed sequences and exact mouse reports"

exec {nullfd}</dev/null
FV_KEY_FD=$nullfd
# stream TITLE BYTES WANT — one test: the keys of BYTES (fed, no fd input)
stream() {
    kt_test_start "$1"
    fv.keyboard.flush
    fv.keyboard.feed "$2"
    fvk_keys got
    if [[ $got == "$3" ]]; then kt_test_pass "$got"; else kt_test_fail "got  $got"$'\n'"want $3"; fi
}

digits=''
for (( i = 0; i < 40; i++ )); do digits+=1; done

stream "an overlong CSI (40 parameter bytes) is read on to its final byte: one kbUnknown, nothing of it becomes keys (P3 3L: long DA1 replies)" \
    $'\e['"$digits"$'A\e[B' \
    "kbUnknown|kbDown"

kt_test_start "the overlong CSI's FV_KEY_SEQ is the whole sequence (ESC [ + 40 + the final byte: 43 bytes)"
fv.keyboard.decode $'\e['"$digits"A
if [[ $FV_KEY == kbUnknown && $FV_KEY_LEN == 43 ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_KEY len=$FV_KEY_LEN"; fi

kt_test_start "a 32-byte CSI is still read whole (an SGR report with long numbers)"
fv.keyboard.decode $'\e[<0;1234567890123;123456789012345M'
if [[ $FV_KEY == kbMouse && $FV_KEY_LEN == 35 ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_KEY len=$FV_KEY_LEN"; fi

stream "a CSI cut by the next ESC: kbUnknown, the next sequence intact" \
    $'\e[1;5\e[A' 'kbUnknown|kbUp'
stream "a CSI cut by a control byte: kbUnknown, the control decoded" \
    $'\e[15\rx' 'kbUnknown|kbEnter|kbChar:x'
stream "a CSI cut by a UTF-8 lead: kbUnknown, the character decoded" \
    $'\e[2жx' 'kbUnknown|kbChar:ж|kbChar:x'
stream "a CSI cut by DEL: kbUnknown, kbBack" \
    $'\e[3\x7f' 'kbUnknown|kbBack'
stream "ESC [ + a control byte: Alt-[ then the control" \
    $'\e[\tx' 'kbAltLftBrack|kbTab|kbChar:x'
stream "ESC [ + ESC: Alt-[ then the next key" \
    $'\e[\eOP' 'kbAltLftBrack|kbF1'
stream "a CSI with an unknown final byte: kbUnknown only for it" \
    $'\e[5zq' 'kbUnknown|kbChar:q'
stream "a CSI with intermediates (ESC [ 1 SP q): one kbUnknown" \
    $'\e[1 qx' 'kbUnknown|kbChar:x'
stream "SS3 + ESC: Alt-O then the next key" \
    $'\eO\e[B' 'kbAltO|kbDown'
stream "SS3 + an unknown letter: one kbUnknown" \
    $'\eOgx' 'kbUnknown|kbChar:x'
stream "SS3 + a modifier digit + ESC: kbUnknown then the next key" \
    $'\eO5\e[C' 'kbUnknown|kbRight'
stream "the Linux console ESC [ [ + ESC: kbUnknown then the next key" \
    $'\e[[\e[D' 'kbUnknown|kbLeft'
stream "the Linux console ESC [ [ + an unknown letter: one kbUnknown" \
    $'\e[[Zx' 'kbUnknown|kbChar:x'
stream "ESC ESC + a mouse report: a lone Esc, then the report" \
    $'\e\e[<0;5;5Mx' 'kbEsc|kbMouse|kbChar:x'
stream "ESC ESC + a malformed CSI: a lone Esc, then kbUnknown" \
    $'\e\e[99~x' 'kbEsc|kbUnknown|kbChar:x'
stream "ESC ESC x: kbAltEsc then x" \
    $'\e\ex' 'kbAltEsc|kbChar:x'
stream "ESC [ alone at the end of the input: Alt-[" \
    $'x\e[' 'kbChar:x|kbAltLftBrack'
stream "a CSI cut by the end of the input: kbUnknown" \
    $'x\e[1;5' 'kbChar:x|kbUnknown'

# --- mouse reports consumed exactly ------------------------------------------------
stream "SGR press, drag, release, wheel back to back, then a key" \
    $'\e[<0;10;5M\e[<32;11;5M\e[<0;11;5m\e[<64;3;3M\e[<65;3;3Mz' \
    'kbMouse|kbMouse|kbMouse|kbMouse|kbMouse|kbChar:z'
stream "X10 whose bytes are ESC [ A: one report, then the key after it" \
    $'\e[M\e[A\e[B' 'kbMouse|kbDown'
stream "X10 whose bytes are controls (CR, Tab, DEL)" \
    $'\e[M\r\t\x7fq' 'kbMouse|kbChar:q'
stream "X10 whose bytes are a UTF-8 lead + continuation (2 of its 3 bytes)" \
    $'\e[M \xd0\xb6\xd0\xb6' $'kbMouse|kbChar:\xd0\xb6'
stream "X10 with column/row 223 (bytes 255) and a high button byte" \
    $'\e[M\xc0\xff\xffw' 'kbMouse|kbChar:w'
stream "X10 cut by the end of the input: kbUnknown" \
    $'q\e[M #' 'kbChar:q|kbUnknown'

kt_test_start "an X10 report's FV_KEY_SEQ is exactly its 6 bytes"
fv.keyboard.decode $'\e[M\xc3\xa9!rest'
s=$FV_KEY_SEQ
if [[ $FV_KEY == kbMouse && $FV_KEY_LEN == 6 && $s == $'\e[M\xc3\xa9!' ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_KEY len=$FV_KEY_LEN"; fi
exec {nullfd}<&-

kt_test_log "006_Malformed.sh completed"
