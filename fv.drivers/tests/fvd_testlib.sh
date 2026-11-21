#!/usr/bin/env bash
# fvd_testlib.sh — what the fv.drivers test files share. Not a test file: the
# ktests runner picks up NNN_*.sh only. No terminal: events come from bytes
# on a file or pipe fd (FV_KEY_FD set directly, no initVideo).
#
#   fvd_init NAME "$@"   ktest init + the unit + a scratch folder ($FVD_TMP)
#   fvd_feed BYTES       FV_KEY_FD = a fresh read fd on a file holding BYTES;
#                        the key queue, the held buttons and the click memory
#                        are reset
#   fvd_ev               REPLY = the event as one line: WHAT and every field
#                        that is not its default (key= char= cmd= id= info=
#                        x= y= b= m= dbl tri wheel= eof)
#   fvd_get WANT [T]     one test: getEvent [T] (default 0) -> rc 0 and the
#                        fvd_ev line WANT, RESULT = WHAT
#   fvd_writer FIRST GAP_US [REST]
#                        FV_KEY_FD = a live pipe that gets FIRST at once and
#                        REST after GAP_US (the writer is recorded, reaped by
#                        fvd_done and by INT/TERM traps; it ends by itself
#                        after REST: no EXIT trap, ktest owns that one);
#                        the driver's state reset as fvd_feed does (a button
#                        held by an earlier test would give an auto before
#                        FIRST arrives on a slow runner)
#   fvd_now             REPLY = EPOCHREALTIME in microseconds

FVD_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVD_TESTS_DIR/../../../ktests/ktest.sh"

fvd_init() {
    local name=$1
    shift
    source "$FVD_TESTS_DIR/../fv.drivers.sh"
    kt_test_init "$name" "$FVD_TESTS_DIR" "$@"
    FVD_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
}

fvd_feed() {
    if [[ -n ${FVD_FD-} ]]; then exec {FVD_FD}<&-; fi
    printf '%s' "$1" > "$FVD_TMP/in.bin"
    exec {FVD_FD}< "$FVD_TMP/in.bin"
    FV_KEY_FD=$FVD_FD
    fv.keyboard.flush
    fv.drivers.doneEvents
}

fvd_ev() {
    REPLY=$FV_EV_WHAT
    if [[ -n $FV_EV_KEY ]]; then REPLY+=" key=$FV_EV_KEY"; fi
    if [[ -n $FV_EV_CHAR ]]; then REPLY+=" char=$FV_EV_CHAR"; fi
    if [[ -n $FV_EV_COMMAND ]]; then REPLY+=" cmd=$FV_EV_COMMAND"; fi
    if [[ -n $FV_EV_ID ]]; then REPLY+=" id=$FV_EV_ID"; fi
    if [[ -n $FV_EV_INFO ]]; then REPLY+=" info=$FV_EV_INFO"; fi
    if [[ $FV_EV_WHAT == evMouse* ]]; then REPLY+=" x=$FV_EV_MOUSE_X y=$FV_EV_MOUSE_Y"
    elif [[ $FV_EV_MOUSE_X$FV_EV_MOUSE_Y != 00 ]]; then REPLY+=" x=$FV_EV_MOUSE_X y=$FV_EV_MOUSE_Y"; fi
    if [[ $FV_EV_MOUSE_BUTTONS != 0 ]]; then REPLY+=" b=$FV_EV_MOUSE_BUTTONS"; fi
    if [[ $FV_EV_MOUSE_MODS != 0 ]]; then REPLY+=" m=$FV_EV_MOUSE_MODS"; fi
    if [[ $FV_EV_MOUSE_DOUBLE != 0 ]]; then REPLY+=" dbl"; fi
    if [[ $FV_EV_MOUSE_TRIPLE != 0 ]]; then REPLY+=" tri"; fi
    if [[ $FV_EV_WHEEL != 0 ]]; then REPLY+=" wheel=$FV_EV_WHEEL"; fi
    if [[ $FV_EV_EOF != 0 ]]; then REPLY+=" eof"; fi
}

fvd_get() {
    local want=$1 rc
    kt_test_start "getEvent -> $want${FVD_NOTE:+ ($FVD_NOTE)}"
    fv.drivers.getEvent "${2:-0}"; rc=$?
    fvd_ev
    if [[ $rc == 0 && $REPLY == "$want" && $RESULT == "$FV_EV_WHAT" ]]; then kt_test_pass "ok"
    else kt_test_fail "rc=$rc got [$REPLY] RESULT=$RESULT"; fi
}

fvd_now() { local e=$EPOCHREALTIME; REPLY=$(( ${e%[.,]*} * 1000000 + 10#${e##*[.,]} )); }

FVD_PIDS=()
fvd_reap() {
    local p
    for p in "${FVD_PIDS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
    FVD_PIDS=()
}
fvd_busy() {        # US — wait US microseconds without a child process
    local t0
    fvd_now; t0=$REPLY
    while fvd_now; (( REPLY - t0 < $1 )); do :; done
}
fvd_writer() {
    if [[ -n ${FVD_WFD-} ]]; then exec {FVD_WFD}<&-; fvd_reap; fi
    if [[ -z ${FVD_TRAPS-} ]]; then
        FVD_TRAPS=1
        trap 'fvd_reap; exit 130' INT
        trap 'fvd_reap; exit 143' TERM
    fi
    exec {FVD_WFD}< <({ printf '%s' "$1"; fvd_busy "$2"; printf '%s' "${3-}"; } 2>/dev/null)
    FVD_PIDS+=("$!")
    FV_KEY_FD=$FVD_WFD
    fv.keyboard.flush
    fv.drivers.doneEvents
}
fvd_done() { exec {FVD_WFD}<&-; FVD_WFD=''; fvd_reap; }
