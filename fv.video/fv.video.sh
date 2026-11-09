#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.video.sh}../../kbool.sh" || return
kk.unit fv.video || return $__kk_unit_rc

# fv.video — the terminal (layer L0 of kcl/fv.*): raw mode, alternate screen,
# hidden cursor, autowrap off, the screen size and the resize flag, all put
# back on every exit path. Port in spirit of the FPC rtl-console Video unit
# (InitVideo, DoneVideo, ScreenWidth / ScreenHeight); plain functions, no
# classes. The screen buffer is P1. Design: kcl/docs/dev/fv/PLAN.md (P0b);
# API, exit paths, deviations: README.md.
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

if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
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
declare -g __FV_VI_UNDEF=${__FV_VI_UNDEF-} __FV_VI_XRAN=${__FV_VI_XRAN:-0} __FV_VI_PID=${__FV_VI_PID-}
declare -gA __FV_VI_TP=() __FV_VI_PREV=()
declare -ga __FV_VI_SIGS=(EXIT INT TERM HUP WINCH)

# the caller's handlers see the status they would have seen without us
fv.video._rc() { return "$1"; }

fv.video.querySize() {
    local __fvv_s=''
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
    local __fvv_fd=$__FV_VI_FD __fvv_s=$'\e[0m\e[?7h\e[?25h'
    if (( __FV_VI_ALT )); then __fvv_s+=$'\e[?1049l'; fi
    __fvv_s+=$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'
    if [[ -z ${1-} ]]; then
        printf '%s' "$__fvv_s" 2>/dev/null >&$__fvv_fd || :
        fv.video._drain "$__fvv_fd"
    fi
    if [[ -n $__FV_VI_SAVED ]]; then stty "$__FV_VI_SAVED" >/dev/null 2>&1 <&$__fvv_fd || :; fi
    __FV_VI_ACT=0 FV_VIDEO_ON=0
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
    exit $(( 128 + __fvv_n ))
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
    local __fvv_alt=1 __fvv_fd='' __fvv_g='' __fvv_a='' __fvv_x __fvv_tty=${FV_TTY:-/dev/tty}
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
    if [[ -z $__FV_VI_UNDEF ]]; then                   # once per process
        __fvv_a=$(stty -a 2>/dev/null <&$__fvv_fd) || __fvv_a=''
        __FV_VI_UNDEF='susp undef quit undef lnext undef'
        for __fvv_x in dsusp discard status swtch; do
            if [[ $__fvv_a == "$__fvv_x ="* || $__fvv_a == *[!a-z]"$__fvv_x ="* ]]; then __FV_VI_UNDEF+=" $__fvv_x undef"; fi
        done
    fi
    fv.video._trap
    __FV_VI_PID=$BASHPID __FV_VI_FD=$__fvv_fd __FV_VI_ALT=$__fvv_alt __FV_VI_SAVED=$__fvv_g __FV_VI_ACT=1
    __FV_VI_KSET=${FV_KEY_FD+1} __FV_VI_KFD=${FV_KEY_FD-}
    FV_TTY_FD=$__fvv_fd FV_KEY_FD=$__fvv_fd
    # shellcheck disable=SC2086  # UNDEF is a list of stty words
    if ! stty -echo -icanon -ixon min 1 time 0 $__FV_VI_UNDEF >/dev/null 2>&1 <&$__fvv_fd; then
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
