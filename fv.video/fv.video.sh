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
# off). FV_KEY_FD is set to FV_TTY_FD (or the reader's pipe, below) while on
# and put back at done.
#
# Ctrl+C stays an interrupt (intr kept; under the kitty keyboard protocol
# fv.keyboard raises SIGINT for its Ctrl+C report: __FV_KB_ISIG, set at init
# and cleared at the restore); susp, quit, lnext (and dsusp,
# discard, status, swtch where stty knows them) are undefined, so Ctrl+Z and
# Ctrl+\ arrive as keys. Nothing here ever prints to stdout: all terminal
# output goes to FV_TTY_FD, so a TUI works inside x=$(...).
#
# The TUI is owned by the process that called initVideo: in its subshells
# initVideo and doneVideo are no-ops. Only the traps active in this process
# are chained (a subshell's inherited trap texts are dropped first). The
# restore drains input still on its way (<= ~0.3 s).
#
# Forks happen at init (stty, trap -p, the reader and its watchdog below), at done (stty) and
# in querySize (stty size: at init and per resize); the WINCH trap only sets
# a flag.
#
# The reader (D13 + its amendment): on Cygwin-family runtimes (OSTYPE msys*
# / cygwin*: Git-bash, MSYS2, Cygwin) initVideo starts a background process
# that reads the terminal one byte at a time with BLOCKING reads and forwards
# each byte through a pipe; FV_KEY_FD is the pipe's read end, so no timed
# read ever touches the terminal (under ConPTY a timed read of the terminal
# can hang on a resize). A second process, the watchdog, does timed reads on
# a pipe from the owner and stops the reader when that pipe ends or the owner
# is gone (every __FV_VI_POLL s). FV_TTY_READER=0|1 forces it off / on
# anywhere; empty = auto. Both end at the restore.
#
# The keyboard protocol (design P3 §14.4): initVideo asks whether the
# terminal has the kitty keyboard protocol (FV_KBD_PROTO=auto, the default;
# kitty = push at once; off = send nothing) and pushes its flags 1|4 when the
# reply comes (fv.video._kpush, run by fv.keyboard as it decodes the reply);
# the restore pops them on every exit path, only when pushed.
#
# Paste, clipboard, cursor shape (design P3 §2.5, §4.5; 10.7-10.9):
# initVideo turns bracketed paste on (ESC [ ? 2004 h), the restore turns it
# off (ESC [ ? 2004 l) on every exit path; updateScreen sends the cursor's
# shape by DECSCUSR when it changes (insert: underline, overwrite: block,
# D27) and the restore sends ESC [ 0 SP q (the terminal's default shape)
# when one was sent; fv.video.setClipboard TEXT sends OSC 52 (the system
# clipboard, D24) with a pure-bash base64.

# the width and cluster class of every code point (the screen buffer's walk)
kk.uses fv.unicode || return

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
# ownership); RPID/RFD: the reader's pid and the read end of its pipe ('' =
# no reader); WPID/WFD: its watchdog's pid and the write end of the
# watchdog's pipe; POLL: the watchdog's interval in seconds (and the
# reader's between-bytes owner check); RMODE: 1 from a reader start that
# succeeded until the restore ends (the restore then never reads the
# terminal, also when a signal re-enters it in the middle of the stop)
declare -g __FV_VI_ACT=${__FV_VI_ACT:-0} __FV_VI_FD=${__FV_VI_FD-} __FV_VI_ALT=${__FV_VI_ALT:-1}
declare -g __FV_VI_SAVED=${__FV_VI_SAVED-} __FV_VI_KSET=${__FV_VI_KSET-} __FV_VI_KFD=${__FV_VI_KFD-}
declare -g __FV_VI_XRAN=${__FV_VI_XRAN:-0} __FV_VI_PID=${__FV_VI_PID-}
declare -g __FV_VI_RPID=${__FV_VI_RPID-} __FV_VI_RFD=${__FV_VI_RFD-} __FV_VI_POLL=${__FV_VI_POLL-0.5}
declare -g __FV_VI_WPID=${__FV_VI_WPID-} __FV_VI_WFD=${__FV_VI_WFD-} __FV_VI_RMODE=${__FV_VI_RMODE:-0}
# KPUSH: 1 = the kitty keyboard flags were pushed on this terminal (the
# restore pops them; design P3 §14.4)
declare -g __FV_VI_KPUSH=${__FV_VI_KPUSH:-0}
# CSHP: 1 = a cursor shape (DECSCUSR) was sent since init (the restore sends
# ESC [ 0 SP q: the terminal's default shape; P3 10.7, D27)
declare -g __FV_VI_CSHP=${__FV_VI_CSHP:-0}
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
    local __fvv_pe=${#__FV_VS_P}${#__FV_VS_B}
    # its scope in _drain1, whose stderr is /dev/null (bash warns when it
    # fails to restore a rejected LC_ALL); outside an entry point (the traps)
    # a failed restore is put right here (L-1)
    fv.video._drain1 "$1" 2>/dev/null
    if [[ ${#__FV_VS_P}${#__FV_VS_B} != "$__fvv_pe" ]]; then fv.video._lcx "$__fvv_pe" 2>/dev/null; fi
}
fv.video._drain1() {
    local LC_ALL=C __fvv_c='' __fvv_n=0 __fvv_t0=${EPOCHREALTIME//[.,]/} __fvv_t
    while (( __fvv_n < 65536 )) && IFS= read -r -n1 -d '' -t 0.05 -u "$1" __fvv_c 2>/dev/null; do
        __fvv_n=$(( __fvv_n + 1 )) __fvv_t=${EPOCHREALTIME//[.,]/}
        if (( __fvv_t - __fvv_t0 > 300000 )); then break; fi
    done
}

# fv.video._fdclose [KEEP] — close every fd but 0, 1, 2, KEEP and bash's own
# 255 when it is not a terminal (an interactive shell keeps the terminal
# there) — the reader and the watchdog, first thing: a caller's pipe or
# coproc fd held there would never see its end of file while the TUI is on.
# The list from /proc/self/fd, else /dev/fd; fork-free; failures ignored
# (the glob's own directory fd is gone by then).
fv.video._fdclose() {
    local __fvv_n __fvv_d=/proc/self/fd
    if [[ ! -d $__fvv_d ]]; then __fvv_d=/dev/fd; fi
    for __fvv_n in "$__fvv_d"/*; do
        __fvv_n=${__fvv_n##*/}
        if [[ $__fvv_n == *[!0-9]* || $__fvv_n == [012] || $__fvv_n == "${1-}" ]]; then continue; fi
        if [[ $__fvv_n == 255 && ! -t 255 ]]; then continue; fi
        { exec {__fvv_n}<&-; } 2>/dev/null || :
    done
}

# fv.video._alive PID — rc 0 when PID runs: kill -0 and, where
# /proc/PID/stat exists, not a zombie (inside a trap handler bash reaps no
# child, so kill -0 alone still finds one that has exited). Fork-free.
fv.video._alive() {
    local __fvv_s=''
    if [[ -z $1 ]] || ! kill -0 "$1" 2>/dev/null; then return 1; fi
    if [[ -r /proc/$1/stat ]] && IFS= read -r __fvv_s 2>/dev/null < "/proc/$1/stat"; then
        __fvv_s=${__fvv_s##*) }
        if [[ $__fvv_s == Z* ]]; then return 1; fi
    fi
    return 0
}

# fv.video._ppid PID — __fvv_pp = PID's parent from /proc/PID/ppid (Cygwin
# family), else field 4 of /proc/PID/stat (Linux); '' when unknown
fv.video._ppid() {
    local __fvv_s=''
    __fvv_pp=''
    if [[ -z $1 ]]; then return 0; fi
    if [[ -r /proc/$1/ppid ]] && IFS= read -r __fvv_s 2>/dev/null < "/proc/$1/ppid"; then __fvv_pp=$__fvv_s
    elif [[ -r /proc/$1/stat ]] && IFS= read -r __fvv_s 2>/dev/null < "/proc/$1/stat"; then
        __fvv_s=${__fvv_s##*) } __fvv_s=${__fvv_s#* }
        __fvv_pp=${__fvv_s%% *}
    fi
    if [[ $__fvv_pp == *[!0-9]* ]]; then __fvv_pp=''; fi
}

# fv.video._mine PID — rc 1 when PID's parent is known (_ppid) and is not
# this shell: the pid is no longer the child it was (never signal it)
fv.video._mine() {
    local __fvv_pp
    fv.video._ppid "$1"
    [[ -z $__fvv_pp || $__fvv_pp == "$BASHPID" ]]
}

# fv.video._reader TTYFD OWNER US — the reader process (D13; _rstart runs it
# in a process substitution, its stdout is the pipe): ONE byte at a time from
# the terminal with a BLOCKING read — never a timed one: under ConPTY a timed
# read of the terminal hangs on a resize even in a process that ignores
# WINCH (the live check of 2026-11-10) — each byte forwarded at once by its
# own printf (a NUL as a NUL), no buffering. It ignores INT (Ctrl+C goes to
# the whole foreground process group: the owner restores, then stops the
# reader), QUIT, TSTP and WINCH; HUP, TERM and PIPE kill it (unless ignored
# when the shell started: bash cannot reset those; the stops then use KILL).
# It ends at end of file or a read error, when a write fails, and between
# bytes (at most every US us) when OWNER is gone; while it blocks, the
# watchdog (below) stops it. Fork-free per byte. The first lines drop what a
# process substitution inherits: set -e / -u / -x / -v / -f and pipefail, ERR
# / DEBUG / RETURN traps (with set -E / -T), the caller's stderr (xtrace
# would hit the screen) and locale (in UTF-8, read -n1 takes a whole
# character), and the owner's other fds (_fdclose).
fv.video._reader() {
    set +efuvx +o pipefail; trap - ERR DEBUG RETURN
    shopt -u failglob nullglob 2>/dev/null
    local LC_ALL=C IFS= __fvv_c='' __fvv_r=0 __fvv_t0=${EPOCHREALTIME//[.,]/} __fvv_t
    exec 2>/dev/null </dev/null
    trap '' INT QUIT TSTP WINCH
    trap - HUP TERM PIPE
    fv.video._fdclose "$1"
    while :; do
        __fvv_r=0 __fvv_c=''
        IFS= read -r -n1 -d '' -u "$1" __fvv_c || __fvv_r=$?
        if [[ -n $__fvv_c ]]; then printf '%s' "$__fvv_c" || exit 0
        elif (( __fvv_r == 0 )); then printf '\0' || exit 0
        else exit 0                                         # end of file, read error
        fi
        __fvv_t=${EPOCHREALTIME//[.,]/}
        if (( __fvv_t - __fvv_t0 >= $3 )); then
            kill -0 "$2" 2>/dev/null || exit 0
            __fvv_t0=$__fvv_t
        fi
    done
}

# fv.video._watchdog OWNER RPID POLL — the reader's watchdog (D13
# amendment): _rstart runs it in a process substitution after the reader;
# its stdin is a pipe whose write end only the owner holds (__FV_VI_WFD). It
# never touches the terminal: timed reads of that pipe every POLL s. The
# reader gone by itself -> it exits without a signal. End of file (the owner
# died, or closed its end), any data, or the owner gone -> it stops the
# reader (_wdstop) and exits. At an orderly restore the owner stops the
# reader itself and then kills the watchdog. Same first lines as the reader;
# it keeps only fd 0 (stdout and stderr go to /dev/null), never the reader's
# pipe nor the terminal.
fv.video._watchdog() {
    set +efuvx +o pipefail; trap - ERR DEBUG RETURN
    shopt -u failglob nullglob 2>/dev/null
    local LC_ALL=C IFS= __fvv_c='' __fvv_r=0
    exec 1>/dev/null 2>/dev/null
    trap '' INT QUIT TSTP WINCH
    trap - HUP TERM PIPE
    fv.video._fdclose
    while :; do
        __fvv_r=0 __fvv_c=''
        IFS= read -r -n1 -d '' -t "$3" -u 0 __fvv_c || __fvv_r=$?
        if ! fv.video._alive "$2"; then exit 0; fi
        if (( __fvv_r > 128 )) && [[ -z $__fvv_c ]] && fv.video._alive "$1"; then continue; fi
        break
    done
    fv.video._wdstop "$1" "$2"
    exit 0
}

# fv.video._wdstop OWNER RPID — the watchdog stops the reader: only while
# RPID runs and its parent is OWNER (or 1: the owner is gone) — never a pid
# that is no longer the reader; SIGKILL (the reader holds nothing to clean
# up; a TERM ignored at shell start would not do), up to 0.1 s for it to go
# (a fork-free spin: the watchdog has nothing to wait on), then taskkill by
# the Windows pid read before the kill.
fv.video._wdstop() {
    local __fvv_pp __fvv_w='' __fvv_e
    if ! fv.video._alive "$2"; then return 0; fi
    fv.video._ppid "$2"
    if [[ -n $__fvv_pp && $__fvv_pp != "$1" && $__fvv_pp != 1 ]]; then return 0; fi
    if [[ -r /proc/$2/winpid ]]; then IFS= read -r __fvv_w 2>/dev/null < "/proc/$2/winpid" || __fvv_w=''; fi
    kill -KILL "$2" 2>/dev/null || :
    __fvv_e=$(( ${EPOCHREALTIME//[.,]/} + 100000 ))
    while fv.video._alive "$2" && (( ${EPOCHREALTIME//[.,]/} < __fvv_e )); do :; done
    if fv.video._alive "$2" && [[ -n $__fvv_w && $__fvv_w != *[!0-9]* ]]; then
        MSYS2_ARG_CONV_EXCL='*' taskkill /F /PID "$__fvv_w" >/dev/null 2>&1 || :
    fi
}

# fv.video._rstart — start the reader and its watchdog when FV_TTY_READER
# says so (0 off, 1 on, '' auto = OSTYPE msys* / cygwin*; anything else: a
# debug line, auto): FV_KEY_FD = the read end of the reader's pipe. Each fd
# goes straight into its global and each pid into its global on the next
# line (a signal from then on finds them for the restore). No reader without
# a watchdog: when either does not start (no new numeric $!, or not alive),
# what did start is killed (SIGKILL, reaped) and the terminal is read
# directly, with one debug line. RMODE = 1 once both run: from then on the
# restore never reads the terminal itself. rc 0 always. The owner is this
# process ($BASHPID, taken here: inside <( ) it would be the reader's own).
# __FV_VI_POLL: the watchdog's interval and the reader's between-bytes owner
# check (seconds; '' = 0.5; junk: a debug line, 0.5).
fv.video._rstart() {
    local IFS= __fvv_m=${FV_TTY_READER-} __fvv_w=${__FV_VI_POLL:-0.5} __fvv_u=500000 __fvv_f __fvv_p=$BASHPID
    local __fvv_o=${!:-} __fvv_why=reader
    if [ "$__fvv_m" = 0 ]; then return 0; fi                  # [ ]: exact, whatever nocasematch says
    if [ "$__fvv_m" != 1 ]; then
        if [[ -n $__fvv_m ]]; then kk.debug "Error: fv.video.initVideo: FV_TTY_READER='$__fvv_m' is not 0, 1 or empty; using auto"; fi
        if [[ $OSTYPE != msys* && $OSTYPE != cygwin* ]]; then return 0; fi
    fi
    if [[ $__fvv_w != *[!0-9.]* && $__fvv_w != *.*.* && $__fvv_w == *[1-9]* && $__fvv_w != *.???????* && ${#__fvv_w} -le 8 ]]; then
        __fvv_u=${__fvv_w%%.*} __fvv_f=000000
        if [[ $__fvv_w == *.* ]]; then __fvv_f=${__fvv_w#*.}000000; fi
        __fvv_u=$(( 10#${__fvv_u:-0} * 1000000 + 10#${__fvv_f:0:6} ))
    else
        kk.debug "Error: fv.video.initVideo: __FV_VI_POLL='$__fvv_w' is not a positive number of seconds; using 0.5"
        __fvv_w=0.5
    fi
    __FV_VI_RFD='' __FV_VI_RPID='' __FV_VI_WFD='' __FV_VI_WPID=''
    { exec {__FV_VI_RFD}< <(fv.video._reader "$__FV_VI_FD" "$__fvv_p" "$__fvv_u"); } 2>/dev/null || __FV_VI_RFD=''
    __FV_VI_RPID=${!:-}
    if [[ -z $__FV_VI_RFD || -z $__FV_VI_RPID || $__FV_VI_RPID == *[!0-9]* || $__FV_VI_RPID == "$__fvv_o" ]]; then
        __FV_VI_RPID=''
    elif kill -0 "$__FV_VI_RPID" 2>/dev/null; then
        __fvv_why="reader's watchdog"
        { exec {__FV_VI_WFD}> >(fv.video._watchdog "$__fvv_p" "$__FV_VI_RPID" "$__fvv_w"); } 2>/dev/null || __FV_VI_WFD=''
        __FV_VI_WPID=${!:-}
        if [[ -z $__FV_VI_WFD || -z $__FV_VI_WPID || $__FV_VI_WPID == *[!0-9]* || $__FV_VI_WPID == "$__FV_VI_RPID" ]]; then
            __FV_VI_WPID=''
        elif kill -0 "$__FV_VI_WPID" 2>/dev/null; then
            __FV_VI_RMODE=1 FV_KEY_FD=$__FV_VI_RFD
            return 0
        fi
    fi
    fv.video._rabort
    kk.debug "Error: fv.video.initVideo: the terminal $__fvv_why did not start; reading the terminal directly"
}

# fv.video._rabort — a start that failed: the fresh children killed outright
# (SIGKILL: no TERM to rely on; just forked, so the pids are still theirs)
# and reaped, the fds closed, the globals cleared
fv.video._rabort() {
    local __fvv_x
    for __fvv_x in "$__FV_VI_RPID" "$__FV_VI_WPID"; do
        if [[ -n $__fvv_x ]]; then kill -KILL "$__fvv_x" 2>/dev/null || :; wait "$__fvv_x" 2>/dev/null || :; fi
    done
    for __fvv_x in "$__FV_VI_RFD" "$__FV_VI_WFD"; do
        if [[ -n $__fvv_x ]]; then { exec {__fvv_x}<&-; } 2>/dev/null || :; fi
    done
    __FV_VI_RFD='' __FV_VI_RPID='' __FV_VI_WFD='' __FV_VI_WPID=''
}

# fv.video._rwait PID FD US — wait up to US us for PID to go, a 0.02 s read
# of FD (the reader's pipe; what it brings is dropped) as the delay: __fvv_g
# = 1 when it no longer runs (_alive), 2 at end of file on FD (the reader has
# exited)
fv.video._rwait() {
    local __fvv_c='' __fvv_r __fvv_e=$(( ${EPOCHREALTIME//[.,]/} + $3 ))
    while (( ${EPOCHREALTIME//[.,]/} < __fvv_e )); do
        if ! fv.video._alive "$1"; then __fvv_g=1; return 0; fi
        __fvv_r=0
        IFS= read -r -d '' -n 4096 -t 0.02 -u "$2" __fvv_c 2>/dev/null || __fvv_r=$?
        if (( __fvv_r == 1 )) && [[ -z $__fvv_c ]]; then
            if [[ -e /dev/fd/$2 ]]; then __fvv_g=2; return 0; fi
            break                                           # no such fd: no delay to wait on
        fi
    done
    if ! fv.video._alive "$1"; then __fvv_g=1; fi
}

# fv.video._rkill PID FD SENT — the owner stops the reader: SIGTERM (unless
# SENT is 1) and up to 0.1 s, SIGKILL (a TERM ignored when the shell started
# stays ignored) and up to 1 s, then, where /proc/PID/winpid exists,
# taskkill on the Windows side and up to 0.5 s more (_rwait, FD = the
# reader's pipe as the delay); no signal once PID is no longer its child
# (_mine). The exited reader is reaped with wait (immediate: a zombie, or not
# our child). __fvv_g (the caller's): 0 = still alive, rc 1.
fv.video._rkill() {
    local __fvv_w=''
    __fvv_g=0
    if (( ! ${3:-0} )) && fv.video._mine "$1"; then kill "$1" 2>/dev/null || :; fi
    fv.video._rwait "$1" "$2" 100000
    if (( ! __fvv_g )) && fv.video._mine "$1"; then
        kill -KILL "$1" 2>/dev/null || :
        fv.video._rwait "$1" "$2" 1000000
    fi
    if (( ! __fvv_g )) && fv.video._mine "$1" && [[ -r /proc/$1/winpid ]]; then
        IFS= read -r __fvv_w 2>/dev/null < "/proc/$1/winpid" || __fvv_w=''
        if [[ -n $__fvv_w && $__fvv_w != *[!0-9]* ]]; then
            MSYS2_ARG_CONV_EXCL='*' taskkill /F /PID "$__fvv_w" >/dev/null 2>&1 || :
        fi
        fv.video._rwait "$1" "$2" 500000
    fi
    if (( ! __fvv_g )); then return 1; fi
    wait "$1" 2>/dev/null || :
}

# fv.video._rstop — stop the reader and its watchdog (at the restore): a pid
# that no longer runs is only reaped, one that is no longer our child
# (_mine) is left alone. SIGTERM to the reader and _rkill (its pipe as the
# delay), then the watchdog killed outright and reaped (SIGKILL + wait: it
# only ever reads a pipe, so KILL works; no spin, no /proc needed, fine
# inside a trap handler). The globals stay set until both are stopped: a
# signal re-entering the restore meanwhile runs the whole stop itself
# (kills of the same pids: harmless) before its stty; the pipes are closed
# only while the globals still name them (not twice, never a reused fd
# number). rc 1: the reader is still alive (one debug line; the terminal fd
# then stays open).
fv.video._rstop() {
    local IFS= __fvv_p=$__FV_VI_RPID __fvv_k=$__FV_VI_RFD __fvv_q=$__FV_VI_WPID __fvv_j=$__FV_VI_WFD __fvv_g=0 __fvv_rc=0
    if [[ -n $__fvv_p ]] && ! fv.video._alive "$__fvv_p"; then wait "$__fvv_p" 2>/dev/null || :; __fvv_p=''; fi
    if [[ -n $__fvv_p ]] && ! fv.video._mine "$__fvv_p"; then __fvv_p=''; fi
    if [[ -n $__fvv_p ]] && ! fv.video._rkill "$__fvv_p" "$__fvv_k" 0; then
        kk.debug "Error: fv.video: the terminal reader (pid $__fvv_p) did not stop"
        __fvv_rc=1
    fi
    if [[ -n $__fvv_q ]] && ! fv.video._alive "$__fvv_q"; then wait "$__fvv_q" 2>/dev/null || :; __fvv_q=''; fi
    if [[ -n $__fvv_q ]] && fv.video._mine "$__fvv_q"; then
        kill -KILL "$__fvv_q" 2>/dev/null || :
        wait "$__fvv_q" 2>/dev/null || :
    fi
    if [[ -n $__fvv_j && $__FV_VI_WFD == "$__fvv_j" ]]; then { exec {__fvv_j}>&-; } 2>/dev/null || :; fi
    if [[ -n $__fvv_k && $__FV_VI_RFD == "$__fvv_k" ]]; then { exec {__fvv_k}<&-; } 2>/dev/null || :; fi
    __FV_VI_RPID='' __FV_VI_RFD='' __FV_VI_WPID='' __FV_VI_WFD=''
    return "$__fvv_rc"
}

# fv.video._restore [quiet] — the terminal as it was (doneVideo, the traps):
# SGR reset, autowrap, cursor, main screen, mouse reporting and bracketed
# paste off, the terminal's default cursor shape (when one was sent), the input
# drained (with a reader: through its pipe, then the reader stopped — no
# timed read of the terminal in this shell, whose WINCH trap is still set;
# else from the terminal itself; none of the output and no drain with quiet:
# a failed init printed nothing), stty, the fd closed, FV_KEY_FD back. Only in the process that called initVideo (a
# subshell's inherited state is its parent's). ACT is cleared after stty: a
# signal in the middle restores once more (harmless; the fd is closed once).
# Every step may fail (the terminal hung up).
fv.video._restore() {
    if (( ! __FV_VI_ACT )) || [[ $__FV_VI_PID != "$BASHPID" ]]; then return 0; fi
    local IFS= __fvv_fd=$__FV_VI_FD __fvv_s=$'\e[0m\e[?7h\e[?25h' __fvv_live=0 __fvv_busy=0
    # the kitty flags popped first, on the screen they were pushed on (the
    # protocol keeps one stack per screen); the hook and the kitty Ctrl+C
    # interrupt (__FV_KB_ISIG) go with the TUI
    if (( __FV_VI_KPUSH )); then __fvv_s=$'\e[<u'$__fvv_s __FV_VI_KPUSH=0; fi
    __FV_KB_ONKITTY='' __FV_KB_ISIG=0
    if (( __FV_VI_ALT )); then __fvv_s+=$'\e[?1049l'; fi
    # mouse reporting and bracketed paste off (P3 10.8); the terminal's
    # default cursor shape back when a shape was sent (10.7, D27: ESC [ 0 SP q)
    __fvv_s+=$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l\e[?2004l'
    if (( __FV_VI_CSHP )); then __fvv_s+=$'\e[0 q'; fi
    __FV_VI_CSHP=0 __FV_VS_SSHP=''
    if [[ -z ${1-} ]]; then printf '%s' "$__fvv_s" 2>/dev/null >&$__fvv_fd || :; fi
    # with a reader (RMODE): drain its pipe while it still forwards, then
    # stop it (before the stty) — never a timed read of the terminal. RMODE
    # with no pid left = a signal re-entered right after the outer restore's
    # stop: nothing to drain, and the terminal fd is left to that restore
    if (( __FV_VI_RMODE )) || [[ -n $__FV_VI_RPID$__FV_VI_RFD$__FV_VI_WPID$__FV_VI_WFD ]]; then
        if [[ -z $__FV_VI_RPID$__FV_VI_RFD$__FV_VI_WPID$__FV_VI_WFD ]]; then __fvv_busy=1; fi
        if [[ -z ${1-} && -n $__FV_VI_RFD ]]; then fv.video._drain "$__FV_VI_RFD"; fi
        if (( ! __fvv_busy )) && ! fv.video._rstop; then __fvv_live=1; fi
    elif [[ -z ${1-} ]]; then
        fv.video._drain "$__fvv_fd"
    fi
    if [[ -n $__FV_VI_SAVED ]]; then stty "$__FV_VI_SAVED" >/dev/null 2>&1 <&$__fvv_fd || :; fi
    __FV_VI_ACT=0 FV_VIDEO_ON=0 __FV_VI_RMODE=0
    # the screen is no longer what the buffer sent: the next frame repaints all
    __FV_VS_FORCE=1 __FV_VS_SVIS='' __FV_VS_SPOS=''
    if [[ -n $__fvv_fd && $__FV_VI_FD == "$__fvv_fd" ]] && (( ! __fvv_busy )); then
        __FV_VI_FD=''
        if (( ! __fvv_live )); then { exec {__fvv_fd}>&-; } 2>/dev/null || :; fi
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

# The keyboard protocol (design P3 §14.4, D30): by FV_KBD_PROTO (auto when
# empty), the caller's __fvv_x = what initVideo sends first (after the
# alternate screen: the kitty protocol keeps one flag stack per screen).
#   auto   the kitty query CSI ? u and DA1 CSI c; nothing waits for a reply
#          (no timed read of the terminal, D13): fv.keyboard decodes the
#          replies as no keys and runs the hook __FV_KB_ONKITTY set here,
#          fv.video._kpush, on a kitty reply. A terminal without the
#          protocol answers DA1 only: nothing is pushed
#   kitty  the push CSI > 5 u (flags 1 disambiguate + 4 alternate keys) now
#   off    nothing
# fv.keyboard's reply state (__FV_KB_KITTY, __FV_KB_DA1) starts afresh, and
# __FV_KB_ISIG=1: Ctrl+C reported as CSI 99;5u (no 0x03 byte under the
# protocol, so no SIGINT from the tty) raises SIGINT in fv.keyboard's readers
# as the tty does for 0x03: Ctrl+C stays the interrupt; the restore clears it.
fv.video._kproto() {
    __FV_VI_KPUSH=0 __FV_KB_KITTY=-1 __FV_KB_DA1=0 __FV_KB_ONKITTY='' __fvv_x='' __FV_KB_ISIG=1
    case ${FV_KBD_PROTO:-auto} in
        auto) __fvv_x=$'\e[?u\e[c' __FV_KB_ONKITTY=fv.video._kpush ;;
        kitty) __fvv_x=$'\e[>5u' __FV_VI_KPUSH=1 ;;
        off) ;;
        *)
            kk.debug "Error: fv.video.initVideo: FV_KBD_PROTO '$FV_KBD_PROTO' is not auto, kitty or off; using auto"
            __fvv_x=$'\e[?u\e[c' __FV_KB_ONKITTY=fv.video._kpush ;;
    esac
}

# fv.keyboard's hook on a kitty reply: the push CSI > 5 u, once, on the
# terminal of a TUI that is on in this process (a late reply after the
# restore, or one read in a subshell, pushes nothing)
fv.video._kpush() {
    if (( ! __FV_VI_ACT || __FV_VI_KPUSH )) || [[ $__FV_VI_PID != "$BASHPID" || -z $__FV_VI_FD ]]; then return 0; fi
    local IFS=
    __FV_VI_KPUSH=1
    printf '%s' $'\e[>5u' 2>/dev/null >&$__FV_VI_FD || :
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
    fv.video._rstart
    # never DECKPAM (ESC =): keypad ESC O p..y would read as vt100 F5-F12
    fv.video._kproto
    # (bracketed paste on, P3 10.8: a paste arrives as one frame that
    # fv.keyboard decodes into one key, kbPaste)
    __fvv_x=$__fvv_x$'\e[?25l\e[?7l\e[0m\e[H\e[2J\e[?2004h'
    if (( __fvv_alt )); then __fvv_x=$'\e[?1049h'$__fvv_x; fi
    __FV_VI_CSHP=0 __FV_VS_SSHP=''
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
# per-row flags (1 holds a continuation \x01, 2 holds a marker \x02); X / XV /
# OXV the markers' contents and versions (wide characters, README); W / H the
# allocated size (H 0 = no screen); SP W blanks; FILL[sym] W copies of sym (built on first
# use; FILL[.] empty); CX1 CY1 CX2 CY2 the clip (x2/y2 exclusive); PAL[sym] "FG BG BOLD";
# SGR[sym] its whole ESC[0;...m; N16[index] the nearest of the 16 colours
# (memoised); CPAL / CSG16 / CSG256 the default palette kept per process
# (D18); SHADOW the reserved shadow symbol V (FV ShadowAttr $08, shadeRect's
# default); DEPTH 16|256; DEF the default symbol; CURX CURY CURT the cursor
# wanted; SVIS ('h' / 'l') SPOS ("X Y") the cursor shown ('' = unknown);
# FORCE the next frame repaints everything; LOC the UTF-8 locale for the calls
# of a non-UTF-8 caller ('' = none: ASCII mode); AMAP the ASCII-mode map.
#
# Locale (D11): every entry point runs with UTF-8 character semantics: a
# caller whose locale is not UTF-8 gets `local LC_ALL=$__FV_VS_LOC` for the
# call; without any UTF-8 locale the unit runs in C and stores ASCII only
# (FV_VIDEO_ASCII=1). nocasematch is cleared and globasciiranges set for
# the call (fv.video._g). The text check "anything but printable ASCII" is
# the pattern __FV_VS_PNA (D21): on bash 5.3+ the range glob `*[!\ -~]*`
# (code order under globasciiranges for every character); before 5.3
# globasciiranges orders only characters <= U+00FF by code and collates the
# rest (en_US.UTF-8 puts U+FF0C, U+3002, ... inside ` -~`), so there the
# bracket lists the 95 characters, no range. The symbol check is
# `*[!$__FV_VS_SYMS]*` (a list, never a range).
# "UTF-8" = both probes, a 2-byte (P, U+0436) and a 3-byte (B, U+2500)
# character, count 1: legacy CJK locales (eucJP, GBK, Big5, eucKR) pass the
# first alone.
#
# Text (fv.video._text): C0, DEL and C1 -> '?'; in UTF-8 mode every invalid
# or cut sequence and every surrogate -> one '?'; the check runs on bytes (C
# locale) and only for text with a non-ASCII byte. The cells (fv.video._walk):
# a wide character + \x01, a cluster or a character past U+FFFF as the
# marker \x02 + its content in X; the fast path skips the walk.
# Every write and updateScreen is fork-free; the only fork is `tput colors`
# in detectColorDepth when TERM / COLORTERM do not tell.

declare -g __FV_VS_P=$'\xd0\xb6' __FV_VS_B=$'\xe2\x94\x80' __FV_VS_CONT=$'\x01' __FV_VS_C1=$'\xc2[\x80-\x9f]'
# both probes in one string, for the entry guard: it is 2 characters long
# exactly when each probe counts 1 (the probe pair reads 11)
declare -g __FV_VS_PB=$__FV_VS_P$__FV_VS_B
# the marker cell (its content in __FV_VS_X), the marker list separator, the
# two characters the cluster rules look at: VS16 U+FE0F and ZWJ U+200D
declare -g __FV_VS_MARK=$'\x02' __FV_VS_US=$'\x1f' __FV_VS_VS16=$'\xef\xb8\x8f' __FV_VS_ZWJ=$'\xe2\x80\x8d'
# a continuation or a marker (a pattern); the frame's resync after wide and
# marker cells (D15): 1, or 0 to turn it off (tests only)
declare -g __FV_VS_CM=$'[\x01\x02]' __FV_VS_RSYNC=${__FV_VS_RSYNC:-1}
# CHA[x] = ESC[x+1G for every column (built by the allocation, kept growing)
declare -ga __FV_VS_CHA
__FV_VS_CHA+=()
# the UTF-8 sequences a write keeps (C-locale byte patterns): 2 bytes, 3 bytes
# without overlongs and surrogates, 4 bytes up to U+10FFFF without overlongs
declare -ga __FV_VS_UV=($'[\xc2-\xdf][\x80-\xbf]' $'\xe0[\xa0-\xbf][\x80-\xbf]'
    $'[\xe1-\xec\xee\xef][\x80-\xbf][\x80-\xbf]' $'\xed[\x80-\x9f][\x80-\xbf]'
    $'\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]' $'[\xf1-\xf3][\x80-\xbf][\x80-\xbf][\x80-\xbf]'
    $'\xf4[\x80-\x8f][\x80-\xbf][\x80-\xbf]')
# the fast path (C-locale byte patterns): valid text that holds none of these
# is all width-1 single characters (ASCII, Latin-1 bar U+00AD, Latin
# extended, IPA, Greek, Cyrillic bar U+0483-0489, general punctuation bar the
# zero-width and bidi controls, arrows, box drawing, blocks, geometric shapes
# bar U+25FC-25FF) and skips the width table: a lead byte outside C2-CB,
# CE-D4, E2; U+00AD; U+0483-0489; E2 not followed by 80 81 86 87 94-97;
# U+200B-200F, U+2028-202F; U+2060-207F; U+25FC-25FF
declare -ga __FV_VS_FP=($'[\xcc\xcd\xd5-\xe1\xe3-\xff]' $'\xc2\xad' $'\xd2[\x83-\x89]'
    $'\xe2[!\x80\x81\x86\x87\x94-\x97]' $'\xe2\x80[\x8b-\x8f\xa8-\xaf]' $'\xe2\x81[\xa0-\xbf]'
    $'\xe2\x97[\xbc-\xbf]')
# the wide fast path (P3 10.12; C-locale byte patterns, the common first):
# the plain wide characters = the runs of class w (fv.unicode, Unicode 16) in
# CJK Unified + Extension A + Yijing U+3400-9FFF, Hiragana U+3041-3096 and
# U+309B-309F (not the combining U+3099-309A), Katakana U+30A0-30FF, CJK
# punctuation U+3000-3029, Hangul syllables U+AC00-D7A3, CJK compatibility
# ideographs U+F900-FAFF, fullwidth forms U+FF01-FF60 and U+FFE0-FFE6.
# Every one is 2 wide, a BMP character, and joins nothing (tests/022 checks
# each code point against fv.unicode). W3: any 3-byte sequence (the
# substitution that adds the continuations, once the test passed); AMP: 1
# when bash has patsub_replacement (& in a replacement; >= 5.2; tests set 0
# for the 5.1 loop); RC / RU the replacements "the match + \x01" / "+ \x1f"
# (from a variable: an unquoted & there is the match too)
declare -ga __FV_VS_WB=($'[\xe4-\xe9][\x80-\xbf][\x80-\xbf]' $'\xe3\x81[\x81-\xbf]' $'\xe3\x82[\x80-\x96\x9b-\xbf]'
    $'\xe3\x83[\x80-\xbf]' $'\xe3\x80[\x80-\xa9]' $'[\xeb\xec][\x80-\xbf][\x80-\xbf]' $'\xea[\xb0-\xbf][\x80-\xbf]'
    $'\xed[\x80-\x9d][\x80-\xbf]' $'\xed\x9e[\x80-\xa3]' $'\xe3[\x90-\xbf][\x80-\xbf]' $'\xef\xbc[\x81-\xbf]'
    $'\xef\xbd[\x80-\xa0]' $'\xef\xbf[\xa0-\xa6]' $'\xef[\xa4-\xab][\x80-\xbf]')
declare -g __FV_VS_W3=$'[\xe0-\xef][\x80-\xbf][\x80-\xbf]' __FV_VS_RC=$'&\x01' __FV_VS_RU=$'&\x1f'
if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 2) )); then
    declare -g __FV_VS_AMP=1
else
    declare -g __FV_VS_AMP=0
fi
declare -g __FV_VS_SYMS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
# __FV_VS_PNA: the pattern "the text holds a character outside printable
# ASCII" (see Locale above), used unquoted in [[ == ]]
if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3) )); then
    declare -g __FV_VS_PNA='*[!\ -~]*'
else
    # (the 95 printable ASCII characters listed, each pattern-escaped)
    declare -g __FV_VS_PNA=$'*[! \x5c\x21\x22\x23\x24\x25\x26\x27\x28\x29\x5c\x2a\x2b\x2c\x5c\x2d\x2e\x2f0123456789\x3a\x3b\x3c\x3d\x3e\x5c\x3f\x40ABCDEFGHIJKLMNOPQRSTUVWXYZ\x5c\x5b\x5c\x5c\x5c\x5d\x5c\x5e\x5f\x60abcdefghijklmnopqrstuvwxyz\x7b\x7c\x7d\x7e]*'
fi
declare -g FV_VIDEO_ASCII=${FV_VIDEO_ASCII:-0} FV_VIDEO_COLORS=${FV_VIDEO_COLORS:-256} FV_VIDEO_OUT_FD=${FV_VIDEO_OUT_FD-}
declare -g __FV_VS_W=${__FV_VS_W:-0} __FV_VS_H=${__FV_VS_H:-0} __FV_VS_SP=${__FV_VS_SP-} __FV_VS_DEF=${__FV_VS_DEF:-0}
declare -g __FV_VS_CX1=${__FV_VS_CX1:-0} __FV_VS_CY1=${__FV_VS_CY1:-0} __FV_VS_CX2=${__FV_VS_CX2:-0} __FV_VS_CY2=${__FV_VS_CY2:-0}
declare -g __FV_VS_DEPTH=${__FV_VS_DEPTH:-256} __FV_VS_FORCE=${__FV_VS_FORCE:-0} __FV_VS_LOC=${__FV_VS_LOC-}
declare -g __FV_VS_CURX=${__FV_VS_CURX:-0} __FV_VS_CURY=${__FV_VS_CURY:-0} __FV_VS_CURT=${__FV_VS_CURT:-0}
declare -g __FV_VS_SVIS=${__FV_VS_SVIS-} __FV_VS_SPOS=${__FV_VS_SPOS-} __FV_VS_SSHP=${__FV_VS_SSHP-}
declare -ga __FV_VS_CH __FV_VS_AT __FV_VS_OCH __FV_VS_OAT __FV_VS_DX1 __FV_VS_DX2 __FV_VS_WIDE __FV_VS_N16
declare -gA __FV_VS_FILL __FV_VS_PAL __FV_VS_SGR __FV_VS_AMAP __FV_VS_TC
# wide characters: X ("Y X" -> the content of the marker cell there); XV / OXV
# per row: the side-map version (from XSEQ) and the one the terminal shows;
# TX: the text cache's marker lists; SC / SX / TB: writeCStr's own cache
# (cells, markers, symbol strings; V: a cache read); CC: the per-character
# class cache of the walk
declare -ga __FV_VS_XV __FV_VS_OXV
# WNEW[y] = 1: a write through _putw put a wide character into row y (or
# wrote into a row that held one) since its reader last looked — also one
# the clip cut or a later write overwrote, so the row may show none now; the
# reader (fv.views._wideMark, a friend) clears it. Rows written only by the
# narrow paths are never set
declare -ga __FV_VS_WNEW
declare -gA __FV_VS_X __FV_VS_TX __FV_VS_TB __FV_VS_CC __FV_VS_SC __FV_VS_SX
declare -g __FV_VS_XSEQ=${__FV_VS_XSEQ:-0} __FV_VS_V=
# a caller locale bash cannot restore (L-1, fv.video._g): LOK[value of the
# caller's LC_ALL] 1 = a `local LC_ALL` restores it, 0 = it does not or it
# cannot be told (no UTF-8 locale): swapped by hand
declare -gA __FV_VS_LOK
__FV_VS_LOK+=()
# set (for set -u) without losing what a reload finds
__FV_VS_CH+=() __FV_VS_AT+=() __FV_VS_OCH+=() __FV_VS_OAT+=() __FV_VS_DX1+=() __FV_VS_DX2+=() __FV_VS_WIDE+=() __FV_VS_N16+=()
__FV_VS_FILL+=() __FV_VS_PAL+=() __FV_VS_SGR+=() __FV_VS_AMAP+=() __FV_VS_TC+=()
__FV_VS_XV+=() __FV_VS_OXV+=() __FV_VS_WNEW+=() __FV_VS_X+=() __FV_VS_TX+=() __FV_VS_TB+=() __FV_VS_CC+=() __FV_VS_SC+=() __FV_VS_SX+=()
# the UTF-8 locale candidates; xterm's default colours 0-15 (R G B each); the
# 6x6x6 cube levels; FV's DOS colour order -> ANSI; the default palette:
# symbol 0 = FPC's DefaultAttr $07, then the 30 distinct bytes of FV's
# CAppColor in order of first appearance, then V = FV's ShadowAttr $08 (dark
# grey on black: the reserved shadow symbol, shadeRect's default)
declare -ga __FV_VS_LOCS=(C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8)
declare -ga __FV_VS_RGB=(0 0 0 205 0 0 0 205 0 205 205 0 0 0 238 205 0 205 0 205 205 229 229 229
    127 127 127 255 0 0 0 255 0 255 255 0 92 92 255 255 0 255 0 255 255 255 255 255)
declare -ga __FV_VS_CUBE=(0 95 135 175 215 255) __FV_VS_DOS=(0 4 2 6 1 5 3 7 8 12 10 14 9 13 11 15)
declare -ga __FV_VS_DEFPAL=(0:07 1:71 2:70 3:78 4:74 5:20 6:28 7:24 8:17 9:1F A:1A B:31 C:1E D:37 E:3F F:3A G:13 H:3E
    I:21 J:7F K:7A L:7E M:2B N:2F O:2E P:30 Q:72 R:38 S:10 T:12 U:32 V:08)
declare -g __FV_VS_SHADOW=V
# the default palette as initScreen builds it, kept per process (D18): CPAL
# the "FG BG BOLD" entries, CSG16 / CSG256 their SGR per depth, each the body
# of a compound assignment ("[SYM]=VALUE ...", values printf %q-quoted; ''
# until the first initScreen at that depth)
# (emptied on every load: initScreen evals them, so they never come from the
# environment or a stale load; a reload costs one rebuild)
declare -g __FV_VS_CPAL='' __FV_VS_CSG16='' __FV_VS_CSG256=''

# fv.video._locok NAME — rc 0 when the locale NAME gives UTF-8 character
# semantics (silent: bash's setlocale warning goes to /dev/null; a name that
# fails leaves the C locale in place, so the test cannot be fooled)
fv.video._locok() {
    local LC_ALL=C
    { LC_ALL=$1; } 2>/dev/null
    (( ${#__FV_VS_P} == 1 && ${#__FV_VS_B} == 1 ))
}

# A caller locale bash cannot restore (L-1): when a `local LC_ALL` goes out of
# scope, bash sets the caller's LC_ALL again or, when it is empty, does
# setlocale(LC_ALL, LANG or "") and then each LC_* variable; when setlocale
# rejects a name on that way (LANG, LC_ALL or, through "", any exported LC_*
# naming a missing locale) the locale of the scope just left stays. So no
# name is modelled: the unit looks at what a restore did. Every scope of its
# own LC_ALL that can be the outermost one is left, and then the caller's
# probe (${#__FV_VS_P}${#__FV_VS_B}: 11 = UTF-8) compared with the one taken
# before; a difference means bash could not restore here, and fv.video._lcx
# sets the probe's locale (C or the UTF-8 one) in a scope whose restore fails
# the same way, so that it stays. That covers fv.video._g (a non-UTF-8
# caller's call), _san and the byte walk (a UTF-8 caller's text-cache miss),
# _drain (the traps) and the load (_findloc, _mode). A non-empty LC_ALL is
# the one case where bash also warns on a failed restore: fv.video._gx swaps
# a rejected one by hand, silently (fv.video._lcknown, cached per value).
# Inside a scope of fv.video the outer LC_ALL is C or the UTF-8 locale, so a
# nested restore never fails. The fast path (a cached or ASCII text) changes
# no locale and checks nothing. A UTF-8 shell under a rejected LC_ALL
# (assigned over a UTF-8 one; on macOS also a shell started with it) runs the
# byte scopes of a text-cache miss (_san1, the byte walk) with stderr off.

# fv.video._lcx PE — a scope of the locale of the probe PE (11: the UTF-8
# locale, else C) and nothing else: called where bash failed to restore the
# caller's locale, it fails again and leaves that locale (2>/dev/null at the
# call: a rejected LC_ALL warns)
fv.video._lcx() {
    if [[ $1 == 11 && -n $__FV_VS_LOC ]]; then local LC_ALL=$__FV_VS_LOC; else local LC_ALL=C; fi
}

# fv.video._lcok NAME — rc 0 when setlocale takes NAME. A rejected name
# leaves the locale as it was, so from C it stays C: a taken name shows by
# UTF-8 character counts or by a Latin-1 letter (é) counting as a letter;
# a name that looks like C from there is told apart from the UTF-8 locale,
# where a rejected one stays UTF-8 (without that locale: rc 1, cannot be
# told). Call it with 2>/dev/null; for a rejected NAME that is the caller's
# LC_ALL the caller's locale is left to be put back (fv.video._gx).
fv.video._lcok() {
    local LC_ALL=C
    { LC_ALL=$1; } 2>/dev/null
    if (( ${#__FV_VS_P} == 1 )) || [[ $'\xe9' == [[:alpha:]] ]]; then return 0; fi
    if [[ -z $__FV_VS_LOC ]]; then return 1; fi
    LC_ALL=$__FV_VS_LOC
    { LC_ALL=$1; } 2>/dev/null
    (( ${#__FV_VS_P} == 2 ))
}

# fv.video._lcknown — rc 0 when the caller's LC_ALL (non-empty) is a value a
# `local LC_ALL` restores (cached in __FV_VS_LOK); one that cannot be told
# counts as not (a swap by hand is right either way)
fv.video._lcknown() {
    local __fvv_k=${__FV_VS_LOK[$LC_ALL]-}
    if [[ -z $__fvv_k ]]; then
        __fvv_k=0
        if fv.video._lcok "$LC_ALL" 2>/dev/null; then __fvv_k=1; fi
        __FV_VS_LOK[$LC_ALL]=$__fvv_k
    fi
    (( __fvv_k ))
}

# the first working candidate -> __FV_VS_LOC ('' when none); once at load.
# The caller's own locale name is tried first (when it is UTF-8 and the
# fixed candidates do not exist, it is the only one there is). The probes
# run in a scope of its own LC_ALL (fv.video._load checks what its end did).
fv.video._findloc() {
    local __fvv_n __fvv_o=${LC_ALL:-${LC_CTYPE:-${LANG:-}}} __fvv_r=1
    local -a __fvv_l=()
    __FV_VS_LOC=''
    if [[ -n $__fvv_o ]] && (( ${#__FV_VS_P} == 1 && ${#__FV_VS_B} == 1 )); then __fvv_l=("$__fvv_o"); fi
    local LC_ALL=C
    for __fvv_n in "${__fvv_l[@]}" "${__FV_VS_LOCS[@]}"; do
        if fv.video._locok "$__fvv_n"; then __FV_VS_LOC=$__fvv_n __fvv_r=0; break; fi
    done
    return "$__fvv_r"
}

# every text cache emptied (initScreen, a full cache)
fv.video._tcclear() {
    __FV_VS_TC=() __FV_VS_TX=() __FV_VS_SC=() __FV_VS_SX=() __FV_VS_TB=()
}

# ASCII mode: forced by FV_ASCII=1, or no UTF-8 locale at all. Decided here
# for the screen, never per call: UTF-8 mode needs a named UTF-8 locale in
# __FV_VS_LOC for the calls of a non-UTF-8 caller, so when the load found
# none but this call runs in a UTF-8 locale, that locale's name is taken;
# without a name ASCII mode it is (a call from a C caller could otherwise
# store and cache the ASCII form of a text the next UTF-8 call reads back)
fv.video._mode() {
    local __fvv_n=${LC_ALL:-${LC_CTYPE:-${LANG:-}}} __fvv_pe=${#__FV_VS_P}${#__FV_VS_B}
    FV_VIDEO_ASCII=0
    fv.video._tcclear
    if [[ ${FV_ASCII-} == 1 ]]; then FV_VIDEO_ASCII=1; return 0; fi
    if [[ -n $__FV_VS_LOC ]]; then return 0; fi
    if [[ ${#__FV_VS_P}${#__FV_VS_B} == 11 && -n $__fvv_n ]] && fv.video._locok "$__fvv_n" 2>/dev/null; then __FV_VS_LOC=$__fvv_n
    else FV_VIDEO_ASCII=1; fi
    if [[ ${#__FV_VS_P}${#__FV_VS_B} != "$__fvv_pe" ]]; then fv.video._lcx "$__fvv_pe" 2>/dev/null; fi
}
# the load: the UTF-8 locale and the mode; what the probes' restores did is
# checked against the caller's probe taken before (L-1)
fv.video._load() {
    local __fvv_pe=${#__FV_VS_P}${#__FV_VS_B}
    fv.video._findloc 2>/dev/null || :
    fv.video._mode
    if [[ ${#__FV_VS_P}${#__FV_VS_B} != "$__fvv_pe" ]]; then fv.video._lcx "$__fvv_pe" 2>/dev/null; fi
}
fv.video._load

# fv.video._g FUNC ARGS — FUNC with nocasematch off, globasciiranges on (the
# range globs, D21), a UTF-8 locale (C when there is none) and an empty IFS
# of its own (P3 3v F4: a caller IFS holding \x01, bash's internal quoting
# byte, drops that byte from expansions such as a pattern substitution over
# wide cells, and breaks initScreen's arithmetic; the guards test "${IFS-}"
# quoted: bash 5.2 misreads an unquoted IFS holding \x01 and more in [[ ]]),
# all put back on every return path. An entry point runs itself through it when the
# caller's state needs it; __fvv_g stops the second round. nocasematch goes off first (the name compares are
# case-sensitive). The locale (L-1): LC_ALL C, or a value a restore takes
# (__FV_VS_LOK) -> a `local LC_ALL` here; every other caller in
# fv.video._gx (kept apart: bash copies a function body on each call, so
# this one stays short).
fv.video._g() {
    local __fvv_g=1 __fvv_rc=0 __fvv_nc=0 __fvv_ga=0 IFS=
    if [[ $BASHOPTS == *nocasematch* ]]; then __fvv_nc=1; shopt -u nocasematch; fi
    if [[ $BASHOPTS != *globasciiranges* ]]; then __fvv_ga=1; shopt -s globasciiranges; fi
    if [[ ${#__FV_VS_P}${#__FV_VS_B} == 11 ]]; then "$@" || __fvv_rc=$?
    elif [[ ${LC_ALL-} == C || ${__FV_VS_LOK[${LC_ALL:-.}]-} == 1 ]]; then
        local LC_ALL=${__FV_VS_LOC:-C}
        "$@" || __fvv_rc=$?
    else fv.video._gx "$@" || __fvv_rc=$?
    fi
    if (( __fvv_nc )); then shopt -s nocasematch; fi
    if (( __fvv_ga )); then shopt -u globasciiranges; fi
    return "$__fvv_rc"
}

# fv.video._gx FUNC ARGS — _g for the other non-UTF-8 callers (L-1):
#   * LC_ALL empty: the scope in fv.video._g1; a restore that failed leaves
#     its UTF-8 locale (the caller was not UTF-8) -> fv.video._lcx sets C;
#   * LC_ALL POSIX, or a value a restore takes (fv.video._lcknown) -> a
#     `local LC_ALL`;
#   * any other LC_ALL (rejected, or no UTF-8 locale to tell): swapped by
#     hand and put back silently, C set first so that it stays when the
#     value is rejected.
fv.video._gx() {
    local __fvv_rc=0 __fvv_sv
    if [[ -z ${LC_ALL-} ]]; then
        fv.video._g1 "$@" || __fvv_rc=$?
        if [[ ${#__FV_VS_P}${#__FV_VS_B} == 11 ]]; then fv.video._lcx 0; fi
    elif [[ $LC_ALL == POSIX ]] || { [[ -z ${__FV_VS_LOK[$LC_ALL]-} ]] && fv.video._lcknown; }; then
        local LC_ALL=${__FV_VS_LOC:-C}
        "$@" || __fvv_rc=$?
    else
        __fvv_sv=$LC_ALL
        LC_ALL=${__FV_VS_LOC:-C}
        "$@" || __fvv_rc=$?
        # (without a UTF-8 locale the swap was to C already)
        if [[ -n $__FV_VS_LOC ]]; then { LC_ALL=C; LC_ALL=$__fvv_sv; } 2>/dev/null
        else { LC_ALL=$__fvv_sv; } 2>/dev/null; fi
    fi
    return "$__fvv_rc"
}
fv.video._g1() {
    local LC_ALL=${__FV_VS_LOC:-C}
    "$@"
}

# fv.video._num VALUE — __fvv_v = VALUE when it is an integer (an optional
# '-', 1-7 digits, leading zeros decimal); rc 2 otherwise
fv.video._num() {
    local __fvv_d=${1#-}
    if [[ -z $__fvv_d || $__fvv_d == *[!0123456789]* || ${#__fvv_d} -gt 7 ]]; then return 2; fi
    __fvv_v=$(( 10#$__fvv_d ))
    if [[ $1 == -* ]]; then __fvv_v=$(( -__fvv_v )); fi
}

# fv.video._xy X Y — __fvv_x / __fvv_y (fast path: plain digits); rc 2 when
# one is not an integer
fv.video._xy() {
    local __fvv_v
    if [[ -n $1 && $1 != *[!0123456789]* && $1 != 0?* && ${#1} -lt 8 ]]; then __fvv_x=$1
    elif fv.video._num "$1"; then __fvv_x=$__fvv_v; else return 2; fi
    if [[ -n $2 && $2 != *[!0123456789]* && $2 != 0?* && ${#2} -lt 8 ]]; then __fvv_y=$2
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
# mode) puts its map entry or '?'. A byte's value is printf %d & 255: musl's
# C locale gives a byte >= 0x80 as 0xDF00 + the byte (glibc, BSD and Cygwin
# give the byte)
fv.video._bytes() {
    local LC_ALL=C __fvv_o='' __fvv_q __fvv_c __fvv_n __fvv_b __fvv_v __fvv_p
    if (( ! $1 && ! ${#__FV_VS_AMAP[@]} )); then fv.video._amap; fi
    while [[ $__fvv_t == *[![:ascii:]]* ]]; do
        __fvv_q=${__fvv_t%%[![:ascii:]]*}
        __fvv_o+=$__fvv_q __fvv_t=${__fvv_t:${#__fvv_q}}
        __fvv_c=${__fvv_t:0:1}
        printf -v __fvv_b '%d' "'$__fvv_c"
        if (( (__fvv_b &= 255) >= 240 )); then __fvv_n=3; elif (( __fvv_b >= 224 )); then __fvv_n=2
        elif (( __fvv_b >= 192 )); then __fvv_n=1; else __fvv_n=0; fi
        while (( __fvv_n-- > 0 )) && [[ -n ${__fvv_t:${#__fvv_c}:1} ]]; do
            printf -v __fvv_b '%d' "'${__fvv_t:${#__fvv_c}:1}"
            if (( (__fvv_b &= 255) < 128 || __fvv_b >= 192 )); then break; fi
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

# fv.video._san — __fvv_t sanitised: every C0, DEL and C1 character -> '?';
# in ASCII mode (or a C-locale call) every non-ASCII character -> ASCII; in
# UTF-8 mode every invalid or cut sequence and every surrogate -> one '?'
# (valid 2-, 3- and 4-byte sequences stay). All of it runs on bytes (C
# locale: no collation, no mbrtowc quirk; [[:cntrl:]] is 0-31 and 127 there).
# UTF-8 mode: C1 (C2 80-9F) -> '?'; when removing every valid sequence leaves
# a non-ASCII byte, the slow pass (_bytes 1) fixes the text. Sets __fvv_f: 1 =
# every character is one width-1 cell (ASCII left, ASCII mode, a C-locale
# call, or the fast set __FV_VS_FP holds nothing of it), 0 = the walk must
# build the cells (then __fvv_a4 = 1 when the text holds a 4-byte sequence).
fv.video._san() {
    local __fvv_u=0 __fvv_s __fvv_p __fvv_pe=${#__FV_VS_P}${#__FV_VS_B}
    if [[ $__fvv_pe == 11 ]] && (( ! FV_VIDEO_ASCII )); then __fvv_u=1; fi
    # a caller LC_ALL a restore rejects (a UTF-8 shell under it): _san1's
    # scope runs with stderr off, where bash warns about that restore
    if [[ -n ${LC_ALL-} && $LC_ALL != C && $LC_ALL != POSIX && $LC_ALL != "$__FV_VS_LOC" ]] && ! fv.video._lcknown; then
        fv.video._san1 2>/dev/null
    else fv.video._san1; fi
    # outside an entry point's scope (a UTF-8 caller): a failed restore put right (L-1)
    if [[ ${#__FV_VS_P}${#__FV_VS_B} != "$__fvv_pe" ]]; then fv.video._lcx "$__fvv_pe" 2>/dev/null; fi
}
fv.video._san1() {
    local LC_ALL=C
    __fvv_f=1
    if [[ $__fvv_t == *[[:cntrl:]]* ]]; then __fvv_t=${__fvv_t//[[:cntrl:]]/"?"}; fi
    fv.video._san2
}
# fv.video._san2 — _san1 after the control characters (C locale; _wrows' batch
# runs it once over many rows joined with \x1f, which nothing here touches).
# With __fvv_wq set (the caller's local: _textx) a text the fast set refuses
# and without a 4-byte sequence tries the wide fast path: __fvv_f = 2 and
# __fvv_t = its cells when every non-ASCII character is a plain wide one
fv.video._san2() {
    if [[ $__fvv_t != *[![:ascii:]]* ]]; then return 0; fi
    if (( ! __fvv_u )); then fv.video._bytes 0; return 0; fi
    if [[ $__fvv_t == *$__FV_VS_C1* ]]; then __fvv_t=${__fvv_t//$__FV_VS_C1/"?"}; fi
    # the common 2-byte and E1-EF 3-byte forms first; E0 / ED / 4-byte only when needed
    __fvv_s=${__fvv_t//${__FV_VS_UV[0]}/} __fvv_s=${__fvv_s//${__FV_VS_UV[2]}/}
    if [[ $__fvv_s == *[![:ascii:]]* ]]; then
        __fvv_s=${__fvv_s//${__FV_VS_UV[1]}/} __fvv_s=${__fvv_s//${__FV_VS_UV[3]}/}
        __fvv_s=${__fvv_s//${__FV_VS_UV[4]}/} __fvv_s=${__fvv_s//${__FV_VS_UV[5]}/} __fvv_s=${__fvv_s//${__FV_VS_UV[6]}/}
        if [[ $__fvv_s == *[![:ascii:]]* ]]; then fv.video._bytes 1; fi
    fi
    if [[ $__fvv_t == *${__FV_VS_FP[0]}* || $__fvv_t == *${__FV_VS_FP[1]}* || $__fvv_t == *${__FV_VS_FP[2]}* \
        || $__fvv_t == *${__FV_VS_FP[3]}* || $__fvv_t == *${__FV_VS_FP[4]}* || $__fvv_t == *${__FV_VS_FP[5]}* \
        || $__fvv_t == *${__FV_VS_FP[6]}* ]]; then
        __fvv_f=0
        if [[ $__fvv_t == *[$'\xf0'-$'\xf4']* ]]; then __fvv_a4=1
        elif (( ${__fvv_wq:-0} )) && fv.video._wfb; then __fvv_f=2; fi
    fi
}

# fv.video._wfb — the wide fast path (P3 10.12; C locale, __fvv_t valid and
# sanitised): rc 0 and __fvv_t = its cells when every non-ASCII character of
# it is in __FV_VS_WB, the plain wide characters (class w in fv.unicode,
# never joined to anything: no zero-width character, modifier, VS16 or ZWJ
# can be among them), each one cell + the continuation \x01 — the walk's
# answer without the walk; rc 1 (nothing changed) otherwise. The test removes
# the accepted sequences pattern by pattern (the common ones first) until no
# non-ASCII byte is left; the cells come from one substitution (& =
# patsub_replacement, bash >= 5.2 with the option on; __FV_VS_AMP 0 forces
# the loop _wfbl, the bash 5.1 path). With an argument (_wrb1's batch, P3 3v
# F1) the loop is not run: rc 2 and __fvv_t unchanged when the test passed
# but only the loop could give the cells (the caller loops per row: the
# loop over the rows joined is quadratic)
fv.video._wfb() {
    # (a 2-byte, an E0-E2 3-byte or a 4-byte sequence: never accepted)
    if [[ $__fvv_t == *[$'\xc2'-$'\xe2\xf0'-$'\xf4']* ]]; then return 1; fi
    local __fvv_s=${__fvv_t//${__FV_VS_WB[0]}/} __fvv_i=1
    while [[ $__fvv_s == *[![:ascii:]]* ]]; do
        if (( __fvv_i >= ${#__FV_VS_WB[@]} )); then return 1; fi
        __fvv_s=${__fvv_s//${__FV_VS_WB[__fvv_i]}/} __fvv_i=$(( __fvv_i + 1 ))
    done
    if (( __FV_VS_AMP )) && [[ $BASHOPTS == *patsub_replacement* ]]; then
        __fvv_t=${__fvv_t//$__FV_VS_W3/$__FV_VS_RC}
        return 0
    fi
    if (( $# )); then return 2; fi
    fv.video._wfbl
}
# fv.video._wfbl — _wfb's loop (bash 5.1, or patsub_replacement off): the
# cells of __fvv_t, whose every non-ASCII character is a plain wide one
fv.video._wfbl() {
    local __fvv_o='' __fvv_q
    # (every non-ASCII byte now starts a 3-byte sequence)
    while [[ $__fvv_t == *[![:ascii:]]* ]]; do
        __fvv_q=${__fvv_t%%[![:ascii:]]*}
        __fvv_o+=$__fvv_q${__fvv_t:${#__fvv_q}:3}$__FV_VS_CONT __fvv_t=${__fvv_t:${#__fvv_q}+3}
    done
    __fvv_t=$__fvv_o$__fvv_t
}

# fv.video._fast TEXT — rc 0 when valid UTF-8 TEXT is in the fast set (the
# caller runs in the C locale); the test of the fast path uses it
fv.video._fast() {
    local __fvv_p
    for __fvv_p in "${__FV_VS_FP[@]}"; do
        if [[ $1 == *$__fvv_p* ]]; then return 1; fi
    done
}

# fv.video._text — __fvv_t ready to store, as CELLS: one bash character per
# display cell; a wide character is its character + the continuation \x01,
# a cell whose content is not exactly one BMP character (a cluster, an
# orphan zero-width character, anything past U+FFFF) and every class-y
# character (the frame pre-blanks it) is the marker \x02 (+ \x01 when wide)
# and its content goes to __fvv_xl as "OFFSET:CONTENT\x1f".
# Sets __fvv_w = 1 when the cells hold \x01 or \x02 (the caller's locals
# __fvv_w / __fvv_xl start as 0 / ''). The writes call it only for text with
# a non-printable or a non-ASCII character.
#
# The answers are cached (__FV_VS_TC: raw text -> cells, those of a wide text
# behind the prefix \x03, its marker list in __FV_VS_TX; at most 512 entries,
# emptied when full and by initScreen): a TUI redraws the same strings again
# and again. One lookup answers a hit (a miss reads as the sentinel \x04,
# which no cells can be). Printable ASCII never gets here, so no key is "@"
# or "*".
fv.video._text() {
    __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
    if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; return 0; fi
    fv.video._textx
}
# fv.video._textx — _text for a wide hit (\x03 + cells) or a miss (\x04)
# (kept apart: the common narrow hit then copies a short body)
fv.video._textx() {
    if [[ $__FV_VS_V != $'\x04' ]]; then __fvv_w=1 __fvv_xl=${__FV_VS_TX[$__fvv_t]-} __fvv_t=${__FV_VS_V:1}; return 0; fi
    local __fvv_key=$__fvv_t __fvv_f __fvv_a4=0 __fvv_wq=1
    fv.video._san
    if (( __fvv_f == 2 )); then __fvv_w=1
    elif (( ! __fvv_f )); then fv.video._textw; fi
    if (( ${#__FV_VS_TC[@]} >= 512 )); then fv.video._tcclear; fi
    if (( __fvv_w )); then __FV_VS_TC[$__fvv_key]=$'\x03'$__fvv_t __FV_VS_TX[$__fvv_key]=$__fvv_xl
    else __FV_VS_TC[$__fvv_key]=$__fvv_t; fi
}

# fv.video._textw — _text's walk: the cells of __fvv_t, its markers, __fvv_w
fv.video._textw() {
    local __fvv_c='' __fvv_cn=0 __fvv_pc='' __fvv_pw=0 __fvv_pk='' __fvv_pp=0 __fvv_pz=0 __fvv_pr=0 __fvv_ps='' __fvv_wa=''
    __fvv_xl=''
    fv.video._walk
    fv.video._wfin
    __fvv_t=$__fvv_c
    if [[ -n $__fvv_xl || $__fvv_t == *"$__FV_VS_CONT"* ]]; then __fvv_w=1; fi
}

# fv.video._wcls — the class of one character __fvv_ch (a cache miss, the
# walk's character mode: a UTF-8 locale where every character is one bash
# character) -> __fvv_v = class letter + 1 (a BMP character) or 0 (past
# U+FFFF); cached in __FV_VS_CC (<= 4096 entries; byte strings as keys, so
# both modes share it)
fv.video._wcls() {
    local __fvv_cp
    printf -v __fvv_cp '%d' "'$__fvv_ch"
    fv.unicode.charClass "$__fvv_cp" || RESULT=n
    __fvv_v=$RESULT$(( __fvv_cp < 65536 ))
    if (( ${#__FV_VS_CC[@]} >= 4096 )); then __FV_VS_CC=(); fi
    __FV_VS_CC[$__fvv_ch]=$__fvv_v
}

# fv.video._wclsb — the same in the byte mode (C locale): __fvv_ch is one
# UTF-8 sequence of __fvv_l bytes, its code point from the bytes
fv.video._wclsb() {
    local __fvv_cp
    case $__fvv_l in
        1) printf -v __fvv_cp '%d' "'$__fvv_ch" ;;
        2) printf -v __fvv_cp '((%d&31)<<6)|(%d&63)' "'${__fvv_ch:0:1}" "'${__fvv_ch:1:1}" ;;
        3) printf -v __fvv_cp '((%d&15)<<12)|((%d&63)<<6)|(%d&63)' "'${__fvv_ch:0:1}" "'${__fvv_ch:1:1}" "'${__fvv_ch:2:1}" ;;
        *) printf -v __fvv_cp '((%d&7)<<18)|((%d&63)<<12)|((%d&63)<<6)|(%d&63)' "'${__fvv_ch:0:1}" "'${__fvv_ch:1:1}" "'${__fvv_ch:2:1}" "'${__fvv_ch:3:1}" ;;
    esac
    __fvv_cp=$(( __fvv_cp ))
    fv.unicode.charClass "$__fvv_cp" || RESULT=n
    __fvv_v=$RESULT$(( __fvv_l < 4 ))
    if (( ${#__FV_VS_CC[@]} >= 4096 )); then __FV_VS_CC=(); fi
    __FV_VS_CC[$__fvv_ch]=$__fvv_v
}

# fv.video._walk — the cells of __fvv_t (sanitised, UTF-8 locale) appended to
# __fvv_c / __fvv_xl, the last cell left pending. A cell is a base character
# plus (fv.unicode classes):
#   * every zero-width character after it (z: marks, ZWJ, VS, tags, Hangul
#     V/T jamo); VS16 U+FE0F makes an Extended_Pictographic narrow base (x:
#     © ❤ ☺) or a keycap base (0-9 # *) 2 wide (D14), nothing else;
#   * an emoji modifier (m) after an Extended_Pictographic base (x, y): the
#     cell is 2 wide; after any other base the modifier is a cell of its own;
#   * after a ZWJ, the next character when both it and the cell's base are
#     Extended_Pictographic (x, y; UAX #29 GB11);
#   * a second regional indicator (r) after a lone one: the flag, 2 wide (a
#     third starts a new cell; a lone one is 1 wide).
# A zero-width character with no cell before it in this text (an orphan) is
# a cell of its own: a space + it, 1 wide. The width of a cell is its base's
# (w, y, m: 2; n, x, r: 1) unless a rule above says otherwise.
# The state (the caller's locals): __fvv_pc the pending cell's content ('' =
# none), __fvv_pw its width, __fvv_pk its base's class (o = orphan), __fvv_pp
# 1 = it is one BMP character, __fvv_pz 1 = it ends in a ZWJ, __fvv_pr 1 = a
# lone regional indicator, __fvv_ps its symbol (writeCStr: __fvv_wa).
# (fv.video._walk1 is the walk; this wrapper checks what the end of its
# byte-mode scope did: L-1; under a caller LC_ALL a restore rejects, that
# scope runs with stderr off, as _san1's)
fv.video._walk() {
    local __fvv_wp=${#__FV_VS_P}${#__FV_VS_B}
    if (( __fvv_a4 )) && [[ -n ${LC_ALL-} && $LC_ALL != C && $LC_ALL != POSIX && $LC_ALL != "$__FV_VS_LOC" ]] && ! fv.video._lcknown; then
        fv.video._walk1 2>/dev/null
    else fv.video._walk1; fi
    if [[ ${#__FV_VS_P}${#__FV_VS_B} != "$__fvv_wp" ]]; then fv.video._lcx "$__fvv_wp" 2>/dev/null; fi
}
fv.video._walk1() {
    local __fvv_r=$__fvv_t __fvv_ch __fvv_v __fvv_k __fvv_p __fvv_bm=0 __fvv_e=$'\xf0\x9f\x98\x80' __fvv_l
    # Cygwin-family bash holds a character past U+FFFF as two halves, and
    # printf %d of a half leaves the conversion state broken for the next
    # one: a text with such characters is walked on bytes there
    if (( __fvv_a4 && ${#__fvv_e} == 2 )); then __fvv_bm=1; fi
    if (( __fvv_bm )); then local LC_ALL=C; fi
    # the text is consumed from the front: ${t:i:1} walks i characters in a
    # UTF-8 locale, ${t:0:1} and ${t:1} do not
    while [[ -n $__fvv_r ]]; do
        if (( __fvv_bm )); then
            printf -v __fvv_l '%d' "'${__fvv_r:0:1}"
            if (( __fvv_l < 128 )); then __fvv_l=1; elif (( __fvv_l >= 240 )); then __fvv_l=4
            elif (( __fvv_l >= 224 )); then __fvv_l=3; else __fvv_l=2; fi
            __fvv_ch=${__fvv_r:0:__fvv_l} __fvv_r=${__fvv_r:__fvv_l}
            __fvv_v=${__FV_VS_CC[$__fvv_ch]-}
            if [[ -z $__fvv_v ]]; then fv.video._wclsb; fi
        else
            __fvv_ch=${__fvv_r:0:1} __fvv_r=${__fvv_r:1}
            __fvv_v=${__FV_VS_CC[$__fvv_ch]-}
            if [[ -z $__fvv_v ]]; then fv.video._wcls; fi
        fi
        __fvv_k=${__fvv_v:0:1} __fvv_p=${__fvv_v:1:1}
        if [[ -n $__fvv_pc ]]; then
            if [[ $__fvv_k == z ]]; then
                __fvv_pc+=$__fvv_ch __fvv_pp=0 __fvv_pz=0
                if [[ $__fvv_ch == "$__FV_VS_ZWJ" ]]; then __fvv_pz=1
                elif [[ $__fvv_ch == "$__FV_VS_VS16" ]] && (( __fvv_pw == 1 )) \
                    && [[ $__fvv_pk == x || ${__fvv_pc:0:1} == [0123456789#*] ]]; then __fvv_pw=2; fi
                continue
            fi
            if [[ $__fvv_k == m ]] && [[ $__fvv_pk == x || $__fvv_pk == y ]]; then
                __fvv_pc+=$__fvv_ch __fvv_pp=0 __fvv_pw=2
                continue
            fi
            if (( __fvv_pz )) && [[ ( $__fvv_k == x || $__fvv_k == y ) && ( $__fvv_pk == x || $__fvv_pk == y ) ]]; then
                __fvv_pc+=$__fvv_ch __fvv_pp=0 __fvv_pz=0 __fvv_pk=$__fvv_k
                if [[ $__fvv_k == y ]]; then __fvv_pw=2; fi
                continue
            fi
            if [[ $__fvv_k == r ]] && (( __fvv_pr )); then
                __fvv_pc+=$__fvv_ch __fvv_pp=0 __fvv_pw=2 __fvv_pr=0
                continue
            fi
            fv.video._wfin
        fi
        __fvv_ps=$__fvv_wa __fvv_pz=0 __fvv_pr=0
        if [[ $__fvv_k == z ]]; then
            __fvv_pc=" $__fvv_ch" __fvv_pk=o __fvv_pp=0 __fvv_pw=1
            if [[ $__fvv_ch == "$__FV_VS_ZWJ" ]]; then __fvv_pz=1; fi
        else
            __fvv_pc=$__fvv_ch __fvv_pk=$__fvv_k __fvv_pp=$__fvv_p __fvv_pw=1
            if [[ $__fvv_k == w || $__fvv_k == m ]]; then __fvv_pw=2
            elif [[ $__fvv_k == y ]]; then __fvv_pw=2 __fvv_pp=0     # a marker: the frame pre-blanks it
            elif [[ $__fvv_k == r ]]; then __fvv_pr=1; fi
        fi
    done
}

# fv.video._wfin — the pending cell appended to __fvv_c (its character, or the
# marker and an __fvv_xl entry at cell __fvv_cn; + \x01 when 2 wide), its
# symbol(s) to __fvv_b when __fvv_wa is set. __fvv_cn counts the cells (the
# byte mode cannot count them with ${#})
fv.video._wfin() {
    if [[ -z $__fvv_pc ]]; then return 0; fi
    if (( __fvv_pp )); then __fvv_c+=$__fvv_pc
    else __fvv_xl+=$__fvv_cn:$__fvv_pc$__FV_VS_US __fvv_c+=$__FV_VS_MARK; fi
    __fvv_cn=$(( __fvv_cn + __fvv_pw ))
    if [[ -n $__fvv_wa ]]; then __fvv_b+=$__fvv_ps; fi
    if (( __fvv_pw == 2 )); then
        __fvv_c+=$__FV_VS_CONT
        if [[ -n $__fvv_wa ]]; then __fvv_b+=$__fvv_ps; fi
    fi
    __fvv_pc=''
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
        # (memoised by _def; an entry initScreen took from its cache may not be)
        fv.video._n16 "$__fvv_f"; fv.video._n16 "$__fvv_b"
        __fvv_f=${__FV_VS_N16[__fvv_f]} __fvv_b=${__FV_VS_N16[__fvv_b]}
        if (( __fvv_f < 8 )); then __fvv_s+=";$(( 30 + __fvv_f ))"; else __fvv_s+=";$(( 82 + __fvv_f ))"; fi
        if (( __fvv_b < 8 )); then __fvv_s+=";$(( 40 + __fvv_b ))"; else __fvv_s+=";$(( 92 + __fvv_b ))"; fi
    fi
    __FV_VS_SGR[$1]=${__fvv_s}m
}

# every row damaged in full and the shown copy forgotten
fv.video._dmgall() {
    local __fvv_y
    __FV_VS_OCH=() __FV_VS_OAT=() __FV_VS_OXV=()
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
            unset '__FV_VS_OCH[__fvv_y]' '__FV_VS_OAT[__fvv_y]' '__FV_VS_OXV[__fvv_y]'
        fi
    done
}

# fv.video._alloc — W x H blanks in the default attribute (FV_SCREEN_W/H; W
# at most FV's FVMaxWidth 1024), the clip reset, everything damaged, the copy
# and the cursor shown unknown
fv.video._alloc() {
    local __fvv_w=${FV_SCREEN_W-} __fvv_h=${FV_SCREEN_H-} __fvv_y __fvv_a
    if [[ -z $__fvv_w || $__fvv_w == *[!0123456789]* || ${#__fvv_w} -gt 5 ]] || (( 10#$__fvv_w < 1 )); then __fvv_w=80; fi
    if [[ -z $__fvv_h || $__fvv_h == *[!0123456789]* || ${#__fvv_h} -gt 5 ]] || (( 10#$__fvv_h < 1 )); then __fvv_h=24; fi
    __fvv_w=$(( 10#$__fvv_w )) __fvv_h=$(( 10#$__fvv_h ))
    if (( __fvv_w > 1024 )); then
        kk.debug "Error: fv.video: the screen is $__fvv_w columns wide; the buffer keeps 1024 (FVMaxWidth)"
        __fvv_w=1024
    fi
    __FV_VS_W=$__fvv_w __FV_VS_H=$__fvv_h
    printf -v __FV_VS_SP '%*s' "$__fvv_w" ''
    # FILL[.] (no symbol) stays empty: _put appends it when the cells take a
    # per-cell symbol string instead of one symbol
    __FV_VS_FILL=([.]='')
    __FV_VS_FILL[$__FV_VS_DEF]=${__FV_VS_SP// /$__FV_VS_DEF}
    __fvv_a=${__FV_VS_FILL[$__FV_VS_DEF]}
    __FV_VS_CH=() __FV_VS_AT=() __FV_VS_OCH=() __FV_VS_OAT=() __FV_VS_WIDE=() __FV_VS_DX1=() __FV_VS_DX2=()
    __FV_VS_X=() __FV_VS_XV=() __FV_VS_OXV=() __FV_VS_WNEW=()
    for (( __fvv_y = 0; __fvv_y < __fvv_h; __fvv_y++ )); do
        __FV_VS_CH[__fvv_y]=$__FV_VS_SP __FV_VS_AT[__fvv_y]=$__fvv_a __FV_VS_WIDE[__fvv_y]=0
        __FV_VS_DX1[__fvv_y]=0 __FV_VS_DX2[__fvv_y]=$__fvv_w
    done
    # the frame's resync strings: CHA[x] = ESC[x+1G, one per column (W + 1)
    for (( __fvv_y = ${#__FV_VS_CHA[@]}; __fvv_y <= __fvv_w; __fvv_y++ )); do
        __FV_VS_CHA[__fvv_y]=$'\e['"$(( __fvv_y + 1 ))G"
    done
    __FV_VS_CX1=0 __FV_VS_CY1=0 __FV_VS_CX2=$__fvv_w __FV_VS_CY2=$__fvv_h
    __FV_VS_FORCE=0 __FV_VS_SVIS='' __FV_VS_SPOS='' __FV_VS_SSHP=''
}

# fv.video.initScreen — the buffer: ASCII mode decided (FV_ASCII, locale),
# the default palette, the colour depth (FV_COLORS; with the terminal on the
# detection, else 256), W x H blanks, the cursor hidden at 0,0
fv.video.initScreen() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_e __fvv_s
    RESULT=''
    fv.video._mode
    __FV_VS_H=0 __FV_VS_DEF=0
    if (( FV_VIDEO_ON )); then fv.video._depth 1; else fv.video._depth 0; fi
    local -n __fvv_cs=__FV_VS_CSG$__FV_VS_DEPTH
    if [[ -n $__fvv_cs && -n $__FV_VS_CPAL ]]; then
        # the default palette built before in this process at this depth (D18)
        eval "__FV_VS_PAL=($__FV_VS_CPAL) __FV_VS_SGR=($__fvv_cs)"
    else
        __FV_VS_PAL=() __FV_VS_SGR=()
        for __fvv_e in "${__FV_VS_DEFPAL[@]}"; do
            __fvv_s=$(( 16#${__fvv_e#*:} ))
            fv.video._def "${__fvv_e%%:*}" "${__FV_VS_DOS[__fvv_s & 15]}" "${__FV_VS_DOS[__fvv_s >> 4]}" 0
        done
        __FV_VS_CPAL='' __fvv_cs=''
        for __fvv_e in "${!__FV_VS_PAL[@]}"; do
            printf -v __fvv_s '[%s]=%q ' "$__fvv_e" "${__FV_VS_PAL[$__fvv_e]}"
            __FV_VS_CPAL+=$__fvv_s
            printf -v __fvv_s '[%s]=%q ' "$__fvv_e" "${__FV_VS_SGR[$__fvv_e]}"
            __fvv_cs+=$__fvv_s
        done
    fi
    fv.video._alloc
    __FV_VS_CURX=0 __FV_VS_CURY=0 __FV_VS_CURT=0
}

# fv.video.resizeScreen — after updateSize / on cmResizeApp: reallocate at
# FV_SCREEN_W x FV_SCREEN_H, clear, damage everything, reset the clip; the
# palette, the depth and the cursor stay
fv.video.resizeScreen() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
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
        elif __fvv_c=$(tput colors 2>/dev/null) && [[ -n $__fvv_c && $__fvv_c != *[!0123456789]* ]] \
            && { while [[ $__fvv_c == 0?* ]]; do __fvv_c=${__fvv_c#0}; done; (( ${#__fvv_c} > 3 || 10#$__fvv_c >= 256 )); }; then
            __fvv_n=256                                      # any count >= 256 (xterm-direct: 16777216)
        else __fvv_n=16; fi
    fi
    __FV_VS_DEPTH=$__fvv_n FV_VIDEO_COLORS=$__fvv_n
}

# fv.video.detectColorDepth — the detection chain on demand, applied as
# setColorDepth does; RESULT = 16 | 256
fv.video.detectColorDepth() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    fv.video._depth 1
    fv.video.setColorDepth "$__FV_VS_DEPTH"
    RESULT=$__FV_VS_DEPTH
}

# fv.video.setColorDepth 16|256 — rebuild every symbol's SGR, damage all
fv.video.setColorDepth() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
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
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_f=${2-} __fvv_b=${3-} __fvv_o=${4:-0} __fvv_k=1
    if [[ -n $__fvv_f && $__fvv_f != *[!0123456789]* && ${#__fvv_f} -le 3 && -n $__fvv_b && $__fvv_b != *[!0123456789]* && ${#__fvv_b} -le 3 ]]; then
        if (( 10#$__fvv_f <= 255 && 10#$__fvv_b <= 255 )); then __fvv_k=0; fi
    fi
    if (( __fvv_k )) || [[ ${1-} != [$__FV_VS_SYMS] || $__fvv_o != [01] ]]; then
        fv.video._bad definePalette 'SYM FG BG [BOLD]' "$@"
        return
    fi
    RESULT=''
    fv.video._def "$1" "$(( 10#$__fvv_f ))" "$(( 10#$__fvv_b ))" "$__fvv_o"
}

# fv.video._put — overlay the cells __fvv_t at (__fvv_x, __fvv_y), clipped;
# the cells get the symbol __fvv_a, or (__fvv_a empty) the per-cell string
# __fvv_b. Wide text (__fvv_w: \x01 / \x02 in it, markers in __fvv_xl), a
# row that holds wide cells, a row outside the clip and a symbol whose fill
# string is not built yet go through _putx.
#
# The hot path is short on purpose (P2 stage 2a): bash copies a function's
# body on every call and each simple command costs a few us on Windows, so
# the rare cases share one test and live in _putx, and the caller declares
# __fvv_n __fvv_o __fvv_r (no `local` here). Assignments inside (( )) are
# avoided: they cost more than a separate $(( )).
fv.video._put() {
    __fvv_n=${#__fvv_t} __fvv_o=0
    if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 || __fvv_w || __FV_VS_WIDE[__fvv_y] || ! ${__FV_VS_FILL[${__fvv_a:-0}]+1}0 )); then fv.video._putx; return; fi
    if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || return 0; fi
    __fvv_r=${__FV_VS_CH[__fvv_y]}
    __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_b:__fvv_o:__fvv_n}${__FV_VS_FILL[${__fvv_a:-.}]:0:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
}
# fv.video._putc — _put's columns cut by the clip: __fvv_o / __fvv_x /
# __fvv_n clipped; rc 1 when nothing is left
fv.video._putc() {
    if (( __fvv_x < __FV_VS_CX1 )); then __fvv_o=$(( __FV_VS_CX1 - __fvv_x )) __fvv_x=$__FV_VS_CX1 __fvv_n=$(( __fvv_n - __fvv_o )); fi
    if (( __fvv_x + __fvv_n > __FV_VS_CX2 )); then __fvv_n=$(( __FV_VS_CX2 - __fvv_x )); fi
    (( __fvv_n > 0 ))
}
# fv.video._putx — _put's rare cases: a row outside the clip (nothing), wide
# text or a row with wide cells (_putw), a symbol without its fill string
# (built, then _put again)
fv.video._putx() {
    if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 )); then return 0; fi
    if (( __fvv_w || __FV_VS_WIDE[__fvv_y] )); then fv.video._putw; return 0; fi
    __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}
    fv.video._put
}

# fv.video._puth H — writeBuf's repeat count: the cells __fvv_t (narrow or
# wide) on H rows from __fvv_y, each clipped as _put does; rc 2 when H is
# not an integer >= 0. Rows outside the clip are skipped without a call.
# Narrow text (stage 2c-p): the columns are clipped and the pieces cut once,
# then each row without wide cells is spliced in place (no _put call per
# row: a frame body is one write of H rows); a row with wide cells takes
# _put (and so _putw) as before.
fv.video._puth() {
    local __fvv_v __fvv_x0=$__fvv_x __fvv_y2 __fvv_s __fvv_m __fvv_e
    if ! fv.video._num "$1" || (( __fvv_v < 0 )); then return 2; fi
    __fvv_y2=$(( __fvv_y + __fvv_v ))
    if (( __fvv_y < __FV_VS_CY1 )); then __fvv_y=$__FV_VS_CY1; fi
    if (( __fvv_y2 > __FV_VS_CY2 )); then __fvv_y2=$__FV_VS_CY2; fi
    if (( __fvv_w )); then
        for (( ; __fvv_y < __fvv_y2; __fvv_y++ )); do
            __fvv_x=$__fvv_x0
            fv.video._put
        done
        return 0
    fi
    # (writeBuf: __fvv_a is empty, the symbols are __fvv_b's)
    __fvv_n=${#__fvv_t} __fvv_o=0
    if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || return 0; fi
    __fvv_s=${__fvv_t:__fvv_o:__fvv_n} __fvv_m=${__fvv_b:__fvv_o:__fvv_n} __fvv_e=$(( __fvv_x + __fvv_n ))
    for (( ; __fvv_y < __fvv_y2; __fvv_y++ )); do
        if (( __FV_VS_WIDE[__fvv_y] )); then
            local __fvv_x1=$__fvv_x __fvv_n1=$__fvv_n __fvv_o1=$__fvv_o
            __fvv_x=$__fvv_x0
            fv.video._put
            __fvv_x=$__fvv_x1 __fvv_n=$__fvv_n1 __fvv_o=$__fvv_o1
            continue
        fi
        __fvv_r=${__FV_VS_CH[__fvv_y]}
        __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}$__fvv_s${__fvv_r:__fvv_e}
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}$__fvv_m${__fvv_r:__fvv_e}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_e )); then __FV_VS_DX2[__fvv_y]=$__fvv_e; fi
    done
}

# fv.video._putw — _put with wide cells (row __fvv_y inside the clip):
#   * a wide character of the text cut by the clip or the screen edge leaves
#     a space (in the write's symbol) in its visible half;
#   * a wide character of the row that the write covers only half of loses
#     its other half: a space in its own symbol, also outside the clip;
#   * the markers the write overwrites leave __FV_VS_X, the text's markers
#     enter it; the row's flags (__FV_VS_WIDE: 1 holds \x01, 2 holds \x02)
#     and, when the side map changed, its version (__FV_VS_XV) follow;
#   * the row's WNEW flag is set for wide text or a row that held a wide
#     character (fv.views' marking reads and clears it);
#   * the damage covers the blanked halves too.
fv.video._putw() {
    local __fvv_n=${#__fvv_t} __fvv_o=0 __fvv_s __fvv_m __fvv_r __fvv_g __fvv_d1 __fvv_d2 __fvv_q __fvv_p __fvv_e __fvv_j __fvv_v=0
    if (( __fvv_x < __FV_VS_CX1 )); then __fvv_o=$(( __FV_VS_CX1 - __fvv_x )) __fvv_x=$__FV_VS_CX1; fi
    __fvv_n=$(( __fvv_n - __fvv_o ))
    if (( __fvv_x + __fvv_n > __FV_VS_CX2 )); then __fvv_n=$(( __FV_VS_CX2 - __fvv_x )); fi
    if (( __fvv_n <= 0 )); then return 0; fi
    __fvv_s=${__fvv_t:__fvv_o:__fvv_n}
    if [[ ${__fvv_s:0:1} == "$__FV_VS_CONT" ]]; then __fvv_s=" ${__fvv_s:1}"; fi
    if [[ ${__fvv_t:__fvv_o+__fvv_n:1} == "$__FV_VS_CONT" ]]; then __fvv_s=${__fvv_s:0:__fvv_n-1}' '; fi
    if [[ -n $__fvv_a ]]; then
        if [[ -z ${__FV_VS_FILL[$__fvv_a]-} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
        __fvv_m=${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}
    else
        __fvv_m=${__fvv_b:__fvv_o:__fvv_n}
    fi
    __fvv_g=${__FV_VS_CH[__fvv_y]} __fvv_d1=$__fvv_x __fvv_d2=$(( __fvv_x + __fvv_n ))
    __fvv_r=$__fvv_g
    if [[ ${__fvv_g:__fvv_x:1} == "$__FV_VS_CONT" ]]; then
        __fvv_d1=$(( __fvv_x - 1 ))
        __fvv_r=${__fvv_r:0:__fvv_d1}' '${__fvv_r:__fvv_x}
    fi
    if [[ ${__fvv_g:__fvv_d2:1} == "$__FV_VS_CONT" ]]; then
        __fvv_r=${__fvv_r:0:__fvv_d2}' '${__fvv_r:__fvv_d2+1}
        __fvv_d2=$(( __fvv_d2 + 1 ))
    fi
    # the markers that go: those of the old row in [d1, x+n)
    if [[ $__fvv_g == *"$__FV_VS_MARK"* ]]; then
        __fvv_q=${__fvv_g:__fvv_d1:__fvv_x+__fvv_n-__fvv_d1} __fvv_p=$__fvv_d1
        while [[ $__fvv_q == *"$__FV_VS_MARK"* ]]; do
            __fvv_e=${__fvv_q%%"$__FV_VS_MARK"*}
            __fvv_p=$(( __fvv_p + ${#__fvv_e} ))
            __fvv_j="$__fvv_y $__fvv_p"
            unset "__FV_VS_X[$__fvv_j]"
            __fvv_q=${__fvv_q:${#__fvv_e}+1} __fvv_p=$(( __fvv_p + 1 )) __fvv_v=1
        done
    fi
    __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}$__fvv_s${__fvv_r:__fvv_x+__fvv_n}
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}$__fvv_m${__fvv_r:__fvv_x+__fvv_n}
    # the text's markers that are written
    __fvv_q=$__fvv_xl
    while [[ -n $__fvv_q ]]; do
        __fvv_e=${__fvv_q%%"$__FV_VS_US"*} __fvv_q=${__fvv_q#*"$__FV_VS_US"}
        __fvv_p=${__fvv_e%%:*}
        if (( __fvv_p >= __fvv_o && __fvv_p < __fvv_o + __fvv_n )) && [[ ${__fvv_s:__fvv_p-__fvv_o:1} == "$__FV_VS_MARK" ]]; then
            __fvv_j="$__fvv_y $(( __fvv_x + __fvv_p - __fvv_o ))"
            __FV_VS_X[$__fvv_j]=${__fvv_e#*:}
            __fvv_v=1
        fi
    done
    __fvv_r=${__FV_VS_CH[__fvv_y]} __fvv_e=0
    if [[ $__fvv_r == *"$__FV_VS_CONT"* ]]; then __fvv_e=1; fi
    if [[ $__fvv_r == *"$__FV_VS_MARK"* ]]; then __fvv_e=$(( __fvv_e + 2 )); fi
    # (WNEW: wide text written, or a row that held a wide character written
    # into: its reader marks the row even when none shows any more)
    if (( __fvv_w || __FV_VS_WIDE[__fvv_y] & 1 )); then __FV_VS_WNEW[__fvv_y]=1; fi
    __FV_VS_WIDE[__fvv_y]=$__fvv_e
    if (( __fvv_v )); then __FV_VS_XSEQ=$(( __FV_VS_XSEQ + 1 )); __FV_VS_XV[__fvv_y]=$__FV_VS_XSEQ; fi
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_d1 )); then __FV_VS_DX1[__fvv_y]=$__fvv_d1; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_d2 )); then __FV_VS_DX2[__fvv_y]=$__fvv_d2; fi
}

# fv.video.writeStr X Y TEXT ATTR — TEXT at (X,Y) in the symbol ATTR (FV
# MoveStr + WriteLine); RESULT = the display cells TEXT advances (unclipped)
fv.video.writeStr() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x=${1-} __fvv_y=${2-} __fvv_t=${3-} __fvv_a=${4-} __fvv_b='' __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r
    if [[ $__fvv_x$__fvv_y == *[!0123456789]* || -z $__fvv_x || -z $__fvv_y || $__fvv_x == 0?* || $__fvv_y == 0?* || $__fvv_x == ????????* || $__fvv_y == ????????* ]] \
        && ! fv.video._xy "$__fvv_x" "$__fvv_y" || [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then fv.video._bad writeStr 'X Y TEXT ATTR' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeStr; return; fi
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then
        # _text's narrow cache hit, inline
        __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
        if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; else fv.video._textx; fi
    fi
    # (_put's body, inline: the most frequent write saves a call; stage 2c-p)
    RESULT=${#__fvv_t} __fvv_n=${#__fvv_t} __fvv_o=0
    if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 || __fvv_w || __FV_VS_WIDE[__fvv_y] || ! ${__FV_VS_FILL[$__fvv_a]+1}0 )); then fv.video._putx; return; fi
    if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || return 0; fi
    __fvv_r=${__FV_VS_CH[__fvv_y]}
    __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
}

# fv.video._wstr X Y TEXT ATTR — FRIEND ENTRY for the fv.* units (stage
# 2c-p): writeStr for a caller that passes two integers and one palette
# symbol it computed itself (fv.views' writers): no argument check, the
# caller-state guard kept (the text is cut and cached by characters); the
# same cells, damage and RESULT as writeStr. Not for scripts
fv.video._wstr() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeStr; return; fi
    local __fvv_x=$1 __fvv_y=$2 __fvv_t=$3 __fvv_a=$4 __fvv_b='' __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then
        __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
        if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; else fv.video._textx; fi
    fi
    # (_put's body, inline, as in writeStr)
    RESULT=${#__fvv_t} __fvv_n=${#__fvv_t} __fvv_o=0
    if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 || __fvv_w || __FV_VS_WIDE[__fvv_y] || ! ${__FV_VS_FILL[$__fvv_a]+1}0 )); then fv.video._putx; return; fi
    if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || return 0; fi
    __fvv_r=${__FV_VS_CH[__fvv_y]}
    __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
}

# fv.video._lead — __fvv_b with the symbol of every continuation cell of the
# cells __fvv_t set to its lead's (a wide character has one look); nothing to
# do for symbols all alike (a list row: one test on the short ASCII string
# instead of a walk over the multibyte cells, P3 3a-1)
fv.video._lead() {
    if [[ -z ${__fvv_b//"${__fvv_b:0:1}"/} ]]; then return 0; fi
    local __fvv_q=$__fvv_t __fvv_p=0 __fvv_e
    while [[ $__fvv_q == *"$__FV_VS_CONT"* ]]; do
        __fvv_e=${__fvv_q%%"$__FV_VS_CONT"*}
        __fvv_p=$(( __fvv_p + ${#__fvv_e} ))
        __fvv_b=${__fvv_b:0:__fvv_p}${__fvv_b:__fvv_p-1:1}${__fvv_b:__fvv_p+1}
        __fvv_q=${__fvv_q:${#__fvv_e}+1} __fvv_p=$(( __fvv_p + 1 ))
    done
}

# fv.video.writeBuf X Y TEXT ATTRS [H] — TEXT with one symbol per display
# cell (ATTRS as long as TEXT in display cells; the symbol under the second
# half of a wide character is ignored: it takes its first half's; spike
# scr_put_ca) on H rows from Y (FV WriteLine; default 1, 0 writes nothing);
# RESULT = the cells advanced along the row, whatever H
fv.video.writeBuf() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x=${1-} __fvv_y=${2-} __fvv_t=${3-} __fvv_a='' __fvv_b=${4-} __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r
    if [[ $__fvv_x$__fvv_y == *[!0123456789]* || -z $__fvv_x || -z $__fvv_y || $__fvv_x == 0?* || $__fvv_y == 0?* || $__fvv_x == ????????* || $__fvv_y == ????????* ]] \
        && ! fv.video._xy "$__fvv_x" "$__fvv_y" || [[ $__fvv_b == *[!$__FV_VS_SYMS]* ]]; then fv.video._bad writeBuf 'X Y TEXT ATTRS [H]' "$@"; return; fi
    if (( ! __FV_VS_H )); then
        # a bad H is rc 2 before the screen matters (as writeChar's COUNT)
        local __fvv_v
        if [[ ${5:-1} != 1 ]] && { ! fv.video._num "$5" || (( __fvv_v < 0 )); }; then fv.video._bad writeBuf 'X Y TEXT ATTRS [H]' "$@"; return; fi
        fv.video._noscr writeBuf; return
    fi
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then
        __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
        if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; else fv.video._textx; fi
    fi
    if (( ${#__fvv_b} != ${#__fvv_t} || __fvv_w )) || [[ ${5:-1} != 1 ]]; then fv.video._wbuf "$@"; return; fi
    RESULT=${#__fvv_t} __fvv_n=${#__fvv_t} __fvv_o=0
    # (_put's body, inline: one call less per row; D21)
    if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 || __FV_VS_WIDE[__fvv_y] )); then fv.video._putx; return; fi
    if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || return 0; fi
    __fvv_r=${__FV_VS_CH[__fvv_y]}
    __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_b:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
}
# fv.video._wbf X Y TEXT ATTRS [H] — FRIEND ENTRY for the fv.* units (stage
# 2c-p): writeBuf for a caller that passes integers and a symbol string it
# built itself (fv.views' frame rows): no check of X / Y / the symbols, the
# caller-state guard kept; the rest as writeBuf (ATTRS of another length or a
# bad H are still refused). Not for scripts
fv.video._wbf() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeBuf; return; fi
    local __fvv_x=$1 __fvv_y=$2 __fvv_t=$3 __fvv_a='' __fvv_b=$4 __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then
        __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
        if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; else fv.video._textx; fi
    fi
    if (( ${#__fvv_b} != ${#__fvv_t} || __fvv_w )) || [[ ${5:-1} != 1 ]]; then fv.video._wbuf "$@"; return; fi
    RESULT=${#__fvv_t} __fvv_n=${#__fvv_t} __fvv_o=0
    # (_put's body, inline: one call less per row; D21)
    if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 || __FV_VS_WIDE[__fvv_y] )); then fv.video._putx; return; fi
    if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || return 0; fi
    __fvv_r=${__FV_VS_CH[__fvv_y]}
    __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_b:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
}
# fv.video._wrows X Y TEXTS ATTRS — FRIEND ENTRY for fv.views.writeLines
# (D21 stage E): for every index k of the indexed array named TEXTS, in index
# order, exactly `writeBuf X Y+k TEXTS[k] ATTRS[k]` (ATTRS: the array of the
# rows' symbol strings; a missing element is ''), in one call: one guard,
# every symbol and every text checked at once (the elements joined with '0',
# a symbol and a printable character), then per row the narrow splice.
# Texts the text cache does not hold are converted at the first such row, all
# of them at once, into the cache (_wrb, P3 10.11: one validity check over the
# rows joined); a row with wide cells (a wide text, or a narrow one on a row
# with wide cells) goes through _wrw -> _putw (P3 10.12; a narrow text into a
# row whose wide cells are plain is spliced by _wrw itself, P3 3v V5). A row
# with bad symbols or ATTRS of another length goes through writeBuf itself
# (its refusal), as does a text the batch left out (none in practice: past
# 256 fresh texts the next batch takes the rest). RESULT = the widest row's
# cells (writeBuf's RESULT, the maximum over the rows; 0 for no rows); a row
# writeBuf refuses
# leaves RESULT '' and rc 2 after the other rows are written. The caller
# passes integers (no check); the names are checked here (the caller's checks
# would cost a second pass over them): rc 3 with RESULT '' and nothing written
# for a name that is no identifier, starts with __fv (any case) or is RESULT,
# or an associative array — no message: the caller reports it (fv.views'
# refusal). Not for scripts
fv.video._wrows() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if [[ -z $3 || -z $4 || $3$4 == *[!_$__FV_VS_SYMS]* || $3 == [0123456789]* || $4 == [0123456789]* || $3 == __[fF][vV]* || $4 == __[fF][vV]* || $3 == RESULT || $4 == RESULT ]]; then RESULT=''; return 3; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeBuf; return; fi
    local -n __fvv_tt=$3 __fvv_aa=$4
    local IFS=0 __fvv_x __fvv_y __fvv_t __fvv_a='' __fvv_b __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r __fvv_k __fvv_st=0 __fvv_sa=0 __fvv_ss=0 __fvv_s=0 __fvv_m=0 __fvv_e=0 __fvv_bt=0
    # (joined with '0': an associative array's attributes are 'A', no other's hold one)
    if [[ ${__fvv_tt[*]@a}${__fvv_aa[*]@a} == *A* ]]; then RESULT=''; return 3; fi
    if [[ ${__fvv_tt[*]-} == $__FV_VS_PNA ]]; then __fvv_st=1 __fvv_ss=1; fi
    if [[ ${__fvv_aa[*]-} == *[!$__FV_VS_SYMS]* ]]; then __fvv_sa=1 __fvv_ss=1; fi
    for __fvv_k in "${!__fvv_tt[@]}"; do
        __fvv_y=$(( $2 + __fvv_k )) __fvv_x=$1 __fvv_t=${__fvv_tt[__fvv_k]} __fvv_b=${__fvv_aa[__fvv_k]-}
        if (( __fvv_ss )); then
            if (( __fvv_st )) && [[ $__fvv_t == $__FV_VS_PNA ]]; then
                # (writeBuf's narrow cache hit; a wide hit or a miss: _wrx)
                __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
                if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; else fv.video._wrx || __fvv_s=1; fi
            fi
            if (( __fvv_sa )) && [[ $__fvv_b == *[!$__FV_VS_SYMS]* ]]; then __fvv_s=1; fi
        fi
        if (( __fvv_s || ${#__fvv_b} != ${#__fvv_t} )); then
            __fvv_s=0 __fvv_w=0 __fvv_xl=''
            if fv.video.writeBuf "$__fvv_x" "$__fvv_y" "${__fvv_tt[__fvv_k]}" "$__fvv_b"; then
                if (( RESULT > __fvv_m )); then __fvv_m=$RESULT; fi
            else __fvv_e=1; fi
            continue
        fi
        if (( ${#__fvv_t} > __fvv_m )); then __fvv_m=${#__fvv_t}; fi
        if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 )); then __fvv_w=0 __fvv_xl=''; continue; fi
        if (( __fvv_w || __FV_VS_WIDE[__fvv_y] )); then fv.video._wrw; continue; fi
        # (writeBuf's narrow row, as in its body)
        __fvv_n=${#__fvv_t} __fvv_o=0
        if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || continue; fi
        __fvv_r=${__FV_VS_CH[__fvv_y]}
        __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_b:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
    done
    if (( __fvv_e )); then RESULT=''; return 2; fi
    RESULT=$__fvv_m
}
# fv.video._wrw — _wrows' row with wide cells (its locals): a wide text takes
# its leads' symbols (writeBuf's rule), then _putw; the wide state is reset.
# P3 3v V5: a narrow text into a row whose wide cells are plain (WIDE 1: a
# panel beside a CJK list), inside the clip, no wide pair cut at its edges,
# is spliced here with _putw's effects (WNEW set, WIDE 0 when no wide cell
# is left, the damage X..X+N) by _wrw5 -- kept out of _wrows, whose body
# bash copies on every call of the narrow pages, and out of _wrw's body (a
# short guard here: the wide rows copy only that, F2)
fv.video._wrw() {
    if (( ! __fvv_w && __FV_VS_WIDE[__fvv_y] == 1 )) && fv.video._wrw5; then return 0; fi
    if (( __fvv_w )); then fv.video._lead; fi
    fv.video._putw
    __fvv_w=0 __fvv_xl=''
}
# fv.video._wrw5 — _wrw's splice of a narrow text into a plain-wide row (its
# locals); rc 1 (nothing changed) when the text is empty, leaves the clip or
# cuts a wide pair of the row at X or X+N: the caller's _putw then
fv.video._wrw5() {
    if (( ! ${#__fvv_t} || __fvv_x < __FV_VS_CX1 || __fvv_x + ${#__fvv_t} > __FV_VS_CX2 )); then return 1; fi
    __fvv_n=${#__fvv_t} __fvv_r=${__FV_VS_CH[__fvv_y]}
    if [[ ${__fvv_r:__fvv_x:1} == "$__FV_VS_CONT" || ${__fvv_r:__fvv_x+__fvv_n:1} == "$__FV_VS_CONT" ]]; then return 1; fi
    __fvv_r=${__fvv_r:0:__fvv_x}$__fvv_t${__fvv_r:__fvv_x+__fvv_n}
    __FV_VS_CH[__fvv_y]=$__fvv_r __FV_VS_WNEW[__fvv_y]=1
    if [[ $__fvv_r != *"$__FV_VS_CONT"* ]]; then __FV_VS_WIDE[__fvv_y]=0; fi
    __fvv_r=${__FV_VS_AT[__fvv_y]}
    __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}$__fvv_b${__fvv_r:__fvv_x+__fvv_n}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
}
# fv.video._wrx — the batch writers' row whose text the narrow cache does not
# answer (their locals, __FV_VS_V = the cache's answer): a miss converts the
# misses from this row on at once (_wrb; a batch that failed is not tried
# again: rc 1, the row is the caller's per-row case); then a narrow answer
# sets __fvv_t to the cells, a wide one __fvv_t, __fvv_w = 1 and __fvv_xl.
# rc 1 when the text is still not in the cache
fv.video._wrx() {
    if [[ $__FV_VS_V == $'\x04' ]]; then
        if (( __fvv_bt )); then return 1; fi
        fv.video._wrb || __fvv_bt=1
        __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
        if [[ $__FV_VS_V == $'\x04' ]]; then return 1; fi
        if [[ $__FV_VS_V != $'\x03'* ]]; then __fvv_t=$__FV_VS_V; return 0; fi
    fi
    __fvv_w=1 __fvv_xl=${__FV_VS_TX[$__fvv_t]-} __fvv_t=${__FV_VS_V:1}
}
# fv.video._wrb — the batch of fresh rows (P3 10.11; the caller's nameref
# __fvv_tt and row index __fvv_k): every text of __fvv_tt from index k on
# that holds a character outside printable ASCII and that the text cache
# does not hold (at most 256 of them) is converted as _text would and cached
# — the control characters per row ('?', a \x1f too), then ONE validity
# check (_san2) over the rows joined with \x1f; when every non-ASCII
# character of the batch is a plain wide one, the wide fast path once over
# the rows joined (P3 3v V1: a per-character substitution, so each row gets
# its own answer); split back, then per row the fast set, the wide fast path
# (10.12) or the walk (after V1: the wide / narrow entry from one test). All
# but the walk run in one C-locale scope (_wrb1: the text test is byte-wise there, the cache keys
# the same bytes). rc 1 (nothing cached: the rows take the per-row path; a
# safety net, the control pass leaves no \x1f in a row) when the split does
# not give the rows back
fv.video._wrb() {
    local __fvv_q __fvv_c=0 __fvv_i __fvv_r=0 __fvv_pe=${#__FV_VS_P}${#__FV_VS_B}
    local -a __fvv_ms=() __fvv_mc=() __fvv_mw=()
    # (under a caller LC_ALL a restore rejects, stderr off as in _san)
    if [[ -n ${LC_ALL-} && $LC_ALL != C && $LC_ALL != POSIX && $LC_ALL != "$__FV_VS_LOC" ]] && ! fv.video._lcknown; then
        fv.video._wrb1 2>/dev/null
    else fv.video._wrb1; fi
    if [[ ${#__FV_VS_P}${#__FV_VS_B} != "$__fvv_pe" ]]; then fv.video._lcx "$__fvv_pe" 2>/dev/null; fi
    # (the rows that need the walk, in the call's UTF-8 locale)
    for __fvv_i in "${!__fvv_mw[@]}"; do fv.video._wrbw; done
    return "$__fvv_r"
}
# fv.video._wrb1 — _wrb's C-locale part: the missed rows into __fvv_ms, the
# check, the narrow and plain wide ones cached; __fvv_mc = the sanitised
# rows, __fvv_mw[i] = the walk's 4-byte flag for a row that needs the walk
fv.video._wrb1() {
    local LC_ALL=C - IFS=$__FV_VS_US __fvv_t='' __fvv_j __fvv_f=1 __fvv_a4=0 __fvv_u=0 __fvv_s __fvv_p __fvv_wb=0
    if [[ $__fvv_pe == 11 ]] && (( ! FV_VIDEO_ASCII )); then __fvv_u=1; fi
    for __fvv_j in "${!__fvv_tt[@]}"; do
        if (( __fvv_j < __fvv_k )); then continue; fi
        __fvv_q=${__fvv_tt[__fvv_j]}
        if [[ $__fvv_q != $__FV_VS_PNA || -n ${__FV_VS_TC[$__fvv_q]+1} ]]; then continue; fi
        __fvv_ms[__fvv_c]=$__fvv_q __fvv_c=$(( __fvv_c + 1 ))
        if [[ $__fvv_q == *[[:cntrl:]]* ]]; then __fvv_q=${__fvv_q//[[:cntrl:]]/"?"}; fi
        __fvv_t+=$__fvv_q$__FV_VS_US
        if (( __fvv_c >= 256 )); then break; fi
    done
    fv.video._san2
    # (P3 3v V1: every non-ASCII character of the batch a plain wide one -> the
    # wide fast path once over the rows joined; a per-character substitution,
    # so each row's cells are its own _wfb answer; _wfb refuses a 4-byte
    # sequence. Without the substitution (bash 5.1) the test only, then the
    # loop per row (F1). Else each row takes its own class below.
    # __fvv_wb: 3 substituted, 2 the loop per row, 1 / 0 the classes)
    if (( ! __fvv_f )); then
        if fv.video._wfb 1; then __fvv_wb=3; else __fvv_wb=$?; fi
    fi
    set -f
    __fvv_mc=($__fvv_t)
    if (( ${#__fvv_mc[@]} != __fvv_c )); then __fvv_r=1; return 0; fi
    if (( ${#__FV_VS_TC[@]} + __fvv_c > 512 )); then fv.video._tcclear; fi
    for (( __fvv_i = 0; __fvv_i < __fvv_c; __fvv_i++ )); do
        __fvv_t=${__fvv_mc[__fvv_i]} __fvv_q=${__fvv_ms[__fvv_i]}
        if (( __fvv_wb == 3 )); then
            if [[ $__fvv_t == *"$__FV_VS_CONT"* ]]; then __FV_VS_TC[$__fvv_q]=$'\x03'$__fvv_t __FV_VS_TX[$__fvv_q]=''
            else __FV_VS_TC[$__fvv_q]=$__fvv_t; fi
        elif (( __fvv_wb == 2 )); then
            if [[ $__fvv_t == *[![:ascii:]]* ]]; then fv.video._wfbl; __FV_VS_TC[$__fvv_q]=$'\x03'$__fvv_t __FV_VS_TX[$__fvv_q]=''
            else __FV_VS_TC[$__fvv_q]=$__fvv_t; fi
        elif (( __fvv_f )) || fv.video._fast "$__fvv_t"; then __FV_VS_TC[$__fvv_q]=$__fvv_t
        elif [[ $__fvv_t == *[$'\xf0'-$'\xf4']* ]]; then __fvv_mw[__fvv_i]=1
        elif fv.video._wfb; then __FV_VS_TC[$__fvv_q]=$'\x03'$__fvv_t __FV_VS_TX[$__fvv_q]=''
        else __fvv_mw[__fvv_i]=0; fi
    done
}
# fv.video._wrbw — _wrb's row __fvv_i that needs the walk (_textw), cached
fv.video._wrbw() {
    local __fvv_t=${__fvv_mc[__fvv_i]} __fvv_w=0 __fvv_xl='' __fvv_a4=${__fvv_mw[__fvv_i]}
    __fvv_q=${__fvv_ms[__fvv_i]}
    fv.video._textw
    if (( __fvv_w )); then __FV_VS_TC[$__fvv_q]=$'\x03'$__fvv_t __FV_VS_TX[$__fvv_q]=$__fvv_xl
    else __FV_VS_TC[$__fvv_q]=$__fvv_t; fi
}

# fv.video._wrowsu X Y W TEXTS SYMS — FRIEND ENTRY for fv.views.writeRows (P3
# 10.2, uniform-symbol rows): for every index k of the indexed array named
# TEXTS, in order, the row TEXTS[k] in the ONE symbol SYMS[k] at (X, Y+k),
# cut or padded to W cells by fv.video's own cells (a wide character that the
# cut halves becomes a space, writeBuf's edge rule; a short row is padded
# with spaces): the same cells, symbols, side map and damage as a writeBuf of
# the text clipped to [X, X+W) plus spaces up to X+W, in one call. W < 1
# writes nothing. Fresh texts are converted at once (_wrb), as in _wrows. A
# row whose SYMS[k] is not one symbol is refused: rc 2 and RESULT '' after
# the other rows; else RESULT = W (0 for no rows or W < 1). X, Y, W are the
# caller's integers (no check); the names as in _wrows (rc 3, no message);
# no screen rc 1. A wide cache hit is read inline, a short row padded inline;
# a plain wide row (no marker in the text or the row, inside the clip, no
# wide pair of the row cut at X or X+W) is spliced here with _putw's effects
# (P3 3v V2), any other row with wide cells takes _putw. Not for scripts
fv.video._wrowsu() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if [[ -z $4 || -z $5 || $4$5 == *[!_$__FV_VS_SYMS]* || $4 == [0123456789]* || $5 == [0123456789]* || $4 == __[fF][vV]* || $5 == __[fF][vV]* || $4 == RESULT || $5 == RESULT ]]; then RESULT=''; return 3; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeRows; return; fi
    local -n __fvv_tt=$4 __fvv_sy=$5
    local IFS=0 __fvv_x __fvv_y __fvv_t __fvv_a __fvv_b='' __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r __fvv_k __fvv_c=$3 __fvv_p='' __fvv_m=0 __fvv_e=0 __fvv_bt=0 __fvv_st=0 __fvv_q
    if [[ ${__fvv_tt[*]@a}${__fvv_sy[*]@a} == *A* ]]; then RESULT=''; return 3; fi
    if (( __fvv_c < 1 )); then __fvv_c=0; fi
    if [[ ${__fvv_tt[*]-} == $__FV_VS_PNA ]]; then __fvv_st=1; fi
    for __fvv_k in "${!__fvv_tt[@]}"; do
        __fvv_y=$(( $2 + __fvv_k )) __fvv_a=${__fvv_sy[__fvv_k]-} __fvv_m=$__fvv_c
        if [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then __fvv_e=1; continue; fi
        if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 || ! __fvv_c )); then continue; fi
        __fvv_x=$1 __fvv_t=${__fvv_tt[__fvv_k]}
        if (( __fvv_st )) && [[ $__fvv_t == $__FV_VS_PNA ]]; then
            # (a narrow or a wide cache hit inline; a miss: the batch, else _textx)
            __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
            if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V
            elif [[ $__FV_VS_V == $'\x03'* ]]; then __fvv_w=1 __fvv_xl=${__FV_VS_TX[$__fvv_t]-} __fvv_t=${__FV_VS_V:1}
            else fv.video._wrx || fv.video._textx; fi
        fi
        # (the pad inline from the screen's spaces, F3; a longer pad or a cut: _wrcut)
        __fvv_n=${#__fvv_t}
        if (( __fvv_n < __fvv_c && __fvv_c - __fvv_n <= ${#__FV_VS_SP} )); then __fvv_t+=${__FV_VS_SP:0:__fvv_c-__fvv_n}
        elif (( __fvv_n != __fvv_c )); then fv.video._wrcut; fi
        if [[ -z ${__FV_VS_FILL[$__fvv_a]+1} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
        if (( __fvv_w || __FV_VS_WIDE[__fvv_y] )); then
            # (P3 3v V2: a plain wide row -- no marker in the text or the row,
            # inside the clip, no wide pair of the row cut at X or X+W --
            # spliced in place with exactly _putw's effects: the cells, the
            # symbol's fill, WNEW, WIDE from one test, the damage X..X+W)
            __fvv_r=${__FV_VS_CH[__fvv_y]}
            if [[ -z $__fvv_xl ]] && (( ! (__FV_VS_WIDE[__fvv_y] & 2) && __fvv_x >= __FV_VS_CX1 && __fvv_x + __fvv_c <= __FV_VS_CX2 )) \
                && [[ ${__fvv_r:__fvv_x:1} != "$__FV_VS_CONT" && ${__fvv_r:__fvv_x+__fvv_c:1} != "$__FV_VS_CONT" ]]; then
                __fvv_r=${__fvv_r:0:__fvv_x}$__fvv_t${__fvv_r:__fvv_x+__fvv_c}
                __FV_VS_CH[__fvv_y]=$__fvv_r __fvv_q=${__FV_VS_AT[__fvv_y]}
                __FV_VS_AT[__fvv_y]=${__fvv_q:0:__fvv_x}${__FV_VS_FILL[$__fvv_a]:0:__fvv_c}${__fvv_q:__fvv_x+__fvv_c}
                if (( __fvv_w || __FV_VS_WIDE[__fvv_y] & 1 )); then __FV_VS_WNEW[__fvv_y]=1; fi
                if [[ $__fvv_r == *"$__FV_VS_CONT"* ]]; then __FV_VS_WIDE[__fvv_y]=1; else __FV_VS_WIDE[__fvv_y]=0; fi
                if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
                if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_c )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_c )); fi
            else
                fv.video._putw
            fi
            __fvv_w=0 __fvv_xl=''
            continue
        fi
        # (writeStr's narrow row, as in its body: the symbol's fill string)
        __fvv_n=$__fvv_c __fvv_o=0
        if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 )); then fv.video._putc || continue; fi
        __fvv_r=${__FV_VS_CH[__fvv_y]}
        __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
    done
    if (( __fvv_e )); then RESULT=''; return 2; fi
    RESULT=$__fvv_m
}
# fv.video._wrcut — _wrowsu's cells __fvv_t (__fvv_n of them) to __fvv_c
# cells: padded with spaces, or cut (a wide character the cut halves leaves
# a space; its marker entry, past the cells, is never written)
fv.video._wrcut() {
    if (( __fvv_n < __fvv_c )); then
        if (( ${#__fvv_p} < __fvv_c )); then printf -v __fvv_p '%*s' "$__fvv_c" ''; fi
        __fvv_t+=${__fvv_p:0:__fvv_c-__fvv_n}
    elif [[ ${__fvv_t:__fvv_c:1} == "$__FV_VS_CONT" ]]; then __fvv_t=${__fvv_t:0:__fvv_c-1}' '
    else __fvv_t=${__fvv_t:0:__fvv_c}; fi
}
# fv.video._wbuf X Y TEXT ATTRS [H] — writeBuf's less common cases (its
# locals): ATTRS of another length (rc 2), wide cells (the leads' symbols),
# a repeat count other than 1
fv.video._wbuf() {
    if (( ${#__fvv_b} != ${#__fvv_t} )); then fv.video._bad writeBuf 'ATTRS not as long as TEXT' "$@"; return; fi
    if (( __fvv_w )); then fv.video._lead; fi
    if [[ ${5:-1} == 1 ]]; then RESULT=${#__fvv_t}; fv.video._put; return 0; fi
    if ! fv.video._puth "$5"; then fv.video._bad writeBuf 'X Y TEXT ATTRS [H]' "$@"; return; fi
    RESULT=${#__fvv_t}
}

# fv.video.writeCStr X Y TEXT ATTR1 ATTR2 — FV MoveCStr: each '~' switches
# between ATTR1 and ATTR2 and takes no cell (nor splits a cluster: a mark
# after it joins the cell before it); a cell takes the symbol of its base
# character. RESULT = the cells advanced. Cached like _text, in arrays of its
# own keyed by TEXT (__FV_VS_SC the cells, __FV_VS_SX the markers, __FV_VS_TB
# the symbol string with \x03 / \x04 for ATTR1 / 2).
fv.video.writeCStr() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x=${1-} __fvv_y=${2-} __fvv_t=${3-} __fvv_a='' __fvv_b='' __fvv_1=${4-} __fvv_2=${5-} __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r
    if [[ $__fvv_x$__fvv_y == *[!0123456789]* || -z $__fvv_x || -z $__fvv_y || $__fvv_x == 0?* || $__fvv_y == 0?* || $__fvv_x == ????????* || $__fvv_y == ????????* ]] \
        && ! fv.video._xy "$__fvv_x" "$__fvv_y" || [[ $__fvv_1 != [$__FV_VS_SYMS] || $__fvv_2 != [$__FV_VS_SYMS] ]]; then
        fv.video._bad writeCStr 'X Y TEXT ATTR1 ATTR2' "$@"
        return
    fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeCStr; return; fi
    # an empty TEXT writes nothing (and is no key: bash refuses an empty one)
    if [[ -z $__fvv_t ]]; then RESULT=0; return 0; fi
    __FV_VS_V=${__FV_VS_SC[$__fvv_t]-$'\x04'}
    if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_b=${__FV_VS_TB[$__fvv_t]-} __fvv_t=$__FV_VS_V
    else fv.video._cstr; fi
    __fvv_b=${__fvv_b//$'\x03'/$__fvv_1} __fvv_b=${__fvv_b//$'\x04'/$__fvv_2}
    RESULT=${#__fvv_t}
    fv.video._put
}

# fv.video._cstr — writeCStr for a wide cache hit (\x03 + cells) or a miss
# (kept apart so that the common narrow hit copies a short body): the cells
# of __fvv_t, the symbol string __fvv_b (\x03 / \x04 for ATTR1 / 2), the
# markers __fvv_xl and __fvv_w, cached
fv.video._cstr() {
    local __fvv_key=$__fvv_t __fvv_f=1 __fvv_a4=0 __fvv_s __fvv_p __fvv_c='' __fvv_cn=0 __fvv_pc='' __fvv_pw=0 __fvv_pk='' __fvv_pp=0 __fvv_pz=0 __fvv_pr=0 __fvv_ps='' __fvv_wa=$'\x03'
    if [[ $__FV_VS_V != $'\x04' ]]; then
        __fvv_b=${__FV_VS_TB[$__fvv_key]-} __fvv_w=1 __fvv_xl=${__FV_VS_SX[$__fvv_key]-} __fvv_t=${__FV_VS_V:1}
    else
        if [[ $__fvv_t == $__FV_VS_PNA ]]; then fv.video._san; fi
        if (( __fvv_f )); then
            # every character one cell: the segments' symbols by their lengths
            while :; do
                __fvv_s=${__fvv_t%%'~'*}
                __fvv_c+=$__fvv_s
                printf -v __fvv_p '%*s' "${#__fvv_s}" ''
                __fvv_b+=${__fvv_p// /$__fvv_wa}
                if [[ $__fvv_s == "$__fvv_t" ]]; then break; fi
                __fvv_t=${__fvv_t#*'~'}
                if [[ $__fvv_wa == $'\x03' ]]; then __fvv_wa=$'\x04'; else __fvv_wa=$'\x03'; fi
            done
        else
            # the walk, segment by segment: the state carries over a '~'
            while :; do
                __fvv_s=${__fvv_t%%'~'*}
                __fvv_p=$__fvv_t __fvv_t=$__fvv_s
                fv.video._walk
                if [[ $__fvv_s == "$__fvv_p" ]]; then break; fi
                __fvv_t=${__fvv_p#*'~'}
                if [[ $__fvv_wa == $'\x03' ]]; then __fvv_wa=$'\x04'; else __fvv_wa=$'\x03'; fi
            done
            fv.video._wfin
            if [[ -n $__fvv_xl || $__fvv_c == *"$__FV_VS_CONT"* ]]; then __fvv_w=1; fi
        fi
        __fvv_t=$__fvv_c
        if (( ${#__FV_VS_SC[@]} >= 512 )); then fv.video._tcclear; fi
        __FV_VS_TB[$__fvv_key]=$__fvv_b
        if (( __fvv_w )); then __FV_VS_SC[$__fvv_key]=$'\x03'$__fvv_t __FV_VS_SX[$__fvv_key]=$__fvv_xl
        else __FV_VS_SC[$__fvv_key]=$__fvv_t; fi
    fi
}

# fv.video._unit — the first cluster of the text __fvv_t ('' is a blank) as
# a fill unit: __fvv_u = its cells ('c', 'c\x01', '\x02' or '\x02\x01'),
# __fvv_uc = the content of a marker ('' otherwise)
fv.video._unit() {
    local __fvv_w=0 __fvv_xl=''
    __fvv_uc=''
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then fv.video._text; fi
    __fvv_u=${__fvv_t:0:1}
    if (( __fvv_w )); then
        if [[ ${__fvv_t:1:1} == "$__FV_VS_CONT" ]]; then __fvv_u+=$__FV_VS_CONT; fi
        if [[ $__fvv_u == "$__FV_VS_MARK"* ]]; then __fvv_uc=${__fvv_xl#0:} __fvv_uc=${__fvv_uc%%"$__FV_VS_US"*}; fi
    fi
}

# fv.video._rect — the rectangle __fvv_x __fvv_y, __fvv_rw cells wide,
# __fvv_h high, clipped, filled with the unit __fvv_u (_unit) in the symbol
# __fvv_a. A wide unit fills whole pairs and a space when __fvv_rw is odd; a
# pair cut by the clip leaves a space in its visible half. Rows with wide
# cells and wide units go through _putw. (The line of a wide unit or a
# marker is built by _rline: the common narrow fill copies a short body.)
fv.video._rect() {
    local __fvv_x1 __fvv_y1 __fvv_x2 __fvv_y2 __fvv_l __fvv_m __fvv_n __fvv_r __fvv_rl='' __fvv_wu=0
    __fvv_x1=$__fvv_x __fvv_y1=$__fvv_y __fvv_x2=$(( __fvv_x + __fvv_rw )) __fvv_y2=$(( __fvv_y + __fvv_h ))
    if (( __fvv_x1 < __FV_VS_CX1 )); then __fvv_x1=$__FV_VS_CX1; fi
    if (( __fvv_y1 < __FV_VS_CY1 )); then __fvv_y1=$__FV_VS_CY1; fi
    if (( __fvv_x2 > __FV_VS_CX2 )); then __fvv_x2=$__FV_VS_CX2; fi
    if (( __fvv_y2 > __FV_VS_CY2 )); then __fvv_y2=$__FV_VS_CY2; fi
    __fvv_n=$(( __fvv_x2 - __fvv_x1 ))
    if (( __fvv_n <= 0 || __fvv_y2 <= __fvv_y1 )); then return 0; fi
    if [[ -z ${__FV_VS_FILL[$__fvv_a]-} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
    __fvv_m=${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}
    if (( ${#__fvv_u} == 1 )) && [[ $__fvv_u != "$__FV_VS_MARK" ]]; then
        __fvv_l=${__FV_VS_SP:0:__fvv_n}
        if [[ $__fvv_u != ' ' ]]; then __fvv_l=${__fvv_l// /"$__fvv_u"}; fi
    else
        __fvv_wu=1
        fv.video._rline
    fi
    for (( __fvv_y = __fvv_y1; __fvv_y < __fvv_y2; __fvv_y++ )); do
        if (( __fvv_wu || __FV_VS_WIDE[__fvv_y] )); then fv.video._rrow; continue; fi
        __fvv_r=${__FV_VS_CH[__fvv_y]}
        __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x1}$__fvv_l${__fvv_r:__fvv_x2}
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x1}$__fvv_m${__fvv_r:__fvv_x2}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x1 )); then __FV_VS_DX1[__fvv_y]=$__fvv_x1; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x2 )); then __FV_VS_DX2[__fvv_y]=$__fvv_x2; fi
    done
}
# fv.video._rline — _rect's line for a wide unit or a narrow marker: __fvv_l
# (the cells of the clipped line) and __fvv_rl (its markers)
fv.video._rline() {
    local __fvv_s=$(( __fvv_x1 - __fvv_x )) __fvv_k __fvv_q __fvv_e __fvv_p
    if (( ${#__fvv_u} == 1 )); then
        # a narrow marker: n copies
        printf -v __fvv_l '%*s' "$__fvv_n" ''
        __fvv_l=${__fvv_l// /"$__fvv_u"}
    else
        # a pair: n / 2 + 2 copies, cut to n from the pattern's phase
        printf -v __fvv_l '%*s' "$(( __fvv_n / 2 + 2 ))" ''
        __fvv_l=${__fvv_l// /"$__fvv_u"}
        __fvv_l=${__fvv_l:__fvv_s % 2:__fvv_n}
        # past the last whole pair (an odd width): spaces
        __fvv_p=$(( __fvv_rw / 2 * 2 ))
        if (( __fvv_s + __fvv_n > __fvv_p )); then
            __fvv_k=$(( __fvv_p - __fvv_s ))
            if (( __fvv_k < 0 )); then __fvv_k=0; fi
            printf -v __fvv_q '%*s' "$(( __fvv_n - __fvv_k ))" ''
            __fvv_l=${__fvv_l:0:__fvv_k}$__fvv_q
        fi
        # a pair cut by the clip: a space in its visible half
        if [[ ${__fvv_l:0:1} == "$__FV_VS_CONT" ]]; then __fvv_l=" ${__fvv_l:1}"; fi
        if (( (__fvv_s + __fvv_n) % 2 == 1 && __fvv_s + __fvv_n < __fvv_p )); then __fvv_l=${__fvv_l:0:__fvv_n-1}' '; fi
    fi
    # the markers of the line
    if [[ -n $__fvv_uc ]]; then
        __fvv_q=$__fvv_l __fvv_p=0
        while [[ $__fvv_q == *"$__FV_VS_MARK"* ]]; do
            __fvv_e=${__fvv_q%%"$__FV_VS_MARK"*}
            __fvv_p=$(( __fvv_p + ${#__fvv_e} ))
            __fvv_rl+=$__fvv_p:$__fvv_uc$__FV_VS_US
            __fvv_q=${__fvv_q:${#__fvv_e}+1} __fvv_p=$(( __fvv_p + 1 ))
        done
    fi
}
# fv.video._rrow — one row of _rect through _putw (the line is inside the clip)
fv.video._rrow() {
    local __fvv_x=$__fvv_x1 __fvv_t=$__fvv_l __fvv_xl=$__fvv_rl __fvv_b='' __fvv_w=1
    fv.video._putw
}

# fv.video.writeChar X Y CH ATTR [COUNT] — the first character (cluster) of
# CH ('' is a blank) COUNT times (default 1; FV MoveChar); RESULT = its width
# x COUNT
fv.video.writeChar() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x=${1-} __fvv_y=${2-} __fvv_v=${5:-1} __fvv_rw __fvv_h=1 __fvv_t=${3:- } __fvv_a=${4-} __fvv_u __fvv_uc
    if [[ $__fvv_x$__fvv_y == *[!0123456789]* || -z $__fvv_x || -z $__fvv_y || $__fvv_x == 0?* || $__fvv_y == 0?* || $__fvv_x == ????????* || $__fvv_y == ????????* ]] \
        && ! fv.video._xy "$__fvv_x" "$__fvv_y" || [[ $__fvv_a != [$__FV_VS_SYMS] ]] \
        || { [[ $__fvv_v == *[!0123456789]* || $__fvv_v == 0?* || $__fvv_v == ????????* ]] && { ! fv.video._num "$__fvv_v" || (( __fvv_v < 0 )); }; }; then
        fv.video._bad writeChar 'X Y CH ATTR [COUNT]' "$@"
        return
    fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeChar; return; fi
    fv.video._unit
    __fvv_rw=$(( __fvv_v * ${#__fvv_u} ))
    RESULT=$__fvv_rw
    fv.video._rect
}

# fv.video.fillRect X Y W H ATTR [CH] — the rectangle in ATTR filled with the
# first character (cluster) of CH (default a blank), clipped; a wide CH fills
# whole pairs and a space when W is odd; RESULT = W (0 when negative)
fv.video.fillRect() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x=${1-} __fvv_y=${2-} __fvv_rw=${3-} __fvv_h=${4-} __fvv_t=${6:- } __fvv_a=${5-} __fvv_u __fvv_uc
    if [[ $__fvv_x$__fvv_y$__fvv_rw$__fvv_h == *[!0123456789]* || -z $__fvv_x || -z $__fvv_y || -z $__fvv_rw || -z $__fvv_h \
        || $__fvv_x == 0?* || $__fvv_y == 0?* || $__fvv_rw == 0?* || $__fvv_h == 0?* \
        || $__fvv_x == ????????* || $__fvv_y == ????????* || $__fvv_rw == ????????* || $__fvv_h == ????????* ]] \
        && ! fv.video._xywh "$__fvv_x" "$__fvv_y" "$__fvv_rw" "$__fvv_h" || [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then
        fv.video._bad fillRect 'X Y W H ATTR [CH]' "$@"
        return
    fi
    if (( ! __FV_VS_H )); then fv.video._noscr fillRect; return; fi
    fv.video._unit
    RESULT=$(( __fvv_rw < 0 ? 0 : __fvv_rw ))
    fv.video._rect
}

# fv.video.fillColumns Y H ATTR CH X [X ...] — the columns X (one cell wide
# each) on the rows Y .. Y+H-1 filled with the first character (cluster) of
# CH ('' a blank) in ATTR, clipped: the same cells, damage and wide-character
# rules as one `fillRect X Y 1 H ATTR CH` per column (a wide CH leaves a
# space in a one-cell column), in one call — a frame's two sides (stage
# 2c-p). RESULT = 1 (the cells a column advances, as fillRect's W 1)
fv.video.fillColumns() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    # (the array first: kkore's unit lint reads `${4:- }` as the end of the body)
    local -a __fvv_cs=()
    local __fvv_y=${1-} __fvv_h=${2-} __fvv_a=${3-} __fvv_t=${4:- } __fvv_v __fvv_c __fvv_i
    if (( $# < 5 )) || [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then fv.video._bad fillColumns 'Y H ATTR CH X [X ...]' "$@"; return; fi
    for __fvv_c in "$1" "$2" "${@:5}"; do
        if [[ -n $__fvv_c && $__fvv_c != *[!0123456789]* && $__fvv_c != 0?* && ${#__fvv_c} -lt 8 ]]; then continue; fi
        if ! fv.video._num "$__fvv_c"; then fv.video._bad fillColumns 'Y H ATTR CH X [X ...]' "$@"; return; fi
    done
    if (( ! __FV_VS_H )); then fv.video._noscr fillColumns; return; fi
    # (plain digits are their value; _num for a sign or leading zeros)
    if [[ $1 == *[!0123456789]* || $1 == 0?* ]]; then fv.video._num "$1"; __fvv_y=$__fvv_v; fi
    if [[ $2 == *[!0123456789]* || $2 == 0?* ]]; then fv.video._num "$2"; __fvv_h=$__fvv_v; fi
    # the columns ascending, each once
    for __fvv_c in "${@:5}"; do
        if [[ $__fvv_c == *[!0123456789]* || $__fvv_c == 0?* ]]; then fv.video._num "$__fvv_c"; else __fvv_v=$__fvv_c; fi
        for (( __fvv_i = ${#__fvv_cs[@]}; __fvv_i > 0; __fvv_i-- )); do
            if (( __fvv_cs[__fvv_i - 1] <= __fvv_v )); then break; fi
        done
        # (a column given twice: filled once; found before anything moves)
        if (( __fvv_i && __fvv_cs[__fvv_i - 1] == __fvv_v )); then continue; fi
        __fvv_cs=("${__fvv_cs[@]:0:__fvv_i}" "$__fvv_v" "${__fvv_cs[@]:__fvv_i}")
    done
    fv.video._fcw
}
# fv.video._fcf Y H ATTR CH X1 [X2] — FRIEND ENTRY for the fv.* units (stage
# 2c-p): fillColumns for a caller that passes integers, a palette symbol and
# one or two columns in ascending order (a frame's sides): no argument
# check, the caller-state guard kept. Not for scripts
fv.video._fcf() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr fillColumns; return; fi
    local -a __fvv_cs=("${@:5}")
    local __fvv_y=$1 __fvv_h=$2 __fvv_a=$3 __fvv_t=${4:- }
    fv.video._fcw
}
# fv.video._fcw — fillColumns' work (its locals: __fvv_y __fvv_h __fvv_a
# __fvv_t and __fvv_cs, the columns ascending, each once): RESULT = 1
fv.video._fcw() {
    local __fvv_x __fvv_rw=1 __fvv_u __fvv_uc __fvv_c __fvv_yy __fvv_y2 __fvv_r __fvv_l __fvv_c1 __fvv_c2 __fvv_n __fvv_e __fvv_g2 __fvv_l2='' __fvv_a2=''
    # (RESULT after _unit: its text walk sets RESULT on a cache miss)
    fv.video._unit
    RESULT=1
    # (a wide unit or a marker: fillRect's own path, column by column)
    if (( ${#__fvv_u} != 1 )) || [[ $__fvv_u == "$__FV_VS_MARK" ]]; then fv.video._fcolsw "${__fvv_cs[@]}"; return 0; fi
    # the columns inside the clip
    __fvv_c1=${__fvv_cs[0]} __fvv_c2=${__fvv_cs[-1]} __fvv_n=${#__fvv_cs[@]}
    if (( __fvv_c1 < __FV_VS_CX1 || __fvv_c2 >= __FV_VS_CX2 )); then
        local -a __fvv_ci=()
        for __fvv_c in "${__fvv_cs[@]}"; do
            if (( __fvv_c >= __FV_VS_CX1 && __fvv_c < __FV_VS_CX2 )); then __fvv_ci+=("$__fvv_c"); fi
        done
        __fvv_cs=("${__fvv_ci[@]}") __fvv_n=${#__fvv_ci[@]}
        if (( ! __fvv_n )); then return 0; fi
        __fvv_c1=${__fvv_cs[0]} __fvv_c2=${__fvv_cs[-1]}
    fi
    # (_fcf given the same column twice: one column)
    if (( __fvv_n == 2 && __fvv_c1 == __fvv_c2 )); then __fvv_n=1; fi
    __fvv_yy=$__fvv_y __fvv_y2=$(( __fvv_y + __fvv_h ))
    if (( __fvv_yy < __FV_VS_CY1 )); then __fvv_yy=$__FV_VS_CY1; fi
    if (( __fvv_y2 > __FV_VS_CY2 )); then __fvv_y2=$__FV_VS_CY2; fi
    if (( __fvv_yy >= __fvv_y2 )); then return 0; fi
    __fvv_l=$__fvv_u __fvv_e=$(( __fvv_c2 + 1 )) __fvv_g2=$(( __fvv_c2 - __fvv_c1 - 1 ))
    # (more than two columns, or a row with wide cells among the rows: cell
    # by cell through fillRect's path; the rows' flags joined once)
    __fvv_r="${__FV_VS_WIDE[*]:__fvv_yy:__fvv_y2-__fvv_yy}"
    if (( __fvv_n > 2 )) || [[ $__fvv_r == *[123456789]* ]]; then fv.video._fcolsc; return 0; fi
    # (one or two columns, narrow rows: one splice per row and string)
    if (( __fvv_n == 2 )); then __fvv_l2=$__fvv_l __fvv_a2=$__fvv_a; else __fvv_g2=0; fi
    for (( ; __fvv_yy < __fvv_y2; __fvv_yy++ )); do
        __fvv_r=${__FV_VS_CH[__fvv_yy]}
        __FV_VS_CH[__fvv_yy]=${__fvv_r:0:__fvv_c1}$__fvv_l${__fvv_r:__fvv_c1+1:__fvv_g2}$__fvv_l2${__fvv_r:__fvv_e}
        __fvv_r=${__FV_VS_AT[__fvv_yy]}
        __FV_VS_AT[__fvv_yy]=${__fvv_r:0:__fvv_c1}$__fvv_a${__fvv_r:__fvv_c1+1:__fvv_g2}$__fvv_a2${__fvv_r:__fvv_e}
        if (( ${__FV_VS_DX1[__fvv_yy]-99999} > __fvv_c1 )); then __FV_VS_DX1[__fvv_yy]=$__fvv_c1; fi
        if (( ${__FV_VS_DX2[__fvv_yy]-0} < __fvv_e )); then __FV_VS_DX2[__fvv_yy]=$__fvv_e; fi
    done
}

# fv.video._fcolsw X... — fillColumns with a wide unit or a marker (its
# locals): each column through _rect, as fillRect X Y 1 H does
fv.video._fcolsw() {
    local __fvv_y0=$__fvv_y
    for __fvv_c; do
        fv.video._num "$__fvv_c"
        __fvv_x=$__fvv_v __fvv_y=$__fvv_y0
        fv.video._rect
    done
}
# fv.video._fcolsc — fillColumns with more than two columns, or with a row
# holding wide cells (its locals: __fvv_cs, rows __fvv_yy .. __fvv_y2): cell
# by cell through _rect (rare: a frame has two sides; apart because bash
# copies a function's body on every call)
fv.video._fcolsc() {
    for (( ; __fvv_yy < __fvv_y2; __fvv_yy++ )); do
        for __fvv_c in "${__fvv_cs[@]}"; do
            __fvv_x=$__fvv_c __fvv_y=$__fvv_yy __fvv_h=1
            fv.video._rect
        done
    done
}

# fv.video._xywh X Y W H — the slow path of a rectangle's check: __fvv_x
# __fvv_y (_xy) and __fvv_rw __fvv_h (_num: any integer, negative included);
# rc 2 when one is not an integer
fv.video._xywh() {
    local __fvv_v
    fv.video._xy "$1" "$2" || return 2
    fv.video._num "$3" || return 2
    __fvv_rw=$__fvv_v
    fv.video._num "$4" || return 2
    __fvv_h=$__fvv_v
}

# fv.video.shadeRect X Y W H [ATTR] — FV's shadow: the cells of the
# rectangle keep their characters (wide halves and markers untouched) and
# take the symbol ATTR (default V, the reserved shadow symbol: FV ShadowAttr
# $08, dark grey on black). Clipped like every write; a wide character of
# which the clipped rectangle covers one half is shaded whole, also its half
# outside the rectangle or the clip (a wide character has one look: a
# terminal draws it in its first half's colours). Damage as for a write;
# RESULT = W (0 when negative).
fv.video.shadeRect() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x=${1-} __fvv_y=${2-} __fvv_rw=${3-} __fvv_h=${4-} __fvv_a=${5:-$__FV_VS_SHADOW}
    if [[ $__fvv_x$__fvv_y$__fvv_rw$__fvv_h == *[!0123456789]* || -z $__fvv_x || -z $__fvv_y || -z $__fvv_rw || -z $__fvv_h \
        || $__fvv_x == 0?* || $__fvv_y == 0?* || $__fvv_rw == 0?* || $__fvv_h == 0?* \
        || $__fvv_x == ????????* || $__fvv_y == ????????* || $__fvv_rw == ????????* || $__fvv_h == ????????* ]] \
        && ! fv.video._xywh "$__fvv_x" "$__fvv_y" "$__fvv_rw" "$__fvv_h" || [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then
        fv.video._bad shadeRect 'X Y W H [ATTR]' "$@"
        return
    fi
    if (( ! __FV_VS_H )); then fv.video._noscr shadeRect; return; fi
    RESULT=$(( __fvv_rw < 0 ? 0 : __fvv_rw ))
    fv.video._shade
}

# fv.video._shadef X Y W H — FRIEND ENTRY for the fv.* units (stage 2c-p):
# shadeRect X Y W H in the shadow symbol for a caller that passes four
# integers it computed itself: no argument check, the caller-state guard
# kept (a row with wide cells is cut by characters). RESULT is left alone;
# rc 1 without a screen. Not for scripts (shadeRect checks what it is given)
fv.video._shadef() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if (( ! __FV_VS_H )); then return 1; fi
    local __fvv_x=$1 __fvv_y=$2 __fvv_rw=$3 __fvv_h=$4 __fvv_a=$__FV_VS_SHADOW
    fv.video._shade
}

# fv.video._shade — shadeRect's rows: the symbol strings of the clipped
# rectangle replaced; in a row with wide characters a pair cut by the edge
# is widened to both halves first (_shadew)
fv.video._shade() {
    local __fvv_x1 __fvv_y1 __fvv_x2 __fvv_y2 __fvv_m __fvv_n __fvv_r
    __fvv_x1=$__fvv_x __fvv_y1=$__fvv_y __fvv_x2=$(( __fvv_x + __fvv_rw )) __fvv_y2=$(( __fvv_y + __fvv_h ))
    if (( __fvv_x1 < __FV_VS_CX1 )); then __fvv_x1=$__FV_VS_CX1; fi
    if (( __fvv_y1 < __FV_VS_CY1 )); then __fvv_y1=$__FV_VS_CY1; fi
    if (( __fvv_x2 > __FV_VS_CX2 )); then __fvv_x2=$__FV_VS_CX2; fi
    if (( __fvv_y2 > __FV_VS_CY2 )); then __fvv_y2=$__FV_VS_CY2; fi
    __fvv_n=$(( __fvv_x2 - __fvv_x1 ))
    if (( __fvv_n <= 0 || __fvv_y2 <= __fvv_y1 )); then return 0; fi
    if [[ -z ${__FV_VS_FILL[$__fvv_a]-} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
    __fvv_m=${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}
    for (( __fvv_y = __fvv_y1; __fvv_y < __fvv_y2; __fvv_y++ )); do
        if (( __FV_VS_WIDE[__fvv_y] & 1 )); then fv.video._shadew; continue; fi
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x1}$__fvv_m${__fvv_r:__fvv_x2}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x1 )); then __FV_VS_DX1[__fvv_y]=$__fvv_x1; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x2 )); then __FV_VS_DX2[__fvv_y]=$__fvv_x2; fi
    done
}
# fv.video._shadew — one row of _shade that holds wide characters: a
# continuation at x1 (the pair starts left of it) or at x2 (the pair ends
# right of it) widens the range to the whole pair
fv.video._shadew() {
    local __fvv_a1=$__fvv_x1 __fvv_a2=$__fvv_x2
    if [[ ${__FV_VS_CH[__fvv_y]:__fvv_x1:1} == "$__FV_VS_CONT" ]]; then __fvv_a1=$(( __fvv_x1 - 1 )); fi
    if [[ ${__FV_VS_CH[__fvv_y]:__fvv_x2:1} == "$__FV_VS_CONT" ]]; then __fvv_a2=$(( __fvv_x2 + 1 )); fi
    __FV_VS_AT[__fvv_y]=${__FV_VS_AT[__fvv_y]:0:__fvv_a1}${__FV_VS_FILL[$__fvv_a]:0:__fvv_a2-__fvv_a1}${__FV_VS_AT[__fvv_y]:__fvv_a2}
    if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_a1 )); then __FV_VS_DX1[__fvv_y]=$__fvv_a1; fi
    if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_a2 )); then __FV_VS_DX2[__fvv_y]=$__fvv_a2; fi
}

# fv.video.clearScreen [ATTR] — the whole screen blank in ATTR (default: the
# default symbol), whatever the clip; damage all (rows the terminal already
# shows that way emit nothing)
fv.video.clearScreen() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_a=${1:-$__FV_VS_DEF} __fvv_y
    if [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then fv.video._bad clearScreen '[ATTR]' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr clearScreen; return; fi
    RESULT=''
    if [[ -z ${__FV_VS_FILL[$__fvv_a]-} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
    __FV_VS_X=()
    for (( __fvv_y = 0; __fvv_y < __FV_VS_H; __fvv_y++ )); do
        __FV_VS_CH[__fvv_y]=$__FV_VS_SP __FV_VS_AT[__fvv_y]=${__FV_VS_FILL[$__fvv_a]}
        __FV_VS_DX1[__fvv_y]=0 __FV_VS_DX2[__fvv_y]=$__FV_VS_W
        if (( __FV_VS_WIDE[__fvv_y] )); then
            __FV_VS_WIDE[__fvv_y]=0 __FV_VS_XSEQ=$(( __FV_VS_XSEQ + 1 ))
            __FV_VS_XV[__fvv_y]=$__FV_VS_XSEQ
        fi
    done
}

# fv.video.setClip X1 Y1 X2 Y2 — writes go only into [X1,X2) x [Y1,Y2) (FV
# TRect, B exclusive), intersected with the screen; a reallocation resets it
fv.video.setClip() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x=${1-} __fvv_y=${2-} __fvv_rw=${3-} __fvv_h=${4-}
    if [[ $__fvv_x$__fvv_y$__fvv_rw$__fvv_h == *[!0123456789]* || -z $__fvv_x || -z $__fvv_y || -z $__fvv_rw || -z $__fvv_h \
        || $__fvv_x == 0?* || $__fvv_y == 0?* || $__fvv_rw == 0?* || $__fvv_h == 0?* \
        || $__fvv_x == ????????* || $__fvv_y == ????????* || $__fvv_rw == ????????* || $__fvv_h == ????????* ]] \
        && ! fv.video._xywh "$__fvv_x" "$__fvv_y" "$__fvv_rw" "$__fvv_h"; then fv.video._bad setClip 'X1 Y1 X2 Y2' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr setClip; return; fi
    RESULT=''
    if (( __fvv_x < 0 )); then __fvv_x=0; fi
    if (( __fvv_y < 0 )); then __fvv_y=0; fi
    if (( __fvv_rw > __FV_VS_W )); then __fvv_rw=$__FV_VS_W; fi
    if (( __fvv_h > __FV_VS_H )); then __fvv_h=$__FV_VS_H; fi
    __FV_VS_CX1=$__fvv_x __FV_VS_CY1=$__fvv_y __FV_VS_CX2=$__fvv_rw __FV_VS_CY2=$__fvv_h
}

# fv.video._clipf X1 Y1 X2 Y2 — FRIEND ENTRY for the fv.* units (stage
# 2c-p): setClip for a caller that passes four integers it computed itself,
# without the caller-state guard and the argument check (four numbers: no
# locale or shell option matters), intersected with the screen as setClip
# does. rc 0, RESULT '' (as setClip: a Draw starts with RESULT empty). Not
# for scripts (setClip checks what it is given)
fv.video._clipf() {
    RESULT='' __FV_VS_CX1=$(( $1 < 0 ? 0 : $1 )) __FV_VS_CY1=$(( $2 < 0 ? 0 : $2 )) __FV_VS_CX2=$(( $3 > __FV_VS_W ? __FV_VS_W : $3 )) __FV_VS_CY2=$(( $4 > __FV_VS_H ? __FV_VS_H : $4 ))
}

fv.video.resetClip() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    RESULT=''
    __FV_VS_CX1=0 __FV_VS_CY1=0 __FV_VS_CX2=$__FV_VS_W __FV_VS_CY2=$__FV_VS_H
}

# fv.video.getClip — RESULT = the clip as setClip takes it, "X1 Y1 X2 Y2"
# (already intersected with the screen), so a caller can save and restore
# it. Reads four integers: no locale or option matters, so no guard
fv.video.getClip() {
    if (( $# )); then fv.video._bad getClip 'no arguments' "$@"; return; fi
    if (( ! __FV_VS_H )); then fv.video._noscr getClip; return; fi
    RESULT="$__FV_VS_CX1 $__FV_VS_CY1 $__FV_VS_CX2 $__FV_VS_CY2"
}

# fv.video.getRow Y — read-only: RESULT = row Y as display text (each cell's
# character; a marker's content from the side map; the continuation half of
# a wide character dropped), REPLY = the row's symbols, one per cell
# (the screen's width W of them, both halves of a wide character included)
fv.video.getRow() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_y=${1-} __fvv_r __fvv_o='' __fvv_e __fvv_p=0 __fvv_j
    if [[ -z $__fvv_y || $__fvv_y == *[!0123456789]* || $__fvv_y == 0?* || ${#__fvv_y} -gt 7 ]] || (( $# != 1 )); then
        REPLY=''; fv.video._bad getRow Y "$@"; return
    fi
    if (( ! __FV_VS_H )); then REPLY=''; fv.video._noscr getRow; return; fi
    if (( __fvv_y >= __FV_VS_H )); then REPLY=''; fv.video._bad getRow 'Y outside the screen' "$@"; return; fi
    __fvv_r=${__FV_VS_CH[__fvv_y]}
    if (( __FV_VS_WIDE[__fvv_y] & 2 )); then
        while [[ $__fvv_r == *"$__FV_VS_MARK"* ]]; do
            __fvv_e=${__fvv_r%%"$__FV_VS_MARK"*}
            __fvv_p=$(( __fvv_p + ${#__fvv_e} )) __fvv_j="$__fvv_y $__fvv_p"
            __fvv_o+=$__fvv_e${__FV_VS_X[$__fvv_j]-?}
            __fvv_r=${__fvv_r:${#__fvv_e}+1} __fvv_p=$(( __fvv_p + 1 ))
        done
    fi
    __fvv_o+=$__fvv_r
    if (( __FV_VS_WIDE[__fvv_y] )); then __fvv_o=${__fvv_o//"$__FV_VS_CONT"/}; fi
    RESULT=$__fvv_o REPLY=${__FV_VS_AT[__fvv_y]}
}

# fv.video.setCursorPos X Y — where the cursor stands after the next update
# (clamped to the screen there)
fv.video.setCursorPos() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_x __fvv_y
    if ! fv.video._xy "${1-}" "${2-}" || (( __fvv_x < 0 || __fvv_y < 0 )); then fv.video._bad setCursorPos 'X Y' "$@"; return; fi
    RESULT=''
    __FV_VS_CURX=$__fvv_x __FV_VS_CURY=$__fvv_y
}

# fv.video.setCursorType 0..3 — FPC crHidden 0 (ESC[?25l); crUnderLine,
# crBlock, crHalfBlock 1-3 all show it (ESC[?25h, no shape sequence)
fv.video.setCursorType() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if [[ ${1-} != [0123] ]]; then fv.video._bad setCursorType '0..3' "$@"; return; fi
    RESULT=''
    __FV_VS_CURT=$1
}

# fv.video.setClipboard TEXT — (P3 10.9, D24) TEXT to the system clipboard by
# OSC 52: ESC ] 52 ; c ; BASE64 BEL (FPC fvclip.inc's form), TEXT's bytes in
# base64 (pure bash; at most FV_PASTE_MAX bytes: fv.video._b64), written at
# once to FV_VIDEO_OUT_FD, else FV_TTY_FD. A
# terminal that does not take OSC 52 ignores it (README "Clipboard"). rc 1:
# no output fd or the write failed (nothing sent), rc 2: not one argument.
# RESULT ''. Fork-free
fv.video.setClipboard() {
    if (( $# != 1 )); then fv.video._bad setClipboard 'TEXT' "$@"; return; fi
    local IFS= __fvv_fd=${FV_VIDEO_OUT_FD:-${FV_TTY_FD-}} __fvv_b=''
    RESULT=''
    if [[ -z $__fvv_fd || $__fvv_fd == *[!0123456789]* ]]; then
        kk.debug "Error: fv.video.setClipboard: no output fd (FV_VIDEO_OUT_FD, FV_TTY_FD)"
        return 1
    fi
    fv.video._b64 "$1"
    printf '%s' $'\e]52;c;'"$__fvv_b"$'\a' 2>/dev/null >&$__fvv_fd || return 1
}
# fv.video._b64 TEXT — the caller's __fvv_b = TEXT's bytes in base64 (RFC
# 4648, with `=` padding); bytes in the C locale (a byte's value & 255: some
# C libraries give a byte >= 0x80 as negative or as 0xDF00 + the byte). At
# most FV_PASTE_MAX bytes (default 65536, fv.keyboard's paste cap): a longer
# TEXT is cut there, an incomplete UTF-8 sequence at the cut dropped. Linear:
# bash copies a value to slice it, so TEXT goes in 3072-byte pieces, each in
# 96-byte pieces, each byte by byte (F3: one slice of the whole per byte was
# quadratic, 128 KB 48 s); one printf per three bytes
fv.video._b64() {
    local LC_ALL=C __fvv_t=$1 __fvv_m=65536 __fvv_c __fvv_e __fvv_o __fvv_i __fvv_n __fvv_v __fvv_r __fvv_x __fvv_y __fvv_z
    local __fvv_k=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
    __fvv_b=''
    if [[ -n ${FV_PASTE_MAX-} && $FV_PASTE_MAX != *[!0123456789]* && ${#FV_PASTE_MAX} -le 9 ]]; then __fvv_m=$(( 10#$FV_PASTE_MAX )); fi
    if (( ${#__fvv_t} > __fvv_m )); then
        __fvv_t=${__fvv_t:0:__fvv_m}
        fv.video._b64cut
    fi
    while [[ -n $__fvv_t ]]; do
        __fvv_c=${__fvv_t:0:3072} __fvv_t=${__fvv_t:3072} __fvv_o=''
        while [[ -n $__fvv_c ]]; do
            __fvv_e=${__fvv_c:0:96} __fvv_c=${__fvv_c:96}
            __fvv_n=${#__fvv_e} __fvv_i=0
            while (( __fvv_i + 2 < __fvv_n )); do
                printf -v __fvv_v '(%d&255)<<16|(%d&255)<<8|(%d&255)' "'${__fvv_e:__fvv_i:1}" "'${__fvv_e:__fvv_i+1:1}" "'${__fvv_e:__fvv_i+2:1}"
                __fvv_v=$(( __fvv_v ))
                __fvv_o+=${__fvv_k:__fvv_v/262144:1}${__fvv_k:__fvv_v/4096%64:1}${__fvv_k:__fvv_v/64%64:1}${__fvv_k:__fvv_v%64:1}
                __fvv_i=$(( __fvv_i + 3 ))
            done
            # (the last one or two bytes: only in TEXT's last piece, 3072 and
            # 96 being multiples of three)
            if (( __fvv_n - __fvv_i == 2 )); then
                printf -v __fvv_x '%d' "'${__fvv_e:__fvv_i:1}"
                printf -v __fvv_y '%d' "'${__fvv_e:__fvv_i+1:1}"
                __fvv_z=0
                fv.video._b64q
                __fvv_o+=${__fvv_r:0:3}=
            elif (( __fvv_n - __fvv_i == 1 )); then
                printf -v __fvv_x '%d' "'${__fvv_e:__fvv_i:1}"
                __fvv_y=0 __fvv_z=0
                fv.video._b64q
                __fvv_o+=${__fvv_r:0:2}==
            fi
        done
        __fvv_b+=$__fvv_o
    done
}
# (_b64's cut __fvv_t, C locale: an incomplete UTF-8 sequence at its end
# dropped — up to three continuation bytes after a lead byte that wants more)
fv.video._b64cut() {
    local __fvv_q=0 __fvv_c __fvv_w
    while (( __fvv_q < 3 && ${#__fvv_t} > __fvv_q + 1 )); do
        __fvv_c=${__fvv_t: -1-__fvv_q:1}
        if [[ $__fvv_c != [$'\x80'-$'\xbf'] ]]; then break; fi
        __fvv_q=$(( __fvv_q + 1 ))
    done
    __fvv_c=${__fvv_t: -1-__fvv_q:1}
    if [[ $__fvv_c == [$'\xc2'-$'\xdf'] ]]; then __fvv_w=1
    elif [[ $__fvv_c == [$'\xe0'-$'\xef'] ]]; then __fvv_w=2
    elif [[ $__fvv_c == [$'\xf0'-$'\xf4'] ]]; then __fvv_w=3
    else return 0; fi
    if (( __fvv_q < __fvv_w )); then __fvv_t=${__fvv_t:0:${#__fvv_t}-1-__fvv_q}; fi
}
# (_b64's three bytes __fvv_x __fvv_y __fvv_z -> its four characters __fvv_r)
fv.video._b64q() {
    local __fvv_v=$(( (__fvv_x & 255) * 65536 + (__fvv_y & 255) * 256 + (__fvv_z & 255) ))
    local __fvv_a=$(( __fvv_v / 262144 )) __fvv_c=$(( __fvv_v / 4096 % 64 )) __fvv_d=$(( __fvv_v / 64 % 64 )) __fvv_e=$(( __fvv_v % 64 ))
    __fvv_r=${__fvv_k:__fvv_a:1}${__fvv_k:__fvv_c:1}${__fvv_k:__fvv_d:1}${__fvv_k:__fvv_e:1}
}

# fv.video.strWidth TEXT — RESULT = the display cells TEXT takes as a write
# stores it (StringDisplayWidth: wide characters 2, a cluster its base's
# width, a control or invalid sequence 1 as its '?')
fv.video.strWidth() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local __fvv_t=${1-} __fvv_w=0 __fvv_xl=''
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then fv.video._text; fi
    RESULT=${#__fvv_t}
}

# fv.video.clusters TEXT CL CW — (P3 10.1) TEXT cut into clusters exactly as
# the writes cut it into cells: the indexed array named CL gets the cluster
# strings, the one named CW their cells (1 or 2); RESULT = the count. Both
# arrays are replaced (an empty TEXT: two empty arrays, RESULT 0).
#   * UTF-8 mode: a cluster is one cell's content — a character, a wide
#     character (2), a base with its zero-width followers, a ZWJ sequence, a
#     flag, a VS16 emoji, a character past U+FFFF (the walk's rules, D14).
#     Valid TEXT without control characters comes back whole (CL joined =
#     TEXT): a zero-width character at TEXT's start is a cluster of its own
#     without the space the screen shows before it. A control character or
#     an invalid sequence is the cluster '?' (as stored).
#   * ASCII mode: every character — one UTF-8 sequence as the writes count
#     them, or one byte below 0x80 — is one cluster of one cell holding
#     TEXT's own bytes (the screen shows '?' or the map's letter there).
# Printable ASCII takes a fast path (no text check). Bad names (no
# identifier, __fv*, RESULT, CL = CW, an associative array) or another
# argument count: rc 2, RESULT '', nothing changed
fv.video.clusters() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if (( $# != 3 )) || [[ -z $2 || -z $3 || $2$3 == *[!_$__FV_VS_SYMS]* || $2 == [0123456789]* || $3 == [0123456789]* \
        || $2 == __[fF][vV]* || $3 == __[fF][vV]* || $2 == RESULT || $3 == RESULT || $2 == "$3" ]]; then
        fv.video._bad clusters 'TEXT CL CW: CL CW names of two indexed arrays' "$@"; return
    fi
    local - IFS=$__FV_VS_US __fvv_t=$1 __fvv_w=0 __fvv_xl='' __fvv_o=''
    # (the attribute of an unset name reads '' only without set -u; `local -` puts it back)
    set +u -f
    local -n __fvv_cl=$2 __fvv_cw=$3
    if [[ ${__fvv_cl@a}${__fvv_cw@a} == *A* ]]; then fv.video._bad clusters 'CL CW must not be associative arrays' "$@"; return; fi
    __fvv_cl=() __fvv_cw=()
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then
        if (( FV_VIDEO_ASCII )); then fv.video._inc fv.video._cla
        else
            fv.video._text
            if (( __fvv_w )); then fv.video._clw "$1"; else fv.video._clsep "$__fvv_t"; fi
        fi
    else fv.video._clsep "$__fvv_t"; fi
    if [[ -n $__fvv_o ]]; then fv.video._clput; fi
    RESULT=${#__fvv_cl[@]}
}
# fv.video._clsep STR — every character of STR + \x1f appended to __fvv_o
# (one substitution with patsub_replacement, else a loop)
fv.video._clsep() {
    local __fvv_i
    if (( __FV_VS_AMP )) && [[ $BASHOPTS == *patsub_replacement* ]]; then __fvv_o+=${1//?/$__FV_VS_RU}; return 0; fi
    for (( __fvv_i = 0; __fvv_i < ${#1}; __fvv_i++ )); do __fvv_o+=${1:__fvv_i:1}$__FV_VS_US; done
}
# fv.video._clput — clusters' __fvv_o (each cluster + \x1f, all narrow) into
# CL, a 1 per cluster into CW (IFS \x1f, globbing off: the caller's)
fv.video._clput() {
    local __fvv_s
    __fvv_cl=($__fvv_o)
    printf -v __fvv_s '%*s' "${#__fvv_cl[@]}" ''
    __fvv_s=${__fvv_s// /1$__FV_VS_US}
    __fvv_cw=($__fvv_s)
}
# fv.video._clw TEXT — clusters' wide cells __fvv_t of TEXT (markers in __fvv_xl, one
# entry per marker in cell order) into CL / CW, cell by cell
fv.video._clw() {
    local __fvv_c __fvv_e __fvv_q=$__fvv_xl __fvv_i=0 __fvv_n=1
    while [[ -n $__fvv_t ]]; do
        __fvv_c=${__fvv_t:0:1} __fvv_t=${__fvv_t:1} __fvv_n=1
        if [[ ${__fvv_t:0:1} == "$__FV_VS_CONT" ]]; then __fvv_t=${__fvv_t:1} __fvv_n=2; fi
        if [[ $__fvv_c == "$__FV_VS_MARK" ]]; then
            __fvv_e=${__fvv_q%%"$__FV_VS_US"*} __fvv_q=${__fvv_q#*"$__FV_VS_US"}
            __fvv_c=${__fvv_e#*:}
            # (an orphan zero-width character at the start: the screen's space dropped)
            if (( ! __fvv_i )) && [[ $__fvv_c == ' '?* && $1 != ' '* ]]; then __fvv_c=${__fvv_c:1}; fi
        fi
        __fvv_cl[__fvv_i]=$__fvv_c __fvv_cw[__fvv_i]=$__fvv_n __fvv_i=$(( __fvv_i + 1 ))
    done
}
# fv.video._cla — clusters in ASCII mode (C locale, via _inc): TEXT's
# sequences as _bytes takes them (a lead byte and up to 3 continuation
# bytes; each other byte alone) into __fvv_o
fv.video._cla() {
    local __fvv_q __fvv_c __fvv_n __fvv_b
    # (a \x1f in TEXT is a character here, not a separator: each cluster goes
    # straight into the arrays; critic 3a-1 M1)
    if [[ $__fvv_t == *"$__FV_VS_US"* ]]; then fv.video._cla1; return; fi
    while [[ $__fvv_t == *[![:ascii:]]* ]]; do
        __fvv_q=${__fvv_t%%[![:ascii:]]*}
        fv.video._clsep "$__fvv_q"
        __fvv_t=${__fvv_t:${#__fvv_q}} __fvv_c=${__fvv_t:0:1}
        printf -v __fvv_b '%d' "'$__fvv_c"
        if (( (__fvv_b &= 255) >= 240 )); then __fvv_n=3; elif (( __fvv_b >= 224 )); then __fvv_n=2
        elif (( __fvv_b >= 192 )); then __fvv_n=1; else __fvv_n=0; fi
        while (( __fvv_n-- > 0 )) && [[ -n ${__fvv_t:${#__fvv_c}:1} ]]; do
            printf -v __fvv_b '%d' "'${__fvv_t:${#__fvv_c}:1}"
            if (( (__fvv_b &= 255) < 128 || __fvv_b >= 192 )); then break; fi
            __fvv_c=${__fvv_t:0:${#__fvv_c}+1}
        done
        __fvv_o+=$__fvv_c$__FV_VS_US __fvv_t=${__fvv_t:${#__fvv_c}}
    done
    fv.video._clsep "$__fvv_t"
}
# fv.video._cla1 — _cla for a TEXT holding \x1f (C locale, via _inc): the
# same sequences, appended to CL / CW one by one (__fvv_o stays empty)
fv.video._cla1() {
    local __fvv_c __fvv_n __fvv_b __fvv_i=0
    while [[ -n $__fvv_t ]]; do
        __fvv_c=${__fvv_t:0:1}
        printf -v __fvv_b '%d' "'$__fvv_c"
        if (( (__fvv_b &= 255) >= 240 )); then __fvv_n=3; elif (( __fvv_b >= 224 )); then __fvv_n=2
        elif (( __fvv_b >= 192 )); then __fvv_n=1; else __fvv_n=0; fi
        while (( __fvv_n-- > 0 )) && [[ -n ${__fvv_t:${#__fvv_c}:1} ]]; do
            printf -v __fvv_b '%d' "'${__fvv_t:${#__fvv_c}:1}"
            if (( (__fvv_b &= 255) < 128 || __fvv_b >= 192 )); then break; fi
            __fvv_c=${__fvv_t:0:${#__fvv_c}+1}
        done
        __fvv_cl[__fvv_i]=$__fvv_c __fvv_cw[__fvv_i]=1 __fvv_i=$(( __fvv_i + 1 )) __fvv_t=${__fvv_t:${#__fvv_c}}
    done
}
# fv.video._inc FUNC — FUNC in a scope of the C locale, the caller's locale
# kept as _san keeps it (L-1: under an LC_ALL a restore rejects the scope
# runs with stderr off; a failed restore is put right)
fv.video._inc() {
    local __fvv_pe=${#__FV_VS_P}${#__FV_VS_B}
    if [[ -n ${LC_ALL-} && $LC_ALL != C && $LC_ALL != POSIX && $LC_ALL != "$__FV_VS_LOC" ]] && ! fv.video._lcknown; then
        fv.video._inc1 "$1" 2>/dev/null
    else fv.video._inc1 "$1"; fi
    if [[ ${#__FV_VS_P}${#__FV_VS_B} != "$__fvv_pe" ]]; then fv.video._lcx "$__fvv_pe" 2>/dev/null; fi
}
fv.video._inc1() {
    local LC_ALL=C
    "$1"
}
# fv.video._roww — updateScreen's body for a row with wide cells (its
# locals): equal to the shown copy only when the side map's version is too;
# the range widened to whole wide characters (the writes keep it so); the
# colour runs sent as the terminal's text with the resync (_cells)
fv.video._roww() {
    # (the wide path's own variables: updateScreen declares only the narrow path's)
    local __fvv_sc __fvv_s __fvv_k __fvv_q __fvv_xx __fvv_re __fvv_nw=0
    if (( __fvv_f )) || [[ -z ${__FV_VS_OCH[__fvv_y]+1} ]]; then __fvv_x0=0 __fvv_n=$__fvv_w
    elif [[ $__fvv_c == "${__FV_VS_OCH[__fvv_y]}" && $__fvv_a == "${__FV_VS_OAT[__fvv_y]}" && ${__FV_VS_XV[__fvv_y]-} == "${__FV_VS_OXV[__fvv_y]-}" ]]; then return 0
    else __fvv_x0=${__FV_VS_DX1[__fvv_y]} __fvv_n=$(( __FV_VS_DX2[__fvv_y] - __FV_VS_DX1[__fvv_y] )); fi
    if (( __fvv_x0 > 0 )) && [[ ${__fvv_c:__fvv_x0:1} == "$__FV_VS_CONT" ]]; then __fvv_x0=$(( __fvv_x0 - 1 )) __fvv_n=$(( __fvv_n + 1 )); fi
    if [[ ${__fvv_c:__fvv_x0+__fvv_n:1} == "$__FV_VS_CONT" ]]; then __fvv_n=$(( __fvv_n + 1 )); fi
    # a range ending on a narrow marker takes the cell after it (and that
    # cell's second half): a terminal that draws the marker 2 wide (a newer
    # table, a lone regional indicator) covers that cell, which would else
    # never be sent again. (A range starting right after one needs nothing:
    # in such a terminal the marker is lost to the cell after it whenever
    # that cell is written, re-sent or not.)
    if (( __FV_VS_WIDE[__fvv_y] & 2 && __fvv_x0 + __fvv_n < __fvv_w )) && [[ ${__fvv_c:__fvv_x0+__fvv_n-1:1} == "$__FV_VS_MARK" ]]; then
        __fvv_n=$(( __fvv_n + 1 ))
        if [[ ${__fvv_c:__fvv_x0+__fvv_n:1} == "$__FV_VS_CONT" ]]; then __fvv_n=$(( __fvv_n + 1 )); fi
    fi
    __FV_VS_OCH[__fvv_y]=$__fvv_c __FV_VS_OAT[__fvv_y]=$__fvv_a
    if [[ -n ${__FV_VS_XV[__fvv_y]-} ]]; then __FV_VS_OXV[__fvv_y]=${__FV_VS_XV[__fvv_y]}; else unset '__FV_VS_OXV[__fvv_y]'; fi
    __fvv_xx=$__fvv_x0 __fvv_re=$(( __fvv_x0 + __fvv_n ))
    __fvv_sa=${__fvv_a:__fvv_x0:__fvv_n} __fvv_sc=${__fvv_c:__fvv_x0:__fvv_n}
    if (( __fvv_y != __fvv_py || __fvv_x0 != __fvv_px )); then __fvv_o+=$'\e['"$(( __fvv_y + 1 ));$(( __fvv_x0 + 1 ))H"; fi
    fv.video._runsw
    __fvv_py=$__fvv_y __fvv_px=$(( __fvv_x0 + __fvv_n ))
    if (( __fvv_px >= __fvv_w )); then __fvv_py=-1; fi
}

# fv.video._runsw — _roww's colour runs, each sent by _cells; __fvv_nw = 1
# when the cell after the run is a wide marker (its pre-blank starts with an
# absolute cursor move: no resync before it)
fv.video._runsw() {
    while [[ -n $__fvv_sa ]]; do
        __fvv_s=${__fvv_sa:0:1}
        __fvv_r=${__fvv_sa%%[!$__fvv_s]*}
        __fvv_k=${#__fvv_r}
        if [[ $__fvv_s != "$__fvv_l" ]]; then
            __fvv_l=$__fvv_s __fvv_sg=${__FV_VS_SGR[$__fvv_s]:-$__fvv_d}
            if [[ $__fvv_sg != "$__fvv_lg" ]]; then __fvv_o+=$__fvv_sg __fvv_lg=$__fvv_sg; fi
        fi
        __fvv_q=${__fvv_sc:0:__fvv_k} __fvv_sa=${__fvv_sa:__fvv_k} __fvv_sc=${__fvv_sc:__fvv_k}
        if [[ ${__fvv_sc:0:2} == "$__FV_VS_MARK$__FV_VS_CONT" ]]; then __fvv_nw=1; else __fvv_nw=0; fi
        fv.video._cells
    done
}

# fv.video._cells — the cells __fvv_q of row __fvv_y from column __fvv_xx
# appended to the frame as the terminal's text (decision D15). A plain
# character goes as itself; a continuation \x01 sends nothing (the terminal
# fills that cell with the wide character before it); a marker sends its
# content (__FV_VS_X). The resync: after every wide cell and every marker
# cell (narrow ones too) that another cell of the row's range follows,
# ESC[nG (__FV_VS_CHA[column]) puts the cursor where the buffer says it is,
# so a terminal whose width table disagrees garbles only that cell; not
# before a wide marker, whose pre-blank starts with such a move anyway. The
# pre-blank: a wide marker (every cluster or character past U+FFFF that is
# 2 wide, and every class y character, which the walk always stores as a
# marker) is sent as ESC[x+2G, a space, ESC[x+1G, the content: a terminal
# that draws it narrow shows a blank in its second half, never what was
# there before. __fvv_re = the end of the row's range; __FV_VS_RSYNC=0
# (tests only) turns both off.
#
# The run is split once at its continuations (IFS, no globbing: `local -`
# puts set -f back; the '.' keeps an empty last piece): each piece but the
# last ends with the first half of a wide cell (a plain character, or a
# marker \x02: then a wide marker); markers elsewhere are narrow.
fv.video._cells() {
    if [[ $__fvv_q != *$__FV_VS_CM* ]]; then
        __fvv_o+=$__fvv_q __fvv_xx=$(( __fvv_xx + ${#__fvv_q} ))
        return 0
    fi
    if (( ! __FV_VS_RSYNC )); then fv.video._cells0; return 0; fi
    local - IFS=$__FV_VS_CONT __fvv_e __fvv_z='' __fvv_pd='' __fvv_i __fvv_n __fvv_j
    local -a __fvv_fs
    set -f
    __fvv_fs=($__fvv_q.)
    __fvv_n=$(( ${#__fvv_fs[@]} - 1 ))
    __fvv_fs[__fvv_n]=${__fvv_fs[__fvv_n]%.}
    if [[ $__fvv_q != *"$__FV_VS_MARK"* ]]; then
        # plain wide characters only (CJK): a resync after each, one step per
        # character; none after the last when the range ends there or a wide
        # marker follows in the next run
        for (( __fvv_i = 0; __fvv_i < __fvv_n; __fvv_i++ )); do
            __fvv_z+=${__fvv_fs[__fvv_i]}${__FV_VS_CHA[__fvv_xx += ${#__fvv_fs[__fvv_i]} + 1]}
        done
        if [[ -z ${__fvv_fs[__fvv_n]} ]] && (( __fvv_xx >= __fvv_re || __fvv_nw )); then __fvv_z=${__fvv_z%"${__FV_VS_CHA[__fvv_xx]}"}; fi
        __fvv_o+=$__fvv_z${__fvv_fs[__fvv_n]} __fvv_xx=$(( __fvv_xx + ${#__fvv_fs[__fvv_n]} ))
        return 0
    fi
    # with markers: the resync after a cell waits in __fvv_pd and is dropped
    # when a wide marker comes next (its pre-blank moves the cursor anyway)
    for (( __fvv_i = 0; __fvv_i < __fvv_n; __fvv_i++ )); do
        __fvv_e=${__fvv_fs[__fvv_i]}
        if [[ $__fvv_e != *"$__FV_VS_MARK"* ]]; then
            # narrow cells and a plain wide character
            __fvv_z+=$__fvv_pd$__fvv_e __fvv_xx=$(( __fvv_xx + ${#__fvv_e} + 1 ))
            __fvv_pd=${__FV_VS_CHA[__fvv_xx]}
        elif [[ $__fvv_e == "$__FV_VS_MARK" ]]; then
            # a wide marker alone (emoji): the pre-blank
            __fvv_j="$__fvv_y $__fvv_xx"
            __fvv_z+=${__FV_VS_CHA[__fvv_xx + 1]}' '${__FV_VS_CHA[__fvv_xx]}${__FV_VS_X[$__fvv_j]-?} __fvv_xx=$(( __fvv_xx + 2 ))
            __fvv_pd=${__FV_VS_CHA[__fvv_xx]}
        else
            fv.video._cellsm 1
        fi
    done
    # the last piece: narrow cells only
    __fvv_e=${__fvv_fs[__fvv_n]}
    if [[ $__fvv_e == *"$__FV_VS_MARK"* ]]; then fv.video._cellsm 0
    elif [[ -n $__fvv_e ]]; then __fvv_z+=$__fvv_pd$__fvv_e __fvv_xx=$(( __fvv_xx + ${#__fvv_e} )) __fvv_pd=''; fi
    if [[ -n $__fvv_pd ]] && (( __fvv_xx < __fvv_re && ! __fvv_nw )); then __fvv_z+=$__fvv_pd; fi
    __fvv_o+=$__fvv_z
}

# fv.video._cellsm WIDE — _cells' piece __fvv_e that holds markers: narrow
# cells, narrow markers (each followed by a pending resync), and with WIDE 1
# a wide cell at its end (a plain character or a wide marker)
fv.video._cellsm() {
    local __fvv_c __fvv_t __fvv_j
    while [[ $__fvv_e == *"$__FV_VS_MARK"* ]]; do
        __fvv_c=${__fvv_e%%"$__FV_VS_MARK"*} __fvv_e=${__fvv_e#*"$__FV_VS_MARK"}
        if [[ -n $__fvv_c ]]; then __fvv_z+=$__fvv_pd$__fvv_c __fvv_xx=$(( __fvv_xx + ${#__fvv_c} )) __fvv_pd=''; fi
        __fvv_j="$__fvv_y $__fvv_xx" __fvv_t=${__FV_VS_X[$__fvv_j]-?}
        if [[ -z $__fvv_e ]] && (( $1 )); then
            # a wide marker: the pre-blank (a pending resync dropped)
            __fvv_z+=${__FV_VS_CHA[__fvv_xx + 1]}' '${__FV_VS_CHA[__fvv_xx]}$__fvv_t __fvv_xx=$(( __fvv_xx + 2 ))
            __fvv_pd=${__FV_VS_CHA[__fvv_xx]}
            return 0
        fi
        __fvv_z+=$__fvv_pd$__fvv_t __fvv_xx=$(( __fvv_xx + 1 ))
        __fvv_pd=${__FV_VS_CHA[__fvv_xx]}
    done
    if [[ -n $__fvv_e ]]; then
        __fvv_z+=$__fvv_pd$__fvv_e __fvv_xx=$(( __fvv_xx + ${#__fvv_e} )) __fvv_pd=''
        if (( $1 )); then __fvv_xx=$(( __fvv_xx + 1 )) __fvv_pd=${__FV_VS_CHA[__fvv_xx]}; fi
    fi
}

# fv.video._cells0 — _cells without the resync (__FV_VS_RSYNC=0, the tests'
# disagreeing terminal): markers' contents, no continuation
fv.video._cells0() {
    local - IFS=$__FV_VS_MARK __fvv_p=$__fvv_xx __fvv_e __fvv_j __fvv_z='' __fvv_i=0
    local -a __fvv_fs
    set -f
    __fvv_fs=($__fvv_q.)
    for __fvv_e in "${__fvv_fs[@]}"; do
        if (( __fvv_i )); then
            __fvv_j="$__fvv_y $__fvv_p"
            __fvv_z+=${__FV_VS_X[$__fvv_j]-?} __fvv_p=$(( __fvv_p + 1 ))
        fi
        __fvv_z+=${__fvv_e//"$__FV_VS_CONT"/} __fvv_p=$(( __fvv_p + ${#__fvv_e} )) __fvv_i=1
    done
    __fvv_o+=${__fvv_z%.} __fvv_xx=$(( __fvv_xx + ${#__fvv_q} ))
}

# fv.video.updateScreen [force] — one printf to FV_VIDEO_OUT_FD, else
# FV_TTY_FD: for each damaged row that differs from the shown copy, its
# damaged columns as colour runs (a cursor move per row, an SGR when the look
# changes; the SGR state is unknown at the start of a frame), then the cursor
# (its position when it is visible and moved or text was written; ?25h/l on
# change; its shape by DECSCUSR when it changed, P3 10.7: ESC [ 4 SP q
# underline for type 1, ESC [ 2 SP q block for 2 and 3, design D27).
# force: every cell of every row, the cursor state re-sent. rc 1:
# no screen, no fd (nothing emitted, the damage kept), or the printf failed
# (the next frame is forced). Fork-free.
fv.video.updateScreen() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 || "${IFS-}" == *$'\x01'* ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    # IFS empty: the fd below is a bare redirect target (bash 5.1 prints >&"$fd" as &> "$fd"),
    # so a caller IFS holding digits must not split it
    local IFS= __fvv_f=0 __fvv_fd=${FV_VIDEO_OUT_FD:-${FV_TTY_FD-}} __fvv_w=$__FV_VS_W __fvv_h=$__FV_VS_H __fvv_y __fvv_c __fvv_a
    local __fvv_x0 __fvv_n __fvv_sa __fvv_r __fvv_o='' __fvv_l='' __fvv_lg='' __fvv_sg __fvv_p
    local __fvv_d=${__FV_VS_SGR[$__FV_VS_DEF]-} __fvv_py=-1 __fvv_px=-1 __fvv_cx=$__FV_VS_CURX __fvv_cy=$__FV_VS_CURY __fvv_v=l __fvv_sh=''
    local -a __fvv_ys
    RESULT=''
    # (the argument, the screen and the fd: rare refusals in _updx)
    if [[ -n ${1-} || -z $__fvv_fd || $__fvv_fd == *[!0123456789]* ]] || (( ! __fvv_h )); then fv.video._updx "$@" || return; fi
    if (( __FV_VS_FORCE )); then __fvv_f=1; fi
    if (( __fvv_f )); then
        __fvv_ys=("${!__FV_VS_CH[@]}") __FV_VS_SVIS='' __FV_VS_SPOS='' __FV_VS_SSHP=''
    else
        __fvv_ys=("${!__FV_VS_DX1[@]}")
    fi
    # (stage 2c-p: a narrow row's colour runs with few expansions per run:
    # consecutive runs always differ in symbol, so each run looks its SGR up
    # and compares it with the last one sent; the text is cut from the row
    # at the running column)
    for __fvv_y in "${__fvv_ys[@]}"; do
        __fvv_c=${__FV_VS_CH[__fvv_y]} __fvv_a=${__FV_VS_AT[__fvv_y]}
        if (( __FV_VS_WIDE[__fvv_y] )); then __fvv_l=''; fv.video._roww; continue; fi
        if (( __fvv_f )) || [[ -z ${__FV_VS_OCH[__fvv_y]+1} ]]; then __fvv_x0=0 __fvv_n=$__fvv_w
        elif [[ $__fvv_c == "${__FV_VS_OCH[__fvv_y]}" && $__fvv_a == "${__FV_VS_OAT[__fvv_y]}" ]]; then continue
        else __fvv_x0=${__FV_VS_DX1[__fvv_y]} __fvv_n=$(( __FV_VS_DX2[__fvv_y] - __FV_VS_DX1[__fvv_y] )); fi
        __FV_VS_OCH[__fvv_y]=$__fvv_c __FV_VS_OAT[__fvv_y]=$__fvv_a __fvv_sa=${__fvv_a:__fvv_x0:__fvv_n} __fvv_p=$__fvv_x0
        if (( __fvv_y != __fvv_py || __fvv_x0 != __fvv_px )); then __fvv_o+=$'\e['"$(( __fvv_y + 1 ));$(( __fvv_x0 + 1 ))H"; fi
        while [[ -n $__fvv_sa ]]; do
            __fvv_r=${__fvv_sa%%[!${__fvv_sa:0:1}]*} __fvv_sg=${__FV_VS_SGR[${__fvv_sa:0:1}]:-$__fvv_d}
            if [[ $__fvv_sg != "$__fvv_lg" ]]; then __fvv_o+=$__fvv_sg __fvv_lg=$__fvv_sg; fi
            __fvv_o+=${__fvv_c:__fvv_p:${#__fvv_r}} __fvv_sa=${__fvv_sa:${#__fvv_r}} __fvv_p=$(( __fvv_p + ${#__fvv_r} ))
        done
        __fvv_py=$__fvv_y __fvv_px=$__fvv_p
        if (( __fvv_p >= __fvv_w )); then __fvv_py=-1; fi
    done
    if (( __FV_VS_CURT )); then fv.video._updcur; fi
    if [[ $__FV_VS_SVIS != "$__fvv_v" ]]; then __fvv_o+=$'\e[?25'$__fvv_v; fi
    __FV_VS_DX1=() __FV_VS_DX2=() __FV_VS_FORCE=0
    if [[ -z $__fvv_o ]]; then return 0; fi
    if ! printf '%s' "$__fvv_o" 2>/dev/null >&$__fvv_fd; then fv.video._updf; return 1; fi
    __FV_VS_SVIS=$__fvv_v __FV_VS_SPOS=''
    if (( __FV_VS_CURT )); then __FV_VS_SPOS="$__fvv_cx $__fvv_cy" __FV_VS_SSHP=$__fvv_sh __FV_VI_CSHP=1; fi
}
# fv.video._updcur — updateScreen's visible cursor (its locals): its place
# clamped to the screen, sent after any text or when it moved or was hidden;
# its shape (__fvv_sh: 4 underline, 2 block) first when the terminal was
# last sent another one (__FV_VS_SSHP; '' = unknown)
fv.video._updcur() {
    __fvv_v=h __fvv_sh=2
    if (( __FV_VS_CURT == 1 )); then __fvv_sh=4; fi
    if [[ $__FV_VS_SSHP != "$__fvv_sh" ]]; then __fvv_o+=$'\e['"$__fvv_sh q"; fi
    if (( __fvv_cx >= __fvv_w )); then __fvv_cx=$(( __fvv_w - 1 )); fi
    if (( __fvv_cy >= __fvv_h )); then __fvv_cy=$(( __fvv_h - 1 )); fi
    if [[ -n $__fvv_o || $__FV_VS_SVIS != h || $__FV_VS_SPOS != "$__fvv_cx $__fvv_cy" ]]; then
        __fvv_o+=$'\e['"$(( __fvv_cy + 1 ));$(( __fvv_cx + 1 ))H"
    fi
}
# fv.video._updx [ARG...] — updateScreen's rare cases (its locals; apart
# because bash copies a function's body on every call): rc 0 and __fvv_f=1
# for `force`; a bad argument (rc 2), no screen (rc 1), no fd (rc 1, the
# damage kept)
fv.video._updx() {
    if [[ -n ${1-} ]]; then
        if [ "$1" = force ]; then __fvv_f=1; else fv.video._bad updateScreen '[force]' "$@"; return; fi
    fi
    if (( ! __fvv_h )); then fv.video._noscr updateScreen; return; fi
    if [[ -z $__fvv_fd || $__fvv_fd == *[!0123456789]* ]]; then
        kk.debug "Error: fv.video.updateScreen: no output fd (FV_VIDEO_OUT_FD, FV_TTY_FD)"
        return 1
    fi
    return 0
}
# fv.video._updf — updateScreen's failed printf: the next frame is forced
fv.video._updf() {
    __FV_VS_FORCE=1 __FV_VS_SVIS='' __FV_VS_SPOS='' __FV_VS_SSHP=''
    kk.debug "Error: fv.video.updateScreen: writing to fd $__fvv_fd failed; the next frame repaints everything"
}
