#!/usr/bin/env bash
# 015_ShellState.sh - the terminal part under an odd caller IFS, and the
# buffer after a re-init, on a real pty under util-linux script(1) (SKIP with
# reason ENV elsewhere):
#   * IFS holding digits: initVideo, doneVideo and the EXIT trap still set up
#     and restore the terminal (the fd numbers in the redirects must not
#     split);
#   * IFS=$'\n\t' and IFS=$'\n': initVideo sets raw mode with the special
#     characters undefined (the stty word list must not depend on IFS);
#   * done -> init (a shell-out): the next updateScreen repaints every row,
#     because initVideo cleared the screen (FPC: a fresh OldVideoBuf).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "015: caller IFS and re-init on a pty (script(1))"

TITLES=("IFS=0123456789 between init and done: doneVideo restores the terminal (stty, ?1049l ?25h ?7h)"
    "IFS=0123456789 at init and exit: initVideo works, the EXIT trap restores the terminal"
    "IFS=\$'\\n\\t' and IFS=\$'\\n': initVideo sets raw mode with susp/quit/lnext undefined, done restores"
    "done -> init -> updateScreen: a full repaint (every row sent again), the cursor state re-sent")

run_all() {
    local l a b ts tail

    fvp_case ifsdone '
fv.video.initVideo || exit 91
IFS=0123456789
fv.video.doneVideo
exit 0'
    fvp_run ifsdone
    kt_test_start "${TITLES[0]}"
    fvp_file ifsdone rc
    if [[ $REPLY == 0 ]] && fvp_restored ifsdone; then kt_test_pass "ok"; else kt_test_fail "rc=$REPLY $(fvp_restored ifsdone; echo "$REPLY")"; fi

    fvp_case ifsexit '
IFS=0123456789
fv.video.initVideo || exit 91
note "on=$FV_VIDEO_ON"
exit 3'
    fvp_run ifsexit
    kt_test_start "${TITLES[1]}"
    fvp_file ifsexit rc; a=$REPLY
    fvp_file ifsexit log; l=$REPLY
    if [[ $a == 3 && $l == on=1 ]] && fvp_restored ifsexit; then kt_test_pass "ok"; else kt_test_fail "rc=$a log=[$l] $(fvp_restored ifsexit; echo "$REPLY")"; fi

    fvp_case ifsnl '
IFS=$'"'"'\n\t'"'"'
fv.video.initVideo; note "rc1=$?"
note "stty1 $(stty -a <&"$FV_TTY_FD" | tr "\n" " ")"
fv.video.doneVideo
IFS=$'"'"'\n'"'"'
fv.video.initVideo; note "rc2=$?"
note "stty2 $(stty -a <&"$FV_TTY_FD" | tr "\n" " ")"
fv.video.doneVideo
exit 0'
    fvp_run ifsnl
    kt_test_start "${TITLES[2]}"
    fvp_file ifsnl log; l=$REPLY
    b=''
    for a in rc1=0 rc2=0; do [[ $l == *"$a"* ]] || b+=" no[$a]"; done
    for a in ' -icanon ' 'susp = <undef>;' 'quit = <undef>;' 'lnext = <undef>;'; do
        [[ ${l#*stty1} == *"$a"*stty2* && ${l#*stty2} == *"$a"* ]] || b+=" missing[$a]"
    done
    if [[ -z $b ]] && fvp_restored ifsnl; then kt_test_pass "ok"; else kt_test_fail "$b [${l//$'\n'/|}] $(fvp_restored ifsnl; echo "$REPLY")"; fi

    fvp_case reinit '
fv.video.initVideo || exit 91
fv.video.initScreen
fv.video.writeStr 0 0 ROWTOP 1
fv.video.writeStr 0 $(( FV_SCREEN_H - 1 )) ROWBOT 2
fv.video.updateScreen; note "u1=$?"
fv.video.doneVideo
fv.video.initVideo || exit 92
fv.video.updateScreen; note "u2=$?"
fv.video.doneVideo
exit 0'
    fvp_run reinit
    kt_test_start "${TITLES[3]}"
    fvp_file reinit log; l=$REPLY
    fvp_ts reinit; ts=$REPLY
    tail=${ts##*$'\e[?1049h'}                      # what came after the second init
    if [[ $l == $'u1=0\nu2=0' && $tail == *ROWTOP*ROWBOT*$'\e[?25l'* ]] && fvp_restored reinit; then kt_test_pass "ok"
    else kt_test_fail "log=[$l] after the second init: $(printf '%q' "${tail:0:300}")"; fi
}

if fvp_detect; then run_all; else fvv_skip "${TITLES[@]}"; fi

kt_test_log "015_ShellState.sh completed"
