#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.video.sh}../../kbool.sh" || return
kk.unit fv.video || return $__kk_unit_rc

# fv.video — the terminal (layer L0 of kcl/fv.*): raw mode, alternate screen,
# hidden cursor, autowrap off, the screen size and the resize flag, all put
# back on every exit path. Port in spirit of the FPC rtl-console Video unit
# (InitVideo, DoneVideo, ScreenWidth / ScreenHeight); plain functions, no
# classes. Layer L1, the screen buffer (VideoBuf + UpdateScreen: writes,
# palette, damage diff), is the second half of this file. Design:
# kcl/docs/dev/fv/PLAN.md (P0b, P1); API, exit paths, deviations: README.md.
#
#   fv.video.initVideo [noalt]  open the terminal (FV_TTY, default /dev/tty)
#                               on its own fd, raw mode, alternate screen
#                               (not with noalt), traps that restore it
#   fv.video.doneVideo          restore the terminal and the caller's traps
#   fv.video.updateSize         FV_SCREEN_W / FV_SCREEN_H from querySize, then
#                               COLUMNS / LINES, then 80x24; clears
#                               FV_VIDEO_RESIZED
#   fv.video.querySize          the size source, RESULT = "ROWS COLS" (default
#                               `stty size` on the terminal; override it)
#
# Out: FV_SCREEN_W, FV_SCREEN_H, FV_VIDEO_ON (1 between init and done),
# FV_VIDEO_RESIZED (1 after SIGWINCH), FV_TTY_FD (the terminal's fd, '' when
# off). FV_KEY_FD is set to FV_TTY_FD while on and put back at done.
#
# Ctrl+C stays an interrupt (intr kept); susp, quit, lnext (and dsusp,
# discard, status, swtch where stty knows them) are undefined, so Ctrl+Z and
# Ctrl+\ arrive as keys. Nothing here ever prints to stdout: all terminal
# output goes to FV_TTY_FD, so a TUI works inside x=$(...).
#
# The TUI is owned by the process that called initVideo: in its subshells
# initVideo and doneVideo are no-ops. Only the traps active in this process
# are chained (a subshell's inherited trap texts are dropped first). The
# restore drains input still on its way (<= ~0.3 s).
#
# Forks happen at init (stty, trap -p), at done (stty) and in querySize
# (stty size: at init and per resize); the WINCH trap only sets a flag.

# kcl-wide (README §1.6): no locale variable set -> LC_CTYPE=C.UTF-8 (silent
# where that name does not exist; the buffer then finds its own, below)
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8 2>/dev/null
fi

declare -g FV_SCREEN_W=${FV_SCREEN_W:-80} FV_SCREEN_H=${FV_SCREEN_H:-24}
declare -g FV_VIDEO_ON=${FV_VIDEO_ON:-0} FV_VIDEO_RESIZED=${FV_VIDEO_RESIZED:-0} FV_TTY_FD=${FV_TTY_FD-}
# ACT: a restore is owed; FD/ALT/SAVED: the terminal's fd, the alternate
# screen in use, its `stty -g`; KSET/KFD: FV_KEY_FD before init (set?, value);
# UNDEF: the special characters to undefine (probed once per process); TP:
# the caller's `trap -p` per signal; PREV: the caller's handler text; XRAN:
# the caller's EXIT handler already ran; PID: the process that called
# initVideo, the owner of the TUI (a subshell inherits the state, not the
# ownership)
declare -g __FV_VI_ACT=${__FV_VI_ACT:-0} __FV_VI_FD=${__FV_VI_FD-} __FV_VI_ALT=${__FV_VI_ALT:-1}
declare -g __FV_VI_SAVED=${__FV_VI_SAVED-} __FV_VI_KSET=${__FV_VI_KSET-} __FV_VI_KFD=${__FV_VI_KFD-}
declare -g __FV_VI_XRAN=${__FV_VI_XRAN:-0} __FV_VI_PID=${__FV_VI_PID-}
declare -ga __FV_VI_UNDEF
__FV_VI_UNDEF+=()
declare -gA __FV_VI_TP=() __FV_VI_PREV=()
declare -ga __FV_VI_SIGS=(EXIT INT TERM HUP WINCH)

# the caller's handlers see the status they would have seen without us
fv.video._rc() { return "$1"; }

# Every function with a bare fd redirect (`>&$fd`: bash 5.1 prints >&"$fd" as
# &> "$fd") sets `local IFS=`, so a caller IFS holding digits cannot split it.
fv.video.querySize() {
    local IFS= __fvv_s=''
    RESULT=''
    if [[ -z $FV_TTY_FD || $FV_TTY_FD == *[!0-9]* ]] || ! __fvv_s=$(stty size 2>/dev/null <&$FV_TTY_FD); then return 1; fi
    RESULT=$__fvv_s
}

# fv.video._dim VALUE ENV DEFAULT — __fvv_v = VALUE when it is a positive
# number of at most 5 digits, else ENV when it is one, else DEFAULT (and
# __fvv_why notes the fallback)
fv.video._dim() {
    local __fvv_x
    for __fvv_x in "$1" "$2"; do
        if [[ -n $__fvv_x && $__fvv_x != *[!0-9]* && ${#__fvv_x} -le 5 ]] && (( 10#$__fvv_x > 0 )); then
            __fvv_v=$(( 10#$__fvv_x ))
            if [[ $__fvv_x != "$1" ]]; then __fvv_why=1; fi
            return 0
        fi
    done
    __fvv_v=$3 __fvv_why=1
}

fv.video.updateSize() {
    local __fvv_r='' __fvv_c='' __fvv_v=0 __fvv_why=0 __fvv_x=''
    FV_VIDEO_RESIZED=0
    if fv.video.querySize; then
        IFS=$' \t\n' read -r __fvv_r __fvv_c __fvv_x <<< "$RESULT" || :
        if [[ -n $__fvv_x || -z $__fvv_c ]]; then __fvv_r='' __fvv_c=''; fi    # two words only
    fi
    fv.video._dim "$__fvv_c" "${COLUMNS-}" 80; FV_SCREEN_W=$__fvv_v
    fv.video._dim "$__fvv_r" "${LINES-}" 24; FV_SCREEN_H=$__fvv_v
    if (( __fvv_why )); then
        kk.debug "Error: fv.video.updateSize: the terminal size is unknown ('$RESULT'); using ${FV_SCREEN_W}x$FV_SCREEN_H (COLUMNS/LINES, else 80x24)"
    fi
    RESULT=''
}

# fv.video._drain FD — drop the input already on its way (mouse reports sent
# before reporting went off, keys typed during the exit), so it does not land
# on the shell after us: read until 0.05 s pass without a byte, at most
# ~0.3 s or 64 KiB. Fork-free; at restore only (typed-ahead keys before init
# are the program's)
fv.video._drain() {
    local LC_ALL=C __fvv_c='' __fvv_n=0 __fvv_t0=${EPOCHREALTIME//[.,]/} __fvv_t
    while (( __fvv_n < 65536 )) && IFS= read -r -n1 -d '' -t 0.05 -u "$1" __fvv_c 2>/dev/null; do
        __fvv_n=$(( __fvv_n + 1 )) __fvv_t=${EPOCHREALTIME//[.,]/}
        if (( __fvv_t - __fvv_t0 > 300000 )); then break; fi
    done
}

# fv.video._restore [quiet] — the terminal as it was (doneVideo, the traps):
# SGR reset, autowrap, cursor, main screen, mouse reporting off and the input
# drained (none of it with quiet: a failed init printed nothing), stty, the fd
# closed, FV_KEY_FD back. Only in the process that called initVideo (a
# subshell's inherited state is its parent's). ACT is cleared after stty: a
# signal in the middle restores once more (harmless; the fd is closed once).
# Every step may fail (the terminal hung up).
fv.video._restore() {
    if (( ! __FV_VI_ACT )) || [[ $__FV_VI_PID != "$BASHPID" ]]; then return 0; fi
    local IFS= __fvv_fd=$__FV_VI_FD __fvv_s=$'\e[0m\e[?7h\e[?25h'
    if (( __FV_VI_ALT )); then __fvv_s+=$'\e[?1049l'; fi
    __fvv_s+=$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'
    if [[ -z ${1-} ]]; then
        printf '%s' "$__fvv_s" 2>/dev/null >&$__fvv_fd || :
        fv.video._drain "$__fvv_fd"
    fi
    if [[ -n $__FV_VI_SAVED ]]; then stty "$__FV_VI_SAVED" >/dev/null 2>&1 <&$__fvv_fd || :; fi
    __FV_VI_ACT=0 FV_VIDEO_ON=0
    # the screen is no longer what the buffer sent: the next frame repaints all
    __FV_VS_FORCE=1 __FV_VS_SVIS='' __FV_VS_SPOS=''
    if [[ -n $__fvv_fd && $__FV_VI_FD == "$__fvv_fd" ]]; then
        __FV_VI_FD=''
        { exec {__fvv_fd}>&-; } 2>/dev/null || :
    fi
    FV_TTY_FD=''
    if [[ -n $__FV_VI_KSET ]]; then FV_KEY_FD=$__FV_VI_KFD; else unset FV_KEY_FD; fi
}

# the caller's handler for $1 (if any), with $? as it was and no arguments.
# `_rc N ||`: a bare failing _rc would end a `set -e` caller here; the `:`
# after the handler: a handler ending in a false `a && b` (no error in a
# plain trap) must not fire errexit or ERR in ours - its real errors and its
# `exit` still do, as in plain bash
fv.video._prev() {
    local __fvv_h=${__FV_VI_PREV[$1]-}
    if [[ -z $__fvv_h ]]; then return 0; fi
    __fvv_h+=$'\n:'
    set --
    if (( ! __fvv_rc )); then eval "$__fvv_h"                # $? is 0 here
    else fv.video._rc "$__fvv_rc" || eval "$__fvv_h"; fi
}

# EXIT: restore, then the caller's EXIT handler, exactly once
fv.video._onexit() {
    local __fvv_rc=$?
    fv.video._restore
    if (( __FV_VI_XRAN )); then return 0; fi
    __FV_VI_XRAN=1
    fv.video._prev EXIT
}

# INT / TERM / HUP (SIG NUMBER): restore, the caller's handler for SIG (its
# `exit` wins), the caller's EXIT handler once, then die of SIG
fv.video._onsig() {
    local __fvv_rc=$? __fvv_sig=$1 __fvv_n=$2
    fv.video._restore
    fv.video._prev "$__fvv_sig"
    if (( ! __FV_VI_XRAN )); then
        __FV_VI_XRAN=1 __fvv_rc=$(( 128 + __fvv_n ))
        fv.video._prev EXIT
    fi
    trap - EXIT "$__fvv_sig"
    kill -"$__fvv_sig" "$BASHPID"
    exit "$(( 128 + __fvv_n ))"
}

# WINCH: only a flag (the idle loop polls it), then the caller's handler
fv.video._onwinch() {
    local __fvv_rc=$?
    FV_VIDEO_RESIZED=1
    fv.video._prev WINCH
}

# put the caller's traps back exactly as they were
fv.video._untrap() {
    local __fvv_s
    for __fvv_s in "${__FV_VI_SIGS[@]}"; do
        if [[ -n ${__FV_VI_TP[$__fvv_s]-} ]]; then eval "${__FV_VI_TP[$__fvv_s]}"; else trap - "$__fvv_s"; fi
    done
}

# In a subshell ($( ), ( ), a pipeline) `trap -p` still shows the parent's
# trap texts, which are not active there, until the subshell's first trap
# command. Re-setting an unused signal to what it is (default, or ignored)
# drops them and changes nothing; a signal with a text of its own is skipped.
fv.video._drop() {
    local __fvv_s __fvv_t
    for __fvv_s in SYS XFSZ VTALRM PROF URG; do
        __fvv_t=$(trap -p "$__fvv_s" 2>/dev/null) || continue
        if [[ -z $__fvv_t ]]; then trap - "$__fvv_s"; return 0; fi
        if [[ $__fvv_t == "trap -- '' "* ]]; then trap '' "$__fvv_s"; return 0; fi
    done
}

# save the caller's traps (only those active in this process) and set ours;
# a signal the caller ignores (trap '' SIG) stays ignored
fv.video._trap() {
    local __fvv_s __fvv_t __fvv_h
    __FV_VI_TP=() __FV_VI_PREV=() __FV_VI_XRAN=0
    if [[ $BASHPID != "$$" ]]; then fv.video._drop; fi
    for __fvv_s in "${__FV_VI_SIGS[@]}"; do
        __fvv_t=$(trap -p "$__fvv_s") || __fvv_t=''
        __fvv_h=''
        if [[ -n $__fvv_t ]]; then
            __FV_VI_TP[$__fvv_s]=$__fvv_t
            __fvv_h=${__fvv_t% *} __fvv_h=${__fvv_h#trap -- }
            eval "__fvv_h=$__fvv_h"
            __FV_VI_PREV[$__fvv_s]=$__fvv_h
        fi
        case $__fvv_s in
            EXIT) trap 'fv.video._onexit' EXIT ;;
            WINCH) trap 'fv.video._onwinch' WINCH ;;
            *)
                if [[ -n $__fvv_t && -z $__fvv_h ]]; then continue; fi
                case $__fvv_s in INT) __fvv_t=2 ;; TERM) __fvv_t=15 ;; *) __fvv_t=1 ;; esac
                # shellcheck disable=SC2064  # the signal is fixed now
                trap "fv.video._onsig $__fvv_s $__fvv_t" "$__fvv_s" ;;
        esac
    done
}

fv.video.initVideo() {
    local IFS= __fvv_alt=1 __fvv_fd='' __fvv_g='' __fvv_a='' __fvv_x __fvv_tty=${FV_TTY:-/dev/tty}
    if [ "${1-}" = noalt ]; then __fvv_alt=0                 # [ ]: exact, whatever nocasematch says
    elif [[ -n ${1-} ]]; then
        kk.debug "Error: fv.video.initVideo: mode '$1' is not 'noalt'"
        RESULT=''
        return 2
    fi
    RESULT=''
    # already on - here, or in the parent of this subshell, whose terminal
    # and FV_TTY_FD the subshell then uses
    if (( FV_VIDEO_ON || __FV_VI_ACT )); then return 0; fi
    if ! { exec {__fvv_fd}<>"$__fvv_tty"; } 2>/dev/null; then
        kk.debug "Error: fv.video.initVideo: cannot open '$__fvv_tty' (no terminal)"
        return 1
    fi
    if [[ ! -t $__fvv_fd ]] || ! __fvv_g=$(stty -g 2>/dev/null <&$__fvv_fd) || [[ -z $__fvv_g ]]; then
        { exec {__fvv_fd}>&-; } 2>/dev/null || :
        kk.debug "Error: fv.video.initVideo: '$__fvv_tty' is not a terminal stty can drive"
        return 1
    fi
    if (( ! ${#__FV_VI_UNDEF[@]} )); then               # once per process
        __fvv_a=$(stty -a 2>/dev/null <&$__fvv_fd) || __fvv_a=''
        __FV_VI_UNDEF=(susp undef quit undef lnext undef)
        for __fvv_x in dsusp discard status swtch; do
            if [[ $__fvv_a == "$__fvv_x ="* || $__fvv_a == *[!a-z]"$__fvv_x ="* ]]; then __FV_VI_UNDEF+=("$__fvv_x" undef); fi
        done
    fi
    fv.video._trap
    __FV_VI_PID=$BASHPID __FV_VI_FD=$__fvv_fd __FV_VI_ALT=$__fvv_alt __FV_VI_SAVED=$__fvv_g __FV_VI_ACT=1
    __FV_VI_KSET=${FV_KEY_FD+1} __FV_VI_KFD=${FV_KEY_FD-}
    FV_TTY_FD=$__fvv_fd FV_KEY_FD=$__fvv_fd
    if ! stty -echo -icanon -ixon min 1 time 0 "${__FV_VI_UNDEF[@]}" >/dev/null 2>&1 <&$__fvv_fd; then
        fv.video._restore quiet
        fv.video._untrap
        kk.debug "Error: fv.video.initVideo: stty cannot set raw mode on '$__fvv_tty'"
        return 1
    fi
    # never DECKPAM (ESC =): keypad ESC O p..y would read as vt100 F5-F12
    __fvv_x=$'\e[?25l\e[?7l\e[0m\e[H\e[2J'
    if (( __fvv_alt )); then __fvv_x=$'\e[?1049h'$__fvv_x; fi
    printf '%s' "$__fvv_x" 2>/dev/null >&$__fvv_fd || :
    fv.video.updateSize
    FV_VIDEO_ON=1
    # the screen was just cleared: the buffer's next frame repaints everything
    # (FPC: a fresh OldVideoBuf)
    __FV_VS_FORCE=1 __FV_VS_SVIS='' __FV_VS_SPOS=''
}

fv.video.doneVideo() {
    RESULT=''
    if (( ! __FV_VI_ACT && ! FV_VIDEO_ON )); then return 0; fi
    # the TUI is owned by the process that called initVideo: a subshell's
    # doneVideo leaves its parent's terminal alone
    if (( __FV_VI_ACT )) && [[ $__FV_VI_PID != "$BASHPID" ]]; then return 0; fi
    fv.video._restore
    fv.video._untrap
    FV_VIDEO_RESIZED=0
}

# ---------------------------------------------------------------------------
# The screen buffer (layer L1; FPC Video's VideoBuf + UpdateScreen and FV's
# TDrawBuffer writes in spirit). Per row a character string and an attribute
# string of the same length in cells, one attribute symbol per cell (one of
# [0-9A-Za-z], an index into the palette, as FV's GetColor); per row the
# damaged columns [DX1,DX2); per row a copy of what the terminal shows.
# updateScreen emits the damaged range of every row that differs from that
# copy as colour runs, then the cursor, in one printf. API: README.md,
# "Screen buffer".
#
# State (__FV_VS_*): CH / AT the rows; OCH / OAT the shown copy (unset =
# unknown); DX1 / DX2 the damage (a row is damaged when DX1 has it); WIDE the
# per-row "has a wide character" flag (0 until P1b); W / H the allocated size
# (H 0 = no screen); SP W blanks; FILL[sym] W copies of sym (built on first
# use); CX1 CY1 CX2 CY2 the clip (x2/y2 exclusive); PAL[sym] "FG BG BOLD";
# SGR[sym] its whole ESC[0;...m; N16[index] the nearest of the 16 colours
# (memoised); DEPTH 16|256; DEF the default symbol; CURX CURY CURT the cursor
# wanted; SVIS ('h' / 'l') SPOS ("X Y") the cursor shown ('' = unknown);
# FORCE the next frame repaints everything; LOC the UTF-8 locale for the calls
# of a non-UTF-8 caller ('' = none: ASCII mode); AMAP the ASCII-mode map.
#
# Locale (D11): every entry point runs with UTF-8 character semantics: a
# caller whose locale is not UTF-8 gets `local LC_ALL=$__FV_VS_LOC` for the
# call; without any UTF-8 locale the unit runs in C and stores ASCII only
# (FV_VIDEO_ASCII=1). nocasematch is cleared for the call (fv.video._g).
# "UTF-8" = both probes, a 2-byte (P, U+0436) and a 3-byte (B, U+2500)
# character, count 1: legacy CJK locales (eucJP, GBK, Big5, eucKR) pass the
# first alone.
#
# Text (fv.video._text): C0, DEL and C1 -> '?'; in UTF-8 mode every invalid
# or cut sequence -> one '?', and so is every character past U+FFFF (P1a:
# Cygwin-based bash counts those as two characters, a UTF-16 surrogate pair,
# so a buffer cell could hold half of one; P1b gives them their real width);
# the check runs on bytes (C locale) and only for text with a non-ASCII byte.
# Every write and updateScreen is fork-free; the only fork is `tput colors`
# in detectColorDepth when TERM / COLORTERM do not tell.

declare -g __FV_VS_P=$'\xd0\xb6' __FV_VS_B=$'\xe2\x94\x80' __FV_VS_CONT=$'\x01' __FV_VS_C1=$'\xc2[\x80-\x9f]'
# the UTF-8 sequences a write keeps (C-locale byte patterns): 2 bytes, 3 bytes
# without overlongs and surrogates
declare -ga __FV_VS_UV=($'[\xc2-\xdf][\x80-\xbf]' $'\xe0[\xa0-\xbf][\x80-\xbf]'
    $'[\xe1-\xec\xee\xef][\x80-\xbf][\x80-\xbf]' $'\xed[\x80-\x9f][\x80-\xbf]')
declare -g __FV_VS_SYMS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
declare -g FV_VIDEO_ASCII=${FV_VIDEO_ASCII:-0} FV_VIDEO_COLORS=${FV_VIDEO_COLORS:-256} FV_VIDEO_OUT_FD=${FV_VIDEO_OUT_FD-}
declare -g __FV_VS_W=${__FV_VS_W:-0} __FV_VS_H=${__FV_VS_H:-0} __FV_VS_SP=${__FV_VS_SP-} __FV_VS_DEF=${__FV_VS_DEF:-0}
declare -g __FV_VS_CX1=${__FV_VS_CX1:-0} __FV_VS_CY1=${__FV_VS_CY1:-0} __FV_VS_CX2=${__FV_VS_CX2:-0} __FV_VS_CY2=${__FV_VS_CY2:-0}
declare -g __FV_VS_DEPTH=${__FV_VS_DEPTH:-256} __FV_VS_FORCE=${__FV_VS_FORCE:-0} __FV_VS_LOC=${__FV_VS_LOC-}
declare -g __FV_VS_CURX=${__FV_VS_CURX:-0} __FV_VS_CURY=${__FV_VS_CURY:-0} __FV_VS_CURT=${__FV_VS_CURT:-0}
declare -g __FV_VS_SVIS=${__FV_VS_SVIS-} __FV_VS_SPOS=${__FV_VS_SPOS-}
declare -ga __FV_VS_CH __FV_VS_AT __FV_VS_OCH __FV_VS_OAT __FV_VS_DX1 __FV_VS_DX2 __FV_VS_WIDE __FV_VS_N16
declare -gA __FV_VS_FILL __FV_VS_PAL __FV_VS_SGR __FV_VS_AMAP __FV_VS_TC
# set (for set -u) without losing what a reload finds
__FV_VS_CH+=() __FV_VS_AT+=() __FV_VS_OCH+=() __FV_VS_OAT+=() __FV_VS_DX1+=() __FV_VS_DX2+=() __FV_VS_WIDE+=() __FV_VS_N16+=()
__FV_VS_FILL+=() __FV_VS_PAL+=() __FV_VS_SGR+=() __FV_VS_AMAP+=() __FV_VS_TC+=()
# the UTF-8 locale candidates; xterm's default colours 0-15 (R G B each); the
# 6x6x6 cube levels; FV's DOS colour order -> ANSI; the default palette:
# symbol 0 = FPC's DefaultAttr $07, then the 30 distinct bytes of FV's
# CAppColor in order of first appearance
declare -ga __FV_VS_LOCS=(C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8)
declare -ga __FV_VS_RGB=(0 0 0 205 0 0 0 205 0 205 205 0 0 0 238 205 0 205 0 205 205 229 229 229
    127 127 127 255 0 0 0 255 0 255 255 0 92 92 255 255 0 255 0 255 255 255 255 255)
declare -ga __FV_VS_CUBE=(0 95 135 175 215 255) __FV_VS_DOS=(0 4 2 6 1 5 3 7 8 12 10 14 9 13 11 15)
declare -ga __FV_VS_DEFPAL=(0:07 1:71 2:70 3:78 4:74 5:20 6:28 7:24 8:17 9:1F A:1A B:31 C:1E D:37 E:3F F:3A G:13 H:3E
    I:21 J:7F K:7A L:7E M:2B N:2F O:2E P:30 Q:72 R:38 S:10 T:12 U:32)

# fv.video._locok NAME — rc 0 when the locale NAME gives UTF-8 character
# semantics (silent: bash's setlocale warning goes to /dev/null; a name that
# fails leaves the C locale in place, so the test cannot be fooled)
fv.video._locok() {
    local LC_ALL=C
    { LC_ALL=$1; } 2>/dev/null
    (( ${#__FV_VS_P} == 1 && ${#__FV_VS_B} == 1 ))
}

# the first working candidate -> __FV_VS_LOC ('' when none); once at load.
# The caller's own locale name is tried first (when it is UTF-8 and the
# fixed candidates do not exist, it is the only one there is).
fv.video._findloc() {
    local __fvv_n __fvv_o=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
    local -a __fvv_l=()
    __FV_VS_LOC=''
    if [[ -n $__fvv_o ]] && (( ${#__FV_VS_P} == 1 && ${#__FV_VS_B} == 1 )); then __fvv_l=("$__fvv_o"); fi
    for __fvv_n in "${__fvv_l[@]}" "${__FV_VS_LOCS[@]}"; do
        if fv.video._locok "$__fvv_n"; then __FV_VS_LOC=$__fvv_n; return 0; fi
    done
    return 1
}
fv.video._findloc || :

# ASCII mode: forced by FV_ASCII=1, or no UTF-8 locale at all
fv.video._mode() {
    FV_VIDEO_ASCII=0 __FV_VS_TC=()
    if [[ ${FV_ASCII-} == 1 ]] || { [[ ${#__FV_VS_P}${#__FV_VS_B} != 11 ]] && [[ -z $__FV_VS_LOC ]]; }; then FV_VIDEO_ASCII=1; fi
}
fv.video._mode

# fv.video._g FUNC ARGS — FUNC with nocasematch off and a UTF-8 locale (C
# when there is none), both put back on every return path. An entry point
# runs itself through it when the caller's state needs it; __fvv_g stops the
# second round.
fv.video._g() {
    local __fvv_g=1 __fvv_rc=0 __fvv_nc=0
    if [[ $BASHOPTS == *nocasematch* ]]; then __fvv_nc=1; shopt -u nocasematch; fi
    if [[ ${#__FV_VS_P}${#__FV_VS_B} == 11 ]]; then "$@" || __fvv_rc=$?
    elif [[ -n $__FV_VS_LOC ]]; then
        local LC_ALL=$__FV_VS_LOC
        "$@" || __fvv_rc=$?
    else
        local LC_ALL=C
        "$@" || __fvv_rc=$?
    fi
    if (( __fvv_nc )); then shopt -s nocasematch; fi
    return "$__fvv_rc"
}

# fv.video._num VALUE — __fvv_v = VALUE when it is an integer (an optional
# '-', 1-7 digits, leading zeros decimal); rc 2 otherwise
fv.video._num() {
    local __fvv_d=${1#-}
    if [[ -z $__fvv_d || $__fvv_d == *[![:digit:]]* || ${#__fvv_d} -gt 7 ]]; then return 2; fi
    __fvv_v=$(( 10#$__fvv_d ))
    if [[ $1 == -* ]]; then __fvv_v=$(( -__fvv_v )); fi
}

# fv.video._xy X Y — __fvv_x / __fvv_y (fast path: plain digits); rc 2 when
# one is not an integer
fv.video._xy() {
    local __fvv_v
    if [[ -n $1 && $1 != *[![:digit:]]* && $1 != 0?* && ${#1} -lt 8 ]]; then __fvv_x=$1
    elif fv.video._num "$1"; then __fvv_x=$__fvv_v; else return 2; fi
    if [[ -n $2 && $2 != *[![:digit:]]* && $2 != 0?* && ${#2} -lt 8 ]]; then __fvv_y=$2
    elif fv.video._num "$2"; then __fvv_y=$__fvv_v; else return 2; fi
}

fv.video._bad() { local IFS=' '; kk.debug "Error: fv.video.$1: bad arguments ($2): ${*:3}"; RESULT=''; return 2; }
fv.video._noscr() { kk.debug "Error: fv.video.$1: no screen (call fv.video.initScreen first)"; RESULT=''; return 1; }

# the ASCII-mode map: box drawing U+2500-257F by class (- | = +, the
# diagonals '?'), the arrows and the square; built on first use
fv.video._amap() {
    local __fvv_p __fvv_c __fvv_i __fvv_k __fvv_h
    printf -v __fvv_p '%64s' ''
    __fvv_c='--||--||--||'${__fvv_p// /+}'--||=|'
    printf -v __fvv_p '%31s' ''
    __fvv_c+=${__fvv_p// /+}'???-|-|-|-|-|-|'
    for (( __fvv_i = 0; __fvv_i < 128; __fvv_i++ )); do
        __fvv_k=${__fvv_c:__fvv_i:1}
        if [[ $__fvv_k == '?' ]]; then continue; fi
        printf -v __fvv_h '\\xe2\\x%x\\x%x' "$(( 0x94 + __fvv_i / 64 ))" "$(( 0x80 + __fvv_i % 64 ))"
        printf -v __fvv_h '%b' "$__fvv_h"
        __FV_VS_AMAP[$__fvv_h]=$__fvv_k
    done
    for __fvv_i in 8691:^ 96b2:^ 8693:v 96bc:v 8692:'>' 96ba:'>' 8690:'<' 9784:'<' 96a0:'*'; do
        printf -v __fvv_h '%b' "\\xe2\\x${__fvv_i:0:2}\\x${__fvv_i:2:2}"
        __FV_VS_AMAP[$__fvv_h]=${__fvv_i#*:}
    done
}

# fv.video._bytes KEEP — every non-ASCII sequence of __fvv_t (its lead byte
# plus up to 3 continuation bytes, on bytes: C locale) replaced: KEEP 1 keeps
# a valid 2- or 3-byte sequence and makes anything else one '?'; KEEP 0 (ASCII
# mode) puts its map entry or '?'
fv.video._bytes() {
    local LC_ALL=C __fvv_o='' __fvv_q __fvv_c __fvv_n __fvv_b __fvv_v __fvv_p
    if (( ! $1 && ! ${#__FV_VS_AMAP[@]} )); then fv.video._amap; fi
    while [[ $__fvv_t == *[![:ascii:]]* ]]; do
        __fvv_q=${__fvv_t%%[![:ascii:]]*}
        __fvv_o+=$__fvv_q __fvv_t=${__fvv_t:${#__fvv_q}}
        __fvv_c=${__fvv_t:0:1}
        printf -v __fvv_b '%d' "'$__fvv_c"
        if (( __fvv_b >= 240 )); then __fvv_n=3; elif (( __fvv_b >= 224 )); then __fvv_n=2
        elif (( __fvv_b >= 192 )); then __fvv_n=1; else __fvv_n=0; fi
        while (( __fvv_n-- > 0 )) && [[ -n ${__fvv_t:${#__fvv_c}:1} ]]; do
            printf -v __fvv_b '%d' "'${__fvv_t:${#__fvv_c}:1}"
            if (( __fvv_b < 128 || __fvv_b >= 192 )); then break; fi
            __fvv_c=${__fvv_t:0:${#__fvv_c}+1}
        done
        if (( $1 )); then
            __fvv_v='?'
            for __fvv_p in "${__FV_VS_UV[@]}"; do
                if [[ $__fvv_c == $__fvv_p ]]; then __fvv_v=$__fvv_c; break; fi
            done
            __fvv_o+=$__fvv_v
        else
            __fvv_o+=${__FV_VS_AMAP[$__fvv_c]:-?}
        fi
        __fvv_t=${__fvv_t:${#__fvv_c}}
    done
    __fvv_t=$__fvv_o$__fvv_t
}

# __fvv_t ready to store: every C0, DEL and C1 character -> '?'; in ASCII
# mode (or a C-locale call) every non-ASCII character -> ASCII; in UTF-8 mode
# every invalid, cut or 4-byte sequence -> one '?'. The writes call it only
# for text with a non-printable or a non-ASCII character. All of it runs on
# bytes (C locale: no collation, no mbrtowc quirk; [[:cntrl:]] is 0-31 and
# 127 there). UTF-8 mode: C1 (C2 80-9F) -> '?'; when removing every valid 2-
# and 3-byte sequence leaves a non-ASCII byte, the slow pass (_bytes 1)
# fixes the text.
#
# The answers are cached (__FV_VS_TC, raw text -> stored text, at most 512
# entries, emptied when full and by initScreen): a TUI redraws the same
# strings again and again. Printable ASCII never gets here, so no key is "@" or "*".
fv.video._text() {
    if [[ -n ${__FV_VS_TC[$__fvv_t]+x} ]]; then __fvv_t=${__FV_VS_TC[$__fvv_t]}; return 0; fi
    local __fvv_u=0 __fvv_s __fvv_p __fvv_k=$__fvv_t
    if [[ ${#__FV_VS_P}${#__FV_VS_B} == 11 ]] && (( ! FV_VIDEO_ASCII )); then __fvv_u=1; fi
    local LC_ALL=C
    if [[ $__fvv_t == *[[:cntrl:]]* ]]; then __fvv_t=${__fvv_t//[[:cntrl:]]/"?"}; fi
    if [[ $__fvv_t == *[![:ascii:]]* ]]; then
        if (( ! __fvv_u )); then fv.video._bytes 0
        else
            if [[ $__fvv_t == *$__FV_VS_C1* ]]; then __fvv_t=${__fvv_t//$__FV_VS_C1/"?"}; fi
            # the common 2-byte and E1-EF 3-byte forms first; E0 / ED only when needed
            __fvv_s=${__fvv_t//${__FV_VS_UV[0]}/} __fvv_s=${__fvv_s//${__FV_VS_UV[2]}/}
            if [[ $__fvv_s == *[![:ascii:]]* ]]; then
                __fvv_s=${__fvv_s//${__FV_VS_UV[1]}/} __fvv_s=${__fvv_s//${__FV_VS_UV[3]}/}
                if [[ $__fvv_s == *[![:ascii:]]* ]]; then fv.video._bytes 1; fi
            fi
        fi
    fi
    if (( ${#__FV_VS_TC[@]} >= 512 )); then __FV_VS_TC=(); fi
    __FV_VS_TC[$__fvv_k]=$__fvv_t
}

# fv.video._n16 INDEX — memoise the nearest of xterm's 16 default colours
# (squared RGB distance, ties to the lower index; 0-15 are themselves)
fv.video._n16() {
    if [[ -n ${__FV_VS_N16[$1]-} ]]; then return 0; fi
    local __fvv_i=$1 __fvv_r __fvv_g __fvv_b __fvv_k __fvv_d __fvv_m=0 __fvv_md=-1
    if (( __fvv_i < 16 )); then __FV_VS_N16[__fvv_i]=$__fvv_i; return 0; fi
    if (( __fvv_i >= 232 )); then
        __fvv_r=$(( 8 + 10 * (__fvv_i - 232) )) __fvv_g=$(( 8 + 10 * (__fvv_i - 232) )) __fvv_b=$(( 8 + 10 * (__fvv_i - 232) ))
    else
        __fvv_k=$(( __fvv_i - 16 ))
        __fvv_r=${__FV_VS_CUBE[__fvv_k / 36]} __fvv_g=${__FV_VS_CUBE[__fvv_k / 6 % 6]} __fvv_b=${__FV_VS_CUBE[__fvv_k % 6]}
    fi
    for (( __fvv_k = 0; __fvv_k < 16; __fvv_k++ )); do
        __fvv_d=$(( (__fvv_r - __FV_VS_RGB[3 * __fvv_k]) ** 2 + (__fvv_g - __FV_VS_RGB[3 * __fvv_k + 1]) ** 2 + (__fvv_b - __FV_VS_RGB[3 * __fvv_k + 2]) ** 2 ))
        if (( __fvv_md < 0 || __fvv_d < __fvv_md )); then __fvv_md=$__fvv_d __fvv_m=$__fvv_k; fi
    done
    __FV_VS_N16[__fvv_i]=$__fvv_m
}

# fv.video._sgr SYM — __FV_VS_SGR[SYM] from its palette entry and the depth:
# ESC[0[;1];38;5;FG;48;5;BGm, or with 16 colours 30-37/90-97 and
# 40-47/100-107 (bold is SGR 1 only, never derived from a bright index)
fv.video._sgr() {
    local __fvv_p=${__FV_VS_PAL[$1]} __fvv_s=$'\e[0' __fvv_f __fvv_b
    __fvv_f=${__fvv_p%% *} __fvv_b=${__fvv_p#* } __fvv_b=${__fvv_b%% *}
    if [[ ${__fvv_p##* } == 1 ]]; then __fvv_s+=';1'; fi
    if (( __FV_VS_DEPTH == 256 )); then __fvv_s+=";38;5;$__fvv_f;48;5;$__fvv_b"
    else
        __fvv_f=${__FV_VS_N16[__fvv_f]} __fvv_b=${__FV_VS_N16[__fvv_b]}
        if (( __fvv_f < 8 )); then __fvv_s+=";$(( 30 + __fvv_f ))"; else __fvv_s+=";$(( 82 + __fvv_f ))"; fi
        if (( __fvv_b < 8 )); then __fvv_s+=";$(( 40 + __fvv_b ))"; else __fvv_s+=";$(( 92 + __fvv_b ))"; fi
    fi
    __FV_VS_SGR[$1]=${__fvv_s}m
}

# every row damaged in full and the shown copy forgotten
fv.video._dmgall() {
    local __fvv_y
    __FV_VS_OCH=() __FV_VS_OAT=()
    for (( __fvv_y = 0; __fvv_y < __FV_VS_H; __fvv_y++ )); do
        __FV_VS_DX1[__fvv_y]=0 __FV_VS_DX2[__fvv_y]=$__FV_VS_W
    done
}

# fv.video._def SYM FG BG BOLD (checked) — the palette entry; when it changes
# the look of a symbol in use, the rows holding it (every row for the default
# symbol: undefined symbols show as it) are damaged and their copy forgotten
fv.video._def() {
    local __fvv_o=${__FV_VS_SGR[$1]:-${__FV_VS_SGR[$__FV_VS_DEF]-}} __fvv_y
    __FV_VS_PAL[$1]="$2 $3 $4"
    fv.video._n16 "$2"
    fv.video._n16 "$3"
    fv.video._sgr "$1"
    if (( ! __FV_VS_H )) || [[ $__fvv_o == "${__FV_VS_SGR[$1]}" ]]; then return 0; fi
    if [[ $1 == "$__FV_VS_DEF" ]]; then fv.video._dmgall; return 0; fi
    for (( __fvv_y = 0; __fvv_y < __FV_VS_H; __fvv_y++ )); do
        if [[ ${__FV_VS_AT[__fvv_y]} == *"$1"* ]]; then
            __FV_VS_DX1[__fvv_y]=0 __FV_VS_DX2[__fvv_y]=$__FV_VS_W
            unset '__FV_VS_OCH[__fvv_y]' '__FV_VS_OAT[__fvv_y]'
        fi
    done
}

# fv.video._alloc — W x H blanks in the default attribute (FV_SCREEN_W/H; W
# at most FV's FVMaxWidth 1024), the clip reset, everything damaged, the copy
# and the cursor shown unknown
fv.video._alloc() {
    local __fvv_w=${FV_SCREEN_W-} __fvv_h=${FV_SCREEN_H-} __fvv_y __fvv_a
    if [[ -z $__fvv_w || $__fvv_w == *[![:digit:]]* || ${#__fvv_w} -gt 5 ]] || (( 10#$__fvv_w < 1 )); then __fvv_w=80; fi
    if [[ -z $__fvv_h || $__fvv_h == *[![:digit:]]* || ${#__fvv_h} -gt 5 ]] || (( 10#$__fvv_h < 1 )); then __fvv_h=24; fi
    __fvv_w=$(( 10#$__fvv_w )) __fvv_h=$(( 10#$__fvv_h ))
    if (( __fvv_w > 1024 )); then
        kk.debug "Error: fv.video: the screen is $__fvv_w columns wide; the buffer keeps 1024 (FVMaxWidth)"
        __fvv_w=1024
    fi
    __FV_VS_W=$__fvv_w __FV_VS_H=$__fvv_h
    printf -v __FV_VS_SP '%*s' "$__fvv_w" ''
    __FV_VS_FILL=()
    __FV_VS_FILL[$__FV_VS_DEF]=${__FV_VS_SP// /$__FV_VS_DEF}
    __fvv_a=${__FV_VS_FILL[$__FV_VS_DEF]}
    __FV_VS_CH=() __FV_VS_AT=() __FV_VS_OCH=() __FV_VS_OAT=() __FV_VS_WIDE=() __FV_VS_DX1=() __FV_VS_DX2=()
    for (( __fvv_y = 0; __fvv_y < __fvv_h; __fvv_y++ )); do
        __FV_VS_CH[__fvv_y]=$__FV_VS_SP __FV_VS_AT[__fvv_y]=$__fvv_a __FV_VS_WIDE[__fvv_y]=0
        __FV_VS_DX1[__fvv_y]=0 __FV_VS_DX2[__fvv_y]=$__fvv_w
    done
    __FV_VS_CX1=0 __FV_VS_CY1=0 __FV_VS_CX2=$__fvv_w __FV_VS_CY2=$__fvv_h
    __FV_VS_FORCE=0 __FV_VS_SVIS='' __FV_VS_SPOS=''
}

# fv.video.initScreen — the buffer: ASCII mode decided (FV_ASCII, locale),
# the default palette, the colour depth (FV_COLORS; with the terminal on the
# detection, else 256), W x H blanks, the cursor hidden at 0,0
fv.video.initScreen() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_e __fvv_s
    RESULT=''
    fv.video._mode
    __FV_VS_H=0 __FV_VS_PAL=() __FV_VS_SGR=() __FV_VS_DEF=0
    if (( FV_VIDEO_ON )); then fv.video._depth 1; else fv.video._depth 0; fi
    for __fvv_e in "${__FV_VS_DEFPAL[@]}"; do
        __fvv_s=$(( 16#${__fvv_e#*:} ))
        fv.video._def "${__fvv_e%%:*}" "${__FV_VS_DOS[__fvv_s & 15]}" "${__FV_VS_DOS[__fvv_s >> 4]}" 0
    done
    fv.video._alloc
    __FV_VS_CURX=0 __FV_VS_CURY=0 __FV_VS_CURT=0
}

# fv.video.resizeScreen — after updateSize / on cmResizeApp: reallocate at
# FV_SCREEN_W x FV_SCREEN_H, clear, damage everything, reset the clip; the
# palette, the depth and the cursor stay
fv.video.resizeScreen() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    RESULT=''
    if (( ! ${#__FV_VS_PAL[@]} )); then fv.video._noscr resizeScreen; return; fi
    fv.video._alloc
}

# fv.video._depth DETECT — the depth from FV_COLORS (16|256; anything else is
# ignored with a debug line), else with DETECT: TERM *256color* or COLORTERM
# set -> 256, TERM=linux -> 16, else `tput colors` (>= 256 -> 256; missing or
# failing -> 16); without DETECT 256. Sets __FV_VS_DEPTH and FV_VIDEO_COLORS.
fv.video._depth() {
    local __fvv_c=${FV_COLORS-} __fvv_n=''
    if [[ $__fvv_c == 16 || $__fvv_c == 256 ]]; then __fvv_n=$__fvv_c
    elif [[ -n $__fvv_c ]]; then kk.debug "Error: fv.video: FV_COLORS='$__fvv_c' is not 16 or 256; ignored"; fi
    if [[ -z $__fvv_n ]]; then
        if (( ! $1 )) || [[ ${TERM-} == *256color* || -n ${COLORTERM-} ]]; then __fvv_n=256
        elif [[ ${TERM-} == linux ]]; then __fvv_n=16
        elif __fvv_c=$(tput colors 2>/dev/null) && [[ -n $__fvv_c && $__fvv_c != *[![:digit:]]* ]] \
            && { while [[ $__fvv_c == 0?* ]]; do __fvv_c=${__fvv_c#0}; done; (( ${#__fvv_c} > 3 || 10#$__fvv_c >= 256 )); }; then
            __fvv_n=256                                      # any count >= 256 (xterm-direct: 16777216)
        else __fvv_n=16; fi
    fi
    __FV_VS_DEPTH=$__fvv_n FV_VIDEO_COLORS=$__fvv_n
}

# fv.video.detectColorDepth — the detection chain on demand, applied as
# setColorDepth does; RESULT = 16 | 256
fv.video.detectColorDepth() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    fv.video._depth 1
    fv.video.setColorDepth "$__FV_VS_DEPTH"
    RESULT=$__FV_VS_DEPTH
}

# fv.video.setColorDepth 16|256 — rebuild every symbol's SGR, damage all
fv.video.setColorDepth() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_s
    if [[ ${1-} != 16 && ${1-} != 256 ]]; then fv.video._bad setColorDepth '16|256' "$@"; return; fi
    RESULT=''
    __FV_VS_DEPTH=$1 FV_VIDEO_COLORS=$1
    for __fvv_s in "${!__FV_VS_PAL[@]}"; do fv.video._sgr "$__fvv_s"; done
    fv.video._dmgall
}

# fv.video.definePalette SYM FG BG [BOLD] — SYM one of [0-9A-Za-z], FG / BG
# 0-255, BOLD 0|1 (default 0); rc 2 otherwise
fv.video.definePalette() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_f=${2-} __fvv_b=${3-} __fvv_o=${4:-0} __fvv_k=1
    if [[ -n $__fvv_f && $__fvv_f != *[![:digit:]]* && ${#__fvv_f} -le 3 && -n $__fvv_b && $__fvv_b != *[![:digit:]]* && ${#__fvv_b} -le 3 ]]; then
        if (( 10#$__fvv_f <= 255 && 10#$__fvv_b <= 255 )); then __fvv_k=0; fi
    fi
    if (( __fvv_k )) || [[ ${1-} != [$__FV_VS_SYMS] || $__fvv_o != [01] ]]; then
        fv.video._bad definePalette 'SYM FG BG [BOLD]' "$@"
        return
    fi
    RESULT=''
    fv.video._def "$1" "$(( 10#$__fvv_f ))" "$(( 10#$__fvv_b ))" "$__fvv_o"
}

# fv.video._put — overlay __fvv_t at (__fvv_x, __fvv_y), clipped; the cells
# get the symbol __fvv_a, or (__fvv_a empty) the per-cell string __fvv_b
fv.video._put() {
    local __fvv_n=${#__fvv_t} __fvv_o=0 __fvv_r __fvv_m
    if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 )); then return 0; fi
    if (( __fvv_x < __FV_VS_CX1 )); then __fvv_o=$(( __FV_VS_CX1 - __fvv_x )) __fvv_x=$__FV_VS_CX1; fi
    __fvv_n=$(( __fvv_n - __fvv_o ))
    if (( __fvv_x + __fvv_n > __FV_VS_CX2 )); then __fvv_n=$(( __FV_VS_CX2 - __fvv_x )); fi
    if (( __fvv_n <= 0 )); then return 0; fi
    __fvv_r=${__FV_VS_CH[__fvv_y]}
    __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    if [[ -n $__fvv_a ]]; then
        if [[ -z ${__FV_VS_FILL[$__fvv_a]-} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
        __fvv_m=${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}
    else
        __fvv_m=${__fvv_b:__fvv_o:__fvv_n}
    fi
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}$__fvv_m${__fvv_r:__fvv_x+__fvv_n}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
}

# fv.video.writeStr X Y TEXT ATTR — TEXT at (X,Y) in the symbol ATTR (FV
# MoveStr + WriteLine); RESULT = the cells TEXT advances (unclipped)
fv.video.writeStr() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y __fvv_t=${3-} __fvv_a=${4-} __fvv_b=''
    if ! fv.video._xy "${1-}" "${2-}" || [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then fv.video._bad writeStr 'X Y TEXT ATTR' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeStr; return; fi
    if [[ $__fvv_t == *[![:print:]]* || $__fvv_t == *[![:ascii:]]* ]]; then fv.video._text; fi
    RESULT=${#__fvv_t}
    fv.video._put
}

# fv.video.writeBuf X Y TEXT ATTRS — TEXT with one symbol per cell (ATTRS as
# long as TEXT in cells; spike scr_put_ca); RESULT = the cells advanced
fv.video.writeBuf() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y __fvv_t=${3-} __fvv_a='' __fvv_b=${4-}
    if ! fv.video._xy "${1-}" "${2-}" || [[ $__fvv_b == *[!$__FV_VS_SYMS]* ]]; then fv.video._bad writeBuf 'X Y TEXT ATTRS' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeBuf; return; fi
    if [[ $__fvv_t == *[![:print:]]* || $__fvv_t == *[![:ascii:]]* ]]; then fv.video._text; fi
    if (( ${#__fvv_b} != ${#__fvv_t} )); then fv.video._bad writeBuf 'ATTRS not as long as TEXT' "$@"; return; fi
    RESULT=${#__fvv_t}
    fv.video._put
}

# fv.video.writeCStr X Y TEXT ATTR1 ATTR2 — FV MoveCStr: each '~' switches
# between ATTR1 and ATTR2 and takes no cell; RESULT = the cells advanced
fv.video.writeCStr() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y __fvv_t=${3-} __fvv_a='' __fvv_b='' __fvv_1=${4-} __fvv_2=${5-} __fvv_s __fvv_o='' __fvv_p
    if ! fv.video._xy "${1-}" "${2-}" || [[ $__fvv_1 != [$__FV_VS_SYMS] || $__fvv_2 != [$__FV_VS_SYMS] ]]; then
        fv.video._bad writeCStr 'X Y TEXT ATTR1 ATTR2' "$@"
        return
    fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeCStr; return; fi
    if [[ $__fvv_t == *[![:print:]]* || $__fvv_t == *[![:ascii:]]* ]]; then fv.video._text; fi
    while :; do
        __fvv_s=${__fvv_t%%'~'*}
        __fvv_o+=$__fvv_s
        printf -v __fvv_p '%*s' "${#__fvv_s}" ''
        __fvv_b+=${__fvv_p// /$__fvv_1}
        if [[ $__fvv_s == "$__fvv_t" ]]; then break; fi
        __fvv_t=${__fvv_t#*'~'} __fvv_p=$__fvv_1 __fvv_1=$__fvv_2 __fvv_2=$__fvv_p
    done
    __fvv_t=$__fvv_o
    RESULT=${#__fvv_t}
    fv.video._put
}

# fv.video._rect — the rectangle __fvv_x __fvv_y __fvv_w __fvv_h, clipped,
# filled with the character __fvv_t in the symbol __fvv_a
fv.video._rect() {
    local __fvv_x1=$__fvv_x __fvv_y1=$__fvv_y __fvv_x2=$(( __fvv_x + __fvv_w )) __fvv_y2=$(( __fvv_y + __fvv_h )) __fvv_l __fvv_m __fvv_n __fvv_r
    if (( __fvv_x1 < __FV_VS_CX1 )); then __fvv_x1=$__FV_VS_CX1; fi
    if (( __fvv_y1 < __FV_VS_CY1 )); then __fvv_y1=$__FV_VS_CY1; fi
    if (( __fvv_x2 > __FV_VS_CX2 )); then __fvv_x2=$__FV_VS_CX2; fi
    if (( __fvv_y2 > __FV_VS_CY2 )); then __fvv_y2=$__FV_VS_CY2; fi
    __fvv_n=$(( __fvv_x2 - __fvv_x1 ))
    if (( __fvv_n <= 0 || __fvv_y2 <= __fvv_y1 )); then return 0; fi
    __fvv_l=${__FV_VS_SP:0:__fvv_n}
    if [[ $__fvv_t != ' ' ]]; then __fvv_l=${__fvv_l// /"$__fvv_t"}; fi
    if [[ -z ${__FV_VS_FILL[$__fvv_a]-} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
    __fvv_m=${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}
    for (( __fvv_y = __fvv_y1; __fvv_y < __fvv_y2; __fvv_y++ )); do
        __fvv_r=${__FV_VS_CH[__fvv_y]}
        __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x1}$__fvv_l${__fvv_r:__fvv_x2}
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x1}$__fvv_m${__fvv_r:__fvv_x2}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x1 )); then __FV_VS_DX1[__fvv_y]=$__fvv_x1; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x2 )); then __FV_VS_DX2[__fvv_y]=$__fvv_x2; fi
    done
}

# fv.video.writeChar X Y CH ATTR [COUNT] — CH (its first character; '' is a
# blank) COUNT times (default 1; FV MoveChar); RESULT = COUNT
fv.video.writeChar() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y __fvv_v __fvv_w __fvv_h=1 __fvv_t=${3:- } __fvv_a=${4-}
    if ! fv.video._xy "${1-}" "${2-}" || [[ $__fvv_a != [$__FV_VS_SYMS] ]] || ! fv.video._num "${5:-1}" || (( __fvv_v < 0 )); then
        fv.video._bad writeChar 'X Y CH ATTR [COUNT]' "$@"
        return
    fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeChar; return; fi
    __fvv_w=$__fvv_v
    if [[ $__fvv_t == *[![:print:]]* || $__fvv_t == *[![:ascii:]]* ]]; then fv.video._text; fi
    __fvv_t=${__fvv_t:0:1}
    RESULT=$__fvv_w
    fv.video._rect
}

# fv.video.fillRect X Y W H ATTR [CH] — the rectangle in ATTR filled with CH
# (default a blank), clipped; RESULT = W (0 when negative)
fv.video.fillRect() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y __fvv_v __fvv_w __fvv_h __fvv_t=${6:- } __fvv_a=${5-}
    if ! fv.video._xy "${1-}" "${2-}" || [[ $__fvv_a != [$__FV_VS_SYMS] ]] || ! fv.video._num "${3-}"; then
        fv.video._bad fillRect 'X Y W H ATTR [CH]' "$@"
        return
    fi
    __fvv_w=$__fvv_v
    if ! fv.video._num "${4-}"; then fv.video._bad fillRect 'X Y W H ATTR [CH]' "$@"; return; fi
    __fvv_h=$__fvv_v
    if (( ! __FV_VS_H )); then fv.video._noscr fillRect; return; fi
    if [[ $__fvv_t == *[![:print:]]* || $__fvv_t == *[![:ascii:]]* ]]; then fv.video._text; fi
    __fvv_t=${__fvv_t:0:1}
    RESULT=$(( __fvv_w < 0 ? 0 : __fvv_w ))
    fv.video._rect
}

# fv.video.clearScreen [ATTR] — the whole screen blank in ATTR (default: the
# default symbol), whatever the clip; damage all (rows the terminal already
# shows that way emit nothing)
fv.video.clearScreen() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_a=${1:-$__FV_VS_DEF} __fvv_y
    if [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then fv.video._bad clearScreen '[ATTR]' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr clearScreen; return; fi
    RESULT=''
    if [[ -z ${__FV_VS_FILL[$__fvv_a]-} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
    for (( __fvv_y = 0; __fvv_y < __FV_VS_H; __fvv_y++ )); do
        __FV_VS_CH[__fvv_y]=$__FV_VS_SP __FV_VS_AT[__fvv_y]=${__FV_VS_FILL[$__fvv_a]}
        __FV_VS_DX1[__fvv_y]=0 __FV_VS_DX2[__fvv_y]=$__FV_VS_W
    done
}

# fv.video.setClip X1 Y1 X2 Y2 — writes go only into [X1,X2) x [Y1,Y2) (FV
# TRect, B exclusive), intersected with the screen; a reallocation resets it
fv.video.setClip() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y __fvv_x1 __fvv_y1
    if ! fv.video._xy "${1-}" "${2-}"; then fv.video._bad setClip 'X1 Y1 X2 Y2' "$@"; return; fi
    __fvv_x1=$__fvv_x __fvv_y1=$__fvv_y
    if ! fv.video._xy "${3-}" "${4-}"; then fv.video._bad setClip 'X1 Y1 X2 Y2' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr setClip; return; fi
    RESULT=''
    if (( __fvv_x1 < 0 )); then __fvv_x1=0; fi
    if (( __fvv_y1 < 0 )); then __fvv_y1=0; fi
    if (( __fvv_x > __FV_VS_W )); then __fvv_x=$__FV_VS_W; fi
    if (( __fvv_y > __FV_VS_H )); then __fvv_y=$__FV_VS_H; fi
    __FV_VS_CX1=$__fvv_x1 __FV_VS_CY1=$__fvv_y1 __FV_VS_CX2=$__fvv_x __FV_VS_CY2=$__fvv_y
}

fv.video.resetClip() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    RESULT=''
    __FV_VS_CX1=0 __FV_VS_CY1=0 __FV_VS_CX2=$__FV_VS_W __FV_VS_CY2=$__FV_VS_H
}

# fv.video.setCursorPos X Y — where the cursor stands after the next update
# (clamped to the screen there)
fv.video.setCursorPos() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y
    if ! fv.video._xy "${1-}" "${2-}" || (( __fvv_x < 0 || __fvv_y < 0 )); then fv.video._bad setCursorPos 'X Y' "$@"; return; fi
    RESULT=''
    __FV_VS_CURX=$__fvv_x __FV_VS_CURY=$__fvv_y
}

# fv.video.setCursorType 0..3 — FPC crHidden 0 (ESC[?25l); crUnderLine,
# crBlock, crHalfBlock 1-3 all show it (ESC[?25h, no shape sequence)
fv.video.setCursorType() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if [[ ${1-} != [0123] ]]; then fv.video._bad setCursorType '0..3' "$@"; return; fi
    RESULT=''
    __FV_VS_CURT=$1
}

# fv.video.strWidth TEXT — RESULT = the cells TEXT takes as a write stores it
# (P1a: one per character)
fv.video.strWidth() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_t=${1-}
    if [[ $__fvv_t == *[![:print:]]* || $__fvv_t == *[![:ascii:]]* ]]; then fv.video._text; fi
    RESULT=${#__fvv_t}
}

# fv.video.updateScreen [force] — one printf to FV_VIDEO_OUT_FD, else
# FV_TTY_FD: for each damaged row that differs from the shown copy, its
# damaged columns as colour runs (a cursor move per row, an SGR when the look
# changes; the SGR state is unknown at the start of a frame), then the cursor
# (its position when it is visible and moved or text was written; ?25h/l on
# change). force: every cell of every row, the cursor state re-sent. rc 1:
# no screen, no fd (nothing emitted, the damage kept), or the printf failed
# (the next frame is forced). Fork-free.
fv.video.updateScreen() {
    if [[ -z ${__fvv_g-} ]] && [[ $BASHOPTS == *nocasematch* || ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    # IFS empty: the fd below is a bare redirect target (bash 5.1 prints >&"$fd" as &> "$fd"),
    # so a caller IFS holding digits must not split it
    local IFS= __fvv_f=0 __fvv_fd=${FV_VIDEO_OUT_FD:-${FV_TTY_FD-}} __fvv_w=$__FV_VS_W __fvv_h=$__FV_VS_H __fvv_y __fvv_c __fvv_a
    local __fvv_x0 __fvv_n __fvv_sa __fvv_sc __fvv_s __fvv_r __fvv_k __fvv_o='' __fvv_l='' __fvv_lg='' __fvv_sg
    local __fvv_d=${__FV_VS_SGR[$__FV_VS_DEF]-} __fvv_py=-1 __fvv_px=-1 __fvv_cx=$__FV_VS_CURX __fvv_cy=$__FV_VS_CURY __fvv_v=l
    local -a __fvv_ys
    RESULT=''
    if [[ -n ${1-} ]]; then
        if [ "$1" = force ]; then __fvv_f=1; else fv.video._bad updateScreen '[force]' "$@"; return; fi
    fi
    if (( ! __fvv_h )); then fv.video._noscr updateScreen; return; fi
    if [[ -z $__fvv_fd || $__fvv_fd == *[![:digit:]]* ]]; then
        kk.debug "Error: fv.video.updateScreen: no output fd (FV_VIDEO_OUT_FD, FV_TTY_FD)"
        return 1
    fi
    if (( __FV_VS_FORCE )); then __fvv_f=1; fi
    if (( __fvv_f )); then
        __fvv_ys=("${!__FV_VS_CH[@]}") __FV_VS_SVIS='' __FV_VS_SPOS=''
    else
        __fvv_ys=("${!__FV_VS_DX1[@]}")
    fi
    for __fvv_y in "${__fvv_ys[@]}"; do
        __fvv_c=${__FV_VS_CH[__fvv_y]} __fvv_a=${__FV_VS_AT[__fvv_y]}
        if (( __fvv_f )) || [[ -z ${__FV_VS_OCH[__fvv_y]+1} ]]; then __fvv_x0=0 __fvv_n=$__fvv_w
        elif [[ $__fvv_c == "${__FV_VS_OCH[__fvv_y]}" && $__fvv_a == "${__FV_VS_OAT[__fvv_y]}" ]]; then continue
        else __fvv_x0=${__FV_VS_DX1[__fvv_y]} __fvv_n=$(( __FV_VS_DX2[__fvv_y] - __FV_VS_DX1[__fvv_y] )); fi
        __FV_VS_OCH[__fvv_y]=$__fvv_c __FV_VS_OAT[__fvv_y]=$__fvv_a
        __fvv_sa=${__fvv_a:__fvv_x0:__fvv_n} __fvv_sc=${__fvv_c:__fvv_x0:__fvv_n}
        if (( __fvv_y != __fvv_py || __fvv_x0 != __fvv_px )); then __fvv_o+=$'\e['"$(( __fvv_y + 1 ));$(( __fvv_x0 + 1 ))H"; fi
        while [[ -n $__fvv_sa ]]; do
            __fvv_s=${__fvv_sa:0:1}
            __fvv_r=${__fvv_sa%%[!$__fvv_s]*}
            __fvv_k=${#__fvv_r}
            if [[ $__fvv_s != "$__fvv_l" ]]; then
                __fvv_l=$__fvv_s __fvv_sg=${__FV_VS_SGR[$__fvv_s]:-$__fvv_d}
                if [[ $__fvv_sg != "$__fvv_lg" ]]; then __fvv_o+=$__fvv_sg __fvv_lg=$__fvv_sg; fi
            fi
            __fvv_o+=${__fvv_sc:0:__fvv_k}
            __fvv_sa=${__fvv_sa:__fvv_k} __fvv_sc=${__fvv_sc:__fvv_k}
        done
        __fvv_py=$__fvv_y __fvv_px=$(( __fvv_x0 + __fvv_n ))
        if (( __fvv_px >= __fvv_w )); then __fvv_py=-1; fi
    done
    if (( __FV_VS_CURT )); then
        __fvv_v=h
        if (( __fvv_cx >= __fvv_w )); then __fvv_cx=$(( __fvv_w - 1 )); fi
        if (( __fvv_cy >= __fvv_h )); then __fvv_cy=$(( __fvv_h - 1 )); fi
        if [[ -n $__fvv_o || $__FV_VS_SVIS != h || $__FV_VS_SPOS != "$__fvv_cx $__fvv_cy" ]]; then
            __fvv_o+=$'\e['"$(( __fvv_cy + 1 ));$(( __fvv_cx + 1 ))H"
        fi
    fi
    if [[ $__FV_VS_SVIS != "$__fvv_v" ]]; then __fvv_o+=$'\e[?25'$__fvv_v; fi
    __FV_VS_DX1=() __FV_VS_DX2=() __FV_VS_FORCE=0
    if [[ -z $__fvv_o ]]; then return 0; fi
    if ! printf '%s' "$__fvv_o" 2>/dev/null >&$__fvv_fd; then
        __FV_VS_FORCE=1 __FV_VS_SVIS='' __FV_VS_SPOS=''
        kk.debug "Error: fv.video.updateScreen: writing to fd $__fvv_fd failed; the next frame repaints everything"
        return 1
    fi
    __FV_VS_SVIS=$__fvv_v __FV_VS_SPOS=''
    if (( __FV_VS_CURT )); then __FV_VS_SPOS="$__fvv_cx $__fvv_cy"; fi
}
