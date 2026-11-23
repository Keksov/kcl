#!/usr/bin/env bash
# 005_Terminal.sh - what initVideo does to the terminal while it is on, on a
# real pty under util-linux script(1) (SKIP with reason ENV elsewhere):
#   * the stty state: -echo -icanon -ixon min 1 time 0, intr = ^C kept, susp
#     quit lnext (+ dsusp discard status swtch where listed) undefined;
#   * FV_TTY_FD is an open tty fd, FV_KEY_FD = it while on and its old value
#     after done, the fd closed; the size from the pty (100 x 30);
#   * the caller's traps: ours while on, exactly the caller's after done;
#   * SIGWINCH: FV_VIDEO_RESIZED=1, the caller's WINCH handler, and the next
#     getEvent is cmResizeApp with the new size;
#   * init twice / done twice: one ?1049h and one ?1049l; noalt: none, no clear
#     (the size known), the restore ends with the move to the last row;
#   * inside x=$(...): it draws on the tty, x gets only the value printed;
#   * FV_TTY = the pty's own path works like /dev/tty;
#   * raw mode refused by stty (a stty function stands in): rc 1, nothing
#     printed, the terminal, the traps, FV_KEY_FD and the fds as they were.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "005: the terminal while on (script(1))"

# count NAME SEQ — REPLY = how often SEQ occurs in the typescript
count() {
    local LC_ALL=C ts n=0
    fvp_ts "$1"; ts=$REPLY
    while [[ $ts == *"$2"* ]]; do ts=${ts#*"$2"}; n=$(( n + 1 )); done
    REPLY=$n
}

TITLES=("raw mode: -echo -icanon -ixon min 1 time 0, intr = ^C, susp/quit/lnext (and the listed dsusp/discard/status/swtch) undefined"
    "FV_TTY_FD is an open tty, FV_KEY_FD = FV_TTY_FD while on (the reader's pipe where the reader runs); after done FV_KEY_FD is back, FV_TTY_FD '' and the fds closed"
    "the size comes from the pty: FV_SCREEN_W x FV_SCREEN_H = 100 x 30"
    "the caller's traps: ours while on, exactly the caller's again after doneVideo"
    "SIGWINCH sets FV_VIDEO_RESIZED and runs the caller's WINCH handler; getEvent -> evCommand cmResizeApp 120 40"
    "the state run restored the terminal"
    "initVideo twice / doneVideo twice: rc 0 each, one ?1049h and one ?1049l, the EXIT trap restores nothing more"
    "noalt: no ?1049h / ?1049l, no clear (ESC [ 2 J: the size is known), cursor and autowrap still restored; exit without doneVideo: the restore ends with ESC [ 30 ; 1 H (the last row, column 1)"
    "inside x=\$(...): drawn on the tty, x holds only the value printed after done"
    "FV_TTY = the pty's path (\$(tty)): works like /dev/tty"
    "raw mode refused by stty: rc 1, nothing printed to the terminal, stty / traps / FV_KEY_FD / fds as they were")

run_all() {

fvp_case state '
trap "note WINCH" WINCH
before=$(trap -p EXIT INT TERM HUP WINCH)
FV_KEY_FD=0
fv.video.initVideo || exit 91
note "stty $(stty -a <&"$FV_TTY_FD" | tr "\n" " ")"
fd=$FV_TTY_FD
rf=$__FV_VI_RFD
if [[ -t $fd && ( ( -z $rf && $FV_KEY_FD == "$fd" ) || ( -n $rf && $FV_KEY_FD == "$rf" && ! -t $rf ) ) ]]; then note "fd ok"; else note "fd bad [$fd] [$FV_KEY_FD] [$rf]"; fi
note "size ${FV_SCREEN_W}x$FV_SCREEN_H"
during=$(trap -p EXIT INT TERM HUP WINCH)
[[ $during == *fv.video._onexit*fv.video._onsig\ INT*fv.video._onsig\ TERM*fv.video._onsig\ HUP*fv.video._onwinch* ]] && note "traps on ok"
stty rows 40 cols 120 <&"$fd"
kill -WINCH $BASHPID
note "resized=$FV_VIDEO_RESIZED"
fv.drivers.getEvent 0
note "event $FV_EV_WHAT $FV_EV_COMMAND $FV_EV_ID $FV_EV_INFO ${FV_SCREEN_W}x$FV_SCREEN_H resized=$FV_VIDEO_RESIZED"
fv.video.doneVideo
after=$(trap -p EXIT INT TERM HUP WINCH)
[[ $before == "$after" ]] && note "traps back ok"
if [[ $FV_KEY_FD == 0 && -z $FV_TTY_FD && ! -e /dev/fd/$fd && ( -z $rf || ! -e /dev/fd/$rf ) ]]; then note "after ok"; else note "after bad [$FV_KEY_FD] [$FV_TTY_FD]"; fi
trap - WINCH
exit 0'
fvp_run state
fvp_file state log; LOG=$REPLY

# line PREFIX — REPLY = the log line starting with PREFIX
line() {
    local l
    REPLY=''
    while IFS= read -r l; do if [[ $l == "$1"* ]]; then REPLY=$l; return 0; fi; done <<< "$LOG"
    return 1
}

kt_test_start "${TITLES[0]}"
line 'stty '; s=$REPLY bad=''
for w in ' -echo ' ' -icanon ' ' -ixon ' 'min = 1;' 'time = 0;' 'intr = ^C;' 'susp = <undef>;' 'quit = <undef>;' 'lnext = <undef>;'; do
    [[ $s == *"$w"* ]] || bad+=" missing[$w]"
done
for w in dsusp discard status swtch; do
    if [[ $s == *" $w = "* && $s != *" $w = <undef>;"* ]]; then bad+=" $w-defined"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad in [$s]"; fi

kt_test_start "${TITLES[1]}"
if line 'fd ok' && line 'after ok'; then kt_test_pass "ok"; else kt_test_fail "[${LOG//$'\n'/|}]"; fi

kt_test_start "${TITLES[2]}"
if line 'size 100x30'; then kt_test_pass "ok"; else kt_test_fail "[${LOG//$'\n'/|}]"; fi

kt_test_start "${TITLES[3]}"
if line 'traps on ok' && line 'traps back ok'; then kt_test_pass "ok"; else kt_test_fail "[${LOG//$'\n'/|}]"; fi

kt_test_start "${TITLES[4]}"
if line 'WINCH' && line 'resized=1' && line 'event evCommand cmResizeApp 120 40 120x40 resized=0'; then
    n=0; while IFS= read -r l; do [[ $l == WINCH ]] && n=$(( n + 1 )); done <<< "$LOG"
    if (( n >= 1 )); then kt_test_pass "ok (caller WINCH x$n)"; else kt_test_fail "no WINCH"; fi
else
    kt_test_fail "[${LOG//$'\n'/|}]"
fi

kt_test_start "${TITLES[5]}"
fvp_file state rc
if [[ $REPLY == 0 ]] && fvp_restored state; then kt_test_pass "ok"; else kt_test_fail "rc=$REPLY $(fvp_restored state; echo "$REPLY")"; fi

fvp_case twice '
fv.video.initVideo; a=$?
fv.video.initVideo; b=$?
fv.video.doneVideo; c=$?
fv.video.doneVideo; d=$?
note "rc $a$b$c$d"
exit 0'
fvp_run twice
kt_test_start "${TITLES[6]}"
fvp_file twice log; l=$REPLY
count twice $'\e[?1049h'; h=$REPLY
count twice $'\e[?1049l'; o=$REPLY
count twice $'\e[?25h'; c=$REPLY
if [[ $l == 'rc 0000' && $h == 1 && $o == 1 && $c == 1 ]] && fvp_restored twice; then kt_test_pass "ok"; else kt_test_fail "log=[$l] ?1049h=$h ?1049l=$o ?25h=$c $REPLY"; fi

fvp_case noalt '
fv.video.initVideo noalt || exit 91
exit 4'
fvp_run noalt
kt_test_start "${TITLES[7]}"
count noalt $'\e[?1049'; n=$REPLY
count noalt $'\e[2J'; n2=$REPLY
fvp_ts noalt; nts=$REPLY
fvp_file noalt rc
if [[ $REPLY == 4 && $n == 0 && $n2 == 0 && $nts == *$'\e[?2004l\e[30;1H'* ]] && fvp_restored noalt 0; then kt_test_pass "ok"; else kt_test_fail "rc=$REPLY ?1049=$n 2J=$n2 $(fvp_restored noalt 0; echo "$REPLY")"; fi

fvp_case subst '
x=$(fv.video.initVideo || exit 91; printf "DRAWN-%s" "$FV_SCREEN_W" >&"$FV_TTY_FD"; fv.video.doneVideo; printf "value")
note "x=[$x]"
exit 0'
fvp_run subst
kt_test_start "${TITLES[8]}"
fvp_file subst log; l=$REPLY
fvp_ts subst
if [[ $l == 'x=[value]' && $REPLY == *$'\e[?1049h'*DRAWN-100*$'\e[?1049l'* ]] && fvp_restored subst; then kt_test_pass "ok"; else kt_test_fail "log=[$l] $REPLY"; fi

fvp_case ttypath '
FV_TTY=$(tty) || exit 92
fv.video.initVideo || exit 91
note "on=$FV_VIDEO_ON size=${FV_SCREEN_W}x$FV_SCREEN_H"
fv.video.doneVideo
exit 0'
fvp_run ttypath
kt_test_start "${TITLES[9]}"
fvp_file ttypath log; l=$REPLY
if [[ $l == 'on=1 size=100x30' ]] && fvp_restored ttypath; then kt_test_pass "ok"; else kt_test_fail "log=[$l] $(fvp_restored ttypath; echo "$REPLY")"; fi

    fvp_case rawfail '
trap "note EXIT" EXIT
before=$(trap -p EXIT INT TERM HUP WINCH)
exec {f}</dev/null; n0=$f; exec {f}<&-
FV_KEY_FD=0
stty() { if [[ $1 == -echo ]]; then return 1; fi; command stty "$@"; }
fv.video.initVideo; rc=$?
unset -f stty
exec {f}</dev/null; n1=$f; exec {f}<&-
after=$(trap -p EXIT INT TERM HUP WINCH)
same=no; if [[ $before == "$after" && $n0 == "$n1" ]]; then same=yes; fi
note "rc=$rc on=$FV_VIDEO_ON fd=[$FV_TTY_FD] key=$FV_KEY_FD same=$same"
exit 0'
    fvp_run rawfail
    kt_test_start "${TITLES[10]}"
    fvp_file rawfail log; l=$REPLY
    fvp_file rawfail before; b=$REPLY
    fvp_file rawfail after; a=$REPLY
    fvp_ts rawfail
    if [[ $l == $'rc=1 on=0 fd=[] key=0 same=yes\nEXIT' && -n $b && $b == "$a" && $REPLY != *$'\e['* ]]; then kt_test_pass "ok"; else kt_test_fail "log=[$l] stty [$b]->[$a] ts=$(printf '%q' "$REPLY")"; fi
}

if fvp_detect; then run_all; else fvv_skip "${TITLES[@]}"; fi

kt_test_log "005_Terminal.sh completed"
