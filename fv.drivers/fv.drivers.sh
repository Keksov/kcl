#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.drivers.sh}../../kbool.sh" || return
kk.unit fv.drivers || return $__kk_unit_rc

# fv.drivers — the event (layer L0 of kcl/fv.*): keys, mouse, resize and idle
# as one Free Vision TEvent in FV_EV_* globals. Port in spirit of the FV
# Drivers unit (TEvent, GetMouseEvent's double/triple clicks) and of
# TProgram.GetEvent / PutEvent; plain functions, no classes, no forks on the
# event path. Design: kcl/docs/dev/fv/PLAN.md (P0b); API, deviations: README.md.
#
#   fv.drivers.getEvent [TIMEOUT]  the next event: a put one, a resize, a key
#                                  or mouse report within TIMEOUT seconds
#                                  (default FV_IDLE_TIMEOUT, 0.05), else
#                                  evMouseAuto while a button is held (P3
#                                  10.6), else evNothing; rc 1 = end of input
#   fv.drivers.putEvent            keep the current FV_EV_* for the next getEvent
#   fv.drivers.clearEvent          FV_EV_* = evNothing
#   fv.drivers.initEvents [any]    mouse reporting on (on FV_TTY_FD)
#   fv.drivers.doneEvents          mouse reporting off
#
# Out: FV_EV_WHAT (evNothing evKeyDown evMouseDown evMouseUp evMouseMove
# evMouseAuto evMouseWheel evCommand evBroadcast), FV_EV_KEY, FV_EV_CHAR, FV_EV_COMMAND
# (a name: cmResizeApp; cmPasteText for a bracketed paste, the text in
# FV_EV_INFO, P3 10.8), FV_EV_ID, FV_EV_INFO, FV_EV_MOUSE_X / _Y (0-based),
# FV_EV_MOUSE_BUTTONS (held after the event: 1 left, 2 right, 4 middle),
# FV_EV_MOUSE_MODS (1 Shift, 2 Alt, 4 Ctrl), FV_EV_MOUSE_DOUBLE,
# FV_EV_MOUSE_TRIPLE, FV_EV_WHEEL (1 up, 2 down), FV_EV_EOF, FV_EV_BASE (a
# key's base-layout key, fv.keyboard's FV_KEY_BASE; '' for every other
# event); RESULT = FV_EV_WHAT. In: FV_IDLE_TIMEOUT, FV_DOUBLE_DELAY (0.44 s), FV_REPEAT_DELAY
# (0.44 s), and fv.keyboard's FV_KEY_FD / FV_ESC_TIMEOUT.

kk.uses fv.keyboard || return
kk.uses fv.mouse || return
kk.uses fv.video || return

if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

declare -g FV_EV_WHAT=evNothing FV_EV_KEY='' FV_EV_CHAR='' FV_EV_COMMAND='' FV_EV_ID='' FV_EV_INFO=''
declare -g FV_EV_MOUSE_X=0 FV_EV_MOUSE_Y=0 FV_EV_MOUSE_BUTTONS=0 FV_EV_MOUSE_MODS=0
declare -g FV_EV_MOUSE_DOUBLE=0 FV_EV_MOUSE_TRIPLE=0 FV_EV_WHEEL=0 FV_EV_EOF=0 FV_EV_BASE=''
# HELD: buttons held (FV bits); DB/DX/DY/DT/LD: the last mouse-down's button
# mask (wheel: 8 up, 16 down, as FPC's MouseButton4/5), cell, time (us) and
# whether it was a double; NOW: the clock hook (tests); TO/TOU/DD/RD: the
# validated FV_IDLE_TIMEOUT (s, us), FV_DOUBLE_DELAY (us) and FV_REPEAT_DELAY
# (us), and their raw values; AP: the evMouseAuto period (us): TOU, at least
# 10000 (0.01 s); AA/AT/LX/LY/LM: evMouseAuto armed (a button
# held since a press), the time (us) the next one is due, the last mouse
# event's cell and modifiers; PEND: the put event (PENDB its FV_EV_BASE, kept apart:
# PEND keeps FV's 14 fields that fv.app and fv.menus read)
declare -g __FV_DR_HELD=0 __FV_DR_DB=-1 __FV_DR_DX=-1 __FV_DR_DY=-1 __FV_DR_DT=0 __FV_DR_LD=0
declare -g __FV_DR_NOW=${__FV_DR_NOW-}
declare -g __FV_DR_TO=0.05 __FV_DR_TOU=50000 __FV_DR_TORAW='' __FV_DR_DD=440000 __FV_DR_DDRAW='' __FV_DR_AP=50000
declare -g __FV_DR_RD=440000 __FV_DR_RDRAW='' __FV_DR_AA=0 __FV_DR_AT=0 __FV_DR_LX=0 __FV_DR_LY=0 __FV_DR_LM=0
declare -ga __FV_DR_PEND=()
declare -g __FV_DR_PENDB=''

# fv.drivers._secs S — rc 0 when S is a number of seconds read -t takes as
# written (digits, one optional dot, at most 6 decimals, 13 characters);
# __fvd_us (the caller's local) = S in microseconds
fv.drivers._secs() {
    if [[ -z $1 || $1 == *[!0-9.]* || $1 == *.*.* || $1 == . || $1 == *.???????* || ${#1} -gt 13 ]]; then
        return 1
    fi
    local __fvd_i=${1%%.*} __fvd_f=000000
    if [[ $1 == *.* ]]; then __fvd_f=${1#*.}000000; fi
    __fvd_us=$(( 10#${__fvd_i:-0} * 1000000 + 10#${__fvd_f:0:6} ))
}

# the environment knobs, checked once per value: a positive number of seconds,
# else the default and a debug line
fv.drivers._knobs() {
    local __fvd_us=0
    if [[ ${FV_IDLE_TIMEOUT-} != "$__FV_DR_TORAW" ]]; then
        __FV_DR_TORAW=${FV_IDLE_TIMEOUT-} __FV_DR_TO=0.05 __FV_DR_TOU=50000
        if fv.drivers._secs "$__FV_DR_TORAW" && (( __fvd_us > 0 )); then __FV_DR_TO=$__FV_DR_TORAW __FV_DR_TOU=$__fvd_us
        elif [[ -n $__FV_DR_TORAW ]]; then
            kk.debug "Error: fv.drivers: FV_IDLE_TIMEOUT '$__FV_DR_TORAW' is not a positive number of seconds (at most 6 decimals); using 0.05"
        fi
        # (the auto-repeat's period: a floor of 0.01 s, so that a tiny
        # timeout does not make every idle read an evMouseAuto)
        __FV_DR_AP=$__FV_DR_TOU
        if (( __FV_DR_AP < 10000 )); then __FV_DR_AP=10000; fi
    fi
    if [[ ${FV_DOUBLE_DELAY-} != "$__FV_DR_DDRAW" ]]; then
        __FV_DR_DDRAW=${FV_DOUBLE_DELAY-} __FV_DR_DD=440000
        if fv.drivers._secs "$__FV_DR_DDRAW" && (( __fvd_us > 0 )); then __FV_DR_DD=$__fvd_us
        elif [[ -n $__FV_DR_DDRAW ]]; then
            kk.debug "Error: fv.drivers: FV_DOUBLE_DELAY '$__FV_DR_DDRAW' is not a positive number of seconds (at most 6 decimals); using 0.44"
        fi
    fi
    if [[ ${FV_REPEAT_DELAY-} != "$__FV_DR_RDRAW" ]]; then
        __FV_DR_RDRAW=${FV_REPEAT_DELAY-} __FV_DR_RD=440000
        if fv.drivers._secs "$__FV_DR_RDRAW" && (( __fvd_us > 0 )); then __FV_DR_RD=$__fvd_us
        elif [[ -n $__FV_DR_RDRAW ]]; then
            kk.debug "Error: fv.drivers: FV_REPEAT_DELAY '$__FV_DR_RDRAW' is not a positive number of seconds (at most 6 decimals); using 0.44"
        fi
    fi
}

fv.drivers.clearEvent() {
    FV_EV_WHAT=evNothing FV_EV_KEY='' FV_EV_CHAR='' FV_EV_COMMAND='' FV_EV_ID='' FV_EV_INFO=''
    FV_EV_MOUSE_X=0 FV_EV_MOUSE_Y=0 FV_EV_MOUSE_BUTTONS=0 FV_EV_MOUSE_MODS=0
    FV_EV_MOUSE_DOUBLE=0 FV_EV_MOUSE_TRIPLE=0 FV_EV_WHEEL=0 FV_EV_EOF=0 FV_EV_BASE='' RESULT=''
}

# FV's `Pending := Event`: one slot, a second put overwrites, evNothing empties it
fv.drivers.putEvent() {
    __FV_DR_PEND=("$FV_EV_WHAT" "$FV_EV_KEY" "$FV_EV_CHAR" "$FV_EV_COMMAND" "$FV_EV_ID" "$FV_EV_INFO"
        "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" "$FV_EV_MOUSE_BUTTONS" "$FV_EV_MOUSE_MODS"
        "$FV_EV_MOUSE_DOUBLE" "$FV_EV_MOUSE_TRIPLE" "$FV_EV_WHEEL" "$FV_EV_EOF")
    __FV_DR_PENDB=$FV_EV_BASE
    if [[ $FV_EV_WHAT == evNothing ]]; then __FV_DR_PEND=(); fi
    RESULT=''
}

# a mouse-down (MASK WHEEL): FV's double / triple click rule (drivers.inc
# GetMouseEvent): the same mask and cell within DoubleDelay is a double, a
# double followed by one more is a triple (not for the wheel), and after a
# triple the next press is single again
fv.drivers._click() {
    local __fvd_t=${__FV_DR_NOW:-$EPOCHREALTIME} __fvd_s __fvd_f
    __fvd_s=${__fvd_t%%[.,]*} __fvd_f=${__fvd_t#*[.,]}
    if [[ $__fvd_t != *[.,]* ]]; then __fvd_f=''; fi
    __fvd_f+=000000
    __fvd_t=$(( 10#${__fvd_s:-0} * 1000000 + 10#${__fvd_f:0:6} ))
    if (( $1 == __FV_DR_DB && FV_EV_MOUSE_X == __FV_DR_DX && FV_EV_MOUSE_Y == __FV_DR_DY )) \
       && (( __fvd_t - __FV_DR_DT <= __FV_DR_DD )); then
        FV_EV_MOUSE_DOUBLE=1
        if (( __FV_DR_LD && ! $2 )); then FV_EV_MOUSE_DOUBLE=0 FV_EV_MOUSE_TRIPLE=1; fi
    fi
    __FV_DR_LD=$FV_EV_MOUSE_DOUBLE __FV_DR_DB=$1 __FV_DR_DX=$FV_EV_MOUSE_X __FV_DR_DY=$FV_EV_MOUSE_Y __FV_DR_DT=$__fvd_t
    if (( FV_EV_MOUSE_TRIPLE )); then __FV_DR_DT=$(( __fvd_t - __FV_DR_DD )); fi
    if (( $2 )); then __FV_DR_LD=0; fi
    # (evMouseAuto: a press, or a wheel event with a button held, starts the
    # delay again, FV's AutoTicks / AutoDelay; nothing held: not armed)
    if (( __FV_DR_HELD )); then __FV_DR_AA=1 __FV_DR_AT=$(( __fvd_t + __FV_DR_RD )); else __FV_DR_AA=0; fi
}

# the kbMouse key in FV_KEY_SEQ -> a mouse event; a report fv.mouse rejects,
# a horizontal wheel, a wheel release and buttons 8-11 stay evNothing
fv.drivers._mouse() {
    local __fvd_b
    if (( BASH_SUBSHELL > 0 )); then fv.mouse.decode "$FV_KEY_SEQ" >/dev/null || return 0
    else fv.mouse.decode "$FV_KEY_SEQ" || return 0; fi
    case $FV_MOUSE_BUTTON in
        0) __fvd_b=0 ;; 1) __fvd_b=1 ;; 2) __fvd_b=4 ;; 3) __fvd_b=2 ;; 4) __fvd_b=8 ;; 5) __fvd_b=16 ;;
        *) return 0 ;;
    esac
    if [[ $FV_MOUSE_WHAT == up ]] && (( __fvd_b >= 8 )); then return 0; fi
    FV_EV_MOUSE_X=$FV_MOUSE_X FV_EV_MOUSE_Y=$FV_MOUSE_Y
    case $FV_MOUSE_WHAT in
        wheel)
            FV_EV_WHAT=evMouseWheel FV_EV_WHEEL=$(( __fvd_b == 8 ? 1 : 2 ))
            fv.drivers._click "$(( __FV_DR_HELD | __fvd_b ))" 1 ;;
        down)
            __FV_DR_HELD=$(( __FV_DR_HELD | __fvd_b )) FV_EV_WHAT=evMouseDown
            fv.drivers._click "$__FV_DR_HELD" 0 ;;
        up)
            # an X10 release names no button: every button is up; any
            # release ends the auto-repeat (FV: AutoTicks := 0)
            if (( __fvd_b )); then __FV_DR_HELD=$(( __FV_DR_HELD & ~__fvd_b )); else __FV_DR_HELD=0; fi
            FV_EV_WHAT=evMouseUp __FV_DR_AA=0 ;;
        *)
            # a drag names the button it holds; a move naming none: none held
            if (( __fvd_b )); then __FV_DR_HELD=$(( __FV_DR_HELD | __fvd_b )); else __FV_DR_HELD=0; fi
            FV_EV_WHAT=evMouseMove ;;
    esac
    FV_EV_MOUSE_BUTTONS=$__FV_DR_HELD FV_EV_MOUSE_MODS=$FV_MOUSE_MODS
    # (what evMouseAuto repeats: the last report's cell and modifiers; a
    # report with no button held ends the repeat, L2)
    __FV_DR_LX=$FV_MOUSE_X __FV_DR_LY=$FV_MOUSE_Y __FV_DR_LM=$FV_MOUSE_MODS
    if (( ! __FV_DR_HELD )); then __FV_DR_AA=0; fi
}

# fv.drivers._paste — fv.keyboard's kbPaste (a bracketed paste, design P3
# §4.5, 10.8) -> FV's evCommand cmPasteText (FPC 2025, drivers.inc): the
# text in FV_EV_INFO, its length in FV_EV_ID (FV's Id: the size); like a key
# it ends the auto-repeat (L2). One event: a pasted newline is never kbEnter
fv.drivers._paste() {
    FV_EV_WHAT=evCommand FV_EV_COMMAND=cmPasteText FV_EV_INFO=$FV_KEY_CHAR FV_EV_ID=${#FV_KEY_CHAR} __FV_DR_AA=0
}

# fv.drivers._now — the caller's __fvd_n = the clock (__FV_DR_NOW or
# EPOCHREALTIME) in microseconds
fv.drivers._now() {
    local __fvd_c=${__FV_DR_NOW:-$EPOCHREALTIME} __fvd_s __fvd_f
    __fvd_s=${__fvd_c%%[.,]*} __fvd_f=${__fvd_c#*[.,]}
    if [[ $__fvd_c != *[.,]* ]]; then __fvd_f=''; fi
    __fvd_f+=000000
    __fvd_n=$(( 10#${__fvd_s:-0} * 1000000 + 10#${__fvd_f:0:6} ))
}

# fv.drivers._autoWait — getEvent's read timeout (its locals __fvd_t, the
# string, and __fvd_tu, in us) cut to the time left until the next
# evMouseAuto is due (0 when it is due now). The clock is wall time
# (EPOCHREALTIME): when it went back, the next one is due further away than
# a press's delay and a period ever put it — it is then due one period from
# now (as in fv.drivers._auto), so the repeat does not stall
fv.drivers._autoWait() {
    local __fvd_n
    fv.drivers._now
    if (( __FV_DR_AT - __fvd_n > __FV_DR_RD + __FV_DR_AP )); then __FV_DR_AT=$(( __fvd_n + __FV_DR_AP )); fi
    __fvd_n=$(( __FV_DR_AT - __fvd_n ))
    if (( __fvd_n >= __fvd_tu )); then return 0; fi
    if (( __fvd_n < 0 )); then __fvd_n=0; fi
    printf -v __fvd_t '%d.%06d' "$(( __fvd_n / 1000000 ))" "$(( __fvd_n % 1000000 ))"
}

# fv.drivers._auto — on an idle read with a button held since a press: the
# evMouseAuto due by now (FV GetMouseEvent: the first FV_REPEAT_DELAY after
# the press, then one per FV_IDLE_TIMEOUT, FV's 1 tick; the period at least
# 0.01 s, __FV_DR_AP), at the last report's cell with the held buttons and
# its modifiers; else nothing (evNothing). A late caller gets one, never a
# burst; the clock gone back: as in fv.drivers._autoWait
fv.drivers._auto() {
    local __fvd_n
    fv.drivers._now
    if (( __FV_DR_AT - __fvd_n > __FV_DR_RD + __FV_DR_AP )); then __FV_DR_AT=$(( __fvd_n + __FV_DR_AP )); fi
    if (( __fvd_n < __FV_DR_AT || ! __FV_DR_HELD )); then return 0; fi
    __FV_DR_AT=$(( __FV_DR_AT + __FV_DR_AP ))
    if (( __FV_DR_AT <= __fvd_n )); then __FV_DR_AT=$(( __fvd_n + __FV_DR_AP )); fi
    FV_EV_WHAT=evMouseAuto FV_EV_MOUSE_X=$__FV_DR_LX FV_EV_MOUSE_Y=$__FV_DR_LY
    FV_EV_MOUSE_BUTTONS=$__FV_DR_HELD FV_EV_MOUSE_MODS=$__FV_DR_LM
}

fv.drivers.getEvent() {
    local __fvd_t=$__FV_DR_TO __fvd_tu=$__FV_DR_TOU __fvd_us=0 __fvd_rc=0
    if (( $# )); then
        if ! fv.drivers._secs "$1"; then
            kk.debug "Error: fv.drivers.getEvent: timeout '$1' is not a number of seconds (at most 6 decimals)"
            RESULT=''
            return 2
        fi
        __fvd_t=$1 __fvd_tu=$__fvd_us
    fi
    if [[ ${FV_IDLE_TIMEOUT-} != "$__FV_DR_TORAW" || ${FV_DOUBLE_DELAY-} != "$__FV_DR_DDRAW" || ${FV_REPEAT_DELAY-} != "$__FV_DR_RDRAW" ]]; then
        fv.drivers._knobs
        if (( ! $# )); then __fvd_t=$__FV_DR_TO __fvd_tu=$__FV_DR_TOU; fi
    fi
    if (( ${#__FV_DR_PEND[@]} )); then
        FV_EV_WHAT=${__FV_DR_PEND[0]} FV_EV_KEY=${__FV_DR_PEND[1]} FV_EV_CHAR=${__FV_DR_PEND[2]}
        FV_EV_COMMAND=${__FV_DR_PEND[3]} FV_EV_ID=${__FV_DR_PEND[4]} FV_EV_INFO=${__FV_DR_PEND[5]}
        FV_EV_MOUSE_X=${__FV_DR_PEND[6]} FV_EV_MOUSE_Y=${__FV_DR_PEND[7]} FV_EV_MOUSE_BUTTONS=${__FV_DR_PEND[8]}
        FV_EV_MOUSE_MODS=${__FV_DR_PEND[9]} FV_EV_MOUSE_DOUBLE=${__FV_DR_PEND[10]}
        FV_EV_MOUSE_TRIPLE=${__FV_DR_PEND[11]} FV_EV_WHEEL=${__FV_DR_PEND[12]} FV_EV_EOF=${__FV_DR_PEND[13]}
        FV_EV_BASE=$__FV_DR_PENDB
        __FV_DR_PEND=() RESULT=$FV_EV_WHAT
        return 0
    fi
    fv.drivers.clearEvent
    # resize before keys (FV: key, mouse, then the system event)
    if (( FV_VIDEO_RESIZED )); then
        fv.video.updateSize
        FV_EV_WHAT=evCommand FV_EV_COMMAND=cmResizeApp FV_EV_ID=$FV_SCREEN_W FV_EV_INFO=$FV_SCREEN_H
        RESULT=$FV_EV_WHAT
        return 0
    fi
    # (a button held since a press: the read waits no longer than the next
    # evMouseAuto is due)
    if (( __FV_DR_AA )); then fv.drivers._autoWait; fi
    fv.keyboard.getKeyEvent "$__fvd_t" || __fvd_rc=$?
    if (( __fvd_rc == 0 )); then
        if [[ $FV_KEY == kbMouse ]]; then fv.drivers._mouse
        elif [[ $FV_KEY == kbPaste ]]; then fv.drivers._paste
        else FV_EV_WHAT=evKeyDown FV_EV_KEY=$FV_KEY FV_EV_CHAR=$FV_KEY_CHAR FV_EV_BASE=$FV_KEY_BASE __FV_DR_AA=0; fi
    elif (( __fvd_rc == 1 && FV_KEY_EOF )); then
        FV_EV_EOF=1 RESULT=''
        return 1
    elif (( __fvd_rc != 1 )); then
        RESULT=''
        return "$__fvd_rc"
    elif (( __FV_DR_AA )); then
        # (nothing came: the auto-repeat while a button is held)
        fv.drivers._auto
    fi
    RESULT=$FV_EV_WHAT
}

fv.drivers.initEvents() {
    if [[ -n ${1-} ]] && [ "$1" != any ]; then      # [ ]: exact, whatever nocasematch says
        kk.debug "Error: fv.drivers.initEvents: mode '$1' is not 'any'"
        RESULT=''
        return 2
    fi
    if [[ -z $FV_TTY_FD ]]; then
        kk.debug "Error: fv.drivers.initEvents: no terminal (fv.video.initVideo first)"
        RESULT=''
        return 1
    fi
    __FV_DR_HELD=0 __FV_DR_DB=-1 __FV_DR_LD=0 __FV_DR_AA=0
    fv.keyboard.flush                  # nothing read before belongs to the new mode
    fv.mouse.enable "$FV_TTY_FD" "${1-}" || return
    RESULT=''
}

fv.drivers.doneEvents() {
    __FV_DR_HELD=0 __FV_DR_DB=-1 __FV_DR_LD=0 __FV_DR_AA=0
    fv.keyboard.flush
    RESULT=''
    if [[ -z $FV_TTY_FD ]]; then return 0; fi
    fv.mouse.disable "$FV_TTY_FD" || return
    RESULT=''
}
