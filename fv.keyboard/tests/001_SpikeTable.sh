#!/usr/bin/env bash
# 001_SpikeTable.sh - the 67 checks of the TUI spike's decoder table
# (2026-11-08, tui_spike/test_keys.sh; xterm, mintty, ConPTY, Linux console,
# rxvt, VT220): its 66 byte strings, unchanged, and its back-to-back stream
# (the spike counted 66 + 1 = 67). Each case:
# decode BYTES -> the key name, every byte consumed, FV_KEY_SEQ == BYTES.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "001: the spike's decoder table (66 cases + the stream = its 67 checks)"

CR=$'\r'   # msys bash drops an unquoted $'\r' word inside a compound assignment
# bytes | expected | terminals
T=(
    $'\e[A'     kbUp          'xterm, mintty, ConPTY, linux, rxvt'
    $'\eOA'     kbUp          'xterm/mintty application cursor mode (DECCKM)'
    $'\e[B'     kbDown        'all'
    $'\e[C'     kbRight       'all'
    $'\e[D'     kbLeft        'all'
    $'\e[H'     kbHome        'xterm, mintty, ConPTY'
    $'\eOH'     kbHome        'xterm application mode'
    $'\e[1~'    kbHome        'linux console, VT220, tmux/screen'
    $'\e[7~'    kbHome        'rxvt/urxvt'
    $'\e[F'     kbEnd         'xterm, mintty, ConPTY'
    $'\eOF'     kbEnd         'xterm application mode'
    $'\e[4~'    kbEnd         'linux console, VT220'
    $'\e[8~'    kbEnd         'rxvt/urxvt'
    $'\e[5~'    kbPgUp        'all'
    $'\e[6~'    kbPgDn        'all'
    $'\e[2~'    kbIns         'all'
    $'\e[3~'    kbDel         'all'
    $'\eOP'     kbF1          'xterm, mintty, ConPTY, VT100/VT220'
    $'\eOQ'     kbF2          'xterm, mintty, ConPTY, VT100/VT220'
    $'\eOR'     kbF3          'xterm, mintty, ConPTY'
    $'\eOS'     kbF4          'xterm, mintty, ConPTY'
    $'\e[11~'   kbF1          'rxvt, xterm vt220 mode, PuTTY'
    $'\e[14~'   kbF4          'rxvt, PuTTY'
    $'\e[[A'    kbF1          'linux console'
    $'\e[[E'    kbF5          'linux console'
    $'\e[15~'   kbF5          'xterm, mintty, rxvt, ConPTY'
    $'\e[17~'   kbF6          'all'
    $'\e[21~'   kbF10         'all'
    $'\e[23~'   kbF11         'all'
    $'\e[24~'   kbF12         'all'
    $'\e[25~'   kbF13         'rxvt Shift-F3 / linux Shift-F1 (ambiguous)'
    $'\e[1;2P'  kbShiftF1     'xterm, mintty'
    $'\e[15;2~' kbShiftF5     'xterm, mintty'
    $'\e[15;5~' kbCtrlF5      'xterm, mintty'
    $'\e[1;5A'  kbCtrlUp      'xterm, mintty, ConPTY'
    $'\e[1;5D'  kbCtrlLeft    'xterm, mintty, ConPTY'
    $'\e[1;2C'  kbShiftRight  'xterm, mintty'
    $'\e[1;3B'  kbAltDown     'xterm, mintty'
    $'\e[1;6H'  kbCtrlShiftHome 'xterm'
    $'\e[3;5~'  kbCtrlDel     'xterm'
    $'\e[5;5~'  kbCtrlPgUp    'xterm'
    $'\eO5P'    kbCtrlF1      'old xterm / konsole'
    $'\eOa'     kbCtrlUp      'rxvt'
    $'\e[a'     kbShiftUp     'rxvt'
    $'\e[2$'    kbShiftIns    'rxvt'
    $'\e[11^'   kbCtrlF1      'rxvt'
    $'\e[Z'     kbShiftTab    'all'
    $'\t'       kbTab         'all'
    "$CR"       kbEnter       'all (raw mode, -icrnl)'
    $'\n'       kbEnter       'Ctrl-J / LF'
    $'\x7f'     kbBack        'xterm, mintty, linux, ConPTY'
    $'\b'       kbBack        'Ctrl-H, some Windows consoles'
    $'\e'       kbEsc         'lone Esc (no byte within the Esc timeout)'
    $'\x01'     kbCtrlA       'all'
    $'\x1a'     kbCtrlZ       'all (when susp is off)'
    $'\ex'      kbAltX        'xterm/mintty meta-sends-escape, ConPTY'
    $'\eX'      kbAltX        'Alt-Shift-x'
    $'\e1'      kbAlt1        'all'
    $'\e\e[A'   kbAltUp       'rxvt Alt-arrow'
    $'\e[M #!'  kbMouse       'X10 mouse report'
    $'\e[<0;10;5M' kbMouse    'SGR mouse report'
    a           kbChar        'printable'
    ' '         kbChar        'space'
    'ж'         kbChar        'UTF-8 2-byte'
    '€'         kbChar        'UTF-8 3-byte'
    $'\e[99~'   kbUnknown     'unknown sequence'
)

kt_test_start "the table holds the spike's 66 byte strings"
if (( ${#T[@]} == 66 * 3 )); then kt_test_pass "66"; else kt_test_fail "$(( ${#T[@]} / 3 )) cases"; fi

for (( i = 0; i < ${#T[@]}; i += 3 )); do
    case ${T[i+1]} in
        kbChar) fvk_chk "${T[i]}" "${T[i+1]}" "${T[i]}" "${T[i+2]}" ;;
        kbAltX) fvk_chk "${T[i]}" "${T[i+1]}" "${T[i]:1}" "${T[i+2]}" ;;
        kbAlt1) fvk_chk "${T[i]}" "${T[i+1]}" 1 "${T[i+2]}" ;;
        *) fvk_chk "${T[i]}" "${T[i+1]}" '' "${T[i+2]}" ;;
    esac
done

# the spike's stream: keys back to back split correctly (queue, then no fd)
kt_test_start "a stream of keys back to back splits correctly (the spike's 67th check)"
exec {nullfd}</dev/null
FV_KEY_FD=$nullfd
fv.keyboard.flush
fv.keyboard.feed $'\e[A\e[Bx\eOP\e[15~\r\e'
fvk_keys got
if [[ $got == 'kbUp|kbDown|kbChar:x|kbF1|kbF5|kbEnter|kbEsc' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi
exec {nullfd}<&-

kt_test_log "001_SpikeTable.sh completed"
