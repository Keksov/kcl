#!/usr/bin/env bash
# 001_Keys.sh - key events from fed bytes (no terminal): evKeyDown with
# FV_EV_KEY = fv.keyboard's name and FV_EV_CHAR = its character, every other
# field at its default; kbUnknown is an evKeyDown too; Ctrl+Z, Ctrl+\ and
# Ctrl+C are plain keys here (on a tty fv.video keeps Ctrl+C an interrupt);
# fv.keyboard.feed input comes through getEvent; RESULT = FV_EV_WHAT.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "001: key events"

fvd_feed $'a\xd0\xb6 \e[A\e[1;5D\eOP\e[15~\ex\eX\e!\r\n\t\x7f\x1a\x1c\x03\e[99~\e[3;5~\xff'
fvd_get "evKeyDown key=kbChar char=a"
fvd_get "evKeyDown key=kbChar char=ж"
fvd_get "evKeyDown key=kbChar char= "
fvd_get "evKeyDown key=kbUp"
fvd_get "evKeyDown key=kbCtrlLeft"
fvd_get "evKeyDown key=kbF1"
fvd_get "evKeyDown key=kbF5"
fvd_get "evKeyDown key=kbAltX char=x"
fvd_get "evKeyDown key=kbAltX char=X"
fvd_get "evKeyDown key=kbAltChar char=!"
fvd_get "evKeyDown key=kbEnter"
fvd_get "evKeyDown key=kbEnter"
fvd_get "evKeyDown key=kbTab"
fvd_get "evKeyDown key=kbBack"
fvd_get "evKeyDown key=kbCtrlZ"
fvd_get "evKeyDown key=kbCtrlBackslash"
fvd_get "evKeyDown key=kbCtrlC"
FVD_NOTE="an unknown sequence is a key" fvd_get "evKeyDown key=kbUnknown"
fvd_get "evKeyDown key=kbCtrlDel"
FVD_NOTE="a bad UTF-8 lead byte" fvd_get "evKeyDown key=kbUnknown"

kt_test_start "the unknown key keeps its raw bytes in FV_KEY_SEQ (fv.keyboard's global)"
fvd_feed $'\e[99~'
fv.drivers.getEvent 0
if [[ $FV_EV_KEY == kbUnknown && $FV_KEY_SEQ == $'\e[99~' ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_EV_KEY [$FV_KEY_SEQ]"; fi

fvd_feed $'\e'
FVD_NOTE="a lone Esc after the Esc timeout" fvd_get "evKeyDown key=kbEsc"

printf 'x\0y' > "$FVD_TMP/nul.bin"
exec {nfd}< "$FVD_TMP/nul.bin"
FV_KEY_FD=$nfd
fv.keyboard.flush
fvd_get "evKeyDown key=kbChar char=x"
FVD_NOTE="NUL" fvd_get "evKeyDown key=kbCtrlSpace"
fvd_get "evKeyDown key=kbChar char=y"
exec {nfd}<&-

fvd_feed 'z'
fv.keyboard.feed $'\e[B'
FVD_NOTE="fv.keyboard.feed input" fvd_get "evKeyDown key=kbDown"
fvd_get "evKeyDown key=kbChar char=z"

kt_test_start "a key event after a mouse event: the mouse fields are back at their defaults"
fvd_feed $'\e[<4;10;5M\e[<4;10;5mq'
fv.drivers.getEvent 0; fv.drivers.getEvent 0; fv.drivers.getEvent 0
fvd_ev
if [[ $REPLY == "evKeyDown key=kbChar char=q" && $FV_EV_MOUSE_X$FV_EV_MOUSE_Y$FV_EV_MOUSE_BUTTONS$FV_EV_MOUSE_MODS == 0000 ]]; then kt_test_pass "ok"; else kt_test_fail "[$REPLY]"; fi

kt_test_log "001_Keys.sh completed"
