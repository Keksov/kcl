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
#   fv.keyboard.layoutBase CHAR        RESULT = the US key at CHAR's position
#                                      in the keyboard layout tables (P3 3L)
#
# Out: FV_KEY (name), FV_KEY_CHAR (character of kbChar / an Alt+character
# key), FV_KEY_BASE (the base-layout key: the US key at that position, one
# lower-case ASCII character, '' when not known), FV_KEY_SEQ (raw bytes),
# FV_KEY_LEN (bytes consumed), FV_KEY_EOF (1 = rc 1 came from end of file),
# RESULT = FV_KEY. In: FV_KEY_FD (default 0), FV_ESC_TIMEOUT (seconds a
# sequence's next byte is awaited, default 0.02), FV_KBD_LAYOUT (layouts that
# win in the tables, a comma list), FV_PASTE_MAX (the bytes a bracketed
# paste keeps, default 65536).
#
# Layout-independent keys (design P3 §14): the kitty keyboard protocol's
# CSI u reports (flags 1|4) are decoded, the name from the typed key when it
# is ASCII, else from the base-layout key; its replies (CSI ? N u, the DA1
# reply CSI ? ... c) are no keys: they set __FV_KB_KITTY / __FV_KB_DA1 and a
# reader runs the hook __FV_KB_ONKITTY (fv.video's push) on a kitty reply;
# with __FV_KB_ISIG (fv.video's TUI on) a reader raises SIGINT for the
# report of Ctrl+C, which brings no 0x03 (fv.keyboard._ctl / _intr). A
# legacy ESC + non-ASCII character looks the character up in the generated
# tables (fv.keyboard.layouts.sh, loaded at the first such key; script
# letters by default, a named layout's symbols too).
#
# Bracketed paste (design P3 §4.5, 10.8; fv.video turns it on): the frame
# ESC [ 200 ~ TEXT ESC [ 201 ~ is ONE key, kbPaste, TEXT in FV_KEY_CHAR
# (fv.drivers makes it FV's evCommand cmPasteText), also when it comes in
# pieces; a pasted newline is never kbEnter.
#
# Bytes, not characters: every entry point pins LC_ALL=C locally (kcl/README
# 1.6) and clears a caller's nocasematch for the call, so `read -n1` takes one
# byte and the patterns compare bytes exactly. Every read of the fd takes ONE
# byte (a bracketed paste reads its frame in larger pieces, never past its
# end), so nothing is read ahead of the key being decoded; bytes read but not
# used (a malformed sequence cut by the next ESC) stay queued for the next key.

# the layout the locale names: the locale's character type decides as POSIX
# says (the first of LC_ALL, LC_CTYPE, LANG that is set and not empty), its
# language picks the layout; a Latin-script locale (@latin: sr_RS@latin)
# has none. Read ONCE, here, at load (inside the readers LC_ALL is C): a
# later change of the locale variables is not seen
fv.keyboard._locale() {
    local __fvk_v=${LC_ALL:-${LC_CTYPE:-${LANG-}}}
    __FV_KB_LOC=''
    if [[ $__fvk_v == *@latin* ]]; then return 0; fi
    case ${__fvk_v%%[_.@]*} in
        ru) __FV_KB_LOC=ru ;; uk) __FV_KB_LOC=ua ;; bg) __FV_KB_LOC=bg ;; el) __FV_KB_LOC=gr ;;
        he) __FV_KB_LOC=il ;; iw) __FV_KB_LOC=il ;; ar) __FV_KB_LOC=ara ;; fa) __FV_KB_LOC=ir ;;
        ka) __FV_KB_LOC=ge ;;
        hy) __FV_KB_LOC=am ;; sr) __FV_KB_LOC=rs ;; th) __FV_KB_LOC=th ;; be) __FV_KB_LOC=by ;;
        kk) __FV_KB_LOC=kz ;; mk) __FV_KB_LOC=mk ;;
    esac
}
declare -g __FV_KB_LOC=''
fv.keyboard._locale

if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

declare -g FV_KEY='' FV_KEY_CHAR='' FV_KEY_SEQ='' FV_KEY_LEN=0 FV_KEY_EOF=0 FV_KEY_BASE=''
declare -g FV_KEY_FD=${FV_KEY_FD:-0}
# queue: bytes from POS on are unread; NULP >= 0: a NUL byte (which a bash
# string cannot hold) sits in front of byte NULP; RPL 1: _parse met a reply
# (no key) the entry point consumes; PK*: the key pollKeyEvent peeked (end,
# nul, values)
declare -g __FV_KB_BUF='' __FV_KB_POS=0 __FV_KB_NULP=-1 __FV_KB_RPL=0
declare -g __FV_KB_PK=0 __FV_KB_PKE=0 __FV_KB_PKN=0 __FV_KB_PKK='' __FV_KB_PKC='' __FV_KB_PKS='' __FV_KB_PKL=0 __FV_KB_PKB=''
declare -g __FV_KB_T=0.02 __FV_KB_TRAW=''        # validated FV_ESC_TIMEOUT, its raw value
declare -g __FV_KB_PT=${__FV_KB_PT:-1}           # a bracketed paste's wait per read (s)
declare -g __FV_KB_FDOK=''                       # the FV_KEY_FD value last found open
# the kitty protocol: KITTY the flags of the last kitty reply (-1 = none
# seen), DA1 1 = a DA1 reply seen, ONKITTY a function a reader runs on each
# kitty reply (fv.video.initVideo sets it: the push; kept across a reload)
declare -g __FV_KB_KITTY=${__FV_KB_KITTY:--1} __FV_KB_DA1=${__FV_KB_DA1:-0} __FV_KB_ONKITTY=${__FV_KB_ONKITTY-}
# Ctrl+C as a CSI u report (no 0x03 byte: the tty raises no SIGINT): ISIG 1 =
# a reader raises SIGINT for it as the tty would (fv.video sets it while its
# TUI is on; kept across a reload), SIG 1 = a reader met one (raised once
# the report is consumed)
declare -g __FV_KB_ISIG=${__FV_KB_ISIG:-0} __FV_KB_SIG=0
# the layout tables: LT character -> US key (built at the first need), LTOK 1
# = built, LRAW the FV_KBD_LAYOUT it was built for, LBAD the unknown names
# already reported, DIR this file's folder (fv.keyboard.layouts.sh lives there)
declare -gA __FV_KB_LT=()
declare -g __FV_KB_LTOK=0 __FV_KB_LRAW='' __FV_KB_LBAD=' ' __FV_KB_DIR=${BASH_SOURCE[0]%/*}
if [[ $__FV_KB_DIR == "${BASH_SOURCE[0]}" ]]; then __FV_KB_DIR=.; fi
if [[ $__FV_KB_DIR != /* && $__FV_KB_DIR != [A-Za-z]:* ]]; then __FV_KB_DIR=$PWD/$__FV_KB_DIR; fi
# Table values are a base name, optionally "M:" first (M = modifier bits:
# 1 Shift, 2 Alt, 4 Ctrl); the name is kb + Ctrl + Alt + Shift + base.
declare -gA __FV_KB_CTRL=() __FV_KB_CSI=() __FV_KB_SS3=() __FV_KB_ALT=() __FV_KB_KUF=()
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
    # the kitty protocol's keypad codes: a name, or ":" + the character's code
    __FV_KB_KUF=(
        [57409]=:46 [57410]=:47 [57411]=:42 [57412]=:45 [57413]=:43 [57415]=:61 [57416]=:44
        [57414]=Enter [57417]=Left [57418]=Right [57419]=Up [57420]=Down [57421]=PgUp [57422]=PgDn
        [57423]=Home [57424]=End [57425]=Ins [57426]=Del [57427]=Center
    )
    for (( i = 0; i < 10; i++ )); do __FV_KB_KUF[$(( 57399 + i ))]=:$(( 48 + i )); done
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
# means) in the caller's frame; rc 1 = no byte, or a reply (no key:
# __FV_KB_RPL=1 and __fvk_end past it — the entry points' no-key branch
# consumes it and reads on, so a typed key pays no check for replies)
fv.keyboard._parse() {
    local __fvk_i=$__FV_KB_POS __fvk_c='' __fvk_rc=0 __fvk_mod=0 __fvk_base=''
    FV_KEY='' FV_KEY_CHAR='' FV_KEY_BASE=''
    if ! fv.keyboard._getc "$1"; then
        if (( __FV_KB_NULP == __FV_KB_POS )); then
            FV_KEY=kbCtrlSpace FV_KEY_SEQ='' FV_KEY_LEN=1 __fvk_end=$__FV_KB_POS __fvk_nul=1
            return 0
        fi
        return 1
    fi
    if [[ $__fvk_c == $'\e' ]]; then
        fv.keyboard._esc || return 1
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

# after an ESC: Esc, Alt+key, a CSI / SS3 sequence, or Alt+sequence (ESC ESC [).
# rc 1 = a reply (no key): the caller's __fvk_end past it, __FV_KB_RPL=1
fv.keyboard._esc() {
    if ! fv.keyboard._getc "$__FV_KB_T"; then FV_KEY=kbEsc; return 0; fi
    case $__fvk_c in
        '[')
            fv.keyboard._csi
            if [[ $FV_KEY == kbReply ]]; then __fvk_end=$__fvk_i __fvk_nul=0 __FV_KB_RPL=1; return 1; fi ;;
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
            # sequence, a reply, a CSI u character) was a lone Esc in front
            # of it: what decoding it set is dropped, it is read again
            if [[ -z $FV_KEY ]]; then __fvk_mod=$(( __fvk_mod | 2 ))
            else __fvk_i=$(( __FV_KB_POS + 1 )) FV_KEY=kbEsc FV_KEY_CHAR='' FV_KEY_BASE='' __FV_KB_SIG=0; fi ;;
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
                if [[ $FV_KEY == kbChar ]]; then FV_KEY=kbAltChar; fv.keyboard._lalt
                else __fvk_i=$(( __FV_KB_POS + 1 )) FV_KEY=kbEsc FV_KEY_CHAR=''; fi
            fi ;;
    esac
    return 0
}

# Alt + a non-ASCII character (FV_KEY_CHAR): the layout tables' US key for it
# -> FV_KEY kbAlt + its name, FV_KEY_BASE; not in the tables: kbAltChar stays
fv.keyboard._lalt() {
    local __fvk_b __fvk_bn=''
    if (( ! __FV_KB_LTOK )) || [[ ${FV_KBD_LAYOUT-} != "$__FV_KB_LRAW" ]]; then fv.keyboard._lload; fi
    __fvk_b=${__FV_KB_LT[$FV_KEY_CHAR]-}
    if [[ -z $__fvk_b ]]; then return 0; fi
    fv.keyboard._bname "$__fvk_b"
    if [[ -n $__fvk_bn ]]; then FV_KEY=kbAlt$__fvk_bn FV_KEY_BASE=$__fvk_b; fi
}

# fv.keyboard._bname B — the caller's __fvk_bn = the key name part of the US
# key B: F for f, 1 for 1, SemiCol for ; (FV's kbAlt names); '' for others
fv.keyboard._bname() {
    case $1 in
        [a-z]) __fvk_bn=${1^} ;;
        [A-Z0-9]) __fvk_bn=$1 ;;
        *) __fvk_bn=${__FV_KB_ALT[$1]-} ;;
    esac
}

# fv.keyboard._lload — __FV_KB_LT from fv.keyboard.layouts.sh (sourced once;
# its variants only when a name needs one): the layouts of FV_KBD_LAYOUT (a
# comma list, bg_phonetic = bg(phonetic)), then the locale's, then the default
# order (__FV_KL_ORDER); for a character in several, the first wins. A
# default layout gives its script letters (__FV_KL_D); its other characters
# (__FV_KL_S: symbols such as № € × “, Latin letters) only when FV_KBD_LAYOUT
# names it, so a Latin-layout typist's ESC § or ESC € stays kbAltChar. A
# Latin layout (us, de, fr_azerty: a file of __FV_KL_NOTAB, the name not in
# __FV_KL_VX) has no table: skipped without a word and without loading the
# variants; another unknown name: one debug line per name. rc 1 = no tables
# (the file missing)
fv.keyboard._lload() {
    local __fvk_r=${FV_KBD_LAYOUT-} __fvk_n __fvk_s='' __fvk_t __fvk_seen=' ' __fvk_e __fvk_j=0
    local -a __fvk_o=()
    __FV_KB_LTOK=1 __FV_KB_LRAW=$__fvk_r
    if [[ -z ${__FV_KL_ORDER-} ]]; then
        # (data, not a dependency: whitelisted in kcl/tests/001, KCLT_DATASRC)
        if ! source "$__FV_KB_DIR/fv.keyboard.layouts.sh" 2>/dev/null || [[ -z ${__FV_KL_ORDER-} ]]; then
            kk.debug "Error: fv.keyboard: no layout tables ($__FV_KB_DIR/fv.keyboard.layouts.sh)"
            __FV_KB_LT=()
            return 1
        fi
    fi
    while [[ -n $__fvk_r ]]; do
        __fvk_n=${__fvk_r%%,*}
        if [[ $__fvk_r == *,* ]]; then __fvk_r=${__fvk_r#*,}; else __fvk_r=''; fi
        __fvk_n=${__fvk_n// /}
        if [[ $__fvk_n == *_* && $__fvk_n != *'('* ]]; then __fvk_n="${__fvk_n%%_*}(${__fvk_n#*_})"; fi
        if [[ -n $__fvk_n ]]; then __fvk_o+=("$__fvk_n"); fi
    done
    __fvk_e=${#__fvk_o[@]}                       # the first __fvk_e: named in FV_KBD_LAYOUT
    if [[ -n $__FV_KB_LOC ]]; then __fvk_o+=("$__FV_KB_LOC"); fi
    __fvk_r="$__FV_KL_ORDER "                    # (no word splitting: the caller's IFS)
    while [[ $__fvk_r == *' '* ]]; do
        __fvk_n=${__fvk_r%%[[:blank:]]*} __fvk_r=${__fvk_r#*[[:blank:]]}
        if [[ -n $__fvk_n ]]; then __fvk_o+=("$__fvk_n"); fi
    done
    for __fvk_n in "${__fvk_o[@]}"; do
        __fvk_j=$(( __fvk_j + 1 ))
        if [[ $__fvk_seen == *" $__fvk_n "* ]]; then continue; fi
        __fvk_seen+="$__fvk_n "
        __fvk_t=${__FV_KL_D[$__fvk_n]-}
        if [[ -n $__fvk_t ]]; then
            if (( __fvk_j <= __fvk_e )) && [[ -n ${__FV_KL_S[$__fvk_n]-} ]]; then __fvk_t+=" ${__FV_KL_S[$__fvk_n]}"; fi
        else
            __fvk_r=${__fvk_n%%'('*}
            if [[ " ${__FV_KL_NOTAB-} " == *" $__fvk_r "* && " ${__FV_KL_VX-} " != *" $__fvk_n "* ]]; then continue; fi
            if [[ -z ${__FV_KL_V[*]+x} ]]; then
                local __FV_KL_ALL=1
                if ! source "$__FV_KB_DIR/fv.keyboard.layouts.sh" 2>/dev/null; then __FV_KL_ALL=0; fi
            fi
            __fvk_t=${__FV_KL_V[$__fvk_n]-}
        fi
        if [[ -z $__fvk_t ]]; then
            if [[ $__FV_KB_LBAD != *" $__fvk_n "* ]]; then
                __FV_KB_LBAD+="$__fvk_n "
                kk.debug "Error: fv.keyboard: FV_KBD_LAYOUT names '$__fvk_n', which is not in the layout tables"
            fi
            continue
        fi
        __fvk_s="$__fvk_t $__fvk_s"
    done
    __FV_KB_LT=()
    eval "__FV_KB_LT=($__fvk_s)"
}

# after ESC [ : X10 mouse, the Linux console's ESC [ [ A, or a CSI sequence
# (parameter/intermediate bytes 0x20-0x3F, one final byte 0x40-0x7E; rxvt's
# 2$ ends on '$'). A byte outside the grammar ends it unread; a timeout
# inside it gives kbUnknown; past 32 parameter bytes fv.keyboard._csilong
# takes the rest (a long DA1 reply).
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
        if (( ${#__fvk_p} > 32 )); then fv.keyboard._csilong; return 0; fi
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
    # CSI u, the replies; anything else ending in u / c goes on to the
    # arms below (rxvt's shifted arrows 1;2c, ;5c are xterm's modifier form)
    if [[ $__fvk_p == *[uc] ]] && fv.keyboard._csix; then return 0; fi
    case $__fvk_p in
        '<'*[Mm]) FV_KEY=kbMouse; return 0 ;;
        200~) fv.keyboard._paste; return 0 ;;                     # bracketed paste
        '27;'*';'*'~') if fv.keyboard._csix; then return 0; fi ;;   # modifyOtherKeys
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

# after CSI 200 ~ (bracketed paste, design P3 §4.5, 10.8): the text up to
# CSI 201 ~ is one key, FV_KEY=kbPaste with the text in FV_KEY_CHAR (bytes as
# they came; at most FV_PASTE_MAX bytes, default 65536: the rest is read and
# dropped, one debug line, an incomplete UTF-8 sequence at the cut dropped
# too). The frame may come in pieces: what is queued first, then (live
# readers) the fd into the queue — up to the next ESC, and after an ESC that
# may begin the end the bytes the end still needs — each read waiting at most
# __FV_KB_PT s. A frame whose end does not come in time (a timeout, the end
# of input, decode's bytes ending inside it) ends there with the text so far
fv.keyboard._paste() {
    local __fvk_s=$__fvk_i __fvk_e=$'\e[201~' __fvk_r __fvk_x __fvk_rc __fvk_m=65536 __fvk_n __fvk_l __fvk_d=0
    if [[ -n ${FV_PASTE_MAX-} && $FV_PASTE_MAX != *[!0-9]* && ${#FV_PASTE_MAX} -le 9 ]]; then __fvk_m=$(( 10#$FV_PASTE_MAX )); fi
    __fvk_r=${__FV_KB_BUF:__fvk_s}
    while [[ $__fvk_r != *"$__fvk_e"* ]] && (( __fvk_live )); do
        __fvk_x='' __fvk_rc=0 __fvk_n=0
        for __fvk_l in 5 4 3 2 1; do
            if [[ $__fvk_r == *"${__fvk_e:0:__fvk_l}" ]]; then __fvk_n=$(( 6 - __fvk_l )); break; fi
        done
        if (( __fvk_n )); then IFS= read -r -N "$__fvk_n" -t "$__FV_KB_PT" -u "$FV_KEY_FD" __fvk_x || __fvk_rc=$?
        else
            IFS= read -r -d $'\e' -t "$__FV_KB_PT" -u "$FV_KEY_FD" __fvk_x || __fvk_rc=$?
            if (( ! __fvk_rc )); then __fvk_x+=$'\e'; fi
        fi
        __fvk_r+=$__fvk_x
        # (past the cap: the head kept, plus the last bytes, which may begin the end)
        if (( ${#__fvk_r} > __fvk_m + 64 )); then __fvk_r=${__fvk_r:0:__fvk_m}${__fvk_r: -6} __fvk_d=1; fi
        # (a timeout that still brought bytes: the frame is still coming —
        # a long paste through a pipe is read a byte per system call)
        if (( __fvk_rc > 128 )) && [[ -n $__fvk_x ]]; then continue; fi
        if (( __fvk_rc )); then break; fi
    done
    __FV_KB_BUF=${__FV_KB_BUF:0:__fvk_s}$__fvk_r
    if [[ $__fvk_r == *"$__fvk_e"* ]]; then
        __fvk_x=${__fvk_r%%"$__fvk_e"*}
        __fvk_i=$(( __fvk_s + ${#__fvk_x} + 6 ))
    else
        __fvk_x=$__fvk_r __fvk_i=${#__FV_KB_BUF}
    fi
    if (( __FV_KB_NULP >= __fvk_s && __FV_KB_NULP < __fvk_i )); then __FV_KB_NULP=-1; fi
    if (( __fvk_d || ${#__fvk_x} > __fvk_m )); then
        kk.debug "fv.keyboard: a paste of more than $__fvk_m bytes cut to $__fvk_m (FV_PASTE_MAX)"
        __fvk_x=${__fvk_x:0:__fvk_m}
        fv.keyboard._pcut
    fi
    FV_KEY=kbPaste FV_KEY_CHAR=$__fvk_x
}
# (the caller's cut paste __fvk_x: an incomplete UTF-8 sequence at its end dropped)
fv.keyboard._pcut() {
    local __fvk_k=0 __fvk_c __fvk_n
    while (( __fvk_k < 3 && ${#__fvk_x} > __fvk_k + 1 )); do
        __fvk_c=${__fvk_x: -1-__fvk_k:1}
        # shellcheck disable=SC2053  # the pattern is the point
        if [[ $__fvk_c != $__FV_KB_U8 ]]; then break; fi
        __fvk_k=$(( __fvk_k + 1 ))
    done
    if (( ! ${#__fvk_x} )); then return 0; fi
    __fvk_c=${__fvk_x: -1-__fvk_k:1}
    if [[ $__fvk_c == [$'\xc2'-$'\xdf'] ]]; then __fvk_n=1
    elif [[ $__fvk_c == [$'\xe0'-$'\xef'] ]]; then __fvk_n=2
    elif [[ $__fvk_c == [$'\xf0'-$'\xf4'] ]]; then __fvk_n=3
    else return 0; fi
    if (( __fvk_k < __fvk_n )); then __fvk_x=${__fvk_x:0:${#__fvk_x}-1-__fvk_k}; fi
}

# a CSI longer than _csi keeps (its 33 parameter bytes in the caller's
# __fvk_p): the rest up to the final byte, at most 256 bytes in all (rare:
# the DA1 replies of Windows Terminal and xterm's decTerminalID 525 are 33-40
# bytes). A ? run ending in c or u goes to fv.keyboard._reply (a reply, or
# kbUnknown when malformed), anything else is kbUnknown, consumed exactly; a
# byte outside the grammar ends it unread; a timeout or 256 bytes without a
# final byte give kbUnknown there
fv.keyboard._csilong() {
    while fv.keyboard._getc "$__FV_KB_T"; do
        if [[ $__fvk_c == [@-~] ]]; then
            __fvk_p+=$__fvk_c __fvk_f=$__fvk_c
            if [[ $__fvk_p == '?'*[uc] ]]; then fv.keyboard._reply; else FV_KEY=kbUnknown; fi
            return 0
        fi
        if [[ $__fvk_c != [\ -?] ]]; then __fvk_i=$(( __fvk_i - 1 )); break; fi
        __fvk_p+=$__fvk_c
        if (( ${#__fvk_p} >= 256 )); then break; fi
    done
    FV_KEY=kbUnknown
}

# the caller's (_csi) parameters + final __fvk_p ending in u or c, or xterm's
# modifyOtherKeys 27;MOD;CODE~ (rare paths, kept out of _csi's body): a reply
# (CSI ? ... u / c), a CSI u report; rc 1 = neither (the caller says kbUnknown)
fv.keyboard._csix() {
    local __fvk_x=${__fvk_p##*;} __fvk_y=${__fvk_p#27;}
    case $__fvk_p in
        '?'*) fv.keyboard._reply ;;
        *u) fv.keyboard._csiu "${__fvk_p%u}" ;;
        *'~') fv.keyboard._csiu "${__fvk_x%'~'};${__fvk_y%%;*}" ;;
        *) return 1 ;;
    esac
}

# a reply to a query fv.video sent (design §14.4): CSI ? FLAGS u (the kitty
# protocol is there) or the DA1 reply CSI ? ... c — no key: FV_KEY=kbReply,
# which every entry point skips. A kitty reply read by a reader (not decode)
# runs the hook __FV_KB_ONKITTY (fv.video's push of the flags)
fv.keyboard._reply() {
    local __fvk_r=${__fvk_p:1:${#__fvk_p}-2}
    if [[ $__fvk_f == u ]]; then
        if [[ -z $__fvk_r || $__fvk_r == *[!0-9]* || ${#__fvk_r} -gt 5 ]]; then FV_KEY=kbUnknown; return 0; fi
        __FV_KB_KITTY=$(( 10#$__fvk_r ))
        if (( __fvk_live )) && [[ -n $__FV_KB_ONKITTY ]]; then "$__FV_KB_ONKITTY" || :; fi
    else
        if [[ $__fvk_r == *[!0-9\;]* ]]; then FV_KEY=kbUnknown; return 0; fi
        __FV_KB_DA1=1
    fi
    FV_KEY=kbReply
}

# fv.keyboard._csiu P — a CSI u report (the kitty keyboard protocol, flags
# 1|4; xterm's formatOtherKeys and modifyOtherKeys come here too) with the
# parameters P = CODE[:SHIFTED[:BASE]][;MODS[:EVENT][;TEXT]]. rc 1 = not that
# grammar (the caller says kbUnknown). A named key sets the caller's
# __fvk_base / __fvk_mod; else FV_KEY: kbChar (no Alt / Ctrl), kbAltChar,
# kbUnknown, kbReply (a release: no key). The typed character (the shifted
# key under Shift) goes to FV_KEY_CHAR, the base key to FV_KEY_BASE (the
# report's, else the code when ASCII, else the layout tables). The name comes
# from the code when it is ASCII (AZERTY's Alt+A is kbAltA, as a legacy
# terminal says), else from the base key; Shift is in the character for
# character keys (Alt+Shift+F is kbAltF, as ESC F).
fv.keyboard._csiu() {
    local __fvk_k=${1%%;*} __fvk_m=1 __fvk_e=1 __fvk_s='' __fvk_b='' __fvk_x __fvk_n __fvk_u='' __fvk_bn=''
    if [[ $1 == *';'* ]]; then
        __fvk_m=${1#*;} __fvk_m=${__fvk_m%%;*}
        if [[ $__fvk_m == *:* ]]; then __fvk_e=${__fvk_m#*:} __fvk_m=${__fvk_m%%:*}; fi
    fi
    __fvk_n=${__fvk_k%%:*}
    if [[ $__fvk_k == *:* ]]; then
        __fvk_x=${__fvk_k#*:} __fvk_s=${__fvk_k#*:} __fvk_s=${__fvk_s%%:*}
        if [[ $__fvk_x == *:* ]]; then __fvk_b=${__fvk_x#*:}; fi
    fi
    if [[ -z $__fvk_n || -z $__fvk_m || -z $__fvk_e || "$__fvk_n$__fvk_s$__fvk_b$__fvk_m$__fvk_e" == *[!0-9]* ]] \
       || (( ${#__fvk_n} > 7 || ${#__fvk_s} > 7 || ${#__fvk_b} > 7 || ${#__fvk_m} > 3 || ${#__fvk_e} > 1 )); then
        return 1
    fi
    __fvk_n=$(( 10#$__fvk_n )) __fvk_m=$(( 10#$__fvk_m ))
    if (( __fvk_m < 1 || __fvk_n > 1114111 )); then return 1; fi
    if (( __fvk_e == 3 )); then FV_KEY=kbReply; return 0; fi
    __fvk_x=$(( __fvk_m - 1 ))
    if (( __fvk_x & 24 )); then FV_KEY=kbUnknown; return 0; fi         # Super, Hyper: no FV key
    __fvk_mod=$(( (__fvk_x & 7) | (__fvk_x & 32 ? 2 : 0) ))             # Meta as Alt; locks ignored
    case $__fvk_n in
        27) __fvk_base=Esc; return 0 ;;
        13) __fvk_base=Enter; return 0 ;;
        9) __fvk_base=Tab; return 0 ;;
        127) __fvk_base=Back; return 0 ;;
        8) __fvk_base=Back; return 0 ;;
    esac
    if (( __fvk_n >= 57344 && __fvk_n <= 63743 )); then             # the protocol's functional keys
        if (( __fvk_n >= 57376 && __fvk_n <= 57398 )); then __fvk_base=F$(( __fvk_n - 57363 )); return 0; fi
        __fvk_x=${__FV_KB_KUF[$__fvk_n]-}
        if [[ -z $__fvk_x ]]; then FV_KEY=kbUnknown; return 0; fi
        if [[ $__fvk_x != :* ]]; then __fvk_base=$__fvk_x; return 0; fi
        __fvk_n=${__fvk_x#:} __fvk_s='' __fvk_b=''                      # a keypad character
    fi
    if (( __fvk_n < 32 || (__fvk_n >= 127 && __fvk_n < 160) )); then FV_KEY=kbUnknown; return 0; fi
    __fvk_x=$__fvk_n
    if (( __fvk_mod & 1 )); then
        if [[ -n $__fvk_s ]]; then __fvk_x=$(( 10#$__fvk_s ))
        elif (( __fvk_n >= 97 && __fvk_n <= 122 )); then __fvk_x=$(( __fvk_n - 32 )); fi
        # (a shifted field that is a control code: no character)
        if (( __fvk_x < 32 || (__fvk_x >= 127 && __fvk_x < 160) )); then FV_KEY=kbUnknown; return 0; fi
    fi
    fv.keyboard._u8 "$__fvk_x"
    if [[ -z $__fvk_u ]]; then FV_KEY=kbUnknown; return 0; fi
    FV_KEY_CHAR=$__fvk_u
    if [[ -n $__fvk_b ]]; then
        __fvk_b=$(( 10#$__fvk_b ))
        if (( __fvk_b > 32 && __fvk_b < 127 )); then fv.keyboard._u8 "$__fvk_b"; FV_KEY_BASE=${__fvk_u,,}; fi
    elif (( __fvk_n < 127 )); then
        if (( __fvk_n > 32 )); then fv.keyboard._u8 "$__fvk_n"; FV_KEY_BASE=${__fvk_u,,}; fi
    else
        fv.keyboard._u8 "$__fvk_n"
        if (( ! __FV_KB_LTOK )) || [[ ${FV_KBD_LAYOUT-} != "$__FV_KB_LRAW" ]]; then fv.keyboard._lload; fi
        FV_KEY_BASE=${__FV_KB_LT[$__fvk_u]-}
    fi
    if (( ! (__fvk_mod & 6) )); then FV_KEY=kbChar; return 0; fi
    # the name: the typed character when ASCII (Alt+Shift+1 types !: kbAltChar,
    # as ESC !), else the code when ASCII, else the base key
    if (( __fvk_x < 127 )); then __fvk_k=$FV_KEY_CHAR
    elif (( __fvk_n < 127 )); then fv.keyboard._u8 "$__fvk_n"; __fvk_k=$__fvk_u
    else __fvk_k=$FV_KEY_BASE; fi
    if [[ $__fvk_k == ' ' ]]; then __fvk_bn=Space
    elif (( (__fvk_mod & 6) == 4 )) && [[ $__fvk_k == '\' ]]; then __fvk_bn=Backslash
    elif (( (__fvk_mod & 6) == 4 )) && [[ $__fvk_k == ']' ]]; then __fvk_bn=RBracket
    elif [[ -n $__fvk_k ]]; then fv.keyboard._bname "$__fvk_k"; fi
    if [[ -z $__fvk_bn ]]; then
        if (( __fvk_mod & 4 )); then FV_KEY=kbUnknown; else FV_KEY=kbAltChar; fi
        return 0
    fi
    if (( __fvk_mod == 4 )) && [[ $__fvk_bn == [CHIJM] || $__fvk_bn == LftBrack ]]; then fv.keyboard._ctl; return 0; fi
    __fvk_mod=$(( __fvk_mod & 6 )) __fvk_base=$__fvk_bn
}

# Ctrl alone + C, H, I, J, M or [ as a CSI u report (_csiu's __fvk_bn): what
# a legacy terminal makes of them. H I J M [ are the control codes 0x08 0x09
# 0x0A 0x0D 0x1B there: kbBack, kbTab, kbEnter, kbEnter, kbEsc (FV_KEY_CHAR
# and FV_KEY_BASE empty, as for those bytes), so an application sees one
# key whatever the terminal. C is 0x03, the tty's interrupt (fv.video keeps
# ISIG): with __FV_KB_ISIG (fv.video's TUI on) a reader answers no key
# (kbReply) and raises SIGINT once the report is consumed (fv.keyboard._intr);
# else it is kbCtrlC
fv.keyboard._ctl() {
    case $__fvk_bn in
        C)
            __fvk_base=C
            if (( __fvk_live && __FV_KB_ISIG )); then FV_KEY=kbReply __FV_KB_SIG=1; fi
            return 0 ;;
        [MJ]) __fvk_base=Enter ;;
        I) __fvk_base=Tab ;;
        H) __fvk_base=Back ;;
        *) __fvk_base=Esc ;;
    esac
    __fvk_mod=0 FV_KEY_CHAR='' FV_KEY_BASE=''
}

# a reader consumed Ctrl+C as a CSI u report with fv.video's TUI on: SIGINT
# to this process group, as the tty sends it for a typed 0x03 (ISIG) to its
# foreground process group. A process that reads the terminal is in that
# group, and so is all a typed Ctrl+C reaches: the TUI's shell (fv.video's
# INT trap restores the terminal, then the process dies of SIGINT, 130), its
# children, D13's reader and watchdog (they ignore INT) and, without job
# control, the shell that started it. kill $$ / $BASHPID would reach the one
# shell only. No fork (kill is a builtin)
fv.keyboard._intr() {
    __FV_KB_SIG=0
    kill -INT 0 2>/dev/null || :
}

# fv.keyboard._u8 N — the caller's __fvk_u = code point N in UTF-8 (bytes:
# the entry points run in C); '' for a surrogate or N > U+10FFFF
fv.keyboard._u8() {
    local __fvk_e
    if (( $1 < 128 )); then printf -v __fvk_e '\\x%02x' "$1"
    elif (( $1 < 2048 )); then printf -v __fvk_e '\\x%02x\\x%02x' "$(( 192 | $1 >> 6 ))" "$(( 128 | ($1 & 63) ))"
    elif (( $1 >= 55296 && $1 <= 57343 )) || (( $1 > 1114111 )); then __fvk_u=''; return 0
    elif (( $1 < 65536 )); then
        printf -v __fvk_e '\\x%02x\\x%02x\\x%02x' "$(( 224 | $1 >> 12 ))" "$(( 128 | ($1 >> 6 & 63) ))" "$(( 128 | ($1 & 63) ))"
    else
        printf -v __fvk_e '\\x%02x\\x%02x\\x%02x\\x%02x' "$(( 240 | $1 >> 18 ))" "$(( 128 | ($1 >> 12 & 63) ))" \
            "$(( 128 | ($1 >> 6 & 63) ))" "$(( 128 | ($1 & 63) ))"
    fi
    printf -v __fvk_u "$__fvk_e"
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
    FV_KEY=kbNoKey FV_KEY_CHAR='' FV_KEY_BASE='' FV_KEY_SEQ='' FV_KEY_LEN=0 FV_KEY_EOF=$__fvk_eof RESULT='' __FV_KB_RPL=0
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
        __fvk_end=$__FV_KB_PKE __fvk_nul=$__FV_KB_PKN __FV_KB_PK=0 FV_KEY_BASE=$__FV_KB_PKB
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
    if (( __FV_KB_RPL )) && fv.keyboard._again "${1-}"; then return 0; fi
    fv.keyboard._none
}

# fv.keyboard._again T — _parse met a reply (__FV_KB_RPL): consume it and
# take the next key in its place. T is the caller's TIMEOUT: '' (blocking)
# waits for it; any other value takes it only when bytes are queued or
# waiting (a reply never makes a timed call or a poll wait twice, or block).
# rc 1 = none
fv.keyboard._again() {
    while (( __FV_KB_RPL )); do
        __FV_KB_RPL=0
        fv.keyboard._commit
        if (( __FV_KB_SIG )); then fv.keyboard._intr; fi
        if [[ -n $1 ]] && (( __FV_KB_POS >= ${#__FV_KB_BUF} && __FV_KB_NULP < 0 )) && ! read -t 0 -u "$FV_KEY_FD"; then
            return 1
        fi
        if fv.keyboard._parse ''; then fv.keyboard._commit; return 0; fi
    done
    return 1
}

fv.keyboard.pollKeyEvent() {
    if [[ $BASHOPTS == *nocasematch* ]]; then fv.keyboard._nc fv.keyboard.pollKeyEvent "$@"; return; fi
    local LC_ALL=C __fvk_end=0 __fvk_nul=0 __fvk_live=1 __fvk_eof=0 __fvk_bad=0
    FV_KEY_EOF=0
    if (( __FV_KB_PK )); then
        FV_KEY=$__FV_KB_PKK FV_KEY_CHAR=$__FV_KB_PKC FV_KEY_SEQ=$__FV_KB_PKS FV_KEY_LEN=$__FV_KB_PKL
        FV_KEY_BASE=$__FV_KB_PKB RESULT=$FV_KEY
        return 0
    fi
    fv.keyboard._ready || return
    while :; do
        if (( __FV_KB_POS >= ${#__FV_KB_BUF} && __FV_KB_NULP < 0 )) && ! read -t 0 -u "$FV_KEY_FD"; then
            if [[ ! -e /dev/fd/$FV_KEY_FD ]]; then __fvk_bad=1; fi
            fv.keyboard._none
            return
        fi
        if fv.keyboard._parse ''; then break; fi
        if (( ! __FV_KB_RPL )); then fv.keyboard._none; return; fi
        __FV_KB_RPL=0                           # a reply: consumed, not peeked
        fv.keyboard._commit
        if (( __FV_KB_SIG )); then fv.keyboard._intr; fi
    done
    __FV_KB_PK=1 __FV_KB_PKE=$__fvk_end __FV_KB_PKN=$__fvk_nul __FV_KB_PKK=$FV_KEY __FV_KB_PKB=$FV_KEY_BASE
    __FV_KB_PKC=$FV_KEY_CHAR __FV_KB_PKS=$FV_KEY_SEQ __FV_KB_PKL=$FV_KEY_LEN RESULT=$FV_KEY
}

fv.keyboard.decode() {
    if [[ $BASHOPTS == *nocasematch* ]]; then fv.keyboard._nc fv.keyboard.decode "$@"; return; fi
    local LC_ALL=C __FV_KB_BUF=${1-} __FV_KB_POS=0 __FV_KB_NULP=-1
    local __fvk_end=0 __fvk_nul=0 __fvk_live=0 __fvk_eof=0 __fvk_bad=0
    if ! fv.keyboard._parse '' && ! fv.keyboard._dskip; then fv.keyboard._none; return; fi
    RESULT=$FV_KEY
    if (( BASH_SUBSHELL > 0 )); then printf '%s' "$RESULT"; fi
    return 0
}

# decode met a reply (__FV_KB_RPL): skip it (and the next ones), the key
# after them; rc 1 = none
fv.keyboard._dskip() {
    while (( __FV_KB_RPL )); do
        __FV_KB_RPL=0 __FV_KB_POS=$__fvk_end
        if fv.keyboard._parse ''; then return 0; fi
    done
    return 1
}

fv.keyboard.feed() {
    __FV_KB_BUF+=${1-}
    RESULT=''
}

fv.keyboard.flush() {
    __FV_KB_BUF='' __FV_KB_POS=0 __FV_KB_NULP=-1 __FV_KB_PK=0 RESULT=''
}

# fv.keyboard.layoutBase CHAR — RESULT = the US key at CHAR's position in the
# layout tables (FV_KBD_LAYOUT, then the locale's layout, then the default
# order; loaded at the first call or the first legacy Alt + non-ASCII key);
# rc 1 = CHAR is in no table (RESULT ''), rc 2 = no CHAR. Inside $( ) it
# prints RESULT (kcl README §1.1)
fv.keyboard.layoutBase() {
    if (( $# != 1 )) || [[ -z $1 ]]; then
        kk.debug "Error: fv.keyboard.layoutBase: one character expected"
        RESULT=''
        return 2
    fi
    local LC_ALL=C
    if (( ! __FV_KB_LTOK )) || [[ ${FV_KBD_LAYOUT-} != "$__FV_KB_LRAW" ]]; then fv.keyboard._lload; fi
    RESULT=${__FV_KB_LT[$1]-}
    if (( BASH_SUBSHELL > 0 )); then printf '%s' "$RESULT"; fi
    [[ -n $RESULT ]]
}
