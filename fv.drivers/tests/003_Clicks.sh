#!/usr/bin/env bash
# 003_Clicks.sh - double and triple clicks (FV drivers.inc GetMouseEvent;
# DoubleDelay 8 ticks x 54.945 ms = 0.44 s), timed through the clock hook
# __FV_DR_NOW (seconds, like EPOCHREALTIME; '.' or ',' as the separator):
#   * a mouse-down with the same button mask and cell as the previous one,
#     within the delay (inclusive), is a double; a double followed by one more
#     is a triple; after a triple the next press is single again;
#   * another cell, another mask, a late press: single; releases between
#     presses do not matter;
#   * the wheel: consecutive wheel events are doubles, never triples, and a
#     wheel event breaks a click series;
#   * FV_DOUBLE_DELAY changes the delay; a bad value falls back to 0.44 with
#     a debug line; without the hook EPOCHREALTIME is the clock.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: double and triple clicks"

L=$'\e[<0;5;5M' LU=$'\e[<0;5;5m' R=$'\e[<2;5;5M' RU=$'\e[<2;5;5m' L2=$'\e[<0;6;5M' L2U=$'\e[<0;6;5m'
W=$'\e[<64;5;5M'

# series TITLE "BYTES@TIME ..." "WANT" — feed the reports, read one event per
# report at its time; WANT = the flags of the mouse-downs and wheels in
# order: s (single), d (double), t (triple)
series() {
    local title=$1 got='' item bytes='' want=$3
    for item in $2; do bytes+=${item%@*}; done
    fvd_feed "$bytes"
    for item in $2; do
        __FV_DR_NOW=${item#*@}
        fv.drivers.getEvent 0
        case $FV_EV_WHAT in
            evMouseDown|evMouseWheel)
                if (( FV_EV_MOUSE_TRIPLE )); then got+=t; elif (( FV_EV_MOUSE_DOUBLE )); then got+=d; else got+=s; fi ;;
        esac
    done
    kt_test_start "$title: $want"
    if [[ $got == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got $got"; fi
}

series "two presses 0.2 s apart" "$L@100.0 $LU@100.1 $L@100.2" sd
series "three presses: single, double, triple" "$L@100.0 $L@100.1 $L@100.2" sdt
series "after a triple the next press is single, then a double again" "$L@100.0 $L@100.1 $L@100.2 $L@100.3 $L@100.4" sdtsd
series "exactly 0.44 s is still a double" "$L@100.000000 $L@100.440000" sd
series "0.440001 s is single" "$L@100.000000 $L@100.440001" ss
series "another cell is single" "$L@100.0 $L2@100.1 $L2U@100.15 $L@100.2" sss
series "another button is single" "$L@100.0 $LU@100.05 $R@100.1 $RU@100.15 $L@100.2" sss
series "a late third press: single, double, single" "$L@100.0 $L@100.2 $L@101.0" sds
series "the delay counts from the last press, not the first" "$L@100.0 $L@100.4 $L@100.8" sdt
series "the wheel: doubles, never a triple" "$W@100.0 $W@100.1 $W@100.2 $W@100.3" sddd
series "a wheel event breaks a click series" "$L@100.0 $W@100.1 $L@100.2" sss
series "a comma separator in the clock" "$L@100,000000 $L@100,300000" sd
series "a left press while right is held: the mask is left+right" "$R@100.0 $L@100.1 $LU@100.15 $L@100.2" ssd

FV_DOUBLE_DELAY=0.1
series "FV_DOUBLE_DELAY=0.1: 0.2 s apart is single" "$L@100.0 $L@100.2" ss
series "FV_DOUBLE_DELAY=0.1: 0.05 s apart is double" "$L@100.0 $L@100.05" sd

kt_test_start "a bad FV_DOUBLE_DELAY: 0.44 is used, with one debug line (once per value)"
FV_DOUBLE_DELAY=abc
fvd_feed "$L$L$L"
__FV_DR_NOW=100.0 VERBOSE_KKLASS=debug fv.drivers.getEvent 0 2> "$FVD_TMP/e"; a=$FV_EV_MOUSE_DOUBLE
__FV_DR_NOW=100.4 VERBOSE_KKLASS=debug fv.drivers.getEvent 0 2>> "$FVD_TMP/e"; b=$FV_EV_MOUSE_DOUBLE
mapfile -t lines < "$FVD_TMP/e"
if [[ $a$b == 01 && ${#lines[@]} == 1 && ${lines[0]} == *FV_DOUBLE_DELAY*abc* ]]; then kt_test_pass "ok"; else kt_test_fail "dbl=$a$b debug=[${lines[*]}]"; fi
for v in 0 -1 0.0000001 1.2.3; do
    FV_DOUBLE_DELAY=$v
    series "FV_DOUBLE_DELAY=$v is not a positive number of seconds: 0.44" "$L@100.0 $L@100.4 $L@101.0" sds
done
unset FV_DOUBLE_DELAY

kt_test_start "without the hook EPOCHREALTIME is the clock: two presses at once are a double"
__FV_DR_NOW=''
fvd_feed "$L$L"
fv.drivers.getEvent 0; a=$FV_EV_MOUSE_DOUBLE
fv.drivers.getEvent 0; b=$FV_EV_MOUSE_DOUBLE
if [[ $a$b == 01 ]]; then kt_test_pass "ok"; else kt_test_fail "dbl=$a$b"; fi

kt_test_start "without the hook the real clock is read: FV_DOUBLE_DELAY=0.05, presses 0.15 s apart (busy wait) are single"
fvd_feed "$L$L"
FV_DOUBLE_DELAY=0.05 fv.drivers.getEvent 0; a=$FV_EV_MOUSE_DOUBLE
fvd_busy 150000
FV_DOUBLE_DELAY=0.05 fv.drivers.getEvent 0; b=$FV_EV_MOUSE_DOUBLE
if [[ $a$b == 00 ]]; then kt_test_pass "ok"; else kt_test_fail "dbl=$a$b"; fi

kt_test_log "003_Clicks.sh completed"
