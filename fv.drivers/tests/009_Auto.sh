#!/usr/bin/env bash
# 009_Auto.sh - evMouseAuto (P3 design 10.6, §3.3; FV drivers.inc
# GetMouseEvent: AutoTicks / AutoDelay, RepeatDelay 8 ticks): while a mouse
# button is held since a press and nothing arrives, getEvent answers
# evMouseAuto — the first FV_REPEAT_DELAY (0.44 s) after the press, then one
# per FV_IDLE_TIMEOUT (0.05 s) — at the last report's cell, with the held
# buttons and that report's modifiers. Timed through the clock hook
# __FV_DR_NOW; "nothing arrives" is fv.keyboard.getKeyEvent answering rc 1
# (a stub here, the reports come from a file as in the other files):
#   * the delay (inclusive), the rate, a late caller gets one (no burst);
#   * the position and modifiers of the last report (a drag moves it);
#   * every ending condition (L2: a lost release must not run away): a
#     release (also of a second button with the first still held, FV), a
#     key, a report with no button held (a move in `any` mode), an X10
#     release; a new press starts the delay again, so does a wheel event
#     with a button held; a drag or a wheel alone never arms it;
#   * the read waits no longer than the next one is due (getEvent's
#     TIMEOUT cut), unarmed it is passed on unchanged;
#   * FV_REPEAT_DELAY, a bad value (0.44 and one debug line), FV_IDLE_TIMEOUT
#     as the rate; FV's constants (fv.views' FV_EM_MOUSEAUTO = evMouseAuto's
#     bit $0008); a view's EventMask without evMouseAuto gets none:
#     fv.views.mouseEvent skips them until the release;
#   * the real clock on a live pipe: the first one not before 0.44 s.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "009: evMouseAuto"

L=$'\e[<0;5;5M' LU=$'\e[<0;5;5m' R=$'\e[<2;5;5M' RU=$'\e[<2;5;5m'
D=$'\e[<32;8;6M' DS=$'\e[<36;9;7M' MV=$'\e[<35;10;6M' W=$'\e[<64;5;5M' X10U=$'\e[M#%%'
K='a'

# the stub: FVA_IDLE > 0 answers "nothing came" (rc 1, no end of input) that
# many times, advancing the clock by the timeout when FVA_ADV is set; every
# timeout asked is noted in FVA_TO
eval "fva_orig_$(declare -f fv.keyboard.getKeyEvent)"
FVA_IDLE=0 FVA_ADV=0 FVA_TO=''
fv.keyboard.getKeyEvent() {
    FVA_TO+="$1 "
    if (( FVA_IDLE > 0 )); then
        FVA_IDLE=$(( FVA_IDLE - 1 ))
        if (( FVA_ADV )); then
            local s=${1%.*} f=000000 n c=${__FV_DR_NOW:-0}
            [[ $1 == *.* ]] && f=${1#*.}000000
            n=$(( ${c%.*} * 1000000 + 10#${c#*.} + 10#$s * 1000000 + 10#${f:0:6} ))
            printf -v __FV_DR_NOW '%d.%06d' "$(( n / 1000000 ))" "$(( n % 1000000 ))"
        fi
        FV_KEY_EOF=0 FV_KEY=''
        return 1
    fi
    fva_orig_fv.keyboard.getKeyEvent "$@"
}

# series TITLE BYTES "STEP..." WANT — feed BYTES, then per STEP one
# getEvent at its time: 'r@T' reads the next report or key, 'i@T' is an idle
# read; GOT = the events, ' | ' between (an evNothing as '-')
series() {
    local title=$1 want=$4 item got='' t
    fvd_feed "$2"
    for item in $3; do
        __FV_DR_NOW=${item#*@}
        if [[ $item == i@* ]]; then FVA_IDLE=1; else FVA_IDLE=0; fi
        fv.drivers.getEvent 0
        FVA_IDLE=0
        if [[ $FV_EV_WHAT == evNothing ]]; then got+='- '
        else fvd_ev; got+="$REPLY | "; fi
    done
    got=${got% }
    kt_test_start "$title"
    if [[ $got == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$got] want [$want]"; fi
}
A1='evMouseAuto x=4 y=4 b=1 |'

series "the delay: none before 0.44 s after the press, one at 0.44 (inclusive), at the press's cell with the held button" \
    "$L" "r@100.0 i@100.2 i@100.439999 i@100.44" "evMouseDown x=4 y=4 b=1 | - - $A1"
series "the rate: then one per FV_IDLE_TIMEOUT (0.05 s) on the schedule, a late caller gets one (no burst), then the schedule again" \
    "$L" "r@100.0 i@100.44 i@100.45 i@100.489999 i@100.49 i@100.54 i@101.3 i@101.31 i@101.349999 i@101.35" \
    "evMouseDown x=4 y=4 b=1 | $A1 - - $A1 $A1 $A1 - - $A1"
series "the position and the modifiers are the last report's: a drag (with Shift) moves them, the held button stays" \
    "$L$D$DS" "r@100.0 r@100.1 i@100.44 r@100.45 i@100.5" \
    "evMouseDown x=4 y=4 b=1 | evMouseMove x=7 y=5 b=1 | evMouseAuto x=7 y=5 b=1 | evMouseMove x=8 y=6 b=1 m=1 | evMouseAuto x=8 y=6 b=1 m=1 |"
series "a release ends it" \
    "$L$LU" "r@100.0 i@100.44 r@100.45 i@100.5 i@101.0" "evMouseDown x=4 y=4 b=1 | $A1 evMouseUp x=4 y=4 | - -"
series "a key ends it (L2: a lost release) and a drag afterwards does not arm it again" \
    "$L$K$D" "r@100.0 i@100.44 r@100.45 i@100.5 i@101.0 r@101.1 i@101.6 i@102.0" \
    "evMouseDown x=4 y=4 b=1 | $A1 evKeyDown key=kbChar char=a | - - evMouseMove x=7 y=5 b=1 | - -"
series "a report with no button held (a move in 'any' mode) ends it" \
    "$L$MV" "r@100.0 i@100.44 r@100.45 i@100.5 i@101.0" "evMouseDown x=4 y=4 b=1 | $A1 evMouseMove x=9 y=5 | - -"
series "an X10 release (no button named) ends it" \
    "$L$X10U" "r@100.0 i@100.44 r@100.45 i@100.5" "evMouseDown x=4 y=4 b=1 | $A1 evMouseUp x=4 y=4 | -"
series "a new press starts the delay again" \
    "$L$L" "r@100.0 i@100.44 r@100.5 i@100.6 i@100.939999 i@100.94" \
    "evMouseDown x=4 y=4 b=1 | $A1 evMouseDown x=4 y=4 b=1 | - - $A1"
series "a release of a second button ends it, the first still held (FV: any release); right + left held: the mask in the event" \
    "$R$L$LU" "r@100.0 r@100.1 i@100.54 r@100.6 i@101.2" \
    "evMouseDown x=4 y=4 b=2 | evMouseDown x=4 y=4 b=3 | evMouseAuto x=4 y=4 b=3 | evMouseUp x=4 y=4 b=2 | -"
series "a wheel event with a button held starts the delay again (FV); a wheel or a drag alone never arms it" \
    "$L$W$LU$W$D" "r@100.0 i@100.3 r@100.3 i@100.44 i@100.74 r@101.0 r@101.1 i@102.0 r@102.1 i@103.0" \
    "evMouseDown x=4 y=4 b=1 | - evMouseWheel x=4 y=4 b=1 wheel=1 | - $A1 evMouseUp x=4 y=4 | evMouseWheel x=4 y=4 wheel=1 | - evMouseMove x=7 y=5 b=1 | -"

kt_test_start "the read waits no longer than the next one is due: getEvent's TIMEOUT cut (1 s at 0.3 after the press -> 0.14; the default 0.05 kept while later; due -> 0, also for TIMEOUT 0); unarmed, passed on unchanged"
fvd_feed "$L$LU"
__FV_DR_NOW=100.0; fv.drivers.getEvent 0
FVA_TO=''
__FV_DR_NOW=100.3; FVA_IDLE=1; fv.drivers.getEvent 1
__FV_DR_NOW=100.3; FVA_IDLE=1; fv.drivers.getEvent
__FV_DR_NOW=100.43; FVA_IDLE=1; fv.drivers.getEvent
__FV_DR_NOW=100.6; FVA_IDLE=1; fv.drivers.getEvent 1; e=$FV_EV_WHAT
__FV_DR_NOW=100.7; fv.drivers.getEvent 0
__FV_DR_NOW=100.8; FVA_IDLE=1; fv.drivers.getEvent 1
FVA_IDLE=0
if [[ $FVA_TO == '0.140000 0.05 0.010000 0.000000 0.000000 1 ' && $e == evMouseAuto ]]; then kt_test_pass "ok"; else kt_test_fail "timeouts [$FVA_TO] event [$e]"; fi

kt_test_start "FV_REPEAT_DELAY=0.2: the first one 0.2 s after the press; FV_IDLE_TIMEOUT=0.1: one per 0.1 s"
fvd_feed "$L"
got=''
FV_REPEAT_DELAY=0.2 FV_IDLE_TIMEOUT=0.1
for t in 100.0 100.19 100.2 100.25 100.3 100.39 100.4; do
    __FV_DR_NOW=$t
    if [[ $t == 100.0 ]]; then FVA_IDLE=0; else FVA_IDLE=1; fi
    fv.drivers.getEvent 0
    if [[ $FV_EV_WHAT == evMouseAuto ]]; then got+=A; elif [[ $FV_EV_WHAT == evNothing ]]; then got+=-; else got+=d; fi
done
FVA_IDLE=0
unset FV_REPEAT_DELAY FV_IDLE_TIMEOUT
if [[ $got == 'd-A-A-A' ]]; then kt_test_pass "ok"; else kt_test_fail "got $got"; fi

kt_test_start "the period has a floor of 0.01 s: FV_IDLE_TIMEOUT=0.000001 gives one per 0.01 s, not one per read; a drain (getEvent 0 until evNothing) at one instant ends after one"
fvd_feed "$L"
got=''
FV_REPEAT_DELAY=0.2 FV_IDLE_TIMEOUT=0.000001
for t in 100.0 100.2 100.200001 100.209999 100.21 100.215 100.22 100.22 100.22; do
    __FV_DR_NOW=$t
    if [[ $t == 100.0 ]]; then FVA_IDLE=0; else FVA_IDLE=1; fi
    fv.drivers.getEvent 0
    if [[ $FV_EV_WHAT == evMouseAuto ]]; then got+=A; elif [[ $FV_EV_WHAT == evNothing ]]; then got+=-; else got+=d; fi
done
r="$__FV_DR_AP"
FVA_IDLE=0
unset FV_REPEAT_DELAY FV_IDLE_TIMEOUT
FVA_IDLE=1; fv.drivers.getEvent 0; FVA_IDLE=0
r+=" $__FV_DR_AP"
if [[ $got == 'dA--A-A--' && $r == '10000 50000' ]]; then kt_test_pass "ok"; else kt_test_fail "got $got period [$r]"; fi

series "the wall clock going back (EPOCHREALTIME): a small step back changes nothing; a big one makes the next one due one period from the new time (no stall), the rate goes on" \
    "$L" "r@1000.0 i@1000.44 i@1000.2 i@1000.49 i@10.0 i@10.049999 i@10.05 i@10.1 i@10.12 i@10.15" \
    "evMouseDown x=4 y=4 b=1 | $A1 - $A1 - - $A1 $A1 - $A1"

kt_test_start "the wall clock going back: the read's timeout is cut to one period from the new time (1 s asked -> 0.05), not kept whole while the next one seems far away"
fvd_feed "$L"
__FV_DR_NOW=1000.0; fv.drivers.getEvent 0
FVA_TO=''
__FV_DR_NOW=10.0; FVA_IDLE=1; fv.drivers.getEvent 1; e=$FV_EV_WHAT
__FV_DR_NOW=10.05; FVA_IDLE=1; fv.drivers.getEvent 1; e+=" $FV_EV_WHAT"
FVA_IDLE=0
if [[ $FVA_TO == '0.050000 0.000000 ' && $e == 'evNothing evMouseAuto' ]]; then kt_test_pass "ok"; else kt_test_fail "timeouts [$FVA_TO] events [$e]"; fi
fvd_feed "$LU"; __FV_DR_NOW=10.1; fv.drivers.getEvent 0

kt_test_start "a bad FV_REPEAT_DELAY: 0.44 is used, with one debug line (once per value)"
fvd_feed "$L"
got=''
{
    FV_REPEAT_DELAY=abc VERBOSE_KKLASS=debug
    for t in 100.0 100.43 100.44; do
        __FV_DR_NOW=$t
        if [[ $t == 100.0 ]]; then FVA_IDLE=0; else FVA_IDLE=1; fi
        fv.drivers.getEvent 0
        if [[ $FV_EV_WHAT == evMouseAuto ]]; then got+=A; elif [[ $FV_EV_WHAT == evNothing ]]; then got+=-; else got+=d; fi
    done
    FVA_IDLE=0
    unset FV_REPEAT_DELAY VERBOSE_KKLASS
} 2> "$FVD_TMP/rd.err"
n=0
while IFS= read -r l; do [[ $l == *FV_REPEAT_DELAY* ]] && n=$(( n + 1 )); done < "$FVD_TMP/rd.err"
if [[ $got == 'd-A' && $n == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "got $got, $n debug lines"; fi

kt_test_start "initEvents / doneEvents end it"
fvd_feed "$L"
__FV_DR_NOW=100.0; fv.drivers.getEvent 0
fv.drivers.doneEvents
__FV_DR_NOW=101.0; FVA_IDLE=1; fv.drivers.getEvent 0; e=$FV_EV_WHAT
FVA_IDLE=0
if [[ $e == evNothing && $__FV_DR_AA == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "[$e] armed=$__FV_DR_AA"; fi

# ---- with fv.views: FV's constants, the EventMask ------------------------------------
kk.uses fv.views || exit 1
kt_test_start "FV's constants: evMouseAuto is EventMask bit \$0008 (fv.views' FV_EM_MOUSEAUTO and its event table), FV_REPEAT_DELAY 0.44 = FV's RepeatDelay 8 ticks of 54.945 ms"
r="$FV_EM_MOUSEAUTO ${__FV_VW_EVBIT[evMouseAuto]-} $__FV_DR_RD $(( 8 * 54945 ))"
if [[ $r == '8 8 440000 439560' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "fv.views.mouseEvent with a mask without evMouseAuto skips them until the release (rc 1); with it, the first one (rc 0)"
TView.new mv 0 0 10 5
FVA_AUTOS=0
eval "fva_auto_$(declare -f fv.drivers._auto)"
fv.drivers._auto() { fva_auto_fv.drivers._auto; if [[ $FV_EV_WHAT == evMouseAuto ]]; then FVA_AUTOS=$(( FVA_AUTOS + 1 )); fi; }
fvd_feed "$L$LU"
__FV_DR_NOW=100.0; fv.drivers.getEvent 0
__FV_VW_GETEVENT=fv.drivers.getEvent __FV_VW_EOF=0
FVA_ADV=1 FVA_IDLE=20
fv.views.mouseEvent mv "$FV_EM_MOUSEMOVE"; r1=$?; w1=$FV_EV_WHAT a1=$FVA_AUTOS
fvd_feed "$L$LU"
__FV_DR_NOW=200.0; FVA_IDLE=0; fv.drivers.getEvent 0
FVA_AUTOS=0 FVA_IDLE=20
fv.views.mouseEvent mv "$(( FV_EM_MOUSEMOVE | FV_EM_MOUSEAUTO ))"; r2=$?; w2=$FV_EV_WHAT a2=$FVA_AUTOS left=$FVA_IDLE
FVA_ADV=0 FVA_IDLE=0
mv.delete
# (20 idle reads from 0.0, 0.05 s each but the one cut to 0.04 when the first
# is due: autos at 0.44, 0.49 .. 0.99 -> 12, then the release)
if [[ "$r1 $w1 $a1" == '1 evMouseUp 12' && "$r2 $w2 $a2" == '0 evMouseAuto 1' ]] && (( left == 11 )); then kt_test_pass "ok"
else kt_test_fail "no auto in the mask: rc $r1 $w1 after $a1 autos; with it: rc $r2 $w2 after $a2 ($left idle reads left)"; fi

# ---- the real clock ----------------------------------------------------------------------
kt_test_start "the real clock (a live pipe: a press, then nothing for 1.2 s): the first evMouseAuto not before 0.44 s after the press, more follow"
unset __FV_DR_NOW; __FV_DR_NOW=''
fvd_writer "$L" 1200000 "$LU"
fv.drivers.getEvent 1; e0=$FV_EV_WHAT
fvd_now; t0=$REPLY
n=0 first=0 rest=0
for (( i = 0; i < 60; i++ )); do
    fv.drivers.getEvent
    if [[ $FV_EV_WHAT == evMouseAuto ]]; then
        n=$(( n + 1 ))
        if (( n == 1 )); then fvd_now; first=$(( (REPLY - t0) / 1000 )); fi
    elif [[ $FV_EV_WHAT == evMouseUp ]]; then break
    fi
done
fvd_done
if [[ $e0 == evMouseDown ]] && (( first >= 430 && first < 3000 && n >= 2 )); then kt_test_pass "first after $first ms, $n in all"
else kt_test_fail "[$e0] first after $first ms, $n autos"; fi

kt_test_log "009_Auto.sh completed"
