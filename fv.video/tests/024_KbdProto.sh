#!/usr/bin/env bash
# 024_KbdProto.sh - the keyboard protocol of initVideo (design P3 §14.4,
# row 10.14): FV_KBD_PROTO=auto (default) sends the kitty query CSI ? u and
# DA1 CSI c right after the alternate screen and waits for nothing; the push
# CSI > 5 u goes out once, only after a kitty reply (fv.keyboard runs
# fv.video._kpush as it decodes the reply); kitty pushes at once; off sends
# nothing; a bad value acts as auto. Every exit path pops CSI < u only when
# pushed, before the main screen comes back (one stack per screen): doneVideo,
# exit without doneVideo (the EXIT trap), SIGTERM, Ctrl+C. No push from a
# subshell, none after the restore (a late reply), none twice. Ctrl+C stays
# the interrupt under the protocol: initVideo sets __FV_KB_ISIG (fv.keyboard
# raises SIGINT for the report CSI 99;5u, which brings no 0x03), the restore
# clears it (the report is then the key kbCtrlC).
#   * headless: fv.video._kproto per value, fv.video._kpush on a fake state
#     writing to a file (no terminal);
#   * on a real pty under util-linux script(1) (SKIP with reason ENV
#     elsewhere): the typescript, the replies typed into the pty.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "024: the kitty keyboard protocol: query, push after the reply, pop on every exit path"

E=$'\e'
Q="${E}[?u${E}[c" PUSH="${E}[>5u" POP="${E}[<u"

# --- headless ------------------------------------------------------------------------
kt_test_start "fv.video._kproto: auto / '' / kitty / off / a bad value -> what initVideo sends, the push flag, the hook; the kitty Ctrl+C interrupt on for every value"
r=''
for v in auto '' kitty off win32; do
    __fvv_x='' __FV_KB_ISIG=0
    FV_KBD_PROTO=$v fv.video._kproto 2>/dev/null
    fvk=$(printf '%q' "$__fvv_x")
    r+="[$v:$fvk:$__FV_VI_KPUSH:$__FV_KB_ONKITTY:$__FV_KB_KITTY:$__FV_KB_DA1:$__FV_KB_ISIG]"
done
__FV_VI_KPUSH=0 __FV_KB_ONKITTY='' __FV_KB_ISIG=0
want="[auto:\$'\\E[?u\\E[c':0:fv.video._kpush:-1:0:1][:\$'\\E[?u\\E[c':0:fv.video._kpush:-1:0:1][kitty:\$'\\E[>5u':1::-1:0:1][off:'':0::-1:0:1][win32:\$'\\E[?u\\E[c':0:fv.video._kpush:-1:0:1]"
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got  $r"$'\n'"want $want"; fi

kt_test_start "fv.video._kproto: a bad FV_KBD_PROTO says so in one debug line"
err="$(VERBOSE_KKLASS=debug; FV_KBD_PROTO=win32 fv.video._kproto 2>&1)"
if [[ $err == *"FV_KBD_PROTO 'win32' is not auto, kitty or off; using auto"* ]]; then kt_test_pass "ok"; else kt_test_fail "got [$err]"; fi

kt_test_start "fv.video._kpush on a TUI of this process: the push once (a second reply pushes nothing)"
exec {pf}>"$FVV_TMP/push.out"
__FV_VI_ACT=1 __FV_VI_PID=$BASHPID __FV_VI_FD=$pf __FV_VI_KPUSH=0
fv.video._kpush; fv.video._kpush
r=$__FV_VI_KPUSH
__FV_VI_ACT=0 __FV_VI_FD='' __FV_VI_KPUSH=0
exec {pf}>&-
got=$(<"$FVV_TMP/push.out")
if [[ $got == "$PUSH" && $r == 1 ]]; then kt_test_pass "ok"; else fvk=$(printf '%q' "$got"); kt_test_fail "got $fvk flag=$r"; fi

kt_test_start "fv.video._kpush pushes nothing with the TUI off, in a subshell of its owner, or without a terminal fd"
exec {pf}>"$FVV_TMP/push2.out"
__FV_VI_ACT=0 __FV_VI_PID=$BASHPID __FV_VI_FD=$pf __FV_VI_KPUSH=0
fv.video._kpush; r=$__FV_VI_KPUSH
__FV_VI_ACT=1
( fv.video._kpush ); r+=$__FV_VI_KPUSH
__FV_VI_FD=''
fv.video._kpush; r+=$__FV_VI_KPUSH
__FV_VI_ACT=0 __FV_VI_KPUSH=0
exec {pf}>&-
got=$(<"$FVV_TMP/push2.out")
if [[ -z $got && $r == 000 ]]; then kt_test_pass "ok"; else kt_test_fail "wrote [$got] flags=$r"; fi

# --- on a pty --------------------------------------------------------------------------
# count NAME TEXT — REPLY = how many times TEXT occurs in the typescript
count() {
    local ts n=0
    fvp_ts "$1"; ts=$REPLY
    while [[ $ts == *"$2"* ]]; do ts=${ts#*"$2"}; n=$(( n + 1 )); done
    REPLY=$n
}
# the child's pieces: the reader's pids recorded; a loop that ends at a typed q
REC='printf "%s" "$__FV_VI_RPID" > "$D/rpid"; printf "%s" "$__FV_VI_WPID" > "$D/rpidw"'
LOOP='
: > "$D/ready"
while fv.drivers.getEvent; do
    if [[ $FV_EV_WHAT == evKeyDown && $FV_EV_CHAR == q ]]; then break; fi
done
note "loop kpush=$__FV_VI_KPUSH kitty=$__FV_KB_KITTY da1=$__FV_KB_DA1"
'
DONE='
fv.video.doneVideo
note "after kpush=$__FV_VI_KPUSH hook=[$__FV_KB_ONKITTY]"
exit 0'

TITLES=("auto, no reply: the query after ?1049h, no push, no pop; restored"
    "auto + a kitty reply typed (twice): one push after it, the pop before ?1049l at doneVideo; the reply is no key"
    "auto + a DA1 reply only (a terminal without the protocol): no push, no pop"
    "kitty: the push right after ?1049h, no query; the pop at doneVideo"
    "kitty + noalt: the push and the pop on the main screen"
    "off: no query, no push, no pop"
    "a bad FV_KBD_PROTO acts as auto (the query, no push without a reply)"
    "exit without doneVideo after the push: the EXIT trap pops (status 3)"
    "SIGTERM after a reply-driven push: popped (status 143)"
    "Ctrl+C typed after the push: popped (status 130)"
    "a late reply after doneVideo and a push from a subshell push nothing; after doneVideo a kitty Ctrl+C report is the key kbCtrlC"
    "Ctrl+C as the kitty report CSI 99;5u (no 0x03, so no SIGINT from the tty): SIGINT all the same, popped, restored (status 130)")

run_pty() {
# pty CASE TITLE WANT_RC — the restore check plus the status; REPLY = the log
ptycheck() {
    local bad=''
    fvp_file "$1" rc
    [[ $REPLY == "$3" ]] || bad+=" rc=$REPLY"
    fvp_restored "$1" "${4:-1}" || bad+=" $REPLY"
    fvp_file "$1" log
    BAD=$bad
}

fvp_case none "fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run none ready sleep:0.3 'type:q'
kt_test_start "${TITLES[0]}"
ptycheck none "${TITLES[0]}" 0; l=$REPLY
fvp_ts none; ts=$REPLY
count none "$PUSH"; np=$REPLY; count none "$POP"; no=$REPLY; count none "$Q"; nq=$REPLY
if [[ -z $BAD && $ts == *"${E}[?1049h$Q"* && $np == 0 && $no == 0 && $nq == 1 && $l == *'loop kpush=0 kitty=-1 da1=0'* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no query=$nq log=[${l//$'\n'/|}]"; fi

fvp_case reply "fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run reply ready 'type:\e[?0u' sleep:0.3 'type:\e[?1u' sleep:0.3 'type:q'
kt_test_start "${TITLES[1]}"
ptycheck reply "${TITLES[1]}" 0; l=$REPLY
fvp_ts reply; ts=$REPLY
count reply "$PUSH"; np=$REPLY; count reply "$POP"; no=$REPLY
after=${ts#*"$Q"}
if [[ -z $BAD && $np == 1 && $no == 1 && $after == *"$PUSH"* && $ts == *"$POP${E}[0m${E}[?7h${E}[?25h${E}[?1049l"* \
      && $l == *'loop kpush=1 kitty=1 da1=0'* && $l == *'after kpush=0 hook=[]'* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no log=[${l//$'\n'/|}]"; fi

fvp_case da1 "fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run da1 ready 'type:\e[?62;22c' sleep:0.3 'type:q'
kt_test_start "${TITLES[2]}"
ptycheck da1 "${TITLES[2]}" 0; l=$REPLY
count da1 "$PUSH"; np=$REPLY; count da1 "$POP"; no=$REPLY
if [[ -z $BAD && $np == 0 && $no == 0 && $l == *'loop kpush=0 kitty=-1 da1=1'* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no log=[${l//$'\n'/|}]"; fi

fvp_case kitty "FV_KBD_PROTO=kitty
fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run kitty ready sleep:0.2 'type:q'
kt_test_start "${TITLES[3]}"
ptycheck kitty "${TITLES[3]}" 0; l=$REPLY
fvp_ts kitty; ts=$REPLY
count kitty "$PUSH"; np=$REPLY; count kitty "$POP"; no=$REPLY; count kitty "$Q"; nq=$REPLY
if [[ -z $BAD && $np == 1 && $no == 1 && $nq == 0 && $ts == *"${E}[?1049h$PUSH"* && $ts == *"$POP${E}[0m${E}[?7h${E}[?25h${E}[?1049l"* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no query=$nq log=[${l//$'\n'/|}]"; fi

fvp_case noalt "FV_KBD_PROTO=kitty
fv.video.initVideo noalt || exit 91
$REC
$LOOP
$DONE"
fvp_run noalt ready sleep:0.2 'type:q'
kt_test_start "${TITLES[4]}"
ptycheck noalt "${TITLES[4]}" 0 0; l=$REPLY
fvp_ts noalt; ts=$REPLY
count noalt "$PUSH"; np=$REPLY; count noalt "$POP"; no=$REPLY; count noalt "${E}[?1049"; na=$REPLY
if [[ -z $BAD && $np == 1 && $no == 1 && $na == 0 && $ts == *"$PUSH${E}[?25l"* && $ts == *"$POP${E}[0m${E}[?7h${E}[?25h"* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no ?1049=$na log=[${l//$'\n'/|}]"; fi

fvp_case off "FV_KBD_PROTO=off
fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run off ready 'type:\e[?0u' sleep:0.3 'type:q'
kt_test_start "${TITLES[5]}"
ptycheck off "${TITLES[5]}" 0; l=$REPLY
count off "$PUSH"; np=$REPLY; count off "$POP"; no=$REPLY; count off "${E}[?u"; nq=$REPLY; count off "${E}[c"; nd=$REPLY
if [[ -z $BAD && $np == 0 && $no == 0 && $nq == 0 && $nd == 0 && $l == *'loop kpush=0 kitty=0'* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no query=$nq da1=$nd log=[${l//$'\n'/|}]"; fi

fvp_case bad "FV_KBD_PROTO=win32
fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run bad ready sleep:0.2 'type:q'
kt_test_start "${TITLES[6]}"
ptycheck bad "${TITLES[6]}" 0; l=$REPLY
count bad "$PUSH"; np=$REPLY; count bad "$Q"; nq=$REPLY
if [[ -z $BAD && $np == 0 && $nq == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD push=$np query=$nq log=[${l//$'\n'/|}]"; fi

fvp_case exit3 "FV_KBD_PROTO=kitty
fv.video.initVideo || exit 91
$REC
: > \"\$D/ready\"
exit 3"
fvp_run exit3 ready
kt_test_start "${TITLES[7]}"
ptycheck exit3 "${TITLES[7]}" 3
fvp_ts exit3; ts=$REPLY
count exit3 "$POP"; no=$REPLY
if [[ -z $BAD && $no == 1 && $ts == *"$POP${E}[0m${E}[?7h${E}[?25h${E}[?1049l"* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD pop=$no"; fi

fvp_case term "fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run term ready 'type:\e[?0u' sleep:0.5 sig:TERM
kt_test_start "${TITLES[8]}"
ptycheck term "${TITLES[8]}" 143
count term "$PUSH"; np=$REPLY; count term "$POP"; no=$REPLY
fvp_ts term; ts=$REPLY
if [[ -z $BAD && $np == 1 && $no == 1 && $ts == *"$PUSH"*"$POP${E}[0m${E}[?7h${E}[?25h${E}[?1049l"* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no"; fi

fvp_case int "FV_KBD_PROTO=kitty
fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run int ready sleep:0.3 'type:\x03'
kt_test_start "${TITLES[9]}"
ptycheck int "${TITLES[9]}" 130
count int "$POP"; no=$REPLY
if [[ -z $BAD && $no == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD pop=$no"; fi

fvp_case late "fv.video.initVideo || exit 91
$REC
: > \"\$D/ready\"
( fv.video._kpush )
note \"sub kpush=\$__FV_VI_KPUSH\"
fv.video.doneVideo
fv.keyboard.feed \$'\\e[?5ux'
fv.keyboard.getKeyEvent 0
note \"late key=\$FV_KEY kitty=\$__FV_KB_KITTY kpush=\$__FV_VI_KPUSH\"
fv.video._kpush
fv.keyboard.feed \$'\\e[99;5u'
fv.keyboard.getKeyEvent 0
note \"ctrlc key=\$FV_KEY:\$FV_KEY_CHAR isig=\$__FV_KB_ISIG\"
exit 0"
fvp_run late ready
kt_test_start "${TITLES[10]}"
ptycheck late "${TITLES[10]}" 0; l=$REPLY
count late "$PUSH"; np=$REPLY; count late "$POP"; no=$REPLY
if [[ -z $BAD && $np == 0 && $no == 0 && $l == *'sub kpush=0'* && $l == *'late key=kbChar kitty=5 kpush=0'* && $l == *'ctrlc key=kbCtrlC:c isig=0'* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD push=$np pop=$no log=[${l//$'\n'/|}]"; fi

fvp_case ikitty "FV_KBD_PROTO=kitty
fv.video.initVideo || exit 91
$REC
note \"on isig=\$__FV_KB_ISIG\"
$LOOP
$DONE"
fvp_run ikitty ready sleep:0.3 'type:\e[99;5u'
kt_test_start "${TITLES[11]}"
ptycheck ikitty "${TITLES[11]}" 130; l=$REPLY
count ikitty "$POP"; no=$REPLY
if [[ -z $BAD && $no == 1 && $l == *'on isig=1'* && $l != *'loop kpush'* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD pop=$no log=[${l//$'\n'/|}]"; fi

}

if fvp_detect; then run_pty; else fvv_skip "${TITLES[@]}"; fi

kt_test_log "024_KbdProto.sh completed"
