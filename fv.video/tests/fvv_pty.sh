#!/usr/bin/env bash
# fvv_pty.sh — run a child script on a real pty under util-linux script(1)
# and look at what it left behind. Not a test file (the ktests runner picks up
# NNN_*.sh only); the fv.video and fv.drivers suites source it after their own
# testlib (it needs ktest's KT_TIMEOUT).
#
# initVideo touches a terminal, so it only ever runs here: inside script(1)'s
# pty, never on the terminal the tests were started from.
#
#   fvp_detect           FVP_SCRIPT = this runtime's script(1) when it is
#                        util-linux, else rc 1 and FVP_WHY ("ENV: ...")
#   fvp_case NAME BODY   write the case folder $FVP_ROOT/NAME: child.sh = the
#                        unit preamble + BODY, wrap.sh = the wrapper
#   fvp_run NAME ACT...  run the case: a feeder performs ACT... on script's
#                        stdin, then waits for the wrapper to finish; every
#                        process is bounded and none survives
#   fvp_ts NAME          REPLY = the typescript (bytes, LC_ALL=C)
#   fvp_reap PID         kill PID for sure (SIGKILL, then taskkill by its
#                        Windows pid where /proc/PID/winpid exists)
#
# Inside the pty the wrapper takes `stty -g` before and after the child
# (files before / after), writes the child's $? to rc and the time it ended
# to t_end; when the child created wantleft, the wrapper then reads what is
# left on the pty for 0.5 s into leftover; when the child created hold, the
# wrapper keeps the pty open until release exists (<= 10 s). The child
# writes its pid to pid, and the pid of each fv.video reader and reader
# watchdog it starts to a file rpid* (fvp_run reaps any of them still alive:
# a survivor);
# BODY uses `note TEXT` (one line to log) and `: > "$D/ready"` once the
# terminal is set up. Feeder actions:
#   ready          wait for the ready file (20 s)
#   wait:FILE      wait for FILE in the case folder (20 s)
#   type:BYTES     type BYTES (printf %b) into the pty
#   sig:SIG        kill -SIG the child (the time before it goes to t_mark)
#   sleep:S        sleep S seconds
#   call:FUNC      run the test's function FUNC with the case folder as $1

FVP_KBOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/kbool.sh"

fvp_detect() {
    local v
    FVP_SCRIPT='' FVP_WHY=''
    case $OSTYPE in
        cygwin*|msys*) FVP_SCRIPT=${BASH%/*}/script ;;    # the same runtime only
        *) FVP_SCRIPT=$(type -P script) || FVP_SCRIPT='' ;;
    esac
    if [[ -z $FVP_SCRIPT || ! -x $FVP_SCRIPT ]]; then
        FVP_SCRIPT='' FVP_WHY="ENV: no script(1) in this runtime (${BASH%/*})"
        return 1
    fi
    v=$("$FVP_SCRIPT" --version 2>&1) || v=''
    if [[ $v != *util-linux* ]]; then
        FVP_SCRIPT='' FVP_WHY="ENV: script(1) is not util-linux's (${v%%$'\n'*})"
        return 1
    fi
    if ! kt_need_timeout; then
        FVP_SCRIPT='' FVP_WHY="ENV: $KT_TIMEOUT_WHY"
        return 1
    fi
}

fvp_case() {
    local d=$FVP_ROOT/$1
    rm -rf "$d"
    mkdir -p "$d"
    cat > "$d/child.sh" <<EOF
D='$d'
cd "\$D" || exit 89
printf '%s' "\$BASHPID" > "\$D/pid"
source '$FVP_KBOOL'
kk.uses fv.drivers || exit 90
note() { printf '%s\n' "\$*" >> "\$D/log"; }
$2
EOF
    cat > "$d/wrap.sh" <<EOF
cd '$d' || exit 89
printf '%s' "\$\$" > wpid
trap : INT QUIT TSTP
stty rows 30 cols 100 2>/dev/null
stty -g > before 2>&1
'$BASH' child.sh 2> child.err
printf '%s' "\$?" > rc
printf '%s' "\$EPOCHREALTIME" > t_end
stty -g > after 2>&1
if [[ -e wantleft ]]; then left=''; IFS= read -r -d '' -n 256 -t 0.5 left; printf '%s' "\$left" > leftover; fi
if [[ -e hold ]]; then n=0; while [[ ! -e release ]] && (( n++ < 200 )); do sleep 0.05; done; fi
: > done
EOF
}

# fvp_wait FILE SECONDS — rc 0 once FILE exists
fvp_wait() {
    local i n=$(( $2 * 20 ))
    for (( i = 0; i < n; i++ )); do
        if [[ -e $1 ]]; then return 0; fi
        sleep 0.05
    done
    return 1
}

fvp_feed() {
    local d=$1 a
    shift
    for a; do
        case $a in
            ready) fvp_wait "$d/ready" 20 || return 1 ;;
            wait:*) fvp_wait "$d/${a#wait:}" 20 || return 1 ;;
            type:*) printf '%b' "${a#type:}" ;;
            sig:*) printf '%s' "$EPOCHREALTIME" > "$d/t_mark"; kill -"${a#sig:}" "$(<"$d/pid")" ;;
            sleep:*) sleep "${a#sleep:}" ;;
            call:*) "${a#call:}" "$d" ;;
        esac
    done
    fvp_wait "$d/done" 30
}

fvp_run() {
    local name=$1 d=$FVP_ROOT/$1 p
    shift
    fvp_feed "$d" "$@" | SHELL=$BASH TERM=xterm-256color "$KT_TIMEOUT" -k 5 60 \
        "$FVP_SCRIPT" -qec "'$BASH' '$d/wrap.sh'" "$d/ts" > "$d/script.out" 2>&1
    # no survivor: the child, the wrapper and the readers by their recorded pids
    for p in pid wpid "$d"/rpid*; do
        p=${p##*/}
        if [[ -s $d/$p ]] && kill -0 "$(<"$d/$p")" 2>/dev/null; then
            fvp_reap "$(<"$d/$p")"
            printf 'killed %s\n' "$p" >> "$d/survivors"
        fi
    done
}

# fvp_reap PID — kill PID: SIGKILL, then (a process that ignores the signals
# of its runtime, /proc/PID/winpid present) taskkill on the Windows side; rc
# 1 and a loud line on stderr when it is still alive after that
fvp_reap() {
    local w='' i
    kill -KILL "$1" 2>/dev/null
    for (( i = 0; i < 10; i++ )); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.05; done
    if [[ -r /proc/$1/winpid ]] && read -r w 2>/dev/null < "/proc/$1/winpid" && [[ -n $w && $w != *[!0-9]* ]]; then
        MSYS2_ARG_CONV_EXCL='*' taskkill /F /PID "$w" >/dev/null 2>&1
        for (( i = 0; i < 20; i++ )); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.05; done
    fi
    kill -0 "$1" 2>/dev/null || return 0
    printf 'fvp_reap: PID %s (winpid %s) is STILL ALIVE after SIGKILL and taskkill\n' "$1" "${w:-?}" >&2
    return 1
}

fvp_ts() {
    local LC_ALL=C
    REPLY=''
    if [[ -f $FVP_ROOT/$1/ts ]]; then REPLY=$(<"$FVP_ROOT/$1/ts"); fi
}

# fvp_file NAME FILE — REPLY = the case's FILE ('' when absent)
fvp_file() {
    REPLY=''
    if [[ -f $FVP_ROOT/$1/$2 ]]; then REPLY=$(<"$FVP_ROOT/$1/$2"); fi
}

# fvp_restored NAME — rc 0 when the run restored everything: stty equal before
# and after, the typescript holds ?1049l (unless noalt was used: pass 0 as
# $2), ?25h, ?7h, the mouse-off sequence and bracketed paste off (?2004l,
# P3 10.8), never DECKPAM / DECKPNM; else
# REPLY says what is wrong
fvp_restored() {
    local LC_ALL=C b a ts bad=''
    fvp_file "$1" before; b=$REPLY
    fvp_file "$1" after; a=$REPLY
    fvp_ts "$1"; ts=$REPLY
    if [[ -z $b || $b != "$a" ]]; then bad+=" stty:[$b]->[$a]"; fi
    if [[ ${2:-1} == 1 && $ts != *$'\e[?1049l'* ]]; then bad+=' no?1049l'; fi
    if [[ $ts != *$'\e[?25h'* ]]; then bad+=' no?25h'; fi
    if [[ $ts != *$'\e[?7h'* ]]; then bad+=' no?7h'; fi
    if [[ $ts != *$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'* ]]; then bad+=' no-mouse-off'; fi
    if [[ $ts != *$'\e[?2004l'* ]]; then bad+=' no?2004l'; fi
    if [[ $ts == *$'\e='* || $ts == *$'\e>'* ]]; then bad+=' DECKPAM/DECKPNM'; fi
    if [[ -e $FVP_ROOT/$1/survivors ]]; then bad+=" survivors:$(<"$FVP_ROOT/$1/survivors")"; fi
    REPLY=$bad
    [[ -z $bad ]]
}
