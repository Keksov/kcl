#!/usr/bin/env bash
# 008_Subshells.sh - the TUI is owned by the process that called initVideo,
# and only the traps active in a process are chained (critic B2, B3); on a
# real pty under util-linux script(1) (SKIP with reason ENV elsewhere):
#   * x=$(initVideo; [doneVideo;] printf v) with parent EXIT/INT traps: the
#     subshell chains none of the parent's (inactive) trap texts, the parent's
#     EXIT handler runs once, in the parent; the terminal is restored by the
#     subshell (its doneVideo or its EXIT trap);
#   * parent on, then x=$(initVideo; doneVideo): both are no-ops in the
#     subshell: the parent's screen, stty, traps and FV_VIDEO_ON stay;
#   * parent off, a ( ) subshell inits and leaves without done: it owns its
#     TUI, restores it at its exit, and the parent's traps are untouched.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "008: subshells (script(1))"

TITLES=("x=\$(initVideo; doneVideo; printf v): no parent trap chained in the subshell, the parent's EXIT handler once, in the parent"
    "... and the terminal is restored"
    "x=\$(initVideo; printf v) without done: the subshell's EXIT trap restores, the parent's EXIT handler once, in the parent"
    "... and the terminal is restored"
    "parent on, x=\$(initVideo; doneVideo): no-ops in the subshell; the parent's stty, screen, traps and FV_VIDEO_ON stay"
    "... and the parent's own doneVideo restores the terminal once"
    "parent off, ( initVideo; exit 5 ): the subshell owns and restores its TUI; the parent's traps untouched"
    "... and the terminal is restored")

# count NAME SEQ — REPLY = how often SEQ occurs in the typescript
count() {
    local LC_ALL=C ts n=0
    fvp_ts "$1"; ts=$REPLY
    while [[ $ts == *"$2"* ]]; do ts=${ts#*"$2"}; n=$(( n + 1 )); done
    REPLY=$n
}

run_all() {
    local l p

    fvp_case comsub '
trap "note PARENT-EXIT \$BASHPID" EXIT
trap "note PARENT-INT" INT
note "parent $BASHPID"
x=$(fv.video.initVideo || exit 91; printf "%s|%s|" "${__FV_VI_PREV[EXIT]-none}" "${__FV_VI_PREV[INT]-none}"; fv.video.doneVideo; printf v)
note "x=$x"
exit 0'
    fvp_run comsub
    fvp_file comsub log; l=$REPLY; p=${l#parent }; p=${p%%$'\n'*}
    kt_test_start "${TITLES[0]}"
    if [[ $l == "parent $p"$'\nx=none|none|v\nPARENT-EXIT '"$p" ]]; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}]"; fi
    kt_test_start "${TITLES[1]}"
    if fvp_restored comsub; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi

    fvp_case comsub2 '
trap "note PARENT-EXIT \$BASHPID" EXIT
note "parent $BASHPID"
x=$(fv.video.initVideo || exit 91; printf v)
note "x=$x"
exit 0'
    fvp_run comsub2
    fvp_file comsub2 log; l=$REPLY; p=${l#parent }; p=${p%%$'\n'*}
    kt_test_start "${TITLES[2]}"
    if [[ $l == "parent $p"$'\nx=v\nPARENT-EXIT '"$p" ]]; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}]"; fi
    kt_test_start "${TITLES[3]}"
    if fvp_restored comsub2; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi

    fvp_case subdone '
fv.video.initVideo || exit 91
t0=$(trap -p EXIT INT TERM HUP WINCH)
s0=$(stty -g <&"$FV_TTY_FD")
x=$(fv.video.initVideo; a=$?; fv.video.doneVideo; printf "%s%s" "$a" "$?")
s1=$(stty -g <&"$FV_TTY_FD")
t1=$(trap -p EXIT INT TERM HUP WINCH)
ok=no; if [[ $x == 00 && $s0 == "$s1" && $t0 == "$t1" && $FV_VIDEO_ON == 1 && -t $FV_TTY_FD ]]; then ok=yes; fi
note "same=$ok"
fv.video.doneVideo
exit 0'
    fvp_run subdone
    fvp_file subdone log; l=$REPLY
    count subdone $'\e[?1049l'; local n=$REPLY
    count subdone $'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'; local m=$REPLY
    kt_test_start "${TITLES[4]}"
    if [[ $l == 'same=yes' ]]; then kt_test_pass "ok"; else kt_test_fail "log=[$l]"; fi
    kt_test_start "${TITLES[5]}"
    if [[ $n == 1 && $m == 1 ]] && fvp_restored subdone; then kt_test_pass "ok"; else kt_test_fail "?1049l x$n, mouse-off x$m $REPLY"; fi

    fvp_case own '
trap "note PARENT-EXIT" EXIT
t0=$(trap -p EXIT INT TERM HUP WINCH)
( fv.video.initVideo || exit 91; note "sub on=$FV_VIDEO_ON"; exit 5 )
r=$?
t1=$(trap -p EXIT INT TERM HUP WINCH)
ok=no; if [[ $t0 == "$t1" && $FV_VIDEO_ON == 0 && -z $FV_TTY_FD ]]; then ok=yes; fi
note "rc=$r same=$ok"
exit 0'
    fvp_run own
    fvp_file own log; l=$REPLY
    kt_test_start "${TITLES[6]}"
    if [[ $l == $'sub on=1\nrc=5 same=yes\nPARENT-EXIT' ]]; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}]"; fi
    kt_test_start "${TITLES[7]}"
    if fvp_restored own; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi
}

if fvp_detect; then run_all; else fvv_skip "${TITLES[@]}"; fi

kt_test_log "008_Subshells.sh completed"
