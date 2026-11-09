#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.keyboard.sh}../../kbool.sh" || return
kk.unit fv.keyboard || return $__kk_unit_rc

# fv.keyboard — terminal bytes -> Free Vision key names (layer L0 of kcl/fv.*).
# Port in spirit of the FPC rtl-console Keyboard unit (GetKeyEvent,
# PollKeyEvent); plain functions, no classes, no forks on any path.
# Design: kcl/docs/dev/fv/PLAN.md (P0a); API, key list, deviations: README.md.
#
#   fv.keyboard.getKeyEvent [TIMEOUT]  next key (blocks; TIMEOUT s for the
#                                      first byte, 0 = poll); rc 1 = none
#   fv.keyboard.pollKeyEvent           peek: rc 0 = a key is ready (the globals
#                                      describe it, it stays queued)
#   fv.keyboard.decode BYTES           the first key of BYTES (no fd)
#   fv.keyboard.feed BYTES             queue BYTES after everything already read
#                                      from the fd, before what it has not sent
#   fv.keyboard.flush                  drop everything queued
#
# Out: FV_KEY (name), FV_KEY_CHAR (character of kbChar / an Alt+character
# key), FV_KEY_SEQ (raw bytes), FV_KEY_LEN (bytes consumed), FV_KEY_EOF (1 =
# rc 1 came from end of file), RESULT = FV_KEY. In: FV_KEY_FD (default 0),
# FV_ESC_TIMEOUT (seconds a sequence's next byte is awaited, default 0.02).
#
# Bytes, not characters: every entry point pins LC_ALL=C locally (kcl/README
# 1.6) and clears a caller's nocasematch for the call, so `read -n1` takes one
# byte and the patterns compare bytes exactly. Every read of the fd takes ONE
# byte, so nothing is read ahead of the key being decoded; bytes read but not
# used (a malformed sequence cut by the next ESC) stay queued for the next key.

if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

declare -g FV_KEY='' FV_KEY_CHAR='' FV_KEY_SEQ='' FV_KEY_LEN=0 FV_KEY_EOF=0
declare -g FV_KEY_FD=${FV_KEY_FD:-0}
# queue: bytes from POS on are unread; NULP >= 0: a NUL byte (which a bash
# string cannot hold) sits in front of byte NULP; PK*: the key pollKeyEvent
# peeked (end, nul, values)
declare -g __FV_KB_BUF='' __FV_KB_POS=0 __FV_KB_NULP=-1
declare -g __FV_KB_PK=0 __FV_KB_PKE=0 __FV_KB_PKN=0 __FV_KB_PKK='' __FV_KB_PKC='' __FV_KB_PKS='' __FV_KB_PKL=0
declare -g __FV_KB_T=0.02 __FV_KB_TRAW=''        # validated FV_ESC_TIMEOUT, its raw value
declare -g __FV_KB_FDOK=''                       # the FV_KEY_FD value last found open
# Table values are a base name, optionally "M:" first (M = modifier bits:
# 1 Shift, 2 Alt, 4 Ctrl); the name is kb + Ctrl + Alt + Shift + base.
declare -gA __FV_KB_CTRL=() __FV_KB_CSI=() __FV_KB_SS3=() __FV_KB_ALT=()
# UTF-8 continuation byte patterns: any, and the second byte after E0 ED F0 F4
# (no overlong form, no surrogate, nothing above U+10FFFF)
declare -g __FV_KB_U8=$'[\x80-\xbf]' __FV_KB_UE0=$'[\xa0-\xbf]' __FV_KB_UED=$'[\x80-\x9f]'
declare -g __FV_KB_UF0=$'[\x90-\xbf]' __FV_KB_UF4=$'[\x80-\x8f]'

fv.keyboard._init() {
    local i c h L=ABCDEFGHIJKLMNOPQRSTUVWXYZ
    for (( i = 1; i <= 26; i++ )); do
        printf -v h '%02x' "$i"
        printf -v c "\\x$h"
        __FV_KB_CTRL[$c]=4:${L:i-1:1}
    done
    __FV_KB_CTRL[$'\x1c']=4:Backslash __FV_KB_CTRL[$'\x1d']=4:RBracket
    __FV_KB_CTRL[$'\x1e']=4:Caret __FV_KB_CTRL[$'\x1f']=4:Underscore
    __FV_KB_CTRL[$'\t']=Tab __FV_KB_CTRL[$'\r']=Enter __FV_KB_CTRL[$'\n']=Enter
    __FV_KB_CTRL[$'\b']=Back __FV_KB_CTRL[$'\x7f']=Back
    __FV_KB_CSI=(
        [A]=Up [B]=Down [C]=Right [D]=Left [H]=Home [F]=End [E]=Center [G]=Center
        [Z]=1:Tab [P]=F1 [Q]=F2 [R]=F3 [S]=F4
        [1~]=Home [7~]=Home [4~]=End [8~]=End [2~]=Ins [3~]=Del [5~]=PgUp [6~]=PgDn
        [11~]=F1 [12~]=F2 [13~]=F3 [14~]=F4 [15~]=F5 [17~]=F6 [18~]=F7 [19~]=F8
        [20~]=F9 [21~]=F10 [23~]=F11 [24~]=F12 [25~]=F13 [26~]=F14 [28~]=F15
        [29~]=F16 [31~]=F17 [32~]=F18 [33~]=F19 [34~]=F20
        ['[A']=F1 ['[B']=F2 ['[C']=F3 ['[D']=F4 ['[E']=F5
        [a]=1:Up [b]=1:Down [c]=1:Right [d]=1:Left
    )
    __FV_KB_SS3=(
        [A]=Up [B]=Down [C]=Right [D]=Left [H]=Home [F]=End [E]=Center [M]=Enter
        [P]=F1 [Q]=F2 [R]=F3 [S]=F4
        [a]=4:Up [b]=4:Down [c]=4:Right [d]=4:Left
        [t]=F5 [u]=F6 [v]=F7 [l]=F8 [w]=F9 [x]=F10 [y]=F11 [z]=F12
    )
    __FV_KB_ALT=(
        ['-']=Minus ['=']=Equal [' ']=Space ['[']=LftBrack [']']=RgtBrack
        [';']=SemiCol ["'"]=Quote ['`']=OpQuote ['\']=BkSlash [',']=Comma
        ['.']=Period ['/']=Slash
    )
}
fv.keyboard._init

# fv.keyboard._getc T — the next byte into __fvk_c: from the queue, else (live
# readers only) one byte from the fd, waiting T seconds ('' = block). rc 1 =
# none: the pending NUL is next (__FV_KB_NULP), a timeout, end of file
# (__fvk_eof=1), a closed fd (__fvk_bad=1), or a NUL just read (it becomes the
# pending one). A read that times out may still have read a byte: it is kept.
# (bash copies a function's body on each call: the rare cases of a read that
# brings no byte are fv.keyboard._nobyte)
fv.keyboard._getc() {
    if (( __fvk_i < ${#__FV_KB_BUF} && __fvk_i != __FV_KB_NULP )); then
        __fvk_c=${__FV_KB_BUF:__fvk_i:1}
        __fvk_i=$(( __fvk_i + 1 ))
        return 0
    fi
    if (( ! __fvk_live || __fvk_i == __FV_KB_NULP )); then return 1; fi
    __fvk_c='' __fvk_rc=0
    # a byte already waiting is read without -t (a timed read costs ~5x more)
    if [[ -n $1 ]] && read -t 0 -u "$FV_KEY_FD"; then
        IFS= read -r -n1 -d '' -u "$FV_KEY_FD" __fvk_c || __fvk_rc=$?
    else
        IFS= read -r -n1 -d '' ${1:+-t "$1"} -u "$FV_KEY_FD" __fvk_c || __fvk_rc=$?
    fi
    if [[ -z $__fvk_c ]]; then fv.keyboard._nobyte; return 1; fi
    __FV_KB_BUF+=$__fvk_c
    __fvk_i=$(( __fvk_i + 1 ))
}

# a read with rc __fvk_rc brought no byte: a NUL (it becomes the pending one),
# a timeout, end of file, or an fd that was closed since its check
fv.keyboard._nobyte() {
    if (( __fvk_rc == 0 )); then __FV_KB_NULP=$__fvk_i
    elif (( __fvk_rc <= 128 )); then
        if [[ -e /dev/fd/$FV_KEY_FD ]]; then __fvk_eof=1; else __fvk_bad=1; fi
    fi
}

# fv.keyboard._mod M — OR the xterm modifier parameter M (1-16 = 1 + Shift 1,
# Alt 2, Ctrl 4, Meta 8 read as Alt) into __fvk_mod; rc 1 = not a modifier
fv.keyboard._mod() {
    if [[ $1 != [1-9] && $1 != 1[0-6] ]]; then return 1; fi
    __fvk_mod=$(( __fvk_mod | (($1 - 1) & 7) | (($1 - 1) & 8 ? 2 : 0) ))
}

# fv.keyboard._parse T — decode one key from the queue (+ the fd); the first
# byte waits T. Sets FV_KEY* and __fvk_end / __fvk_nul (what consuming it
# means) in the caller's frame; rc 1 = no byte.
fv.keyboard._parse() {
    local __fvk_i=$__FV_KB_POS __fvk_c='' __fvk_rc=0 __fvk_mod=0 __fvk_base=''
    FV_KEY='' FV_KEY_CHAR=''
    if ! fv.keyboard._getc "$1"; then
        if (( __FV_KB_NULP == __FV_KB_POS )); then
            FV_KEY=kbCtrlSpace FV_KEY_SEQ='' FV_KEY_LEN=1 __fvk_end=$__FV_KB_POS __fvk_nul=1
            return 0
        fi
        return 1
    fi
    if [[ $__fvk_c == $'\e' ]]; then
        fv.keyboard._esc
    elif [[ -n ${__FV_KB_CTRL[$__fvk_c]+x} ]]; then
        __fvk_base=${__FV_KB_CTRL[$__fvk_c]}
    elif [[ $__fvk_c == [[:print:]] ]]; then
        FV_KEY=kbChar FV_KEY_CHAR=$__fvk_c
    else
        fv.keyboard._utf8
    fi
    if [[ -z $FV_KEY ]]; then
        if [[ $__fvk_base == ?:* ]]; then
            __fvk_mod=$(( __fvk_mod | ${__fvk_base:0:1} ))
            __fvk_base=${__fvk_base:2}
        fi
        FV_KEY=kb
        if (( __fvk_mod & 4 )); then FV_KEY+=Ctrl; fi
        if (( __fvk_mod & 2 )); then FV_KEY+=Alt; fi
        if (( __fvk_mod & 1 )); then FV_KEY+=Shift; fi
        FV_KEY+=$__fvk_base
    fi
    FV_KEY_LEN=$(( __fvk_i - __FV_KB_POS ))
    FV_KEY_SEQ=${__FV_KB_BUF:__FV_KB_POS:FV_KEY_LEN}
    __fvk_end=$__fvk_i __fvk_nul=0
}

# after an ESC: Esc, Alt+key, a CSI / SS3 sequence, or Alt+sequence (ESC ESC [)
fv.keyboard._esc() {
    if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbEsc; return 0; fi
    case $__fvk_c in
        '[') fv.keyboard._csi ;;
        O) fv.keyboard._ss3 ;;
        $'\e')
            if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbAltEsc; return 0; fi
            if [[ $__fvk_c == '[' ]]; then fv.keyboard._csi
            elif [[ $__fvk_c == O ]]; then fv.keyboard._ss3
            else
                __fvk_i=$(( __fvk_i - 1 )) FV_KEY=kbAltEsc
                return 0
            fi
            # Alt + a named key; anything else (a mouse report, a malformed
            # sequence) was a lone Esc in front of it
            if [[ -z $FV_KEY ]]; then __fvk_mod=$(( __fvk_mod | 2 ))
            else __fvk_i=$(( __FV_KB_POS + 1 )) FV_KEY=kbEsc; fi ;;
        [a-z]) FV_KEY=kbAlt${__fvk_c^} FV_KEY_CHAR=$__fvk_c ;;
        [A-Z0-9]) FV_KEY=kbAlt$__fvk_c FV_KEY_CHAR=$__fvk_c ;;
        *)
            if [[ -n ${__FV_KB_CTRL[$__fvk_c]+x} ]]; then
                __fvk_base=${__FV_KB_CTRL[$__fvk_c]} __fvk_mod=2
            elif [[ -n ${__FV_KB_ALT[$__fvk_c]+x} ]]; then
                FV_KEY=kbAlt${__FV_KB_ALT[$__fvk_c]} FV_KEY_CHAR=$__fvk_c
            elif [[ $__fvk_c == [[:print:]] ]]; then
                FV_KEY=kbAltChar FV_KEY_CHAR=$__fvk_c
            else
                fv.keyboard._utf8
                if [[ $FV_KEY == kbChar ]]; then FV_KEY=kbAltChar
                else __fvk_i=$(( __FV_KB_POS + 1 )) FV_KEY=kbEsc FV_KEY_CHAR=''; fi
            fi ;;
    esac
}

# after ESC [ : X10 mouse, the Linux console's ESC [ [ A, or a CSI sequence
# (parameter/intermediate bytes 0x20-0x3F, one final byte 0x40-0x7E; rxvt's
# 2$ ends on '$'). A byte outside the grammar ends it unread; > 32 bytes or a
# timeout inside it give kbUnknown.
fv.keyboard._csi() {
    local __fvk_p='' __fvk_v='' __fvk_a __fvk_m __fvk_f __fvk_k
    if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbAltLftBrack; return 0; fi
    if [[ $__fvk_c == M ]]; then
        for __fvk_k in 1 2 3; do
            if fv.keyboard._getc "$__FV_KB_T"; then continue; fi
            if (( __FV_KB_NULP == __fvk_i )); then
                # xterm's past-the-end coordinate is a NUL: kept as \xff, the clamp
                __FV_KB_BUF=${__FV_KB_BUF:0:__fvk_i}$'\xff'${__FV_KB_BUF:__fvk_i}
                __FV_KB_NULP=-1 __fvk_i=$(( __fvk_i + 1 ))
            else
                FV_KEY=kbUnknown
                return 0
            fi
        done
        FV_KEY=kbMouse
        return 0
    fi
    if [[ $__fvk_c == '[' ]]; then
        if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbUnknown; return 0; fi
        if [[ $__fvk_c == [A-E] ]]; then __fvk_v="[$__fvk_c" __fvk_base=${__FV_KB_CSI[$__fvk_v]}; return 0; fi
        if [[ $__fvk_c != [\ -~] ]]; then __fvk_i=$(( __fvk_i - 1 )); fi
        FV_KEY=kbUnknown
        return 0
    fi
    while [[ $__fvk_c == [\ -?] ]]; do
        if [[ $__fvk_c == '$' && -n $__fvk_p && $__fvk_p != *[!0-9]* ]]; then break; fi
        __fvk_p+=$__fvk_c
        if (( ${#__fvk_p} > 32 )); then FV_KEY=kbUnknown; return 0; fi
        if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbUnknown; return 0; fi
    done
    if [[ $__fvk_c != [@-~] && $__fvk_c != '$' ]]; then
        __fvk_i=$(( __fvk_i - 1 ))
        if [[ -z $__fvk_p ]]; then FV_KEY=kbAltLftBrack; else FV_KEY=kbUnknown; fi
        return 0
    fi
    __fvk_p+=$__fvk_c __fvk_f=$__fvk_c
    __fvk_v=${__FV_KB_CSI[$__fvk_p]-}
    if [[ -n $__fvk_v ]]; then __fvk_base=$__fvk_v; return 0; fi
    case $__fvk_p in
        '<'*[Mm]) FV_KEY=kbMouse; return 0 ;;
        *';'*)                                   # xterm: 1;5A 15;2~ (one modifier)
            __fvk_a=${__fvk_p%%;*} __fvk_m=${__fvk_p#*;}
            __fvk_m=${__fvk_m%?}
            if [[ $__fvk_a != *[!0-9]* ]]; then
                if [[ $__fvk_f == '~' ]]; then __fvk_v=${__FV_KB_CSI[$__fvk_a~]-}
                elif [[ $__fvk_a == '' || $__fvk_a == 1 ]]; then __fvk_v=${__FV_KB_CSI[$__fvk_f]-}; fi
                if [[ -n $__fvk_v ]] && fv.keyboard._mod "$__fvk_m"; then
                    __fvk_base=$__fvk_v
                    return 0
                fi
            fi ;;
        *[0-9][\$^@])                            # rxvt: 2$ Shift, 11^ Ctrl, 11@ Ctrl+Shift
            __fvk_a=${__fvk_p%?}
            if [[ $__fvk_a != *[!0-9]* ]]; then __fvk_v=${__FV_KB_CSI[$__fvk_a~]-}; fi
            if [[ -n $__fvk_v ]]; then
                case $__fvk_f in '$') __fvk_m=1 ;; '^') __fvk_m=4 ;; *) __fvk_m=5 ;; esac
                __fvk_mod=$(( __fvk_mod | __fvk_m )) __fvk_base=$__fvk_v
                return 0
            fi ;;
    esac
    FV_KEY=kbUnknown
}

# after ESC O : SS3 (application cursor keys, VT100 PF keys) with optional
# parameters: ESC O 5 P (old xterm) and ESC O 1 ; 5 P (old VTE / konsole),
# the modifier read as in a CSI
fv.keyboard._ss3() {
    local __fvk_p='' __fvk_v __fvk_m
    if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbAltO; return 0; fi
    while [[ $__fvk_c == [0-9] || $__fvk_c == ';' ]]; do
        __fvk_p+=$__fvk_c
        if (( ${#__fvk_p} > 32 )); then FV_KEY=kbUnknown; return 0; fi
        if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbUnknown; return 0; fi
    done
    __fvk_v=${__FV_KB_SS3[$__fvk_c]-}
    if [[ -z $__fvk_v ]]; then
        if [[ $__fvk_c != [\ -~] ]]; then
            __fvk_i=$(( __fvk_i - 1 ))
            if [[ -z $__fvk_p ]]; then FV_KEY=kbAltO; return 0; fi
        fi
        FV_KEY=kbUnknown
        return 0
    fi
    if [[ -n $__fvk_p ]]; then
        __fvk_m=${__fvk_p#*;}                    # "5" -> 5, "1;5" -> 5
        if [[ $__fvk_p == *';'* && ${__fvk_p%%;*} != '' && ${__fvk_p%%;*} != 1 ]] \
           || ! fv.keyboard._mod "$__fvk_m"; then
            FV_KEY=kbUnknown
            return 0
        fi
    fi
    __fvk_base=$__fvk_v
}

# a UTF-8 character from its lead byte in __fvk_c (2-4 bytes; the second byte
# range excludes overlong forms, surrogates and code points above U+10FFFF);
# a bad lead or continuation is kbUnknown, the offending byte left unread
fv.keyboard._utf8() {
    local __fvk_n __fvk_s=$__fvk_c __fvk_q=$__FV_KB_U8
    if [[ $__fvk_c == [$'\xc2'-$'\xdf'] ]]; then __fvk_n=1
    elif [[ $__fvk_c == $'\xe0' ]]; then __fvk_n=2 __fvk_q=$__FV_KB_UE0
    elif [[ $__fvk_c == $'\xed' ]]; then __fvk_n=2 __fvk_q=$__FV_KB_UED
    elif [[ $__fvk_c == [$'\xe1'-$'\xef'] ]]; then __fvk_n=2
    elif [[ $__fvk_c == $'\xf0' ]]; then __fvk_n=3 __fvk_q=$__FV_KB_UF0
    elif [[ $__fvk_c == $'\xf4' ]]; then __fvk_n=3 __fvk_q=$__FV_KB_UF4
    elif [[ $__fvk_c == [$'\xf1'-$'\xf3'] ]]; then __fvk_n=3
    else FV_KEY=kbUnknown; return 0; fi
    while (( __fvk_n > 0 )); do
        if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbUnknown; return 0; fi
        # shellcheck disable=SC2053  # the pattern is the point
        if [[ $__fvk_c != $__fvk_q ]]; then
            __fvk_i=$(( __fvk_i - 1 )) FV_KEY=kbUnknown
            return 0
        fi
        __fvk_s+=$__fvk_c __fvk_n=$(( __fvk_n - 1 )) __fvk_q=$__FV_KB_U8
    done
    FV_KEY=kbChar FV_KEY_CHAR=$__fvk_s
}

# the no-key answer of the readers: rc 1; rc 2 when the fd turned out closed
fv.keyboard._none() {
    FV_KEY=kbNoKey FV_KEY_CHAR='' FV_KEY_SEQ='' FV_KEY_LEN=0 FV_KEY_EOF=$__fvk_eof RESULT=''
    if (( __fvk_bad )); then
        __FV_KB_FDOK='' FV_KEY_EOF=0
        kk.debug "Error: fv.keyboard: FV_KEY_FD '$FV_KEY_FD' is not an open file descriptor"
        return 2
    fi
    return 1
}

# fv.keyboard._secs S — rc 0 when S is a number of seconds read -t takes as
# written: digits with one optional dot, at most 6 fractional digits (bash runs
# a finer value as -t 0: a false EOF or a phantom NUL), at most 13 characters
fv.keyboard._secs() {
    [[ -n $1 && $1 != *[!0-9.]* && $1 != *.*.* && $1 != . && $1 != *.???????* && ${#1} -le 13 ]]
}

# the checks of a reader call: FV_KEY_FD is a number, FV_ESC_TIMEOUT cached.
# An fd is open when /dev/fd/N exists (bash stats it, emulating /dev/fd where
# the OS has none); `{ true <&N; } 2>/dev/null` would be fooled, because bash
# saves fd 2 on the lowest free fd >= 10 for the redirection
fv.keyboard._ready() {
    if [[ $FV_KEY_FD != "$__FV_KB_FDOK" ]]; then        # checked once per value
        if [[ -z $FV_KEY_FD || $FV_KEY_FD == *[!0-9]* || ${#FV_KEY_FD} -gt 4 ]] \
           || [[ ! -e /dev/fd/$FV_KEY_FD ]]; then
            kk.debug "Error: fv.keyboard: FV_KEY_FD '$FV_KEY_FD' is not an open file descriptor"
            RESULT=''
            return 2
        fi
        __FV_KB_FDOK=$FV_KEY_FD
    fi
    if [[ ${FV_ESC_TIMEOUT-} == "$__FV_KB_TRAW" ]]; then return 0; fi
    __FV_KB_TRAW=${FV_ESC_TIMEOUT-} __FV_KB_T=0.02
    if fv.keyboard._secs "$__FV_KB_TRAW" && [[ $__FV_KB_TRAW == *[1-9]* ]]; then
        __FV_KB_T=$__FV_KB_TRAW
    elif [[ -n $__FV_KB_TRAW ]]; then
        kk.debug "Error: fv.keyboard: FV_ESC_TIMEOUT '$__FV_KB_TRAW' is not a positive number of seconds (at most 6 decimals); using 0.02"
    fi
}

# consume the decoded key: __fvk_end / __fvk_nul of the caller's frame
fv.keyboard._commit() {
    __FV_KB_POS=$__fvk_end
    if (( __fvk_nul )); then __FV_KB_NULP=-1; fi
    if (( __FV_KB_POS >= ${#__FV_KB_BUF} && __FV_KB_NULP < 0 )); then
        __FV_KB_BUF='' __FV_KB_POS=0
    elif (( __FV_KB_POS > 4096 )); then
        if (( __FV_KB_NULP >= 0 )); then __FV_KB_NULP=$(( __FV_KB_NULP - __FV_KB_POS )); fi
        __FV_KB_BUF=${__FV_KB_BUF:__FV_KB_POS} __FV_KB_POS=0
    fi
    RESULT=$FV_KEY
}

# A caller's nocasematch would make [[ == ]] and case compare bytes without
# case: each entry point runs itself again through fv.keyboard._nc, which
# clears it for the call and restores it on every return path.
fv.keyboard._nc() {
    local __fvk_r=0
    shopt -u nocasematch
    "$@" || __fvk_r=$?
    shopt -s nocasematch
    return "$__fvk_r"
}

fv.keyboard.getKeyEvent() {
    if [[ $BASHOPTS == *nocasematch* ]]; then fv.keyboard._nc fv.keyboard.getKeyEvent "$@"; return; fi
    local LC_ALL=C __fvk_end=0 __fvk_nul=0 __fvk_live=1 __fvk_eof=0 __fvk_bad=0 __fvk_t=''
    FV_KEY_EOF=0
    if (( __FV_KB_PK )); then
        FV_KEY=$__FV_KB_PKK FV_KEY_CHAR=$__FV_KB_PKC FV_KEY_SEQ=$__FV_KB_PKS FV_KEY_LEN=$__FV_KB_PKL
        __fvk_end=$__FV_KB_PKE __fvk_nul=$__FV_KB_PKN __FV_KB_PK=0
        fv.keyboard._commit
        return 0
    fi
    if (( $# )); then
        if ! fv.keyboard._secs "$1"; then
            kk.debug "Error: fv.keyboard.getKeyEvent: timeout '$1' is not a number of seconds (at most 6 decimals)"
            RESULT=''
            return 2
        fi
        __fvk_t=$1
    fi
    fv.keyboard._ready || return
    if [[ $__fvk_t == *[1-9]* || -z $__fvk_t ]]; then :
    elif (( __FV_KB_POS >= ${#__FV_KB_BUF} && __FV_KB_NULP < 0 )) && ! read -t 0 -u "$FV_KEY_FD"; then
        if [[ ! -e /dev/fd/$FV_KEY_FD ]]; then __fvk_bad=1; fi    # closed since its check
        fv.keyboard._none
        return
    else
        __fvk_t=''
    fi
    if fv.keyboard._parse "$__fvk_t"; then fv.keyboard._commit; return 0; fi
    fv.keyboard._none
}

fv.keyboard.pollKeyEvent() {
    if [[ $BASHOPTS == *nocasematch* ]]; then fv.keyboard._nc fv.keyboard.pollKeyEvent "$@"; return; fi
    local LC_ALL=C __fvk_end=0 __fvk_nul=0 __fvk_live=1 __fvk_eof=0 __fvk_bad=0
    FV_KEY_EOF=0
    if (( __FV_KB_PK )); then
        FV_KEY=$__FV_KB_PKK FV_KEY_CHAR=$__FV_KB_PKC FV_KEY_SEQ=$__FV_KB_PKS FV_KEY_LEN=$__FV_KB_PKL
        RESULT=$FV_KEY
        return 0
    fi
    fv.keyboard._ready || return
    if (( __FV_KB_POS >= ${#__FV_KB_BUF} && __FV_KB_NULP < 0 )) && ! read -t 0 -u "$FV_KEY_FD"; then
        if [[ ! -e /dev/fd/$FV_KEY_FD ]]; then __fvk_bad=1; fi
        fv.keyboard._none
        return
    fi
    if ! fv.keyboard._parse ''; then fv.keyboard._none; return; fi
    __FV_KB_PK=1 __FV_KB_PKE=$__fvk_end __FV_KB_PKN=$__fvk_nul __FV_KB_PKK=$FV_KEY
    __FV_KB_PKC=$FV_KEY_CHAR __FV_KB_PKS=$FV_KEY_SEQ __FV_KB_PKL=$FV_KEY_LEN RESULT=$FV_KEY
}

fv.keyboard.decode() {
    if [[ $BASHOPTS == *nocasematch* ]]; then fv.keyboard._nc fv.keyboard.decode "$@"; return; fi
    local LC_ALL=C __FV_KB_BUF=${1-} __FV_KB_POS=0 __FV_KB_NULP=-1
    local __fvk_end=0 __fvk_nul=0 __fvk_live=0 __fvk_eof=0 __fvk_bad=0
    if ! fv.keyboard._parse ''; then fv.keyboard._none; return; fi
    RESULT=$FV_KEY
    if (( BASH_SUBSHELL > 0 )); then printf '%s' "$RESULT"; fi
    return 0
}

fv.keyboard.feed() {
    __FV_KB_BUF+=${1-}
    RESULT=''
}

fv.keyboard.flush() {
    __FV_KB_BUF='' __FV_KB_POS=0 __FV_KB_NULP=-1 __FV_KB_PK=0 RESULT=''
}
