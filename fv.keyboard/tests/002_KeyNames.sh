#!/usr/bin/env bash
# 002_KeyNames.sh - every key name the unit README claims, each from at least
# one byte string a terminal sends: the Free Vision names (drivers.inc kbXXX)
# the decoder produces, then the names it adds where FV has none. Every byte
# of each string is consumed and FV_KEY_SEQ holds it.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: the claimed key names"

# --- FV names: C0 controls ----------------------------------------------------
L=ABCDEFGHIJKLMNOPQRSTUVWXYZ
for (( i = 1; i <= 26; i++ )); do
    case $i in 8|9|10|13) continue ;; esac      # Back, Tab, Enter, Enter
    printf -v h '%02x' "$i"
    printf -v c "\\x$h"
    fvk_chk "$c" "kbCtrl${L:i-1:1}"
done
fvk_chk $'\t' kbTab
fvk_chk $'\r' kbEnter
fvk_chk $'\x7f' kbBack
fvk_chk $'\e' kbEsc

# --- FV names: Alt (ESC prefix, xterm/mintty meta-sends-escape) ---------------
for (( i = 0; i < 26; i++ )); do
    c=${L:i:1}
    fvk_chk $'\e'"${c,}" "kbAlt$c" "${c,}"
done
for c in 0 1 2 3 4 5 6 7 8 9; do fvk_chk $'\e'"$c" "kbAlt$c" "$c"; done
A=( '-' Minus '=' Equal ' ' Space ']' RgtBrack ';' SemiCol "'" Quote '`' OpQuote
    '\' BkSlash ',' Comma '.' Period '/' Slash )
for (( i = 0; i < ${#A[@]}; i += 2 )); do fvk_chk $'\e'"${A[i]}" "kbAlt${A[i+1]}" "${A[i]}"; done
fvk_chk $'\e[' kbAltLftBrack '' 'ESC [ and nothing within the Esc timeout'
fvk_chk $'\eO' kbAltO '' 'ESC O and nothing within the Esc timeout'
fvk_chk $'\e\e' kbAltEsc
fvk_chk $'\e\x7f' kbAltBack
fvk_chk $'\e\b' kbAltBack
fvk_chk $'\e\t' kbAltTab

# --- FV names: cursor block and editing keys, plain and modified --------------
#     xterm/mintty/ConPTY: CSI 1;m X and CSI N;m ~ (m = 1 + Shift 1 + Alt 2 + Ctrl 4)
N=( Up A Down B Right C Left D Home H End F Center E )
for (( i = 0; i < ${#N[@]}; i += 2 )); do
    fvk_chk $'\e['"${N[i+1]}" "kb${N[i]}"
    fvk_chk $'\e[1;5'"${N[i+1]}" "kbCtrl${N[i]}"
    fvk_chk $'\e[1;3'"${N[i+1]}" "kbAlt${N[i]}"
done
N=( PgUp 5 PgDn 6 Ins 2 Del 3 )
for (( i = 0; i < ${#N[@]}; i += 2 )); do
    fvk_chk $'\e['"${N[i+1]}~" "kb${N[i]}"
    fvk_chk $'\e['"${N[i+1]};5~" "kbCtrl${N[i]}"
    fvk_chk $'\e['"${N[i+1]};3~" "kbAlt${N[i]}"
done
fvk_chk $'\e[2;2~' kbShiftIns
fvk_chk $'\e[3;2~' kbShiftDel
fvk_chk $'\e[G' kbCenter '' 'linux console keypad 5'
fvk_chk $'\eOE' kbCenter '' 'application keypad 5'
fvk_chk $'\eOM' kbEnter '' 'application keypad Enter'

# --- FV names: function keys F1-F12 with Shift / Ctrl / Alt ---------------------
F=( 1 P 2 Q 3 R 4 S )
for (( i = 0; i < ${#F[@]}; i += 2 )); do
    fvk_chk $'\eO'"${F[i+1]}" "kbF${F[i]}"
    fvk_chk $'\e[1;2'"${F[i+1]}" "kbShiftF${F[i]}"
    fvk_chk $'\e[1;5'"${F[i+1]}" "kbCtrlF${F[i]}"
    fvk_chk $'\e[1;3'"${F[i+1]}" "kbAltF${F[i]}"
done
F=( 5 15 6 17 7 18 8 19 9 20 10 21 11 23 12 24 )
for (( i = 0; i < ${#F[@]}; i += 2 )); do
    fvk_chk $'\e['"${F[i+1]}~" "kbF${F[i]}"
    fvk_chk $'\e['"${F[i+1]};2~" "kbShiftF${F[i]}"
    fvk_chk $'\e['"${F[i+1]};5~" "kbCtrlF${F[i]}"
    fvk_chk $'\e['"${F[i+1]};3~" "kbAltF${F[i]}"
done
F=( 5 t 6 u 7 v 8 l 9 w 10 x 11 y 12 z )
for (( i = 0; i < ${#F[@]}; i += 2 )); do
    fvk_chk $'\eO'"${F[i+1]}" "kbF${F[i]}" '' 'terminfo vt100 kf5-kf12 (VT100 keypad)'
done
fvk_chk $'\e[12~' kbF2 '' 'rxvt'
fvk_chk $'\e[13~' kbF3 '' 'rxvt'
fvk_chk $'\e[[B' kbF2 '' 'linux console'
fvk_chk $'\e[[C' kbF3 '' 'linux console'
fvk_chk $'\e[[D' kbF4 '' 'linux console'

# --- FV names through other encodings -------------------------------------------
fvk_chk $'\e\e[A' kbAltUp '' 'rxvt: ESC + the sequence'
fvk_chk $'\e\e[3~' kbAltDel '' 'rxvt: ESC + the sequence'
fvk_chk $'\e\eOP' kbAltF1 '' 'ESC + an SS3 sequence'
fvk_chk $'\e[1;9A' kbAltUp '' 'xterm Meta (modifier 9) reads as Alt'
fvk_chk $'\eO2P' kbShiftF1 '' 'SS3 with a modifier digit'
fvk_chk $'\eOb' kbCtrlDown '' 'rxvt'
fvk_chk $'\e[3^' kbCtrlDel '' 'rxvt'

# --- names the decoder adds (FV has none) -----------------------------------------
fvk_chk a kbChar
fvk_chk '~' kbChar
fvk_chk $'\e!' kbAltChar '!' 'Alt + a printable character FV does not name'
fvk_chk $'\e@' kbAltChar '@'
fvk_chk $'\e\r' kbAltEnter
fvk_chk $'\e\x01' kbCtrlAltA '' 'ESC + Ctrl-A'
fvk_chk $'\e\x1a' kbCtrlAltZ '' 'ESC + Ctrl-Z'
fvk_chk $'\x1c' kbCtrlBackslash
fvk_chk $'\x1d' kbCtrlRBracket
fvk_chk $'\x1e' kbCtrlCaret
fvk_chk $'\x1f' kbCtrlUnderscore
F=( 13 25 14 26 15 28 16 29 17 31 18 32 19 33 20 34 )
for (( i = 0; i < ${#F[@]}; i += 2 )); do fvk_chk $'\e['"${F[i+1]}~" "kbF${F[i]}" '' 'rxvt / linux Shift-F'; done
fvk_chk $'\e[1;2A' kbShiftUp
fvk_chk $'\e[1;6H' kbCtrlShiftHome
fvk_chk $'\e[1;7D' kbCtrlAltLeft
fvk_chk $'\e[3;8~' kbCtrlAltShiftDel
fvk_chk $'\e[1;4C' kbAltShiftRight
fvk_chk $'\e\e[1;5D' kbCtrlAltLeft '' 'ESC + CSI 1;5D'
fvk_chk $'\e[Z' kbShiftTab
fvk_chk $'\e[1;5Z' kbCtrlShiftTab
fvk_chk $'\e[11@' kbCtrlShiftF1 '' 'rxvt'
fvk_chk $'\e[25;2~' kbShiftF13
fvk_chk $'\e[M #!' kbMouse '' 'X10'
fvk_chk $'\e[<64;3;4M' kbMouse '' 'SGR wheel'
fvk_chk $'\e[<0;3;4m' kbMouse '' 'SGR release'
fvk_chk $'\e[99~' kbUnknown
fvk_chk $'\e[I' kbUnknown '' 'focus-in report (not enabled by fv)'
fvk_chk $'\e[200~' kbPaste '' 'bracketed paste start alone: an empty paste (P3 3d; 014_Paste)'
fvk_chk $'\e[1;2;3A' kbUnknown '' 'two modifier parameters'
fvk_chk $'\e[1;17A' kbUnknown '' 'modifier out of range'
fvk_chk $'\e[1;0A' kbUnknown '' 'modifier 0'

# --- SS3 with parameters (fix round F4): the CSI modifier rule ---------------------
fvk_chk $'\eO1;5P' kbCtrlF1 '' 'old VTE / konsole: ESC O 1 ; 5 P'
fvk_chk $'\eO1;2Q' kbShiftF2 '' 'old VTE / konsole'
fvk_chk $'\eO1;3D' kbAltLeft '' 'old VTE / konsole'
fvk_chk $'\eO;5A' kbCtrlUp '' 'an empty first parameter'
fvk_chk $'\eO9A' kbAltUp '' 'single digit: Meta (9) read as Alt'
fvk_chk $'\eO1;9B' kbAltDown '' 'Meta read as Alt'
fvk_chk $'\eO1;13C' kbCtrlAltRight '' 'Meta + Ctrl'
fvk_chk $'\eO1A' kbUp '' 'modifier 1 = none'
fvk_chk $'\eO2;5P' kbUnknown '' 'the first parameter must be 1'
fvk_chk $'\eO1;17P' kbUnknown '' 'modifier out of range'
fvk_chk $'\eO0A' kbUnknown '' 'modifier 0'
fvk_chk $'\eO1;2;3P' kbUnknown '' 'two modifier parameters'

kt_test_start "decode of nothing: rc 1, kbNoKey, RESULT=''"
fv.keyboard.decode ''; rc=$?
if [[ $rc == 1 && $FV_KEY == kbNoKey && -z $FV_KEY_SEQ && $FV_KEY_LEN == 0 && -z $RESULT ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "rc=$rc key=$FV_KEY len=$FV_KEY_LEN RESULT=$RESULT"
fi

kt_test_log "002_KeyNames.sh completed"
