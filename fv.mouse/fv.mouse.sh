#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.mouse.sh}../../kbool.sh" || return
kk.unit fv.mouse || return $__kk_unit_rc

# fv.mouse — terminal mouse reports -> button, wheel, position (layer L0 of
# kcl/fv.*). Port in spirit of the FPC rtl-console Mouse unit; plain
# functions, no classes, no forks. Design: kcl/docs/dev/fv/PLAN.md (P0a); API
# and deviations: README.md. The report comes from fv.keyboard as the
# FV_KEY_SEQ of a kbMouse key; this unit does not read the terminal.
#
#   fv.mouse.decode RAW         an SGR 1006 (ESC [ < b ; x ; y M|m) or X10
#                               (ESC [ M Cb Cx Cy) report; rc 1 = malformed
#   fv.mouse.enable [FD] [any]  print the sequence that turns reporting on
#                               (buttons + drag + SGR; `any` adds all motion)
#   fv.mouse.disable [FD]       print the sequence that turns it off
#
# Out of decode: FV_MOUSE_WHAT (down up move wheel), FV_MOUSE_BUTTON (1 left,
# 2 middle, 3 right, 4/5 wheel up/down, 6/7 wheel left/right, 8-11 extra
# buttons, 0 = none or not named), FV_MOUSE_X / FV_MOUSE_Y (0-based cells),
# FV_MOUSE_MODS (1 Shift, 2 Alt, 4 Ctrl), RESULT = FV_MOUSE_WHAT.

# the settings hook (kkore kk.settings): the kcl locale default
fv.mouse._settings() {
    kk.localeDefault
    return 0
}
kk.settings fv.mouse._settings LC_CTYPE || return

declare -g FV_MOUSE_WHAT='' FV_MOUSE_BUTTON=0 FV_MOUSE_X=0 FV_MOUSE_Y=0 FV_MOUSE_MODS=0
# byte -> value for the X10 bytes 32-255, built once: `printf %d "'c"` goes
# through mbtowc, and musl's C locale maps 0x80-0xFF to U+DF80...
declare -gA __FV_MS_ORD=()

fv.mouse._init() {
    local i h c
    for (( i = 32; i < 256; i++ )); do
        printf -v h '%02x' "$i"
        printf -v c "\\x$h"
        __FV_MS_ORD[$c]=$i
    done
}
fv.mouse._init

# fv.mouse._bits CODE RELEASE — the button byte of either encoding (RELEASE =
# 1 for an SGR 'm' report)
fv.mouse._bits() {
    local __fvm_lo=$(( $1 & 3 ))
    FV_MOUSE_MODS=$(( ($1 >> 2) & 7 ))
    if (( $1 & 64 && ! ($1 & 128) )); then
        FV_MOUSE_BUTTON=$(( 4 + __fvm_lo ))
        if (( $2 )); then FV_MOUSE_WHAT=up; else FV_MOUSE_WHAT=wheel; fi
        return 0
    fi
    if (( $1 & 128 )); then FV_MOUSE_BUTTON=$(( 8 + __fvm_lo ))
    elif (( __fvm_lo == 3 )); then FV_MOUSE_BUTTON=0
    else FV_MOUSE_BUTTON=$(( __fvm_lo + 1 )); fi
    if (( $1 & 32 )); then FV_MOUSE_WHAT=move
    elif (( $2 || (__fvm_lo == 3 && ! ($1 & 128)) )); then FV_MOUSE_WHAT=up
    else FV_MOUSE_WHAT=down; fi
}

# a caller's nocasematch (case would read m as M) is cleared for the call and
# restored on every return path
fv.mouse._nc() {
    local __fvm_rc=0
    shopt -u nocasematch
    "$@" || __fvm_rc=$?
    shopt -s nocasematch
    return "$__fvm_rc"
}

fv.mouse.decode() {
    if [[ $BASHOPTS == *nocasematch* ]]; then fv.mouse._nc fv.mouse.decode "$@"; return; fi
    local LC_ALL=C __fvm_r=${1-} __fvm_b __fvm_x __fvm_y __fvm_t
    FV_MOUSE_WHAT='' FV_MOUSE_BUTTON=0 FV_MOUSE_X=0 FV_MOUSE_Y=0 FV_MOUSE_MODS=0
    case $__fvm_r in
        $'\e[<'*[Mm])
            __fvm_t=${__fvm_r:3:${#__fvm_r}-4}
            if [[ $__fvm_t != *';'*';'* ]]; then __fvm_t=x; fi    # 3 fields at least
            __fvm_b=${__fvm_t%%;*} __fvm_t=${__fvm_t#*;}
            __fvm_x=${__fvm_t%%;*} __fvm_y=${__fvm_t#*;}
            if [[ $__fvm_b$__fvm_x$__fvm_y == *[!0-9]* || -z $__fvm_b || -z $__fvm_x || -z $__fvm_y \
                  || ${#__fvm_b} -gt 3 || ${#__fvm_x} -gt 5 || ${#__fvm_y} -gt 5 ]] \
               || (( 10#$__fvm_b > 255 || 10#$__fvm_x < 1 || 10#$__fvm_y < 1 )); then
                kk.debug "Error: fv.mouse.decode: malformed SGR report"
                RESULT=''
                return 1
            fi
            if [[ $__fvm_r == *m ]]; then __fvm_t=1; else __fvm_t=0; fi
            fv.mouse._bits "$(( 10#$__fvm_b ))" "$__fvm_t"
            FV_MOUSE_X=$(( 10#$__fvm_x - 1 )) FV_MOUSE_Y=$(( 10#$__fvm_y - 1 )) ;;
        $'\e[M'???)
            # one byte each: value + 32, coordinates 1-based, so 255 = column
            # 223 is the last one X10 can say (fv.keyboard stores xterm's NUL
            # past-the-end marker as \xff: the same clamp)
            __fvm_b=${__FV_MS_ORD[${__fvm_r:3:1}]-0}
            __fvm_x=${__FV_MS_ORD[${__fvm_r:4:1}]-0}
            __fvm_y=${__FV_MS_ORD[${__fvm_r:5:1}]-0}
            if (( __fvm_b < 32 || __fvm_x < 33 || __fvm_y < 33 )); then
                kk.debug "Error: fv.mouse.decode: malformed X10 report"
                RESULT=''
                return 1
            fi
            fv.mouse._bits "$(( __fvm_b - 32 ))" 0
            FV_MOUSE_X=$(( __fvm_x - 33 )) FV_MOUSE_Y=$(( __fvm_y - 33 )) ;;
        *)
            kk.debug "Error: fv.mouse.decode: not a mouse report"
            RESULT=''
            return 1 ;;
    esac
    RESULT=$FV_MOUSE_WHAT
    if (( BASH_SUBSHELL > 0 )); then printf '%s' "$RESULT"; fi
    return 0
}

# fv.mouse._emit FD SEQ — print SEQ to FD, then RESULT = SEQ. rc 2, RESULT=''
# and nothing printed when FD is not a number, not open, or not writable (the
# write fails: its message is dropped, FD's own stream is untouched). IFS is
# empty here: `>&$1` is a bare redirect target (bash 5.1 prints >&"$1" as
# &> "$1"), and a caller IFS holding digits must not split it.
fv.mouse._emit() {
    local IFS=
    if [[ -z $1 || $1 == *[!0-9]* || ${#1} -gt 4 || ! -e /dev/fd/$1 ]] \
       || ! printf '%s' "$2" >&$1 2>/dev/null; then
        kk.debug "Error: fv.mouse: '$1' is not a file descriptor open for writing"
        RESULT=''
        return 2
    fi
    RESULT=$2
}

fv.mouse.enable() {
    local __fvm_s=$'\e[?1000h\e[?1002h'
    case ${2-} in
        '') ;;
        any) __fvm_s+=$'\e[?1003h' ;;
        *) kk.debug "Error: fv.mouse.enable: mode '$2' is not 'any'"; RESULT=''; return 2 ;;
    esac
    fv.mouse._emit "${1:-1}" "$__fvm_s"$'\e[?1006h'
}

fv.mouse.disable() {
    fv.mouse._emit "${1:-1}" $'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'
}
