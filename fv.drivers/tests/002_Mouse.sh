#!/usr/bin/env bash
# 002_Mouse.sh - mouse events from fed reports (no terminal):
#   * SGR and X10 down / up / drag / move / wheel -> evMouseDown, evMouseUp,
#     evMouseMove, evMouseWheel with 0-based cells and fv.mouse's modifiers;
#   * FV_EV_MOUSE_BUTTONS = the FV mask held AFTER the event (left 1, right 2,
#     middle 4), tracked by the unit: an SGR release names its button, an X10
#     release names none (every button up), a drag adds its button, a move
#     naming no button means none is held;
#   * FV_EV_WHEEL 1 up / 2 down, the held buttons kept; a horizontal wheel, a
#     wheel release, buttons 8-11 and a report fv.mouse rejects are evNothing.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: mouse events"

# far apart in time: no double clicks here (003 has those)
__FV_DR_NOW=0
tick() { __FV_DR_NOW=$(( ${__FV_DR_NOW%%.*} + 10 )); }
get() { tick; fvd_get "$@"; }

fvd_feed $'\e[<0;10;5M\e[<0;10;5m\e[<2;1;1M\e[<2;1;1m\e[<1;300;200M\e[<1;300;200m'
get "evMouseDown x=9 y=4 b=1"
get "evMouseUp x=9 y=4"
get "evMouseDown x=0 y=0 b=2"
get "evMouseUp x=0 y=0"
get "evMouseDown x=299 y=199 b=4"
get "evMouseUp x=299 y=199"

fvd_feed $'\e[<4;2;2M\e[<8;2;2m\e[<16;2;2M\e[<28;2;2m'
FVD_NOTE=Shift get "evMouseDown x=1 y=1 b=1 m=1"
FVD_NOTE=Alt get "evMouseUp x=1 y=1 m=2"
FVD_NOTE=Ctrl get "evMouseDown x=1 y=1 b=1 m=4"
FVD_NOTE="all three" get "evMouseUp x=1 y=1 m=7"

fvd_feed $'\e[<0;5;5M\e[<2;5;5M\e[<1;5;5M\e[<2;5;5m\e[<0;5;5m\e[<1;5;5m'
FVD_NOTE="held: left" get "evMouseDown x=4 y=4 b=1"
FVD_NOTE="held: left+right" get "evMouseDown x=4 y=4 b=3"
FVD_NOTE="held: all three" get "evMouseDown x=4 y=4 b=7"
FVD_NOTE="SGR release names right" get "evMouseUp x=4 y=4 b=5"
FVD_NOTE="then left" get "evMouseUp x=4 y=4 b=4"
FVD_NOTE="then middle" get "evMouseUp x=4 y=4"

fvd_feed $'\e[<0;3;3M\e[<32;4;3M\e[<32;5;3M\e[<0;5;3m\e[<35;6;3M\e[<34;7;3M\e[<35;8;3M'
get "evMouseDown x=2 y=2 b=1"
FVD_NOTE="drag with left" get "evMouseMove x=3 y=2 b=1"
get "evMouseMove x=4 y=2 b=1"
get "evMouseUp x=4 y=2"
FVD_NOTE="move, no button (any mode)" get "evMouseMove x=5 y=2"
FVD_NOTE="a drag adds its button" get "evMouseMove x=6 y=2 b=2"
FVD_NOTE="a move naming no button: none held" get "evMouseMove x=7 y=2"

fvd_feed $'\e[<64;3;3M\e[<65;3;3M\e[<0;3;3M\e[<65;4;4M\e[<0;3;3m\e[<68;1;1M'
get "evMouseWheel x=2 y=2 wheel=1"
get "evMouseWheel x=2 y=2 wheel=2"
get "evMouseDown x=2 y=2 b=1"
FVD_NOTE="the held left button stays" get "evMouseWheel x=3 y=3 b=1 wheel=2"
get "evMouseUp x=2 y=2"
FVD_NOTE="Shift+wheel" get "evMouseWheel x=0 y=0 m=1 wheel=1"

fvd_feed $'\e[<66;3;3M\e[<67;3;3M\e[<64;3;3m\e[<128;3;3M\e[<129;3;3m\e[<0;0;1M\e[<0;1M\e[<300;1;1Mq'
FVD_NOTE="horizontal wheel left" get "evNothing"
FVD_NOTE="horizontal wheel right" get "evNothing"
FVD_NOTE="a wheel release" get "evNothing"
FVD_NOTE="button 8" get "evNothing"
FVD_NOTE="button 9 release" get "evNothing"
FVD_NOTE="column 0: fv.mouse rejects it" get "evNothing"
FVD_NOTE="two fields" get "evNothing"
FVD_NOTE="button code 300" get "evNothing"
FVD_NOTE="the stream goes on" get "evKeyDown key=kbChar char=q"

# X10: ESC [ M Cb Cx Cy, each value + 32, cells 1-based
fvd_feed $'\e[M #$\e[M##$\e[M"#$\e[M!#$\e[M##$\e[M@&\'\e[MC&\'\e[M`!!\e[Ma!!\e[M \xff\xff\e[M##$\e[M4!!\e[M#!!'
FVD_NOTE="X10 left" get "evMouseDown x=2 y=3 b=1"
FVD_NOTE="X10 release" get "evMouseUp x=2 y=3"
FVD_NOTE="X10 right" get "evMouseDown x=2 y=3 b=2"
FVD_NOTE="X10 middle too" get "evMouseDown x=2 y=3 b=6"
FVD_NOTE="an X10 release names no button: every button up" get "evMouseUp x=2 y=3"
FVD_NOTE="X10 drag with left" get "evMouseMove x=5 y=6 b=1"
FVD_NOTE="X10 move, no button" get "evMouseMove x=5 y=6"
FVD_NOTE="X10 wheel up" get "evMouseWheel x=0 y=0 wheel=1"
FVD_NOTE="X10 wheel down" get "evMouseWheel x=0 y=0 wheel=2"
FVD_NOTE="X10 at the 223 clamp" get "evMouseDown x=222 y=222 b=1"
get "evMouseUp x=2 y=3"
FVD_NOTE="X10 Ctrl+Shift" get "evMouseDown x=0 y=0 b=1 m=5"
get "evMouseUp x=0 y=0"

fvd_feed $'\e[<0;3;3M\e[<65;4;4M\e[<0;3;3m'
get "evMouseDown x=2 y=2 b=1"
kt_test_start "IFS=0123456789: a wheel with a held button keeps the button mask (the number must not split)"
tick; IFS=0123456789 fv.drivers.getEvent 0; rc=$?
fvd_ev
if [[ $rc == 0 && $REPLY == "evMouseWheel x=3 y=3 b=1 wheel=2" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc got [$REPLY]"; fi
get "evMouseUp x=2 y=2"

kt_test_log "002_Mouse.sh completed"
